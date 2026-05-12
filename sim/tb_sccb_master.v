//============================================================================
// Testbench: tb_sccb_master
// Description: Verifies the SCCB 2-wire 3-phase write protocol.
//              Checks:
//              - Start condition (SDA low while SCL high)
//              - 3 phases of 9 bits each (8 data + 1 don't-care)
//              - Stop condition (SDA high while SCL high)
//              - done signal assertion after transaction completes
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
    wire       sda;

    // Pull-up resistor on SDA (simulates external pull-up)
    pullup (sda);

    //------------------------------------------------------------------------
    // DUT instantiation
    //------------------------------------------------------------------------
    sccb_master uut (
        .clk   (clk),
        .rst   (rst),
        .start (start),
        .addr  (addr),
        .data  (data),
        .done  (done),
        .scl   (scl),
        .sda   (sda)
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
    reg sda_prev = 1;

    always @(posedge clk) begin
        scl_prev <= scl;
        sda_prev <= sda;

        // Detect SCL rising edge
        if (scl && !scl_prev) begin
            scl_rising_count <= scl_rising_count + 1;
        end

        // Detect start condition: SDA falls while SCL is high
        if (!sda && sda_prev && scl) begin
            $display("[%0t] START condition detected", $time);
        end

        // Detect stop condition: SDA rises while SCL is high
        if (sda && !sda_prev && scl) begin
            $display("[%0t] STOP condition detected", $time);
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

        // Start SCCB write transaction
        $display("[%0t] Initiating SCCB write...", $time);
        start = 1;
        #10;  // One clock cycle
        start = 0;

        // Wait for done signal
        wait (done == 1);
        $display("[%0t] Transaction DONE!", $time);
        $display("Total SCL rising edges: %0d (expected 27: 3 phases x 9 bits)", scl_rising_count);

        // Verify expected number of SCL edges
        if (scl_rising_count == 27)
            $display("PASS: Correct number of SCL clock cycles");
        else
            $display("FAIL: Expected 27 SCL rising edges, got %0d", scl_rising_count);

        // Wait a bit and do a second transaction with different data
        #10000;
        scl_rising_count = 0;
        addr = 8'h40;  // COM15 register
        data = 8'hD0;  // RGB565 value

        $display("\n[%0t] Starting second transaction: SubAddr=0x40, Data=0xD0", $time);
        start = 1;
        #10;
        start = 0;

        wait (done == 1);
        $display("[%0t] Second transaction DONE!", $time);
        $display("SCL rising edges: %0d", scl_rising_count);

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
    // Optional: dump waveforms
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_sccb_master.vcd");
        $dumpvars(0, tb_sccb_master);
    end

endmodule
