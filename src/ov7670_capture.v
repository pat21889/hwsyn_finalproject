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
// BRAM timing:
//   - Capture logic runs on negedge pclk
//   - BRAM write port runs on posedge pclk (in frame_buffer.v)
//   - Therefore: wr_addr/wr_data/wr_en set at negedge N are stable at posedge N
//
// CRITICAL ADDRESS FIX:
//   wr_addr must NOT be incremented in the same clock cycle as wr_en=1.
//   Reason: all non-blocking assignments take effect simultaneously, so
//   if we set wr_addr++ and wr_en=1 at negedge N, the BRAM sees the
//   incremented address at posedge N — writing pixel_N to addr_N+1 (WRONG).
//   Fix: register wr_en and increment addr ONE cycle after the write.
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
    reg       wr_en_prev;     // Previous wr_en — used to increment addr one cycle late

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
            wr_en_prev  <= 1'b0;
            byte1       <= 8'd0;
            byte_toggle <= 1'b0;
            vsync_prev  <= 1'b0;
        end else begin
            vsync_prev <= vsync;
            wr_en_prev <= wr_en;   // Register previous wr_en
            wr_en      <= 1'b0;    // Default: no write this cycle

            //----------------------------------------------------------------
            // Increment address ONE CYCLE AFTER a write completed.
            // wr_en_prev is the value from the previous clock edge.
            // At that edge, BRAM wrote to the current wr_addr (at posedge),
            // so now it's safe to advance wr_addr for the next pixel.
            //----------------------------------------------------------------
            if (wr_en_prev && !vsync_rising) begin
                if (wr_addr < 17'd76799)
                    wr_addr <= wr_addr + 17'd1;
            end

            //----------------------------------------------------------------
            // VSYNC rising edge: reset write address for new frame.
            // This NBA overrides the increment above (last NBA wins).
            //----------------------------------------------------------------
            if (vsync_rising) begin
                wr_addr     <= 17'd0;
                byte_toggle <= 1'b0;
                wr_en_prev  <= 1'b0;
            end

            //----------------------------------------------------------------
            // HREF high: valid pixel data on D[7:0]
            //----------------------------------------------------------------
            if (href) begin
                if (~byte_toggle) begin
                    // First byte: latch it, wait for second byte
                    byte1       <= d;
                    byte_toggle <= 1'b1;
                end else begin
                    // Second byte: assemble RGB565 -> downsample to RGB444
                    // byte1 = {R[4:0], G[5:3]}
                    // d     = {G[2:0], B[4:0]}
                    // RGB444: R = R[4:1], G = G[5:2], B = B[4:1]
                    wr_data <= {byte1[7:4],           // R[4:1] -> 4 bits
                                {byte1[2:0], d[7]},   // G[5:2] -> 4 bits
                                d[4:1]};               // B[4:1] -> 4 bits
                    wr_en       <= 1'b1;
                    // NOTE: wr_addr is NOT incremented here.
                    //       It will be incremented at the NEXT negedge
                    //       (when wr_en_prev=1 is detected above).
                    byte_toggle <= 1'b0;
                end
            end else begin
                byte_toggle <= 1'b0; // Reset when HREF drops
            end
        end
    end

endmodule
