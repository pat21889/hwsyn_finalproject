//============================================================================
// Module: ov7670_capture
// Description: OV7670 Pixel Capture / Frame Buffer Writer (Dual Bank)
//              Captures RGB565 pixel data from the OV7670 camera and converts
//              it to RGB444 for BRAM storage.
//
//              Modified for Dual-Bank Memory (Bilinear Interpolation):
//              - Bank 0: Even rows (0, 2, 4...)
//              - Bank 1: Odd rows (1, 3, 5...)
//
// Camera output: RGB565 format, 2 bytes per pixel
//   Byte 1 (first PCLK): {R[4:0], G[5:3]} = D[7:0]
//   Byte 2 (next PCLK):  {G[2:0], B[4:0]} = D[7:0]
//
// Data is sampled on the FALLING edge of PCLK (per OV7670 tPDV timing).
//============================================================================

module ov7670_capture (
    input  wire        pclk,       // OV7670 pixel clock
    input  wire        rst,        // Synchronous reset (active high, sync to pclk)
    input  wire        href,       // Horizontal reference (data valid when high)
    input  wire        vsync,      // Vertical sync (frame start on rising edge)
    input  wire [7:0]  d,          // Camera data bus D[7:0]
    
    // Dual-bank memory interface
    output reg  [15:0] wr_addr,    // BRAM write address per bank (0 to 38399)
    output reg  [11:0] wr_data,    // BRAM write data (RGB444)
    output reg         wr_en,      // BRAM write enable
    output wire        bank_sel    // Bank select (0=Even, 1=Odd)
);

    //------------------------------------------------------------------------
    // Internal registers
    //------------------------------------------------------------------------
    reg [7:0] byte1;          // First byte of RGB565 pixel (latched)
    reg       byte_toggle;    // 0 = expecting byte 1, 1 = expecting byte 2
    reg       vsync_prev;     // Previous VSYNC value for edge detection
    reg       href_prev;      // Previous HREF value for edge detection

    reg [8:0] x_count;        // X coordinate (0 to 319)
    reg [7:0] y_count;        // Y coordinate (0 to 239)

    //------------------------------------------------------------------------
    // Edge detection
    //------------------------------------------------------------------------
    wire vsync_rising = vsync & ~vsync_prev;
    wire href_falling = ~href & href_prev;

    //------------------------------------------------------------------------
    // Bank Selection and Address Calculation
    // bank_sel is the LSB of the Y coordinate.
    // wr_addr  is (Y/2) * 320 + X.
    //------------------------------------------------------------------------
    assign bank_sel = y_count[0];
    
    // row_offset = (y_count / 2) * 320
    wire [6:0] y_half = y_count[7:1];
    wire [15:0] row_offset = ({y_half, 8'd0}) + ({2'd0, y_half, 6'd0}); // (y_half << 8) + (y_half << 6)

    //------------------------------------------------------------------------
    // Main capture logic — clocked on FALLING edge of PCLK
    //------------------------------------------------------------------------
    always @(negedge pclk) begin
        if (rst) begin
            wr_addr     <= 16'd0;
            wr_data     <= 12'd0;
            wr_en       <= 1'b0;
            byte1       <= 8'd0;
            byte_toggle <= 1'b0;
            vsync_prev  <= 1'b0;
            href_prev   <= 1'b0;
            x_count     <= 9'd0;
            y_count     <= 8'd0;
        end else begin
            vsync_prev <= vsync;
            href_prev  <= href;
            wr_en      <= 1'b0;   // Default: no write

            //----------------------------------------------------------------
            // VSYNC rising edge: reset coordinates for new frame
            //----------------------------------------------------------------
            if (vsync_rising) begin
                x_count     <= 9'd0;
                y_count     <= 8'd0;
                byte_toggle <= 1'b0;
            end

            //----------------------------------------------------------------
            // HREF falling edge: increment Y coordinate
            //----------------------------------------------------------------
            if (href_falling) begin
                x_count     <= 9'd0;
                if (y_count < 8'd239)
                    y_count <= y_count + 8'd1;
                else
                    y_count <= 8'd0;
            end

            //----------------------------------------------------------------
            // HREF high: valid pixel data on D[7:0]
            //----------------------------------------------------------------
            if (href) begin
                if (~byte_toggle) begin
                    byte1       <= d;
                    byte_toggle <= 1'b1;
                end else begin
                    // Downsample RGB565 -> RGB444
                    wr_data <= {byte1[7:4],               // R[4:1] -> 4 bits
                                {byte1[2:0], d[7]},       // G[5:2] -> 4 bits
                                d[4:1]};                   // B[4:1] -> 4 bits
                    
                    // Set address using calculated offset and X coordinate
                    wr_addr <= row_offset + {7'd0, x_count};
                    wr_en   <= 1'b1;
                    
                    byte_toggle <= 1'b0;

                    // Increment X coordinate
                    if (x_count < 9'd319)
                        x_count <= x_count + 9'd1;
                end
            end else begin
                byte_toggle <= 1'b0; // Ensure reset if HREF drops unexpectedly
            end
        end
    end

endmodule
