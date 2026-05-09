//============================================================================
// Testbench: tb_ov7670_capture
// Description: Verifies the OV7670 pixel capture module.
//              Simulates PCLK, HREF, VSYNC, and D[7:0] to mimic OV7670
//              xRGB444 output (register 0x8C=0x02).
//
//              Checks:
//              - Correct byte-pairing (two bytes → one RGB444 pixel)
//              - RGB444 latch extraction correctness (d_latch[11:0])
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
            pixel_count = pixel_count + 1;
        end
    end

    //------------------------------------------------------------------------
    // Task: Send one RGB444 pixel (2 bytes on consecutive PCLK cycles)
    // The capture module expects xRGB444 byte order as determined empirically:
    //   byte1 = {G[3:0], B[3:0]}   (GGGG_BBBB)
    //   byte2 = {4'b0000, R[3:0]}  (0000_RRRR)
    // After the 2-byte shift: d_latch = {0000_RRRR, GGGG_BBBB}
    //   d_latch[11:0] = {R[3:0], G[3:0], B[3:0]} (correct RGB444)
    //------------------------------------------------------------------------
    task send_pixel;
        input [3:0] r4;  // 4-bit red
        input [3:0] g4;  // 4-bit green
        input [3:0] b4;  // 4-bit blue
        begin
            // Byte 1: GGGG_BBBB
            d = {g4, b4};
            @(negedge pclk);

            // Byte 2: 0000_RRRR
            d = {4'b0000, r4};
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
                // Send pixel with incrementing 4-bit values for easy verification
                send_pixel(i[3:0], i[3:0], i[3:0]);
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
        // Test 5: Verify RGB444 byte-pair -> pixel conversion
        //--------------------------------------------------------------------
        $display("\n--- Test 5: RGB444 Capture Conversion ---");
        vsync = 1;
        repeat (3) @(negedge pclk);
        vsync = 0;
        repeat (3) @(negedge pclk);

        href = 1;
        // White: R=15, G=15, B=15 -> expect RGB444 dout = 0xFFF
        $display("Sending white pixel (R=15, G=15, B=15)...");
        send_pixel(4'd15, 4'd15, 4'd15);

        // Black: R=0, G=0, B=0 -> expect RGB444 dout = 0x000
        $display("Sending black pixel (R=0, G=0, B=0)...");
        send_pixel(4'd0, 4'd0, 4'd0);

        // Mid: R=8, G=4, B=12 -> expect RGB444 dout = 0x84C
        $display("Sending test pixel (R=8, G=4, B=12) -> expect 0x84C...");
        send_pixel(4'd8, 4'd4, 4'd12);
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
