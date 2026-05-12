//============================================================================
// Module: top
// Description: Top-level module for Real-Time Video Capture and Processing System
//              Simplified single-bank version for debugging.
//
// Target: Basys 3 (Xilinx Artix-7 xc7a35tcpg236-1)
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
    input  wire [2:0]  sw,           // Filter selection
    output wire [3:0]  led           // Hardware Debugging LEDs
);

    //------------------------------------------------------------------------
    // Internal wires — Clock domain
    //------------------------------------------------------------------------
    wire clk_25mhz;
    wire clk_24mhz;
    wire mmcm_locked;
    wire sys_rst = ~mmcm_locked;

    //------------------------------------------------------------------------
    // Reset synchronizers
    //------------------------------------------------------------------------
    // 25MHz VGA domain
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

    // PCLK camera domain
    reg rst_pclk_meta, rst_pclk_sync;
    always @(posedge cam_pclk or posedge sys_rst) begin
        if (sys_rst) begin
            rst_pclk_meta <= 1'b1;
            rst_pclk_sync <= 1'b1;
        end else begin
            rst_pclk_meta <= 1'b0;
            rst_pclk_sync <= rst_pclk_meta;
        end
    end

    //------------------------------------------------------------------------
    // Internal wires — SCCB
    //------------------------------------------------------------------------
    wire       sccb_start;
    wire [7:0] sccb_addr;
    wire [7:0] sccb_data;
    wire       sccb_done;
    wire       sccb_scl;

    // Camera init
    wire       cam_rst_from_init;
    wire       init_done;

    // Capture to frame buffer
    wire [16:0] cap_wr_addr;
    wire [11:0] cap_wr_data;
    wire        cap_wr_en;

    // Frame buffer to VGA display
    wire [16:0] vga_rd_addr;
    wire [11:0] vga_rd_data;

    // VGA sync
    wire [9:0]  hcount;
    wire [9:0]  vcount;
    wire        hactive;
    wire        vactive;
    wire        hsync_wire;
    wire        vsync_wire;

    //------------------------------------------------------------------------
    // Camera control outputs
    //------------------------------------------------------------------------
    assign cam_xclk = clk_25mhz;            // Drive 25MHz XCLK (reference uses 25MHz, not 24MHz)
    assign cam_pwdn = 1'b0;
    assign cam_rst  = 1'b1;                  // Always not-in-reset (reference: assign reset = 1)
    assign cam_scl  = sccb_scl;

    //------------------------------------------------------------------------
    // VGA sync delay: 2 cycles to match display pipeline latency
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
    assign led[0] = init_done;
    assign led[1] = cam_vsync;
    assign led[2] = cam_href;
    assign led[3] = cam_pclk;

    //========================================================================
    // Module Instantiations
    //========================================================================

    // 1. Clock Wizard
    clk_wiz u_clk_wiz (
        .clk_in    (clk100),
        .rst       (1'b0),
        .clk_25mhz (clk_25mhz),
        .clk_24mhz (clk_24mhz),
        .locked    (mmcm_locked)
    );

    // 2. SCCB Master
    sccb_master u_sccb (
        .clk   (clk100),
        .rst   (sys_rst),
        .start (sccb_start),
        .addr  (sccb_addr),
        .data  (sccb_data),
        .done  (sccb_done),
        .scl   (sccb_scl),
        .sda   (cam_sda)
    );

    // 3. OV7670 Init Sequencer
    ov7670_init u_init (
        .clk        (clk100),
        .rst        (sys_rst),
        .sccb_start (sccb_start),
        .sccb_addr  (sccb_addr),
        .sccb_data  (sccb_data),
        .sccb_done  (sccb_done),
        .cam_rst_out(cam_rst_from_init),
        .init_done  (init_done)
    );

    // 4. OV7670 Capture (reference-based, no reset needed)
    ov7670_capture u_capture (
        .pclk  (cam_pclk),
        .vsync (cam_vsync),
        .href  (cam_href),
        .d     (cam_d),
        .addr  (cap_wr_addr),
        .dout  (cap_wr_data),
        .we    (cap_wr_en)
    );

    // 5. Frame Buffer (simplified single-bank)
    frame_buffer u_fbuf (
        .clk_a  (cam_pclk),
        .we_a   (cap_wr_en),
        .addr_a (cap_wr_addr),
        .din_a  (cap_wr_data),
        .clk_b  (clk_25mhz),
        .addr_b (vga_rd_addr),
        .dout_b (vga_rd_data)
    );

    // 6. VGA Sync Generator
    vga_sync u_vga_sync (
        .clk     (clk_25mhz),
        .rst     (rst_25_sync),
        .hsync   (hsync_wire),
        .vsync   (vsync_wire),
        .hactive (hactive),
        .vactive (vactive),
        .hcount  (hcount),
        .vcount  (vcount)
    );

    // 7. VGA Display (simplified single-bank, nearest-neighbor)
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
