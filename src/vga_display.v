//============================================================================
// Module: vga_display
// Description: Simplified Frame Buffer Reader + VGA Output Driver
//              Reads from single-bank frame buffer, applies nearest-neighbor
//              upscaling (320x240 -> 640x480), applies image filter, outputs.
//
// Pipeline: 2-cycle latency (1 for BRAM read, 1 for output register)
//============================================================================

module vga_display (
    input  wire        clk,       // 25MHz VGA pixel clock
    input  wire        rst,       // Synchronous reset (active high)
    // VGA sync signals
    input  wire [9:0]  hcount,    // Horizontal pixel counter (0-799)
    input  wire [9:0]  vcount,    // Vertical line counter (0-524)
    input  wire        hactive,   // Horizontal active region
    input  wire        vactive,   // Vertical active region
    // Filter select
    input  wire [1:0]  sw,        // SW[1:0] for filter mode
    // Single-bank Frame buffer read port
    output wire [16:0] rd_addr,   // Read address
    input  wire [11:0] rd_data,   // Read data (RGB444)
    // VGA color outputs
    output reg  [3:0]  vga_r,     // VGA red channel
    output reg  [3:0]  vga_g,     // VGA green channel
    output reg  [3:0]  vga_b      // VGA blue channel
);

    //------------------------------------------------------------------------
    // Address Calculation
    // VGA 640x480 -> Camera 320x240: divide both by 2
    // cam_x = hcount / 2  (0..319)
    // cam_y = vcount / 2  (0..239)
    // Linear address = cam_y * 320 + cam_x
    // 320 = 256 + 64, so cam_y * 320 = (cam_y << 8) + (cam_y << 6)
    //------------------------------------------------------------------------
    wire [8:0] cam_x = hcount[9:1]; // 0..319
    wire [7:0] cam_y = vcount[9:1]; // 0..239

    // cam_y * 320 = cam_y * 256 + cam_y * 64
    wire [16:0] row_offset = ({1'b0, cam_y, 8'd0}) + ({3'b0, cam_y, 6'd0});

    assign rd_addr = row_offset + {8'd0, cam_x};

    //------------------------------------------------------------------------
    // Pipeline: delay active signals by 1 cycle for BRAM read latency
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
    // Image Filter
    //------------------------------------------------------------------------
    wire [11:0] filtered_pixel;

    image_filter u_filter (
        .pixel_in  (rd_data),
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
