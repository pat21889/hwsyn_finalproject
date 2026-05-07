//============================================================================
// Module: vga_display
// Description: Frame Buffer Reader + Bilinear Filter + VGA Output Driver
//              Reads pixel data from the dual-bank frame buffer, applies
//              bilinear interpolation for high-quality upscaling, applies the
//              selected image filter, and drives VGA color outputs.
//
// Dual-Bank Architecture:
//   Bank 0 stores Even camera rows.
//   Bank 1 stores Odd camera rows.
//   This allows reading two vertical neighbors simultaneously.
//
// Bilinear Interpolation:
//   Averages 2x2 blocks of source pixels to compute intermediate VGA pixels,
//   smoothing out the image instead of nearest-neighbor blockiness.
//============================================================================

module vga_display (
    input  wire        clk,       // 25MHz VGA pixel clock
    input  wire        rst,       // Synchronous reset (active high)
    // VGA sync signals (from vga_sync)
    input  wire [9:0]  hcount,    // Horizontal pixel counter
    input  wire [9:0]  vcount,    // Vertical line counter
    input  wire        hactive,   // Horizontal active region
    input  wire        vactive,   // Vertical active region
    // Filter select
    input  wire [1:0]  sw,        // SW[1:0] for filter mode
    // Dual-bank Frame buffer read ports
    output wire [15:0] rd_addr_even, // Address for Even bank
    output wire [15:0] rd_addr_odd,  // Address for Odd bank
    input  wire [11:0] rd_data_even, // Data from Even bank
    input  wire [11:0] rd_data_odd,  // Data from Odd bank
    // VGA color outputs
    output reg  [3:0]  vga_r,     // VGA red channel
    output reg  [3:0]  vga_g,     // VGA green channel
    output reg  [3:0]  vga_b      // VGA blue channel
);

    //------------------------------------------------------------------------
    // Address Calculation for Dual-Bank BRAM
    // hcount maps to X, vcount maps to Y
    //------------------------------------------------------------------------
    // Horizontal: read ahead by 1 so data arrives in time for interpolation
    wire [9:0] col_next = hcount + 1'b1;
    wire [8:0] bram_col = (col_next[9:1] > 9'd319) ? 9'd319 : col_next[9:1];

    // Vertical: determine which banks need which row
    wire [8:0] y_cam     = vcount[9:1]; // Camera row (0 to 239)
    wire [6:0] bank_addr = y_cam[8:1];  // Address within bank (0 to 119)

    wire [6:0] addr_odd  = bank_addr;
    wire [7:0] addr_even_calc = bank_addr + y_cam[0];
    wire [6:0] addr_even = (addr_even_calc > 7'd119) ? 7'd119 : addr_even_calc[6:0];

    // Multiply by 320 to get 1D addresses
    wire [15:0] row_even_x256 = {2'd0, addr_even, 7'd0};  // addr << 7 is not *256 wait...
    // Let's re-do carefully: max addr is 119. 119 * 320 = 38080 (fits in 16 bits)
    // 320 = 256 + 64 = (addr << 8) + (addr << 6)
    wire [15:0] row_even_x256_fix = {1'd0, addr_even, 8'd0};
    wire [15:0] row_even_x64_fix  = {3'd0, addr_even, 6'd0};
    wire [15:0] offset_even       = row_even_x256_fix + row_even_x64_fix;

    wire [15:0] row_odd_x256_fix = {1'd0, addr_odd, 8'd0};
    wire [15:0] row_odd_x64_fix  = {3'd0, addr_odd, 6'd0};
    wire [15:0] offset_odd       = row_odd_x256_fix + row_odd_x64_fix;

    assign rd_addr_even = offset_even + {7'd0, bram_col};
    assign rd_addr_odd  = offset_odd  + {7'd0, bram_col};

    //------------------------------------------------------------------------
    // Pipeline delayed sync signals (match 1-cycle BRAM read latency)
    //------------------------------------------------------------------------
    reg hactive_d, vactive_d;
    reg [9:0] hcount_d, vcount_d;

    always @(posedge clk) begin
        if (rst) begin
            hactive_d <= 1'b0;
            vactive_d <= 1'b0;
            hcount_d  <= 10'd0;
            vcount_d  <= 10'd0;
        end else begin
            hactive_d <= hactive;
            vactive_d <= vactive;
            hcount_d  <= hcount;
            vcount_d  <= vcount;
        end
    end

    //------------------------------------------------------------------------
    // Bilinear Interpolation Logic
    //------------------------------------------------------------------------
    // Determine which BRAM is top/bottom based on delayed Y coordinate
    wire y_is_odd = vcount_d[1]; // vcount_d[9:1] is y_cam. bit 0 of y_cam is vcount_d[1].
    
    wire [11:0] p_top_curr = (y_is_odd == 1'b0) ? rd_data_even : rd_data_odd;
    wire [11:0] p_bot_curr = (y_is_odd == 1'b0) ? rd_data_odd  : rd_data_even;

    // Registers to hold previous column pixels for horizontal interpolation
    reg [11:0] p_top_prev;
    reg [11:0] p_bot_prev;

    always @(posedge clk) begin
        if (hcount_d == 10'd0) begin
            // Reset at start of line
            p_top_prev <= p_top_curr;
            p_bot_prev <= p_bot_curr;
        end else begin
            p_top_prev <= p_top_curr;
            p_bot_prev <= p_bot_curr;
        end
    end

    // Averaging function for RGB444 pixels
    function [11:0] avg;
        input [11:0] p1;
        input [11:0] p2;
        reg [4:0] r, g, b;
        begin
            r = {1'b0, p1[11:8]} + {1'b0, p2[11:8]};
            g = {1'b0, p1[7:4]}  + {1'b0, p2[7:4]};
            b = {1'b0, p1[3:0]}  + {1'b0, p2[3:0]};
            avg = {r[4:1], g[4:1], b[4:1]};
        end
    endfunction

    // Horizontal interpolation
    wire h_interp = hcount_d[0];
    wire [11:0] p_top_interp = (h_interp) ? avg(p_top_prev, p_top_curr) : p_top_curr;
    wire [11:0] p_bot_interp = (h_interp) ? avg(p_bot_prev, p_bot_curr) : p_bot_curr;

    // Vertical interpolation
    wire v_interp = vcount_d[0];
    wire [11:0] final_pixel = (v_interp) ? avg(p_top_interp, p_bot_interp) : p_top_interp;

    //------------------------------------------------------------------------
    // Image Filter
    //------------------------------------------------------------------------
    wire [11:0] filtered_pixel;

    image_filter u_filter (
        .pixel_in  (final_pixel), // Apply filter to the bilinearly upscaled pixel
        .sw        (sw),
        .pixel_out (filtered_pixel)
    );

    //------------------------------------------------------------------------
    // VGA output register
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else begin
            if (hactive_d & vactive_d) begin
                vga_r <= filtered_pixel[11:8];
                vga_g <= filtered_pixel[7:4];
                vga_b <= filtered_pixel[3:0];
            end else begin
                vga_r <= 4'h0;
                vga_g <= 4'h0;
                vga_b <= 4'h0;
            end
        end
    end

endmodule
