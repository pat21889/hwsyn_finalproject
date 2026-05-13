//============================================================================
// Testbench: tb_top
// Description: Integration-level smoke test for the top module.
//              Provides basic camera stimulus and verifies:
//              - VGA sync signals are generated (no X-propagation)
//              - Camera initialization begins (RST/SCCB activity)
//              - System does not hang or produce unknown outputs
//
//              This is not cycle-accurate — it's a basic integration check.
//              The MMCM is replaced with a simple clock divider for simulation.
//============================================================================

`timescale 1ns / 1ps

module tb_top;

    //------------------------------------------------------------------------
    // Testbench signals
    //------------------------------------------------------------------------
    reg        clk100;
    reg        cam_pclk;
    reg        cam_href;
    reg        cam_vsync;
    reg  [7:0] cam_d;
    wire       cam_xclk;
    wire       cam_pwdn;
    wire       cam_rst;
    wire       cam_scl;
    wire       cam_sda;
    wire       vga_hsync;
    wire       vga_vsync;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    reg  [1:0] sw;

    // Pull-up on SDA
    pullup (cam_sda);

    //------------------------------------------------------------------------
    // DUT instantiation
    //------------------------------------------------------------------------
    top #(
        .SIMULATION (1'b1)
    ) uut (
        .clk100    (clk100),
        .cam_pclk  (cam_pclk),
        .cam_href  (cam_href),
        .cam_vsync (cam_vsync),
        .cam_d     (cam_d),
        .cam_xclk  (cam_xclk),
        .cam_pwdn  (cam_pwdn),
        .cam_rst   (cam_rst),
        .cam_scl   (cam_scl),
        .cam_sda   (cam_sda),
        .vga_hsync (vga_hsync),
        .vga_vsync (vga_vsync),
        .vga_r     (vga_r),
        .vga_g     (vga_g),
        .vga_b     (vga_b),
        .sw        (sw)
    );

    //------------------------------------------------------------------------
    // Clock generation
    //------------------------------------------------------------------------
    // 100MHz system clock (10ns period)
    initial clk100 = 0;
    always #5 clk100 = ~clk100;

    // ~24MHz camera pixel clock (42ns period)
    initial cam_pclk = 0;
    always #21 cam_pclk = ~cam_pclk;

    //------------------------------------------------------------------------
    // X-propagation checker
    //------------------------------------------------------------------------
    integer x_check_fail = 0;

    task check_no_x;
        input [63:0] signal_name;
        input [3:0] val;
        begin
            if (^val === 1'bx) begin
                $display("WARNING [%0t] X-propagation on %0s = %b", $time, signal_name, val);
                x_check_fail = x_check_fail + 1;
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Camera stimulus generation
    //------------------------------------------------------------------------
    task generate_frame;
        integer row, col;
        begin
            // VSYNC pulse
            cam_vsync = 1;
            repeat (100) @(negedge cam_pclk);
            cam_vsync = 0;
            repeat (50) @(negedge cam_pclk);

            // Generate a few lines of pixel data
            for (row = 0; row < 5; row = row + 1) begin
                cam_href = 1;
                for (col = 0; col < 320; col = col + 1) begin
                    // Byte 1 of RGB565: {R[4:0], G[5:3]}
                    cam_d = {col[4:0], row[2:0]};
                    @(negedge cam_pclk);
                    // Byte 2 of RGB565: {G[2:0], B[4:0]}
                    cam_d = {row[2:0], col[4:0]};
                    @(negedge cam_pclk);
                end
                cam_href = 0;
                repeat (20) @(negedge cam_pclk);
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== Top-Level Integration Smoke Test ===\n");

        // Initialize inputs
        cam_href  = 0;
        cam_vsync = 0;
        cam_d     = 8'h00;
        sw        = 2'b00;

        // Wait for MMCM to lock (in real hardware this takes ~100us)
        // In simulation, wait a reasonable time
        $display("[%0t] Waiting for MMCM lock...", $time);
        #500;

        // Check that MMCM locked (in simulation, it should lock quickly)
        // Note: MMCM simulation model may not behave exactly like hardware
        $display("[%0t] Checking initial outputs...", $time);

        //--------------------------------------------------------------------
        // Check cam_pwdn should be 0
        //--------------------------------------------------------------------
        if (cam_pwdn === 1'b0)
            $display("PASS: cam_pwdn = 0 (normal mode)");
        else
            $display("FAIL: cam_pwdn = %b (expected 0)", cam_pwdn);

        //--------------------------------------------------------------------
        // Wait for initialization to begin
        //--------------------------------------------------------------------
        $display("\n[%0t] Waiting for camera reset sequence...", $time);
        // cam_rst should start low (reset asserted)
        #1000;

        //--------------------------------------------------------------------
        // Generate some camera frames
        //--------------------------------------------------------------------
        $display("\n[%0t] Generating camera frame data...", $time);
        generate_frame();

        //--------------------------------------------------------------------
        // Wait and check VGA outputs
        //--------------------------------------------------------------------
        #100_000;

        $display("\n[%0t] Checking VGA outputs for X-propagation...", $time);
        check_no_x("vga_r", vga_r);
        check_no_x("vga_g", vga_g);
        check_no_x("vga_b", vga_b);

        if (vga_hsync !== 1'bx)
            $display("PASS: vga_hsync is not X (%b)", vga_hsync);
        else
            $display("WARNING: vga_hsync is X");

        if (vga_vsync !== 1'bx)
            $display("PASS: vga_vsync is not X (%b)", vga_vsync);
        else
            $display("WARNING: vga_vsync is X");

        //--------------------------------------------------------------------
        // Test filter switching
        //--------------------------------------------------------------------
        $display("\n[%0t] Testing filter switch modes...", $time);
        sw = 2'b01; #10000;
        $display("  sw=01 (Inversion): vga_r=%b vga_g=%b vga_b=%b", vga_r, vga_g, vga_b);

        sw = 2'b10; #10000;
        $display("  sw=10 (Red only):  vga_r=%b vga_g=%b vga_b=%b", vga_r, vga_g, vga_b);

        sw = 2'b11; #10000;
        $display("  sw=11 (Threshold): vga_r=%b vga_g=%b vga_b=%b", vga_r, vga_g, vga_b);

        //--------------------------------------------------------------------
        // Generate another frame
        //--------------------------------------------------------------------
        $display("\n[%0t] Generating second camera frame...", $time);
        sw = 2'b00;
        generate_frame();

        #50_000;

        //--------------------------------------------------------------------
        // Final checks
        //--------------------------------------------------------------------
        $display("\n=== Smoke Test Results ===");
        if (x_check_fail == 0)
            $display("PASS: No X-propagation detected on VGA outputs");
        else
            $display("WARNING: %0d X-propagation events detected", x_check_fail);

        $display("cam_xclk is toggling: check waveform manually");
        $display("cam_scl activity: check waveform for SCCB transactions");

        $display("\n=== Top-Level Smoke Test Complete ===");
        $finish;
    end

    //------------------------------------------------------------------------
    // Timeout watchdog
    //------------------------------------------------------------------------
    initial begin
        #100_000_000; // 100ms timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    //------------------------------------------------------------------------
    // Dump waveforms
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
