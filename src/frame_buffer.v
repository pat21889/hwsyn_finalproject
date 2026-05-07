//============================================================================
// Module: frame_buffer
// Description: Dual-Bank True Dual-Port Block RAM for frame buffer storage.
//              Bank 0 stores Even rows (0, 2, 4...)
//              Bank 1 stores Odd rows (1, 3, 5...)
//
//              This dual-bank architecture allows the VGA display engine to
//              read two vertical neighbors simultaneously for bilinear filtering.
//
//              Width: 12 bits (RGB444) per bank
//              Depth: 38,400 addresses (320 x 120 pixels) per bank
//              Total: 921,600 bits ≈ 922 Kbits (fits in Basys 3's 1800 Kbit BRAM)
//============================================================================

module frame_buffer (
    // Port A: Write port (clocked by camera PCLK)
    input  wire        clk_a,       // Camera PCLK (write clock)
    input  wire        we_a,        // Write enable
    input  wire        bank_sel_a,  // Bank select (0=Even, 1=Odd)
    input  wire [15:0] addr_a,      // Write address (0 to 38399)
    input  wire [11:0] din_a,       // Write data (RGB444)

    // Port B: Read port (clocked by 25MHz VGA clock)
    input  wire        clk_b,       // VGA pixel clock (read clock)
    input  wire [15:0] addr_even_b, // Read address for Even Bank
    input  wire [15:0] addr_odd_b,  // Read address for Odd Bank
    output reg  [11:0] dout_even_b, // Read data from Even Bank (Bank 0)
    output reg  [11:0] dout_odd_b   // Read data from Odd Bank (Bank 1)
);

    //------------------------------------------------------------------------
    // BRAM Arrays: 38400 x 12 bits each
    //------------------------------------------------------------------------
    (* ram_style = "block" *) reg [11:0] bank_even [0:38399];
    (* ram_style = "block" *) reg [11:0] bank_odd  [0:38399];

    //------------------------------------------------------------------------
    // Port A: Write operations (clocked on camera PCLK)
    //------------------------------------------------------------------------
    always @(negedge clk_a) begin
        if (we_a) begin
            if (bank_sel_a == 1'b0) begin
                bank_even[addr_a] <= din_a;
            end else begin
                bank_odd[addr_a]  <= din_a;
            end
        end
    end

    //------------------------------------------------------------------------
    // Port B: Read operations (clocked on 25MHz VGA clock)
    // Synchronous read — data appears one clock cycle after address is set.
    // Both banks are read simultaneously.
    //------------------------------------------------------------------------
    always @(posedge clk_b) begin
        dout_even_b <= bank_even[addr_even_b];
        dout_odd_b  <= bank_odd[addr_odd_b];
    end

endmodule
