//============================================================================
// Module: frame_buffer
// Description: True Dual-Port Block RAM for frame buffer storage.
//              Single-bank architecture matching the simplified capture module.
//
//              Width: 12 bits (RGB444)
//              Depth: 76,800 addresses (320 x 240 pixels)
//              Total: 921,600 bits ≈ 922 Kbits (fits in Basys 3's 1800 Kbit BRAM)
//
// Port A: Write port — clocked by camera PCLK (negedge, since capture
//         produces data on negedge; BRAM write uses posedge for hold time)
// Port B: Read port — clocked by 25MHz VGA pixel clock
//
// Clock domain crossing is inherently handled by the dual-port BRAM nature.
//============================================================================

module frame_buffer (
    // Port A: Write port (camera domain)
    input  wire        clk_wr,      // Camera PCLK (write clock)
    input  wire        we,          // Write enable
    input  wire [16:0] wr_addr,     // Write address (0 to 76799)
    input  wire [11:0] wr_data,     // Write data (RGB444)

    // Port B: Read port (VGA domain)
    input  wire        clk_rd,      // VGA 25MHz pixel clock (read clock)
    input  wire [16:0] rd_addr,     // Read address (0 to 76799)
    output reg  [11:0] rd_data      // Read data (RGB444)
);

    //------------------------------------------------------------------------
    // BRAM Array: 76800 x 12 bits
    // Use Xilinx block RAM inference attribute
    //------------------------------------------------------------------------
    (* ram_style = "block" *) reg [11:0] mem [0:76799];

    //------------------------------------------------------------------------
    // Port A: Write operations
    // Write on posedge of PCLK. The capture module produces wr_en/wr_data
    // on negedge pclk, so they are stable well before posedge — ensuring
    // proper setup time for the BRAM write port.
    //------------------------------------------------------------------------
    always @(posedge clk_wr) begin
        if (we) begin
            mem[wr_addr] <= wr_data;
        end
    end

    //------------------------------------------------------------------------
    // Port B: Read operations (clocked on 25MHz VGA clock)
    // Synchronous read — data appears one clock cycle after address is set.
    //------------------------------------------------------------------------
    always @(posedge clk_rd) begin
        rd_data <= mem[rd_addr];
    end

endmodule
