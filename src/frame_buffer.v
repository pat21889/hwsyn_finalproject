//============================================================================
// Module: frame_buffer
// Description: Simple single-bank True Dual-Port Block RAM for frame buffer.
//              Width: 12 bits (RGB444)
//              Depth: 76,800 addresses (320 x 240 pixels)
//
//              Simplified design - no dual-bank, no bilinear.
//              Just get the basic capture-to-display pipeline working.
//============================================================================

module frame_buffer (
    // Port A: Write port (clocked by camera PCLK)
    input  wire        clk_a,       // Camera PCLK (write clock)
    input  wire        we_a,        // Write enable
    input  wire [16:0] addr_a,      // Write address (0 to 76799)
    input  wire [11:0] din_a,       // Write data (RGB444)

    // Port B: Read port (clocked by 25MHz VGA clock)
    input  wire        clk_b,       // VGA pixel clock (read clock)
    input  wire [16:0] addr_b,      // Read address (0 to 76799)
    output reg  [11:0] dout_b       // Read data (RGB444)
);

    //------------------------------------------------------------------------
    // BRAM Array: 76800 x 12 bits
    // 76800 * 12 = 921,600 bits ≈ 922 Kbits (fits in Basys 3's 1800 Kbit BRAM)
    //------------------------------------------------------------------------
    (* ram_style = "block" *) reg [11:0] mem [0:76799];

    //------------------------------------------------------------------------
    // Port A: Write operations
    //------------------------------------------------------------------------
    always @(posedge clk_a) begin
        if (we_a) begin
            mem[addr_a] <= din_a;
        end
    end

    //------------------------------------------------------------------------
    // Port B: Read operations (synchronous read - 1 cycle latency)
    //------------------------------------------------------------------------
    always @(posedge clk_b) begin
        dout_b <= mem[addr_b];
    end

endmodule
