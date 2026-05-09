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

    always @(posedge pclk) begin
        if (vsync) begin
            // During VSYNC high: continuously reset (level-sensitive, NOT edge)
            x       <= 0;
            y       <= 0;
            wr_hold <= 0;
            we      <= 0;
        end else begin
            // Shift in data bytes — reverse order to test byte swap fix
            // If camera sends byte1=GGGG_BBBB first, byte2=0000_RRRR second:
            // d_latch = {byte2, byte1} = {0000_RRRR, GGGG_BBBB}
            d_latch <= {d, d_latch[15:8]};

            // wr_hold is a 2-stage pipeline that toggles every other clock
            // when href is high, creating a write pulse every 2 PCLKs
            wr_hold <= {wr_hold[0], (href && !wr_hold[0])};

            // Write enable is delayed by 1 cycle from wr_hold[1]
            we <= wr_hold[1];

            if (wr_hold[1]) begin
                // RGB444 Native: d_latch = {0000_RRRR, GGGG_BBBB}
                // d_latch[11:0] = {R[3:0], G[3:0], B[3:0]}
                dout_reg <= d_latch[11:0];

                // Increment position (row-major order)
                if (x < 319) begin
                    x <= x + 1;
                end else begin
                    x <= 0;
                    if (y < 239)
                        y <= y + 1;
                    else
                        y <= 0;
                end
            end
        end
    end

endmodule
