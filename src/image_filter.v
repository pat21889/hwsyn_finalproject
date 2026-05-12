//============================================================================
// Module: image_filter
// Description: Real-time combinational image filter module.
//              Selects between 4 modes via sw[1:0]:
//                00 - Raw pass-through (no filter)
//                01 - Color Inversion (Negative)
//                10 - Red Channel Isolation
//                11 - Thresholding (Binary Black & White)
//
// Input format:  RGB444 = {R[3:0], G[3:0], B[3:0]}
// Output format: RGB444 = {R[3:0], G[3:0], B[3:0]}
//
// This module is purely combinational — no clock, no registers.
//============================================================================

module image_filter #(
    parameter [3:0] THRESHOLD = 4'h8  // Luminance threshold for B&W filter (tunable)
) (
    input  wire [11:0] pixel_in,   // Input pixel: {R[3:0], G[3:0], B[3:0]}
    input  wire [1:0]  sw,         // Filter select switches
    output reg  [11:0] pixel_out   // Output pixel: {R[3:0], G[3:0], B[3:0]}
);

    //------------------------------------------------------------------------
    // Extract individual color channels from input
    //------------------------------------------------------------------------
    wire [3:0] r_in = pixel_in[11:8];
    wire [3:0] g_in = pixel_in[7:4];
    wire [3:0] b_in = pixel_in[3:0];

    //------------------------------------------------------------------------
    // Luminance calculation for thresholding filter
    // Approximation of: Y = 0.299*R + 0.587*G + 0.114*B
    // Using integer math: luma = (R*5 + G*9 + B*2) >> 4
    // This gives a 4-bit luminance value (0-15 range fits naturally)
    //------------------------------------------------------------------------
    wire [7:0] luma_full = (r_in * 4'd5) + (g_in * 4'd9) + (b_in * 4'd2);
    wire [3:0] luma = luma_full[7:4]; // Divide by 16 (>> 4)

    //------------------------------------------------------------------------
    // Filter selection — purely combinational
    //------------------------------------------------------------------------
    always @(*) begin
        case (sw)
            // Mode 00: Raw pass-through — no processing
            2'b00: begin
                pixel_out = pixel_in;
            end

            // Mode 01: Color Inversion (Negative)
            // Each channel is inverted: out = 0xF - in
            2'b01: begin
                pixel_out = {4'hF - r_in, 4'hF - g_in, 4'hF - b_in};
            end

            // Mode 10: Red Channel Isolation
            // Keep red channel, zero out green and blue
            2'b10: begin
                pixel_out = {r_in, 4'h0, 4'h0};
            end

            // Mode 11: Thresholding (Binary / Black & White)
            // Compare luminance against threshold
            // Output white (0xFFF) if above threshold, black (0x000) if below
            2'b11: begin
                if (luma >= THRESHOLD)
                    pixel_out = 12'hFFF; // White
                else
                    pixel_out = 12'h000; // Black
            end

            // Default: pass-through (should never reach here)
            default: begin
                pixel_out = pixel_in;
            end
        endcase
    end

endmodule
