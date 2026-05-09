//============================================================================
// Testbench: tb_ov7670_capture
// Description: Verifies the OV7670 pixel capture module.
//              Simulates PCLK, HREF, VSYNC, and D[7:0] to mimic OV7670
//              RGB565 output.
//
//              Checks:
//              - Correct byte-pairing (two bytes → one RGB565 pixel)
//              - RGB565 → RGB444 conversion correctness
//              - Write address increments per pixel
//              - Write address resets on VSYNC level-high
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
    // Note: port names match ov7670_capture exactly (addr/dout/we)
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
    // PCLK generation: ~24MHz (41.667ns period)
    // Using 42ns period for simplicity
    //------------------------------------------------------------------------
    initial pclk = 0;
    always #21 pclk = ~pclk; // ~23.8MHz

    //------------------------------------------------------------------------
    // Monitor write events
    //------------------------------------------------------------------------
    integer pixel_count = 0;
    always @(negedge pclk) begin
        if (wr_en) begin
            $display("[%0t] Pixel %0d: addr=%0d, data=0x%03h (R=%01h G=%01h B=%01h)",
                     $time, pixel_count, wr_addr, wr_data,
                     wr_data[11:8], wr_data[7:4], wr_data[3:0]);
            pixel_count <= pixel_count + 1;
        end
    end

    //------------------------------------------------------------------------
    // Task: Send one RGB565 pixel (2 bytes on consecutive PCLK cycles)
    // byte1 = {R[4:0], G[5:3]}
    // byte2 = {G[2:0], B[4:0]}
    //------------------------------------------------------------------------
    task send_pixel;
        input [4:0] r5;  // 5-bit red
        input [5:0] g6;  // 6-bit green
        input [4:0] b5;  // 5-bit blue
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
                // Send pixel with incrementing values for easy verification
                send_pixel(i[4:0], i[5:0], i[4:0]);
            end
            href = 0;
            // Horizontal blanking (a few PCLK cycles)
            repeat (10) @(negedge pclk);
        end
    endtask

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== OV7670 Capture Testbench (RGB565 Mode) ===");

        // Initialize (no external reset — module resets on vsync level)
        href  = 0;
        vsync = 0;
        d     = 8'h00;

        // Brief idle
        repeat (5) @(negedge pclk);

        //--------------------------------------------------------------------
        // Test 1: VSYNC pulse (frame start)
        //--------------------------------------------------------------------
        $display("\n--- Test 1: VSYNC Frame Start ---");
        vsync = 1;
        repeat (5) @(negedge pclk);
        vsync = 0;
        repeat (5) @(negedge pclk);

        //--------------------------------------------------------------------
        // Test 2: Capture a few pixels on one line
        //--------------------------------------------------------------------
        $display("\n--- Test 2: Capture 5 pixels (1 line) ---");
        pixel_count = 0;
        send_line(5);

        // Verify: should have 5 writes with addresses 0-4
        if (pixel_count == 5)
            $display("PASS: Captured 5 pixels correctly");
        else
            $display("FAIL: Expected 5 pixels, got %0d", pixel_count);

        //--------------------------------------------------------------------
        // Test 3: Second line — address should continue from 5
        //--------------------------------------------------------------------
        $display("\n--- Test 3: Capture 3 pixels (2nd line) ---");
        pixel_count = 0;
        send_line(3);

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

        // After VSYNC, address should start from 0 again
        $display("Address after VSYNC should start from 0");

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
        $display("Sending white pixel (R=31, G=63, B=31)...");
        send_pixel(5'd31, 6'd63, 5'd31);

        // Black: R=0, G=0, B=0 -> expect RGB444 = 0x000
        $display("Sending black pixel (R=0, G=0, B=0)...");
        send_pixel(5'd0, 6'd0, 5'd0);

        // Test: R=16, G=32, B=8 -> expect R=8, G=8, B=4 = 0x884
        $display("Sending test pixel (R=16, G=32, B=8)...");
        send_pixel(5'd16, 6'd32, 5'd8);
        href = 0;

        repeat (20) @(negedge pclk);
        $display("\n=== Testbench Complete ===");
        $finish;
    end

    //------------------------------------------------------------------------
    // Timeout watchdog
    //------------------------------------------------------------------------
    initial begin
        #10_000_000; // 10ms timeout
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
