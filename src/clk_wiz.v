//============================================================================
// Module: clk_wiz
// Description: Clock Management using Xilinx MMCM (Mixed-Mode Clock Manager)
//              Generates two output clocks from 100MHz input:
//                - clk_25mhz: 25MHz for VGA pixel clock
//                - clk_24mhz: 24MHz for OV7670 XCLK
//
// If using Vivado Clocking Wizard IP instead, this file can be replaced
// by the generated IP. See the Vivado Guide section for IP configuration.
//
// MMCM Configuration:
//   Input:  100 MHz (CLKIN1_PERIOD = 10.000 ns)
//   VCO:    Must be in range 600-1200 MHz for Artix-7
//
//   For 25MHz output:
//     VCO = 100 MHz * CLKFBOUT_MULT_F / DIVCLK_DIVIDE
//     Choose CLKFBOUT_MULT_F = 10.0, DIVCLK_DIVIDE = 1 -> VCO = 1000 MHz
//     CLKOUT0_DIVIDE_F = 1000/25 = 40.0
//
//   For 24MHz output:
//     CLKOUT1_DIVIDE = 1000/24 ≈ 41.667 -> use integer 42 (gives ~23.81MHz)
//     Or use fractional: not available on CLKOUT1
//     Alternative: CLKFBOUT_MULT_F=12.0 -> VCO=1200MHz
//       CLKOUT0_DIVIDE_F = 1200/25 = 48.0
//       CLKOUT1_DIVIDE = 1200/24 = 50 -> exactly 24MHz!
//
//   Final choice: MULT=12, VCO=1200MHz
//     CLKOUT0: 1200/48 = 25.0 MHz (exact)
//     CLKOUT1: 1200/50 = 24.0 MHz (exact)
//============================================================================

module clk_wiz (
    input  wire clk_in,       // 100MHz input clock
    input  wire rst,          // Reset (active high)
    output wire clk_25mhz,    // 25MHz VGA pixel clock
    output wire clk_24mhz,    // 24MHz OV7670 XCLK
    output wire locked        // MMCM lock indicator
);

`ifdef SIMULATION
    //------------------------------------------------------------------------
    // Behavioral Model for Simulation (Simplifies Clock Generation)
    //------------------------------------------------------------------------
    reg [1:0] count_4 = 0;
    
    // 100MHz / 4 = 25MHz
    always @(posedge clk_in) begin
        if (rst) count_4 <= 0;
        else count_4 <= count_4 + 1;
    end
    assign clk_25mhz = count_4[1];

    // For simulation, 24MHz and 25MHz can be treated as same-phase if needed,
    // or we can use a fractional-style toggle if precision is required.
    // For now, simple 25MHz behavior is used for simulation stability.
    assign clk_24mhz = count_4[1]; 

    assign locked = !rst;

`else
    //------------------------------------------------------------------------
    // Hardware Model (Xilinx Primitives)
    //------------------------------------------------------------------------
    wire clkfb;          // Feedback clock
    wire clk_25_unbuf;   // Unbuffered 25MHz
    wire clk_24_unbuf;   // Unbuffered 24MHz

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (12.0),
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD       (10.0),
        .CLKOUT0_DIVIDE_F   (48.0),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (50),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKOUT0  (clk_25_unbuf),
        .CLKOUT1  (clk_24_unbuf),
        .CLKFBOUT  (clkfb),
        .LOCKED    (locked),
        .PWRDWN    (1'b0),
        .RST       (rst),
        .CLKIN1    (clk_in),
        .CLKFBIN   (clkfb)
    );

    BUFG u_bufg_25 ( .I (clk_25_unbuf), .O (clk_25mhz) );
    BUFG u_bufg_24 ( .I (clk_24_unbuf), .O (clk_24mhz) );
`endif

endmodule
