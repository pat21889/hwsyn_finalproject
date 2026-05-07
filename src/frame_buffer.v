//============================================================================
// Module: frame_buffer
// Description: True Dual-Port Block RAM for frame buffer storage.
//              Single-bank architecture: 320x240 = 76,800 pixels.
//
//              Width:  12 bits (RGB444)
//              Depth:  76,800 addresses (0 to 76799)
//              Memory: 921,600 bits ≈ 922 Kbits (fits in Basys 3's 1800 Kbits)
//
// Write port (Port A): camera PCLK domain
//   - Clocked on POSEDGE of clk_wr (cam_pclk)
//   - ov7670_capture sets wr_en/wr_addr/wr_data at negedge pclk,
//     so they are stable and valid at the next posedge pclk.
//
// Read port (Port B): VGA 25MHz domain
//   - Clocked on POSEDGE of clk_rd
//   - Synchronous read: rd_data valid ONE cycle after rd_addr is set
//
// Clock Domain Crossing:
//   Handled inherently by the dual-port BRAM (different clocks per port).
//   A pixel may glitch during simultaneous read/write to the same address,
//   but no data corruption — this is acceptable for video.
//============================================================================

module frame_buffer (
    // Port A: Write port (camera domain)
    input  wire        clk_wr,      // Camera PCLK write clock
    input  wire        we,          // Write enable (active high)
    input  wire [16:0] wr_addr,     // Write address (0 to 76799)
    input  wire [11:0] wr_data,     // Write data (RGB444)

    // Port B: Read port (VGA domain)
    input  wire        clk_rd,      // VGA 25MHz read clock
    input  wire [16:0] rd_addr,     // Read address (0 to 76799)
    output reg  [11:0] rd_data      // Read data (RGB444), valid 1 cycle after rd_addr
);

    //------------------------------------------------------------------------
    // BRAM Array: 76800 entries x 12 bits
    // Xilinx Vivado infers RAMB36 primitives from this pattern:
    //   (* ram_style = "block" *) + two separate clocked always blocks
    //------------------------------------------------------------------------
    (* ram_style = "block" *) reg [11:0] mem [0:76799];

    //------------------------------------------------------------------------
    // Port A: Write — posedge of cam_pclk
    // ov7670_capture writes wr_en/wr_addr/wr_data on negedge pclk,
    // so all signals are stable well before this posedge.
    //------------------------------------------------------------------------
    always @(posedge clk_wr) begin
        if (we) begin
            mem[wr_addr] <= wr_data;
        end
    end

    //------------------------------------------------------------------------
    // Port B: Synchronous Read — posedge of VGA clock (25MHz)
    // rd_data is available ONE cycle after rd_addr is presented.
    // vga_display accounts for this 1-cycle latency by using hactive_d.
    //------------------------------------------------------------------------
    always @(posedge clk_rd) begin
        rd_data <= mem[rd_addr];
    end

endmodule
