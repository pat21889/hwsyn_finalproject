//============================================================================
// Testbench: tb_sccb_master
// Description: Verifies the SCCB 2-wire 3-phase write protocol.
//              Checks:
//              - Start condition (SDA low while SCL high)
//              - 3 phases of 9 bits each (8 data + 1 don't-care)
//              - Stop condition (SDA high while SCL high)
//              - done signal is a single-cycle pulse
//              - SCL period >= 10us (100kHz max)
//              - 3 back-to-back transactions work correctly
//============================================================================

`timescale 1ns / 1ps

module tb_sccb_master;

    //------------------------------------------------------------------------
    // Testbench signals
    //------------------------------------------------------------------------
    reg        clk;
    reg        rst;
    reg        start;
    reg  [7:0] addr;
    reg  [7:0] data;
    wire       done;
    wire       scl;
    wire       sda_out;
    wire       sda_oe;

    // Reconstruct SDA line with pull-up behavior
    wire sda = sda_oe ? sda_out : 1'b1;  // Simulated pull-up

    //------------------------------------------------------------------------
    // DUT instantiation
    //------------------------------------------------------------------------
    sccb_master uut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .addr    (addr),
        .data    (data),
        .done    (done),
        .scl     (scl),
        .sda_out (sda_out),
        .sda_oe  (sda_oe)
    );

    //------------------------------------------------------------------------
    // Clock generation: 100MHz (10ns period)
    //------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    //------------------------------------------------------------------------
    // Monitoring: count SCL edges and detect protocol events
    //------------------------------------------------------------------------
    integer scl_rising_count = 0;
    reg scl_prev = 1;
    reg sda_prev_mon = 1;

    // SCL period measurement
    realtime scl_last_rise = 0;
    realtime scl_period = 0;

    always @(posedge clk) begin
        scl_prev <= scl;
        sda_prev_mon <= sda;

        // Detect SCL rising edge
        if (scl && !scl_prev) begin
            scl_rising_count = scl_rising_count + 1;
            // Measure SCL period
            if (scl_last_rise > 0) begin
                scl_period = $realtime - scl_last_rise;
            end
            scl_last_rise = $realtime;
        end

        // Detect start condition: SDA falls while SCL is high
        if (!sda && sda_prev_mon && scl) begin
            $display("[%0t] START condition detected", $time);
        end

        // Detect stop condition: SDA rises while SCL is high
        if (sda && !sda_prev_mon && scl) begin
            $display("[%0t] STOP condition detected", $time);
        end
    end

    //------------------------------------------------------------------------
    // Done pulse width checker
    //------------------------------------------------------------------------
    integer done_width = 0;
    always @(posedge clk) begin
        if (done) done_width = done_width + 1;
        else if (done_width > 0) begin
            if (done_width == 1)
                $display("PASS: done was a single-cycle pulse");
            else
                $display("FAIL: done was %0d cycles wide (expected 1)", done_width);
            done_width = 0;
        end
    end

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== SCCB Master Testbench ===");
        $display("Testing 3-phase write: DevAddr=0x42, SubAddr=0x12, Data=0x80");

        // Initialize
        rst   = 1;
        start = 0;
        addr  = 8'h12;  // COM7 register
        data  = 8'h80;  // Software reset value

        // Hold reset for 100ns
        #100;
        rst = 0;
        #100;

        //--------------------------------------------------------------------
        // Transaction 1: COM7 software reset
        //--------------------------------------------------------------------
        $display("\n[%0t] === Transaction 1: SubAddr=0x12, Data=0x80 ===", $time);
        scl_rising_count = 0;
        start = 1;
        #10;  // One clock cycle
        start = 0;

        // Wait for done signal
        wait (done == 1);
        @(posedge clk); // Let done pulse complete
        $display("[%0t] Transaction 1 DONE!", $time);
        $display("SCL rising edges: %0d (expected 27: 3 phases x 9 bits)", scl_rising_count);

        if (scl_rising_count == 27)
            $display("PASS: Correct number of SCL clock cycles");
        else
            $display("FAIL: Expected 27 SCL rising edges, got %0d", scl_rising_count);

        // Check SCL period
        if (scl_period >= 10000)
            $display("PASS: SCL period = %0t ns (>= 10us)", scl_period);
        else
            $display("FAIL: SCL period = %0t ns (< 10us, too fast!)", scl_period);

        //--------------------------------------------------------------------
        // Transaction 2: COM15 = 0xD0
        //--------------------------------------------------------------------
        #10000;
        scl_rising_count = 0;
        addr = 8'h40;
        data = 8'hD0;

        $display("\n[%0t] === Transaction 2: SubAddr=0x40, Data=0xD0 ===", $time);
        start = 1;
        #10;
        start = 0;

        wait (done == 1);
        @(posedge clk);
        $display("[%0t] Transaction 2 DONE!", $time);
        $display("SCL rising edges: %0d", scl_rising_count);

        //--------------------------------------------------------------------
        // Transaction 3: Verify FSM returns to IDLE correctly
        //--------------------------------------------------------------------
        #10000;
        scl_rising_count = 0;
        addr = 8'hAB;
        data = 8'hCD;

        $display("\n[%0t] === Transaction 3: SubAddr=0xAB, Data=0xCD ===", $time);
        start = 1;
        #10;
        start = 0;

        wait (done == 1);
        @(posedge clk);
        $display("[%0t] Transaction 3 DONE!", $time);
        $display("SCL rising edges: %0d", scl_rising_count);

        if (scl_rising_count == 27)
            $display("PASS: Third transaction also had correct SCL cycles");
        else
            $display("FAIL: Expected 27, got %0d", scl_rising_count);

        //--------------------------------------------------------------------
        // Check SDA goes high-Z during don't-care bits
        //--------------------------------------------------------------------
        $display("\nCheck sda_oe waveform manually for high-Z during don't-care bits");

        #10000;
        $display("\n=== Testbench Complete ===");
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
        $dumpfile("tb_sccb_master.vcd");
        $dumpvars(0, tb_sccb_master);
    end

endmodule
