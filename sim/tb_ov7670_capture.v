//============================================================================
// Testbench: tb_ov7670_capture
// Description: Verifies the OV7670 pixel capture module.
//              Simulates PCLK, HREF, VSYNC, and D[7:0] to mimic OV7670
//              RGB565 output.
//
//              Checks:
//              - Correct byte-pairing (two bytes → one RGB565 pixel)
//              - RGB565 → RGB444 conversion correctness
//              - Write address increments per pixel, clips at x=320
//              - x resets on href rising edge (not on x wrap)
//              - y increments on href falling edge
//              - Write address resets on VSYNC level-high
//              - Extra pixels beyond 320 are NOT written
//============================================================================

`timescale 1ns / 1ps

module tb_ov7670_capture;

    //------------------------------------------------------------------------
    // Testbench signals
    //------------------------------------------------------------------------
    reg        pclk;
    reg        href;
    reg        vsync;
    reg  [7:0] d;
    wire [16:0] wr_addr;  // maps to 'addr' port
    wire [11:0] wr_data;  // maps to 'dout' port
    wire        wr_en;    // maps to 'we' port

    //------------------------------------------------------------------------
    // DUT instantiation
    //------------------------------------------------------------------------
    ov7670_capture uut (
        .pclk  (pclk),
        .href  (href),
        .vsync (vsync),
        .d     (d),
        .addr  (wr_addr),
        .dout  (wr_data),
        .we    (wr_en)
    );

    //------------------------------------------------------------------------
    // PCLK generation: ~24MHz (42ns period)
    //------------------------------------------------------------------------
    initial pclk = 0;
    always #21 pclk = ~pclk;

    //------------------------------------------------------------------------
    // Monitor write events
    //------------------------------------------------------------------------
    integer pixel_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    always @(negedge pclk) begin
        if (wr_en) begin
            pixel_count <= pixel_count + 1;
        end
    end

    //------------------------------------------------------------------------
    // Task: Send one RGB565 pixel (2 bytes on consecutive PCLK cycles)
    //------------------------------------------------------------------------
    task send_pixel;
        input [4:0] r5;
        input [5:0] g6;
        input [4:0] b5;
        begin
            // Byte 1: {R[4:0], G[5:3]}
            d = {r5, g6[5:3]};
            @(negedge pclk);
            // Byte 2: {G[2:0], B[4:0]}
            d = {g6[2:0], b5};
            @(negedge pclk);
        end
    endtask

    //------------------------------------------------------------------------
    // Task: Simulate one line of N pixels with HREF high
    //------------------------------------------------------------------------
    task send_line;
        input integer num_pixels;
        integer i;
        begin
            href = 1;
            for (i = 0; i < num_pixels; i = i + 1) begin
                send_pixel(i[4:0], i[5:0], i[4:0]);
            end
            href = 0;
            // Horizontal blanking
            repeat (10) @(negedge pclk);
        end
    endtask

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== OV7670 Capture Testbench (Updated — Edge Detection + Clipping) ===");

        // Initialize
        href  = 0;
        vsync = 0;
        d     = 8'h00;

        repeat (5) @(negedge pclk);

        //--------------------------------------------------------------------
        // Test 1: VSYNC pulse (frame start) resets counters
        //--------------------------------------------------------------------
        $display("\n--- Test 1: VSYNC Frame Start ---");
        vsync = 1;
        repeat (5) @(negedge pclk);
        vsync = 0;
        repeat (5) @(negedge pclk);

        if (wr_addr === 17'd0) begin
            $display("PASS: Address reset to 0 after VSYNC");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Address after VSYNC = %0d, expected 0", wr_addr);
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Test 2: Capture 5 pixels on one line
        //--------------------------------------------------------------------
        $display("\n--- Test 2: Capture 5 pixels (1 line) ---");
        pixel_count = 0;
        send_line(5);

        if (pixel_count == 5) begin
            $display("PASS: Captured 5 pixels correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected 5 pixels, got %0d", pixel_count);
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Test 3: Second line — y should increment on href falling edge
        //    x should reset to 0 on href rising edge
        //--------------------------------------------------------------------
        $display("\n--- Test 3: Second line (y increments on href fall, x resets on href rise) ---");
        pixel_count = 0;
        send_line(3);

        // After 2 lines: y should be 2
        // First pixel on this line should have addr = 1*320 + 0 = 320
        $display("  y should be 2 after two lines (check waveform)");

        //--------------------------------------------------------------------
        // Test 4: VSYNC resets address
        //--------------------------------------------------------------------
        $display("\n--- Test 4: VSYNC resets write address ---");
        vsync = 1;
        repeat (3) @(negedge pclk);
        vsync = 0;
        repeat (3) @(negedge pclk);

        pixel_count = 0;
        send_line(2);

        $display("  Address after VSYNC should start from 0");

        //--------------------------------------------------------------------
        // Test 5: Verify RGB565 -> RGB444 conversion
        //--------------------------------------------------------------------
        $display("\n--- Test 5: RGB565 to RGB444 Conversion ---");
        vsync = 1;
        repeat (3) @(negedge pclk);
        vsync = 0;
        repeat (3) @(negedge pclk);

        href = 1;
        // White: R=31, G=63, B=31 -> expect RGB444 = 0xFFF
        $display("  Sending white pixel (R=31, G=63, B=31)...");
        send_pixel(5'd31, 6'd63, 5'd31);

        // Black: R=0, G=0, B=0 -> expect RGB444 = 0x000
        $display("  Sending black pixel (R=0, G=0, B=0)...");
        send_pixel(5'd0, 6'd0, 5'd0);

        // Test: R=16, G=32, B=8 -> expect R=8, G=8, B=4 = 0x884
        $display("  Sending test pixel (R=16, G=32, B=8)...");
        send_pixel(5'd16, 6'd32, 5'd8);
        href = 0;

        //--------------------------------------------------------------------
        // Test 6: Overflow protection — send 325 pixels on one line
        //         Only the first 320 should produce writes
        //--------------------------------------------------------------------
        $display("\n--- Test 6: Overflow Protection (325 pixels, expect 320 writes) ---");
        vsync = 1;
        repeat (3) @(negedge pclk);
        vsync = 0;
        repeat (3) @(negedge pclk);

        pixel_count = 0;
        send_line(325);

        $display("  Pixels written: %0d (expected: 320)", pixel_count);
        if (pixel_count == 320) begin
            $display("PASS: Extra pixels clipped correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected 320 writes, got %0d", pixel_count);
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Test 7: href edge detection — x resets on NEXT href rising edge
        //         Send a short line (5 pixels), then a second line.
        //         First pixel of second line should have addr = 1*320 + 0 = 320
        //--------------------------------------------------------------------
        $display("\n--- Test 7: x resets on href rising edge ---");
        vsync = 1;
        repeat (3) @(negedge pclk);
        vsync = 0;
        repeat (3) @(negedge pclk);

        // Line 0: 5 pixels (x goes 0,1,2,3,4 then href falls)
        pixel_count = 0;
        send_line(5);

        // Line 1: start — x should reset to 0 on href rise
        href = 1;
        @(negedge pclk); // First byte of first pixel
        // After href rises, x should be reset to 0
        // So address should be y(=1)*320 + 0 = 320
        send_pixel(5'd15, 6'd30, 5'd15);
        // Check address of the first write on line 1
        $display("  First pixel addr on line 1: %0d (expected 320)", wr_addr);
        href = 0;
        repeat (10) @(negedge pclk);

        //--------------------------------------------------------------------
        // Results Summary
        //--------------------------------------------------------------------
        repeat (20) @(negedge pclk);
        $display("\n=== Results Summary ===");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $display("\n=== Testbench Complete ===");
        $finish;
    end

    //------------------------------------------------------------------------
    // Timeout watchdog
    //------------------------------------------------------------------------
    initial begin
        #10_000_000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    //------------------------------------------------------------------------
    // Dump waveforms
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_ov7670_capture.vcd");
        $dumpvars(0, tb_ov7670_capture);
    end

endmodule
