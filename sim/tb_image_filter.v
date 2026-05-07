//============================================================================
// Testbench: tb_image_filter
// Description: Verifies the image filter module for all 4 switch positions.
//              Tests:
//              - Pass-through (sw=00)
//              - Color Inversion / Negative (sw=01)
//              - Red Channel Isolation (sw=10)
//              - Thresholding / B&W (sw=11)
//
//              Edge cases tested: all-black, all-white, mid-gray, specific colors
//============================================================================

`timescale 1ns / 1ps

module tb_image_filter;

    //------------------------------------------------------------------------
    // Testbench signals
    //------------------------------------------------------------------------
    reg  [11:0] pixel_in;
    reg  [1:0]  sw;
    wire [11:0] pixel_out;

    //------------------------------------------------------------------------
    // DUT instantiation (threshold = 8, default)
    //------------------------------------------------------------------------
    image_filter #(
        .THRESHOLD(4'h8)
    ) uut (
        .pixel_in  (pixel_in),
        .sw        (sw),
        .pixel_out (pixel_out)
    );

    //------------------------------------------------------------------------
    // Test variables
    //------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num = 0;

    //------------------------------------------------------------------------
    // Task: Check expected output
    //------------------------------------------------------------------------
    task check;
        input [11:0] expected;
        input [255:0] test_name; // String description (fixed width for Verilog)
        begin
            test_num = test_num + 1;
            #10; // Allow combinational propagation
            if (pixel_out === expected) begin
                $display("PASS [Test %0d] %0s: in=0x%03h, sw=%b -> out=0x%03h",
                         test_num, test_name, pixel_in, sw, pixel_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [Test %0d] %0s: in=0x%03h, sw=%b -> out=0x%03h (expected 0x%03h)",
                         test_num, test_name, pixel_in, sw, pixel_out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== Image Filter Testbench ===\n");

        //====================================================================
        // Test Group 1: Pass-Through (sw = 2'b00)
        //====================================================================
        $display("--- Mode 00: Pass-Through ---");
        sw = 2'b00;

        pixel_in = 12'h000; check(12'h000, "Black pass-through");
        pixel_in = 12'hFFF; check(12'hFFF, "White pass-through");
        pixel_in = 12'h888; check(12'h888, "Mid-gray pass-through");
        pixel_in = 12'hF00; check(12'hF00, "Red pass-through");
        pixel_in = 12'h0F0; check(12'h0F0, "Green pass-through");
        pixel_in = 12'h00F; check(12'h00F, "Blue pass-through");
        pixel_in = 12'hA5C; check(12'hA5C, "Arbitrary pass-through");

        //====================================================================
        // Test Group 2: Color Inversion / Negative (sw = 2'b01)
        //====================================================================
        $display("\n--- Mode 01: Color Inversion ---");
        sw = 2'b01;

        // Black -> White
        pixel_in = 12'h000; check(12'hFFF, "Black inverted to white");
        // White -> Black
        pixel_in = 12'hFFF; check(12'h000, "White inverted to black");
        // Mid-gray -> inverted mid-gray
        pixel_in = 12'h888; check(12'h777, "Mid-gray inversion");
        // Red -> Cyan
        pixel_in = 12'hF00; check(12'h0FF, "Red inverted to cyan");
        // Green -> Magenta
        pixel_in = 12'h0F0; check(12'hF0F, "Green inverted to magenta");
        // Blue -> Yellow
        pixel_in = 12'h00F; check(12'hFF0, "Blue inverted to yellow");
        // Arbitrary
        pixel_in = 12'hA5C; check(12'h5A3, "Arbitrary inversion");

        //====================================================================
        // Test Group 3: Red Channel Isolation (sw = 2'b10)
        //====================================================================
        $display("\n--- Mode 10: Red Channel Isolation ---");
        sw = 2'b10;

        pixel_in = 12'h000; check(12'h000, "Black red isolation");
        pixel_in = 12'hFFF; check(12'hF00, "White red isolation");
        pixel_in = 12'hF00; check(12'hF00, "Pure red isolation");
        pixel_in = 12'h0F0; check(12'h000, "Pure green -> black");
        pixel_in = 12'h00F; check(12'h000, "Pure blue -> black");
        pixel_in = 12'hA5C; check(12'hA00, "Arbitrary red isolation");

        //====================================================================
        // Test Group 4: Thresholding / B&W (sw = 2'b11)
        //====================================================================
        $display("\n--- Mode 11: Thresholding (threshold=8) ---");
        sw = 2'b11;

        // Black: luma = (0*5 + 0*9 + 0*2)/16 = 0 < 8 -> black
        pixel_in = 12'h000; check(12'h000, "Black threshold");

        // White: luma = (15*5 + 15*9 + 15*2)/16 = (75+135+30)/16 = 240/16 = 15 >= 8 -> white
        pixel_in = 12'hFFF; check(12'hFFF, "White threshold");

        // Mid-gray (0x888): luma = (8*5 + 8*9 + 8*2)/16 = (40+72+16)/16 = 128/16 = 8 >= 8 -> white
        pixel_in = 12'h888; check(12'hFFF, "Mid-gray threshold (borderline)");

        // Dark gray (0x777): luma = (7*5 + 7*9 + 7*2)/16 = (35+63+14)/16 = 112/16 = 7 < 8 -> black
        pixel_in = 12'h777; check(12'h000, "Dark gray threshold (below)");

        // Pure red (0xF00): luma = (15*5 + 0*9 + 0*2)/16 = 75/16 = 4 < 8 -> black
        pixel_in = 12'hF00; check(12'h000, "Pure red threshold");

        // Pure green (0x0F0): luma = (0*5 + 15*9 + 0*2)/16 = 135/16 = 8 >= 8 -> white
        pixel_in = 12'h0F0; check(12'hFFF, "Pure green threshold");

        // Pure blue (0x00F): luma = (0*5 + 0*9 + 15*2)/16 = 30/16 = 1 < 8 -> black
        pixel_in = 12'h00F; check(12'h000, "Pure blue threshold");

        //====================================================================
        // Results Summary
        //====================================================================
        $display("\n=== Results Summary ===");
        $display("Passed: %0d / %0d", pass_count, test_num);
        $display("Failed: %0d / %0d", fail_count, test_num);
        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $display("\n=== Image Filter Testbench Complete ===");
        $finish;
    end

    //------------------------------------------------------------------------
    // Dump waveforms
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_image_filter.vcd");
        $dumpvars(0, tb_image_filter);
    end

endmodule
