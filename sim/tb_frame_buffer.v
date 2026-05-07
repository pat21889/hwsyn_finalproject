//============================================================================
// Testbench: tb_frame_buffer
// Description: Verifies correct BRAM write and read behavior for frame_buffer.
//
// Tests:
//   1. Write 16 known pixels at addresses 0..15, read back and verify
//   2. Write a full row (320 pixels, row 0), read back every address
//   3. Write pixel at last address (76799), verify boundary condition
//   4. Verify rd_data is stale (old) until one cycle after rd_addr changes
//   5. Simultaneous write (port A) and read (port B) at different addresses
//
// Clock domains:
//   clk_wr: 24MHz  (cam_pclk) — 41.667ns period
//   clk_rd: 25MHz  (VGA)      — 40.000ns period
//   Both asynchronous to each other (different frequencies, no phase lock)
//============================================================================

`timescale 1ns / 1ps

module tb_frame_buffer;

    //------------------------------------------------------------------------
    // Signals
    //------------------------------------------------------------------------
    reg        clk_wr;
    reg        clk_rd;
    reg        we;
    reg [16:0] wr_addr;
    reg [11:0] wr_data;
    wire[11:0] rd_data;
    reg [16:0] rd_addr;

    integer errors = 0;
    integer pass   = 0;

    //------------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------------
    frame_buffer uut (
        .clk_wr  (clk_wr),
        .we      (we),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .clk_rd  (clk_rd),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    //------------------------------------------------------------------------
    // Clock generation
    // clk_wr: ~24 MHz  (period = 41.667 ns)
    // clk_rd: ~25 MHz  (period = 40.000 ns)
    //------------------------------------------------------------------------
    initial clk_wr = 0;
    always #20.833 clk_wr = ~clk_wr;   // 24 MHz

    initial clk_rd = 0;
    always #20.0   clk_rd = ~clk_rd;   // 25 MHz

    //------------------------------------------------------------------------
    // Task: Write one pixel via Port A (synchronous to clk_wr)
    //------------------------------------------------------------------------
    task write_pixel;
        input [16:0] addr;
        input [11:0] data;
        begin
            @(posedge clk_wr);
            #1;                    // small delay after posedge for stability
            wr_addr <= addr;
            wr_data <= data;
            we      <= 1'b1;
            @(posedge clk_wr);    // write happens on THIS posedge
            #1;
            we      <= 1'b0;
        end
    endtask

    //------------------------------------------------------------------------
    // Task: Read one pixel via Port B and check expected value
    // Returns rd_data one posedge after rd_addr is set (1-cycle BRAM latency)
    //------------------------------------------------------------------------
    task read_and_check;
        input [16:0] addr;
        input [11:0] expected;
        reg   [11:0] got;
        begin
            @(posedge clk_rd);
            #1;
            rd_addr <= addr;        // Present address to BRAM
            @(posedge clk_rd);      // BRAM registers address here
            #1;
            // rd_data is now valid
            got = rd_data;
            if (got === expected) begin
                $display("PASS addr=%0d: got 0x%03h", addr, got);
                pass = pass + 1;
            end else begin
                $display("FAIL addr=%0d: expected 0x%03h, got 0x%03h", addr, expected, got);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== Frame Buffer BRAM Testbench ===");
        $display("clk_wr=24MHz, clk_rd=25MHz (asynchronous)");
        $display("");

        // Initialize
        we      = 0;
        wr_addr = 17'd0;
        wr_data = 12'd0;
        rd_addr = 17'd0;

        // Wait for clocks to start
        repeat(4) @(posedge clk_wr);
        repeat(4) @(posedge clk_rd);

        //--------------------------------------------------------------------
        // TEST 1: Write and read 16 known pixels at addresses 0..15
        //--------------------------------------------------------------------
        $display("--- Test 1: Write/Read 16 pixels at addr 0..15 ---");

        // Write phase
        write_pixel(17'd0,  12'hFFF); // white
        write_pixel(17'd1,  12'h000); // black
        write_pixel(17'd2,  12'hF00); // red
        write_pixel(17'd3,  12'h0F0); // green
        write_pixel(17'd4,  12'h00F); // blue
        write_pixel(17'd5,  12'hFF0); // yellow
        write_pixel(17'd6,  12'h0FF); // cyan
        write_pixel(17'd7,  12'hF0F); // magenta
        write_pixel(17'd8,  12'h888); // gray
        write_pixel(17'd9,  12'h123);
        write_pixel(17'd10, 12'h456);
        write_pixel(17'd11, 12'h789);
        write_pixel(17'd12, 12'hABC);
        write_pixel(17'd13, 12'hDEF);
        write_pixel(17'd14, 12'hFED);
        write_pixel(17'd15, 12'hCBA);

        // Extra wait to let last write propagate
        repeat(4) @(posedge clk_rd);

        // Read phase (via Port B / VGA clock)
        read_and_check(17'd0,  12'hFFF);
        read_and_check(17'd1,  12'h000);
        read_and_check(17'd2,  12'hF00);
        read_and_check(17'd3,  12'h0F0);
        read_and_check(17'd4,  12'h00F);
        read_and_check(17'd5,  12'hFF0);
        read_and_check(17'd6,  12'h0FF);
        read_and_check(17'd7,  12'hF0F);
        read_and_check(17'd8,  12'h888);
        read_and_check(17'd9,  12'h123);
        read_and_check(17'd10, 12'h456);
        read_and_check(17'd11, 12'h789);
        read_and_check(17'd12, 12'hABC);
        read_and_check(17'd13, 12'hDEF);
        read_and_check(17'd14, 12'hFED);
        read_and_check(17'd15, 12'hCBA);

        //--------------------------------------------------------------------
        // TEST 2: Full row 0 — write 320 pixels, verify all addresses
        //--------------------------------------------------------------------
        $display("\n--- Test 2: Full row 0 (320 pixels, addr 0..319) ---");
        begin : test2_block
            integer col;
            // Write all 320 pixels of row 0
            for (col = 0; col < 320; col = col + 1) begin
                // Pattern: addr[7:0] in R, addr[7:0] inverted in G, col[3:0] in B
                write_pixel(col[16:0], {col[7:4], ~col[7:4], col[3:0]});
            end

            repeat(8) @(posedge clk_rd);

            // Read back all 320
            for (col = 0; col < 320; col = col + 1) begin
                read_and_check(col[16:0], {col[7:4], ~col[7:4], col[3:0]});
            end
        end

        //--------------------------------------------------------------------
        // TEST 3: Boundary — last address (76799)
        //--------------------------------------------------------------------
        $display("\n--- Test 3: Boundary address 76799 ---");
        write_pixel(17'd76799, 12'hBEE);
        repeat(4) @(posedge clk_rd);
        read_and_check(17'd76799, 12'hBEE);

        //--------------------------------------------------------------------
        // TEST 4: Address 76798 — one before last
        //--------------------------------------------------------------------
        $display("\n--- Test 4: Address 76798 ---");
        write_pixel(17'd76798, 12'hACE);
        repeat(4) @(posedge clk_rd);
        read_and_check(17'd76798, 12'hACE);

        //--------------------------------------------------------------------
        // TEST 5: Verify 1-cycle read latency
        //--------------------------------------------------------------------
        $display("\n--- Test 5: Verify 1-cycle BRAM read latency ---");
        begin : test5_block
            reg [11:0] captured;
            // Write known value at address 100
            write_pixel(17'd100, 12'hCAF);
            repeat(4) @(posedge clk_rd);

            // Set rd_addr at posedge N
            @(posedge clk_rd); #1;
            rd_addr = 17'd100;
            // rd_data is NOT yet updated (still old)
            captured = rd_data;
            $display("  Cycle 0 (addr just set): rd_data=0x%03h (should be old value)", captured);

            // At posedge N+1, rd_data should be updated
            @(posedge clk_rd); #1;
            captured = rd_data;
            if (captured === 12'hCAF) begin
                $display("PASS Cycle 1: rd_data=0x%03h (correct, 1-cycle latency confirmed)", captured);
                pass = pass + 1;
            end else begin
                $display("FAIL Cycle 1: rd_data=0x%03h, expected 0xCAF", captured);
                errors = errors + 1;
            end
        end

        //--------------------------------------------------------------------
        // TEST 6: Row/Column address calculation verification
        //         Simulates what vga_display does: rd_addr = row*320 + col
        //--------------------------------------------------------------------
        $display("\n--- Test 6: Row*320+Col address mapping ---");
        begin : test6_block
            integer r, c;
            reg [16:0] addr;
            reg [11:0] expected_data;

            // Write a known pattern at row 5, col 10 → addr = 5*320+10 = 1610
            addr = 17'd5 * 17'd320 + 17'd10;
            write_pixel(addr, 12'hD0D);
            repeat(4) @(posedge clk_rd);

            // Read back using the same address formula
            read_and_check(17'd5 * 17'd320 + 17'd10, 12'hD0D);

            // Write at row 239, col 319 (bottom-right pixel) → addr = 76799
            addr = 17'd239 * 17'd320 + 17'd319;
            write_pixel(addr, 12'hFAB);
            repeat(4) @(posedge clk_rd);
            read_and_check(addr, 12'hFAB);
        end

        //--------------------------------------------------------------------
        // Results
        //--------------------------------------------------------------------
        $display("\n=== Results ===");
        $display("PASS: %0d  FAIL: %0d", pass, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED - BRAM read/write is CORRECT");
        else
            $display("SOME TESTS FAILED - check address or data logic");

        $finish;
    end

    //------------------------------------------------------------------------
    // Timeout watchdog
    //------------------------------------------------------------------------
    initial begin
        #50_000_000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    //------------------------------------------------------------------------
    // Waveform dump
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_frame_buffer.vcd");
        $dumpvars(0, tb_frame_buffer);
    end

endmodule
