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

    //------------------------------------------------------------------------
    // Internal wires for MMCM
    //------------------------------------------------------------------------
    wire clkfb;          // Feedback clock
    wire clk_25_unbuf;   // Unbuffered 25MHz
    wire clk_24_unbuf;   // Unbuffered 24MHz

    //------------------------------------------------------------------------
    // MMCM Primitive Instantiation
    // Artix-7 MMCME2_BASE
    //
    // VCO = CLKIN * CLKFBOUT_MULT_F / DIVCLK_DIVIDE = 100 * 12.0 / 1 = 1200 MHz
    // CLKOUT0 = VCO / CLKOUT0_DIVIDE_F = 1200 / 48.0 = 25.0 MHz
    // CLKOUT1 = VCO / CLKOUT1_DIVIDE   = 1200 / 50   = 24.0 MHz
    //------------------------------------------------------------------------
    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),   // Jitter programming
        .CLKFBOUT_MULT_F    (12.0),          // VCO multiplier (VCO = 1200 MHz)
        .CLKFBOUT_PHASE     (0.0),           // Feedback clock phase
        .CLKIN1_PERIOD       (10.0),          // Input clock period (100 MHz = 10 ns)
        .CLKOUT0_DIVIDE_F   (48.0),          // CLKOUT0 divide (1200/48 = 25 MHz)
        .CLKOUT0_DUTY_CYCLE (0.5),           // 50% duty cycle
        .CLKOUT0_PHASE      (0.0),           // No phase shift
        .CLKOUT1_DIVIDE     (50),            // CLKOUT1 divide (1200/50 = 24 MHz)
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT2_DIVIDE     (1),             // Unused outputs
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT6_DIVIDE     (1),
        .DIVCLK_DIVIDE      (1),             // Input clock divide
        .REF_JITTER1        (0.010),         // Input jitter estimate
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        // Clock outputs
        .CLKOUT0  (clk_25_unbuf),
        .CLKOUT0B (),                        // Unused inverted outputs
        .CLKOUT1  (clk_24_unbuf),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        // Feedback
        .CLKFBOUT  (clkfb),
        .CLKFBOUTB (),
        // Status and control
        .LOCKED    (locked),
        .PWRDWN    (1'b0),                   // Not powered down
        .RST       (rst),                    // Reset input
        // Clock input
        .CLKIN1    (clk_in),
        .CLKFBIN   (clkfb)                  // Feedback clock input
    );

    //------------------------------------------------------------------------
    // Global clock buffers for output clocks
    // BUFG ensures the clocks are routed on the global clock network
    //------------------------------------------------------------------------
    BUFG u_bufg_25 (
        .I (clk_25_unbuf),
        .O (clk_25mhz)
    );

    BUFG u_bufg_24 (
        .I (clk_24_unbuf),
        .O (clk_24mhz)
    );

endmodule
