//============================================================================
// Module: top
// Description: Top-level module for Real-Time Video Capture and Processing System
//              Wires together all sub-modules:
//                - clk_wiz:       Clock generation (25MHz VGA, 24MHz XCLK)
//                - ov7670_init:   Camera initialization sequencer
//                - sccb_master:   SCCB protocol controller
//                - ov7670_capture: Pixel capture from camera
//                - frame_buffer:  Dual-port BRAM (single-bank)
//                - vga_sync:      VGA timing generator
//                - vga_display:   Frame buffer reader + filter + VGA output
//
// Target: Basys 3 (Xilinx Artix-7 xc7a35tcpg236-1)
//
// CRITICAL FIX: SDA tristate is handled HERE at the top level,
//   not inside sccb_master. sccb_master outputs sda_out + sda_oe.
//============================================================================

module top (
    input  wire        clk100,       // Basys 3 100MHz oscillator
    // Camera inputs
    input  wire        cam_pclk,     // OV7670 pixel clock output
    input  wire        cam_href,     // OV7670 horizontal reference
    input  wire        cam_vsync,    // OV7670 vertical sync
    input  wire [7:0]  cam_d,        // OV7670 data bus D[7:0]
    // Camera outputs
    output wire        cam_xclk,     // Master clock to OV7670 (24MHz)
    output wire        cam_pwdn,     // OV7670 power down (active high)
    output wire        cam_rst,      // OV7670 reset (active low)
    output wire        cam_scl,      // SCCB clock
    inout  wire        cam_sda,      // SCCB data (bidirectional)
    // VGA outputs
    output wire        vga_hsync,    // VGA horizontal sync
    output wire        vga_vsync,    // VGA vertical sync
    output wire [3:0]  vga_r,        // VGA red channel [3:0]
    output wire [3:0]  vga_g,        // VGA green channel [3:0]
    output wire [3:0]  vga_b,        // VGA blue channel [3:0]
    // User controls
    input  wire [1:0]  sw,           // Filter selection
    output wire [3:0]  led           // Hardware Debugging LEDs
);

    //------------------------------------------------------------------------
    // Internal wires
    //------------------------------------------------------------------------
    // Clock domain signals
    wire clk_25mhz;        // 25MHz VGA pixel clock
    wire clk_24mhz;        // 24MHz camera XCLK
    wire mmcm_locked;      // MMCM lock status

    // System reset: active high, de-asserts when MMCM is locked
    wire sys_rst = ~mmcm_locked;

    //------------------------------------------------------------------------
    // Reset synchronizers (CDC for reset signal)
    // sys_rst originates in the MMCM/clk100 domain. It must be synchronized
    // into each destination clock domain with a 2-flop synchronizer to
    // prevent metastability on de-assertion.
    //------------------------------------------------------------------------

    // 25MHz VGA domain reset synchronizer
    reg rst_25_meta, rst_25_sync;
    always @(posedge clk_25mhz or posedge sys_rst) begin
        if (sys_rst) begin
            rst_25_meta <= 1'b1;
            rst_25_sync <= 1'b1;
        end else begin
            rst_25_meta <= 1'b0;
            rst_25_sync <= rst_25_meta;
        end
    end

    // PCLK camera domain reset synchronizer
    // Uses negedge because capture samples on negedge
    reg rst_pclk_meta, rst_pclk_sync;
    always @(negedge cam_pclk or posedge sys_rst) begin
        if (sys_rst) begin
            rst_pclk_meta <= 1'b1;
            rst_pclk_sync <= 1'b1;
        end else begin
            rst_pclk_meta <= 1'b0;
            rst_pclk_sync <= rst_pclk_meta;
        end
    end

    //------------------------------------------------------------------------
    // SCCB interface wires
    //------------------------------------------------------------------------
    wire       sccb_start;
    wire [7:0] sccb_addr;
    wire [7:0] sccb_data;
    wire       sccb_done;
    wire       sccb_scl;
    wire       sccb_sda_out;
    wire       sccb_sda_oe;

    // Camera initialization wires
    wire       cam_rst_from_init;
    wire       init_done;

    // Capture to frame buffer wires (single-bank)
    wire [16:0] cap_wr_addr;
    wire [11:0] cap_wr_data;
    wire        cap_wr_en;

    // Frame buffer to VGA display wires (single-bank)
    wire [16:0] vga_rd_addr;
    wire [11:0] vga_rd_data;

    // VGA sync wires
    wire [9:0]  hcount;
    wire [9:0]  vcount;
    wire        hactive;
    wire        vactive;
    wire        hsync_wire;
    wire        vsync_wire;

    //------------------------------------------------------------------------
    // Camera control outputs
    //------------------------------------------------------------------------
    assign cam_xclk = clk_24mhz;           // Drive 24MHz XCLK to camera
    assign cam_pwdn = 1'b0;                 // Power down = 0 (normal operation)
    assign cam_rst  = cam_rst_from_init;    // RST controlled by init sequencer
    assign cam_scl  = sccb_scl;             // SCCB clock to camera

    //------------------------------------------------------------------------
    // SDA tristate control — CRITICAL: done at top level
    // When sda_oe=1: drive sda_out value to the pin
    // When sda_oe=0: release pin (high-Z, external pull-up pulls high)
    //------------------------------------------------------------------------
    assign cam_sda = sccb_sda_oe ? sccb_sda_out : 1'bz;

    //------------------------------------------------------------------------
    // VGA sync outputs — delayed by 2 clock cycles
    // The vga_display module has a 2-cycle latency:
    //   1 cycle for BRAM read
    //   1 cycle for vga_r/g/b output register
    // Therefore, hsync and vsync must be delayed by 2 cycles to remain aligned.
    //------------------------------------------------------------------------
    reg hsync_d1, vsync_d1;
    reg hsync_d2, vsync_d2;
    always @(posedge clk_25mhz) begin
        if (rst_25_sync) begin
            hsync_d1 <= 1'b1;
            vsync_d1 <= 1'b1;
            hsync_d2 <= 1'b1;
            vsync_d2 <= 1'b1;
        end else begin
            hsync_d1 <= hsync_wire;
            vsync_d1 <= vsync_wire;
            hsync_d2 <= hsync_d1;
            vsync_d2 <= vsync_d1;
        end
    end
    assign vga_hsync = hsync_d2;
    assign vga_vsync = vsync_d2;

    //========================================================================
    // Hardware Debugging (LEDs)
    //========================================================================
    assign led[0] = init_done;           // High when camera initialized
    assign led[1] = cam_vsync;           // Blinks when camera sends frames
    assign led[2] = cam_href;            // Should be dimly lit (pulse width ~50%)
    assign led[3] = cam_pclk;            // Should be dimly lit (24MHz clock)

    //========================================================================
    // Module Instantiations
    //========================================================================

    //------------------------------------------------------------------------
    // 1. Clock Wizard — generates 25MHz (VGA) and 24MHz (camera XCLK)
    //------------------------------------------------------------------------
    clk_wiz u_clk_wiz (
        .clk_in    (clk100),
        .rst       (1'b0),           // Don't reset MMCM on system reset
        .clk_25mhz (clk_25mhz),
        .clk_24mhz (clk_24mhz),
        .locked    (mmcm_locked)
    );

    //------------------------------------------------------------------------
    // 2. SCCB Master — I2C-like protocol controller for camera configuration
    //    CRITICAL: sda_out and sda_oe are separate outputs.
    //    Tristate is handled above with: cam_sda = sda_oe ? sda_out : 1'bz
    //------------------------------------------------------------------------
    sccb_master u_sccb (
        .clk     (clk100),            // Runs on 100MHz system clock
        .rst     (sys_rst),
        .start   (sccb_start),
        .addr    (sccb_addr),
        .data    (sccb_data),
        .done    (sccb_done),
        .scl     (sccb_scl),
        .sda_out (sccb_sda_out),
        .sda_oe  (sccb_sda_oe)
    );

    //------------------------------------------------------------------------
    // 3. OV7670 Initialization Sequencer — configures camera registers
    //------------------------------------------------------------------------
    ov7670_init u_init (
        .clk        (clk100),        // Runs on 100MHz system clock
        .rst        (sys_rst),
        .sccb_start (sccb_start),
        .sccb_addr  (sccb_addr),
        .sccb_data  (sccb_data),
        .sccb_done  (sccb_done),
        .cam_rst_out(cam_rst_from_init),
        .init_done  (init_done)
    );

    //------------------------------------------------------------------------
    // 4. OV7670 Capture — captures pixel data from camera
    //    Clocked on cam_pclk (camera pixel clock domain)
    //    Single-bank: 17-bit address, 12-bit RGB444 data
    //------------------------------------------------------------------------
    ov7670_capture u_capture (
        .pclk    (cam_pclk),
        .rst     (rst_pclk_sync),   // Use PCLK-domain synchronized reset
        .href    (cam_href),
        .vsync   (cam_vsync),
        .d       (cam_d),
        .wr_addr (cap_wr_addr),
        .wr_data (cap_wr_data),
        .wr_en   (cap_wr_en)
    );

    //------------------------------------------------------------------------
    // 5. Frame Buffer — dual-port BRAM (single-bank)
    //    Port A (write): clocked on cam_pclk (posedge), driven by ov7670_capture
    //    Port B (read):  clocked on clk_25mhz, read by vga_display
    //------------------------------------------------------------------------
    frame_buffer u_fbuf (
        .clk_wr  (cam_pclk),
        .we      (cap_wr_en),
        .wr_addr (cap_wr_addr),
        .wr_data (cap_wr_data),
        .clk_rd  (clk_25mhz),
        .rd_addr (vga_rd_addr),
        .rd_data (vga_rd_data)
    );

    //------------------------------------------------------------------------
    // 6. VGA Sync Generator — generates 640x480 @ 60Hz timing signals
    //    Clocked on 25MHz VGA pixel clock
    //------------------------------------------------------------------------
    vga_sync u_vga_sync (
        .clk     (clk_25mhz),
        .rst     (rst_25_sync),     // Use 25MHz-domain synchronized reset
        .hsync   (hsync_wire),
        .vsync   (vsync_wire),
        .hactive (hactive),
        .vactive (vactive),
        .hcount  (hcount),
        .vcount  (vcount)
    );

    //------------------------------------------------------------------------
    // 7. VGA Display — reads frame buffer, applies filter, drives VGA output
    //    Clocked on 25MHz VGA pixel clock
    //    image_filter is instantiated inside vga_display
    //------------------------------------------------------------------------
    vga_display u_vga_display (
        .clk     (clk_25mhz),
        .rst     (rst_25_sync),
        .hcount  (hcount),
        .vcount  (vcount),
        .hactive (hactive),
        .vactive (vactive),
        .sw      (sw),
        .rd_addr (vga_rd_addr),
        .rd_data (vga_rd_data),
        .vga_r   (vga_r),
        .vga_g   (vga_g),
        .vga_b   (vga_b)
    );

endmodule
