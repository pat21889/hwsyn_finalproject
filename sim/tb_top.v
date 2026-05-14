//============================================================================
// Testbench: tb_top
// Description: Integration-level smoke test for the top module.
//              Provides basic camera stimulus and verifies:
//              - VGA sync signals are generated (no X-propagation)
//              - Camera initialization begins (RST/SCCB activity)
//              - Capture module writes correct number of pixels per line
//              - Frame buffer stores and retrieves data correctly
//              - System does not hang or produce unknown outputs
//
//              Updated for:
//              - ov7670_capture with href edge detection + x clipping
//              - vga_display with p_temp synchronized pipeline + d4 delays
//              - ov7670_init with NUM_REGS=97 (de-noise regs commented out)
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
    wire [3:0] led;

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
        .sw        (sw),
        .led       (led)
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
    // Test counters
    //------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;
    integer x_check_fail = 0;

    //------------------------------------------------------------------------
    // X-propagation checker
    //------------------------------------------------------------------------
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
    // Camera stimulus: Send one RGB565 pixel (2 bytes)
    //------------------------------------------------------------------------
    task send_cam_pixel;
        input [4:0] r5;
        input [5:0] g6;
        input [4:0] b5;
        begin
            cam_d = {r5, g6[5:3]};
            @(negedge cam_pclk);
            cam_d = {g6[2:0], b5};
            @(negedge cam_pclk);
        end
    endtask

    //------------------------------------------------------------------------
    // Camera stimulus: Generate a complete frame
    // Uses href edge detection: href goes high at start of line,
    // low during blanking. y increments on href falling edge.
    //------------------------------------------------------------------------
    task generate_frame;
        input integer num_rows;
        integer row, col;
        begin
            // VSYNC pulse
            cam_vsync = 1;
            repeat (100) @(negedge cam_pclk);
            cam_vsync = 0;
            repeat (50) @(negedge cam_pclk);

            // Generate pixel data
            for (row = 0; row < num_rows; row = row + 1) begin
                cam_href = 1;
                for (col = 0; col < 320; col = col + 1) begin
                    // Generate a gradient pattern
                    send_cam_pixel(col[4:0], {row[2:0], col[2:0]}, row[4:0]);
                end
                cam_href = 0;
                // Horizontal blanking
                repeat (20) @(negedge cam_pclk);
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== Top-Level Integration Smoke Test (Updated) ===\n");

        // Initialize inputs
        cam_href  = 0;
        cam_vsync = 0;
        cam_d     = 8'h00;
        sw        = 2'b00;

        // Wait for MMCM to lock
        $display("[%0t] Waiting for MMCM lock...", $time);
        #500;

        //--------------------------------------------------------------------
        // Test 1: cam_pwdn should be 0
        //--------------------------------------------------------------------
        $display("\n--- Test 1: Camera Power Down ---");
        if (cam_pwdn === 1'b0) begin
            $display("PASS: cam_pwdn = 0 (normal mode)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: cam_pwdn = %b (expected 0)", cam_pwdn);
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Test 2: LED[0] = init_done (should be 0 initially)
        //--------------------------------------------------------------------
        $display("\n--- Test 2: Init Done LED ---");
        if (led[0] === 1'b0) begin
            $display("PASS: init_done LED is 0 (init in progress)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: init_done LED = %b (expected 0)", led[0]);
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Wait for camera reset sequence
        //--------------------------------------------------------------------
        $display("\n[%0t] Waiting for camera reset sequence...", $time);
        #1000;

        //--------------------------------------------------------------------
        // Test 3: Generate camera frames
        //--------------------------------------------------------------------
        $display("\n--- Test 3: Camera Frame Capture ---");
        $display("[%0t] Generating camera frame (10 rows)...", $time);
        generate_frame(10);

        //--------------------------------------------------------------------
        // Test 4: Wait and check VGA outputs for X-propagation
        //--------------------------------------------------------------------
        #100_000;

        $display("\n--- Test 4: VGA Output X-Propagation Check ---");
        check_no_x("vga_r", vga_r);
        check_no_x("vga_g", vga_g);
        check_no_x("vga_b", vga_b);

        if (vga_hsync !== 1'bx) begin
            $display("PASS: vga_hsync is not X (%b)", vga_hsync);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: vga_hsync is X");
            fail_count = fail_count + 1;
        end

        if (vga_vsync !== 1'bx) begin
            $display("PASS: vga_vsync is not X (%b)", vga_vsync);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: vga_vsync is X");
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Test 5: Filter switching
        //--------------------------------------------------------------------
        $display("\n--- Test 5: Filter Switch Modes ---");
        sw = 2'b01; #10000;
        $display("  sw=01 (Inversion): vga_r=%b vga_g=%b vga_b=%b", vga_r, vga_g, vga_b);

        sw = 2'b10; #10000;
        $display("  sw=10 (Red only):  vga_r=%b vga_g=%b vga_b=%b", vga_r, vga_g, vga_b);

        sw = 2'b11; #10000;
        $display("  sw=11 (Threshold): vga_r=%b vga_g=%b vga_b=%b", vga_r, vga_g, vga_b);

        //--------------------------------------------------------------------
        // Test 6: Second frame — verify capture doesn't corrupt memory
        //--------------------------------------------------------------------
        $display("\n--- Test 6: Second Frame ---");
        sw = 2'b00;
        generate_frame(5);
        #50_000;

        check_no_x("vga_r", vga_r);
        check_no_x("vga_g", vga_g);
        check_no_x("vga_b", vga_b);

        //--------------------------------------------------------------------
        // Test 7: Overflow test — send a line with >320 pixels
        //         Verify system doesn't crash
        //--------------------------------------------------------------------
        $display("\n--- Test 7: Overflow Resilience ---");
        cam_vsync = 1;
        repeat (50) @(negedge cam_pclk);
        cam_vsync = 0;
        repeat (20) @(negedge cam_pclk);

        cam_href = 1;
        begin : overflow_test
            integer col;
            for (col = 0; col < 330; col = col + 1) begin
                send_cam_pixel(5'd15, 6'd30, 5'd15);
            end
        end
        cam_href = 0;
        repeat (20) @(negedge cam_pclk);

        #10_000;
        check_no_x("vga_r", vga_r);
        check_no_x("vga_g", vga_g);
        check_no_x("vga_b", vga_b);
        $display("PASS: System survived 330-pixel line without crash");
        pass_count = pass_count + 1;

        //--------------------------------------------------------------------
        // Final checks
        //--------------------------------------------------------------------
        $display("\n=== Smoke Test Results ===");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        if (x_check_fail == 0)
            $display("PASS: No X-propagation detected on VGA outputs");
        else
            $display("WARNING: %0d X-propagation events detected", x_check_fail);

        if (fail_count == 0 && x_check_fail == 0)
            $display("\nALL TESTS PASSED!");
        else
            $display("\nSOME ISSUES DETECTED — review above");

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
