//============================================================================
// Module: vga_display
// Description: Frame Buffer Reader + Filter + VGA Output Driver
//              Reads pixel data from the single-bank frame buffer, applies
//              pixel-doubling (320x240 -> 640x480) for VGA output, applies the
//              selected image filter, and drives VGA color outputs.
//
// Pixel Doubling (2x2):
//   Each BRAM pixel covers a 2x2 block of VGA pixels.
//   bram_col = hcount >> 1   (0..319)
//   bram_row = vcount >> 1   (0..239)
//   rd_addr  = bram_row * 320 + bram_col
//
// Pipeline: 1 cycle BRAM read latency
//   Cycle 0: set rd_addr from hcount/vcount
//   Cycle 1: rd_data valid -> apply filter -> register VGA output
//   hsync/vsync are delayed 2 cycles in top.v to compensate
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
    // Frame buffer read port (single-bank)
    output wire [16:0] rd_addr,   // Read address (0 to 76799)
    input  wire [11:0] rd_data,   // Read data from BRAM (RGB444)
    // VGA color outputs
    output reg  [3:0]  vga_r,     // VGA red channel
    output reg  [3:0]  vga_g,     // VGA green channel
    output reg  [3:0]  vga_b      // VGA blue channel
);

    //------------------------------------------------------------------------
    // Address Calculation
    // Map VGA 640x480 coordinates to BRAM 320x240
    // Read ahead by 1 pixel so BRAM data arrives in time for the output register
    //------------------------------------------------------------------------
    wire [9:0] h_next = hcount + 10'd1;
    wire [8:0] bram_col = h_next[9:1]; // Divide by 2 (0..319)
    wire [7:0] bram_row = vcount[9:1]; // Divide by 2 (0..239)

    // Clamp to valid range
    wire [8:0] col_clamped = (bram_col > 9'd319) ? 9'd319 : bram_col;
    wire [7:0] row_clamped = (bram_row > 8'd239) ? 8'd239 : bram_row;

    // Calculate 1D address: row * 320 + col
    // 320 = 256 + 64 = (row << 8) + (row << 6)
    wire [16:0] row_x256 = {1'b0, row_clamped, 8'd0};    // row << 8
    wire [16:0] row_x64  = {3'b000, row_clamped, 6'd0};  // row << 6
    wire [16:0] row_offset = row_x256 + row_x64;          // row * 320

    assign rd_addr = row_offset + {8'd0, col_clamped};

    //------------------------------------------------------------------------
    // Pipeline delayed sync signals (match 1-cycle BRAM read latency)
    //------------------------------------------------------------------------
    reg hactive_d, vactive_d;

    always @(posedge clk) begin
        if (rst) begin
            hactive_d <= 1'b0;
            vactive_d <= 1'b0;
        end else begin
            hactive_d <= hactive;
            vactive_d <= vactive;
        end
    end

    //------------------------------------------------------------------------
    // Image Filter — purely combinational, instantiated inline
    //------------------------------------------------------------------------
    wire [11:0] filtered_pixel;

    image_filter u_filter (
        .pixel_in  (rd_data),
        .sw        (sw),
        .pixel_out (filtered_pixel)
    );

    //------------------------------------------------------------------------
    // VGA output register
    // Registered output for clean signals and proper timing
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
