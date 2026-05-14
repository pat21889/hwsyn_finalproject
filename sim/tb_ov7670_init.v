//============================================================================
// Testbench: tb_ov7670_init
// Description: Verifies the camera initialization FSM and register table.
//              Uses SIMULATION=1 to skip the long hardware delays.
//              Updated to verify:
//              - Hardware reset sequence (cam_rst_out low then high)
//              - Software reset (COM7=0x80 via SCCB)
//              - All 97 active registers are sent (de-noise regs commented out)
//              - Correct first register (COM7=0x14) and last register (0xB8=0x0A)
//              - init_done assertion
//============================================================================

`timescale 1ns / 1ps

module tb_ov7670_init;

    reg        clk;
    reg        rst;
    wire       sccb_start;
    wire [7:0] sccb_addr;
    wire [7:0] sccb_data;
    reg        sccb_done;
    wire       cam_rst_out;
    wire       init_done;

    // DUT
    ov7670_init #(
        .SIMULATION (1'b1)
    ) uut (
        .clk         (clk),
        .rst         (rst),
        .sccb_start  (sccb_start),
        .sccb_addr   (sccb_addr),
        .sccb_data   (sccb_data),
        .sccb_done   (sccb_done),
        .cam_rst_out (cam_rst_out),
        .init_done   (init_done)
    );

    // Clock generation (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    //------------------------------------------------------------------------
    // SCCB Master mock: completes every transaction after a few cycles
    //------------------------------------------------------------------------
    integer reg_count = 0;
    reg [7:0] last_addr, last_data;
    reg [7:0] first_addr, first_data;
    reg first_reg_captured = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    initial sccb_done = 0;
    always @(posedge clk) begin
        if (sccb_start) begin
            last_addr = sccb_addr;
            last_data = sccb_data;

            // Skip the software reset (COM7=0x80) from counting
            if (!(sccb_addr == 8'h12 && sccb_data == 8'h80)) begin
                reg_count = reg_count + 1;
                if (!first_reg_captured) begin
                    first_addr = sccb_addr;
                    first_data = sccb_data;
                    first_reg_captured = 1;
                end
            end

            repeat (5) @(posedge clk);
            sccb_done <= 1;
            @(posedge clk);
            sccb_done <= 0;
        end
    end

    initial begin
        $display("=== OV7670 Initialization Testbench (Updated) ===");

        rst = 1;
        #100;
        rst = 0;

        //--------------------------------------------------------------------
        // Test 1: Hardware reset sequence
        //--------------------------------------------------------------------
        $display("\n--- Test 1: Hardware Reset Sequence ---");
        // cam_rst_out should start low (assert camera reset)
        if (cam_rst_out === 1'b0) begin
            $display("PASS: cam_rst_out is low during reset");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: cam_rst_out = %b, expected 0", cam_rst_out);
            fail_count = fail_count + 1;
        end

        wait (cam_rst_out == 1);
        $display("[%0t] Hardware reset released (cam_rst_out = 1)", $time);

        //--------------------------------------------------------------------
        // Test 2: Software reset
        //--------------------------------------------------------------------
        $display("\n--- Test 2: Software Reset ---");
        wait (sccb_start && sccb_addr == 8'h12 && sccb_data == 8'h80);
        $display("[%0t] PASS: Software reset sent (COM7 = 0x80)", $time);
        pass_count = pass_count + 1;

        //--------------------------------------------------------------------
        // Test 3: First configuration register
        //--------------------------------------------------------------------
        $display("\n--- Test 3: First Configuration Register ---");
        wait (first_reg_captured);
        $display("[%0t] First config register: addr=0x%02h data=0x%02h",
                 $time, first_addr, first_data);
        if (first_addr == 8'h12 && first_data == 8'h14) begin
            $display("PASS: First register is COM7=0x14 (QVGA + RGB)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected addr=0x12, data=0x14");
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Test 4: Wait for init_done
        //--------------------------------------------------------------------
        $display("\n--- Test 4: Initialization Complete ---");
        wait (init_done == 1);
        $display("[%0t] init_done asserted!", $time);

        //--------------------------------------------------------------------
        // Test 5: Verify register count
        // With de-noise registers (97-100) commented out, the table has
        // entries 0-96 = 97 active registers.
        //--------------------------------------------------------------------
        $display("\n--- Test 5: Register Count ---");
        $display("Total configuration registers sent: %0d", reg_count);
        if (reg_count == 97) begin
            $display("PASS: Correct number of registers (97)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected 97 registers, got %0d", reg_count);
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Test 6: Verify last register was 0xB8=0x0A (entry 96)
        //--------------------------------------------------------------------
        $display("\n--- Test 6: Last Register ---");
        $display("Last register: addr=0x%02h data=0x%02h", last_addr, last_data);
        if (last_addr == 8'hB8 && last_data == 8'h0A) begin
            $display("PASS: Last register is 0xB8=0x0A");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected addr=0xB8, data=0x0A");
            fail_count = fail_count + 1;
        end

        //--------------------------------------------------------------------
        // Results Summary
        //--------------------------------------------------------------------
        $display("\n=== Results Summary ===");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $display("\n=== OV7670 Init Testbench Complete ===");
        $finish;
    end

    //------------------------------------------------------------------------
    // Timeout watchdog
    //------------------------------------------------------------------------
    initial begin
        #50_000_000; // 50ms timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    //------------------------------------------------------------------------
    // Dump waveforms
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_ov7670_init.vcd");
        $dumpvars(0, tb_ov7670_init);
    end

endmodule
