//============================================================================
// Module: ov7670_capture
// Description: OV7670 Pixel Capture / Frame Buffer Writer
//              Captures RGB565 pixel data from the OV7670 camera and converts
//              it to RGB444 for BRAM storage.
//
// Camera output: RGB565 format, 2 bytes per pixel
//   Byte 1 (first PCLK): {R[4:0], G[5:3]} = D[7:0]
//   Byte 2 (next PCLK):  {G[2:0], B[4:0]} = D[7:0]
//
// Data is sampled on the FALLING edge of PCLK (per OV7670 tPDV timing).
// VSYNC rising edge resets write_addr to 0 for each new frame.
//
// Single-bank architecture: 320x240 = 76,800 pixels, 17-bit address.
//============================================================================

module ov7670_capture (
    input  wire        pclk,       // OV7670 pixel clock
    input  wire        rst,        // Synchronous reset (active high, sync to pclk)
    input  wire        href,       // Horizontal reference (data valid when high)
    input  wire        vsync,      // Vertical sync (frame start on rising edge)
    input  wire [7:0]  d,          // Camera data bus D[7:0]

    // Frame buffer write interface
    output reg  [16:0] wr_addr,    // BRAM write address (0 to 76799)
    output reg  [11:0] wr_data,    // BRAM write data (RGB444)
    output reg         wr_en       // BRAM write enable
);

    //------------------------------------------------------------------------
    // Internal registers
    //------------------------------------------------------------------------
    reg [7:0] byte1;          // First byte of RGB565 pixel (latched)
    reg       byte_toggle;    // 0 = expecting byte 1, 1 = expecting byte 2
    reg       vsync_prev;     // Previous VSYNC value for edge detection

    //------------------------------------------------------------------------
    // Edge detection
    //------------------------------------------------------------------------
    wire vsync_rising = vsync & ~vsync_prev;

    //------------------------------------------------------------------------
    // Main capture logic — clocked on FALLING edge of PCLK
    // OV7670 datasheet: pixel data is stable on falling edge of PCLK
    //------------------------------------------------------------------------
    always @(negedge pclk) begin
        if (rst) begin
            wr_addr     <= 17'd0;
            wr_data     <= 12'd0;
            wr_en       <= 1'b0;
            byte1       <= 8'd0;
            byte_toggle <= 1'b0;
            vsync_prev  <= 1'b0;
        end else begin
            vsync_prev <= vsync;
            wr_en      <= 1'b0;   // Default: no write

            //----------------------------------------------------------------
            // VSYNC rising edge: reset write address for new frame
            //----------------------------------------------------------------
            if (vsync_rising) begin
                wr_addr     <= 17'd0;
                byte_toggle <= 1'b0;
            end

            //----------------------------------------------------------------
            // HREF high: valid pixel data on D[7:0]
            //----------------------------------------------------------------
            if (href) begin
                if (~byte_toggle) begin
                    // First byte: latch it
                    byte1       <= d;
                    byte_toggle <= 1'b1;
                end else begin
                    // Second byte: assemble RGB565 -> downsample to RGB444
                    // byte1 = {R[4:0], G[5:3]}
                    // d     = {G[2:0], B[4:0]}
                    // RGB444: R = byte1[7:4] = R[4:1]
                    //         G = {byte1[2:0], d[7]} = {G[5:3], G[2]} = G[5:2]
                    //         B = d[4:1] = B[4:1]
                    wr_data <= {byte1[7:4],           // R[4:1] -> 4 bits
                                {byte1[2:0], d[7]},   // G[5:2] -> 4 bits
                                d[4:1]};               // B[4:1] -> 4 bits

                    wr_en       <= 1'b1;
                    byte_toggle <= 1'b0;

                    // Increment write address (wraps naturally at 17 bits)
                    if (wr_addr < 17'd76799)
                        wr_addr <= wr_addr + 17'd1;
                end
            end else begin
                byte_toggle <= 1'b0; // Reset byte toggle when HREF drops
            end
        end
    end

endmodule
