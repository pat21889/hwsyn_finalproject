//============================================================================
// Module: ov7670_capture
// Description: OV7670 Pixel Capture — based on proven working reference design.
//              Uses shift-register data latching and wr_hold pipeline.
//============================================================================

module ov7670_capture (
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,
    output wire [16:0] addr,
    output wire [11:0] dout,
    output reg         we
);

    reg [15:0] d_latch;
    reg [11:0] dout_reg;
    reg [1:0]  wr_hold;

    // X/Y coordinates
    reg [9:0] x;
    reg [9:0] y;

    assign addr = y * 320 + x;
    assign dout = dout_reg;

    reg href_prev;
 
    always @(posedge pclk) begin
        if (vsync) begin
            // During VSYNC high: continuously reset (level-sensitive, NOT edge)
            x       <= 0;
            y       <= 0;
            wr_hold <= 0;
            we      <= 0;
            href_prev <= 0;
        end else begin
            href_prev <= href;
 
            // Start of a new line: Reset horizontal counter
            if (href && !href_prev) begin
                x <= 0;
            end
 
            // End of a line: Increment vertical counter
            if (!href && href_prev) begin
                if (y < 239) y <= y + 1;
                else         y <= 0;
            end
 
            // Standard MSB-first shift order (Correct Byte Alignment)
            d_latch <= {d_latch[7:0], d};
 
            // wr_hold is a 2-stage pipeline that toggles every other clock
            wr_hold <= {wr_hold[0], (href && !wr_hold[0])};
 
            // Write enable is delayed by 1 cycle from wr_hold[1]
            // Also clip writing if x exceeds frame width
            we <= wr_hold[1] && (x < 320);
 
            if (wr_hold[1]) begin
                // RGB565 to RGB444 down-conversion
                dout_reg <= {d_latch[15:12], d_latch[10:7], d_latch[4:1]};
 
                // Increment position only if within bounds
                if (x < 320) begin
                    x <= x + 1;
                end
            end
        end
    end
endmodule
