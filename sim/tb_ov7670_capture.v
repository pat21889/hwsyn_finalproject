//============================================================================
// Testbench: tb_ov7670_capture
// Description: Verifies the OV7670 pixel capture module.
//              Simulates PCLK, HREF, VSYNC, and D[7:0] to mimic OV7670
//              RGB565 output.
//
// KEY TEST: Verifies the address is NOT incremented in the same cycle
//           as wr_en=1 (the off-by-one bug fix).
//           Expected: pixel 0 writes to addr 0, pixel 1 to addr 1, etc.
//============================================================================

`timescale 1ns / 1ps

module tb_ov7670_capture;

    //------------------------------------------------------------------------
    // Testbench signals
    //------------------------------------------------------------------------
    reg        pclk;
    reg        rst;
    reg        href;
    reg        vsync;
    reg  [7:0] d;
    wire [16:0] wr_addr;
    wire [11:0] wr_data;
    wire        wr_en;

    integer errors = 0;
    integer pass   = 0;

    //------------------------------------------------------------------------
    // DUT instantiation
    //------------------------------------------------------------------------
    ov7670_capture uut (
        .pclk    (pclk),
        .rst     (rst),
        .href    (href),
        .vsync   (vsync),
        .d       (d),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .wr_en   (wr_en)
    );

    // ~24MHz PCLK (41.667ns period → 21ns half-period)
    initial pclk = 0;
    always #21 pclk = ~pclk;

    //------------------------------------------------------------------------
    // Capture writes into a local array to verify later
    //------------------------------------------------------------------------
    reg [16:0] captured_addr [0:9];
    reg [11:0] captured_data [0:9];
    integer capture_idx;

    always @(posedge pclk) begin   // BRAM writes on posedge, so check here
        if (wr_en) begin
            if (capture_idx < 10) begin
                captured_addr[capture_idx] <= wr_addr;
                captured_data[capture_idx] <= wr_data;
                capture_idx                <= capture_idx + 1;
            end
        end
    end

    //------------------------------------------------------------------------
    // Task: send one RGB565 pixel (2 bytes on consecutive negedge PCLK)
    // R5=5-bit red, G6=6-bit green, B5=5-bit blue
    //------------------------------------------------------------------------
    task send_pixel;
        input [4:0] r5;
        input [5:0] g6;
        input [4:0] b5;
        begin
            d = {r5, g6[5:3]};       // byte1 = {R[4:0], G[5:3]}
            @(negedge pclk);
            d = {g6[2:0], b5};        // byte2 = {G[2:0], B[4:0]}
            @(negedge pclk);
        end
    endtask

    //------------------------------------------------------------------------
    // Task: compute expected RGB444 from RGB565 input
    //------------------------------------------------------------------------
    function [11:0] expected_rgb444;
        input [4:0] r5;
        input [5:0] g6;
        input [4:0] b5;
        reg [7:0] byte1_val, byte2_val;
        begin
            byte1_val = {r5, g6[5:3]};
            byte2_val = {g6[2:0], b5};
            expected_rgb444 = {byte1_val[7:4],               // R[4:1]
                               {byte1_val[2:0], byte2_val[7]}, // G[5:2]
                               byte2_val[4:1]};               // B[4:1]
        end
    endfunction

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== OV7670 Capture Testbench ===");

        // Initialize
        rst         = 1;
        href        = 0;
        vsync       = 0;
        d           = 8'h00;
        capture_idx = 0;

        repeat(5) @(negedge pclk);
        rst = 0;
        repeat(2) @(negedge pclk);

        //--------------------------------------------------------------------
        // VSYNC pulse to start frame
        //--------------------------------------------------------------------
        $display("\n--- Frame Start: VSYNC pulse ---");
        vsync = 1;
        repeat(3) @(negedge pclk);
        vsync = 0;
        repeat(3) @(negedge pclk);

        //--------------------------------------------------------------------
        // TEST 1: KEY TEST — verify addr starts at 0, increments correctly
        // Send 5 pixels and verify each writes to addr 0,1,2,3,4
        //--------------------------------------------------------------------
        $display("\n--- Test 1: Address sequence (off-by-one fix check) ---");
        capture_idx = 0;
        href = 1;
        // Send 5 known pixels
        send_pixel(5'd31, 6'd0,  5'd0);   // Pixel 0: R=max, G=0, B=0
        send_pixel(5'd0,  6'd63, 5'd0);   // Pixel 1: R=0, G=max, B=0
        send_pixel(5'd0,  6'd0,  5'd31);  // Pixel 2: R=0, G=0, B=max
        send_pixel(5'd31, 6'd63, 5'd31);  // Pixel 3: all max = white
        send_pixel(5'd0,  6'd0,  5'd0);   // Pixel 4: all 0 = black
        href = 0;

        // Wait for last pixel's addr increment (1 extra cycle)
        repeat(4) @(negedge pclk);

        // Verify: each pixel should have been written to addrs 0,1,2,3,4
        $display("Checking pixel write addresses and data...");
        begin : check_block
            integer i;
            reg [11:0] exp;
            for (i = 0; i < 5; i = i + 1) begin
                case(i)
                    0: exp = expected_rgb444(5'd31, 6'd0,  5'd0);
                    1: exp = expected_rgb444(5'd0,  6'd63, 5'd0);
                    2: exp = expected_rgb444(5'd0,  6'd0,  5'd31);
                    3: exp = expected_rgb444(5'd31, 6'd63, 5'd31);
                    4: exp = expected_rgb444(5'd0,  6'd0,  5'd0);
                    default: exp = 12'hXXX;
                endcase

                if (captured_addr[i] === i[16:0]) begin
                    $display("PASS pixel %0d: addr=%0d (correct)", i, captured_addr[i]);
                    pass = pass + 1;
                end else begin
                    $display("FAIL pixel %0d: addr=%0d, expected %0d (OFF-BY-ONE?)",
                             i, captured_addr[i], i);
                    errors = errors + 1;
                end

                if (captured_data[i] === exp) begin
                    $display("PASS pixel %0d: data=0x%03h (correct)", i, captured_data[i]);
                    pass = pass + 1;
                end else begin
                    $display("FAIL pixel %0d: data=0x%03h, expected=0x%03h",
                             i, captured_data[i], exp);
                    errors = errors + 1;
                end
            end
        end

        //--------------------------------------------------------------------
        // TEST 2: VSYNC resets write address to 0
        //--------------------------------------------------------------------
        $display("\n--- Test 2: VSYNC resets write address ---");
        // Send one more pixel (should go to addr 5 from test 1)
        href = 1;
        capture_idx = 0;
        send_pixel(5'd15, 6'd30, 5'd15);
        href = 0;
        repeat(4) @(negedge pclk);
        $display("Before VSYNC: pixel wrote to addr=%0d (expected 5)", captured_addr[0]);
        if (captured_addr[0] === 17'd5) begin
            $display("PASS: addr=5 correct");
            pass = pass + 1;
        end else begin
            $display("FAIL: addr=%0d, expected 5", captured_addr[0]);
            errors = errors + 1;
        end

        // Now send VSYNC
        vsync = 1;
        repeat(3) @(negedge pclk);
        vsync = 0;
        repeat(3) @(negedge pclk);

        // Send one pixel after VSYNC — should go to addr 0
        capture_idx = 0;
        href = 1;
        send_pixel(5'd10, 6'd20, 5'd10);
        href = 0;
        repeat(4) @(negedge pclk);

        if (captured_addr[0] === 17'd0) begin
            $display("PASS: After VSYNC, addr=0 (frame reset correct)");
            pass = pass + 1;
        end else begin
            $display("FAIL: After VSYNC, addr=%0d, expected 0", captured_addr[0]);
            errors = errors + 1;
        end

        //--------------------------------------------------------------------
        // TEST 3: RGB565 -> RGB444 conversion correctness
        //--------------------------------------------------------------------
        $display("\n--- Test 3: RGB565 -> RGB444 conversion ---");
        vsync = 1;
        repeat(3) @(negedge pclk);
        vsync = 0;
        repeat(3) @(negedge pclk);

        capture_idx = 0;
        href = 1;

        // White: R=31, G=63, B=31 → RGB444 = 0xFFF
        send_pixel(5'd31, 6'd63, 5'd31);
        // Black: all 0 → 0x000
        send_pixel(5'd0, 6'd0, 5'd0);
        // Pure red: R=31, G=0, B=0 → RGB444 = {R[4:1]=1111,G=0,B=0} = 0xF00
        send_pixel(5'd31, 6'd0, 5'd0);

        href = 0;
        repeat(4) @(negedge pclk);

        begin : rgb_check
            reg [11:0] exp;

            // White
            exp = expected_rgb444(5'd31, 6'd63, 5'd31);
            if (captured_data[0] === exp) begin
                $display("PASS White: 0x%03h", captured_data[0]);
                pass = pass + 1;
            end else begin
                $display("FAIL White: got 0x%03h, expected 0x%03h", captured_data[0], exp);
                errors = errors + 1;
            end

            // Black
            exp = expected_rgb444(5'd0, 6'd0, 5'd0);
            if (captured_data[1] === exp) begin
                $display("PASS Black: 0x%03h", captured_data[1]);
                pass = pass + 1;
            end else begin
                $display("FAIL Black: got 0x%03h, expected 0x%03h", captured_data[1], exp);
                errors = errors + 1;
            end

            // Pure red
            exp = expected_rgb444(5'd31, 6'd0, 5'd0);
            if (captured_data[2] === exp) begin
                $display("PASS Red: 0x%03h (expected 0x%03h)", captured_data[2], exp);
                pass = pass + 1;
            end else begin
                $display("FAIL Red: got 0x%03h, expected 0x%03h", captured_data[2], exp);
                errors = errors + 1;
            end
        end

        //--------------------------------------------------------------------
        // Summary
        //--------------------------------------------------------------------
        $display("\n=== Results ===");
        $display("PASS: %0d  FAIL: %0d", pass, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Timeout
    initial begin
        #10_000_000;
        $display("ERROR: Timeout!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_ov7670_capture.vcd");
        $dumpvars(0, tb_ov7670_capture);
    end

endmodule
