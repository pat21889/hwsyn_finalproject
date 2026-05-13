//============================================================================
// Testbench: tb_frame_buffer
// Description: Verifies the Dual-Port BRAM (Frame Buffer).
//              Tests:
//              - Writing a pattern from the camera domain (Port A, 24MHz)
//              - Reading the pattern from the VGA domain (Port B, 25MHz)
//              - Simultaneous access and address boundary checks
//============================================================================

`timescale 1ns / 1ps

module tb_frame_buffer;

    //------------------------------------------------------------------------
    // Port A (Camera Write) - 24MHz
    //------------------------------------------------------------------------
    reg         clk_a;
    reg         we_a;
    reg  [16:0] addr_a;
    reg  [11:0] din_a;

    //------------------------------------------------------------------------
    // Port B (VGA Read) - 25MHz
    //------------------------------------------------------------------------
    reg         clk_b;
    reg  [16:0] addr_b;
    wire [11:0] dout_b;

    //------------------------------------------------------------------------
    // DUT instantiation
    //------------------------------------------------------------------------
    frame_buffer uut (
        .clk_a  (clk_a),
        .we_a   (we_a),
        .addr_a (addr_a),
        .din_a  (din_a),
        .clk_b  (clk_b),
        .addr_b (addr_b),
        .dout_b (dout_b)
    );

    //------------------------------------------------------------------------
    // Clock generation
    //------------------------------------------------------------------------
    // Port A: 24MHz (~41.6ns period)
    initial clk_a = 0;
    always #21 clk_a = ~clk_a;

    // Port B: 25MHz (40ns period)
    initial clk_b = 0;
    always #20 clk_b = ~clk_b;

    //------------------------------------------------------------------------
    // Test variables
    //------------------------------------------------------------------------
    integer i;

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== Frame Buffer (Dual-Port BRAM) Testbench ===");
        
        // Initialize
        we_a   = 0;
        addr_a = 0;
        din_a  = 0;
        addr_b = 0;

        #100;

        //--------------------------------------------------------------------
        // Test 1: Simple Write-Read
        //--------------------------------------------------------------------
        $display("\n--- Test 1: Simple Write-Read ---");
        
        // Write 0xABC to address 100 on Port A
        @(posedge clk_a);
        we_a   = 1;
        addr_a = 17'd100;
        din_a  = 12'hABC;
        @(posedge clk_a);
        we_a   = 0;
        $display("[%0t] Wrote 0xABC to addr 100 (Port A)", $time);

        #100;

        // Read from Port B
        @(posedge clk_b);
        addr_b = 17'd100;
        @(posedge clk_b); // BRAM read latency (1 cycle)
        #5; // Wait for output to settle
        $display("[%0t] Read Port B addr 100: 0x%03h", $time, dout_b);
        
        if (dout_b === 12'hABC)
            $display("PASS: Data matches");
        else
            $display("FAIL: Data mismatch! Expected 0xABC, got 0x%03h", dout_b);

        //--------------------------------------------------------------------
        // Test 2: Address Boundaries
        //--------------------------------------------------------------------
        $display("\n--- Test 2: Address Boundaries (Max Addr) ---");
        
        // Max addr = 320*240 - 1 = 76799
        @(posedge clk_a);
        we_a   = 1;
        addr_a = 17'd76799;
        din_a  = 12'hF0F;
        @(posedge clk_a);
        we_a   = 0;
        
        #100;
        
        @(posedge clk_b);
        addr_b = 17'd76799;
        @(posedge clk_b);
        #5;
        $display("[%0t] Read Port B addr 76799: 0x%03h", $time, dout_b);
        if (dout_b === 12'hF0F)
            $display("PASS: Boundary address correct");
        else
            $display("FAIL: Boundary address mismatch");

        //--------------------------------------------------------------------
        // Test 3: Burst Write and Read (Sequential)
        //--------------------------------------------------------------------
        $display("\n--- Test 3: Burst Write and Read ---");
        
        $display("Writing 10 incrementing values to addr 1000...");
        @(posedge clk_a);
        we_a = 1;
        for (i = 0; i < 10; i = i + 1) begin
            addr_a = 17'd1000 + i;
            din_a  = i[11:0];
            @(posedge clk_a);
        end
        we_a = 0;

        #200;

        $display("Reading back values from Port B...");
        for (i = 0; i < 10; i = i + 1) begin
            addr_b = 17'd1000 + i;
            @(posedge clk_b);
            #5;
            $display("  Addr %0d: expected %0d, got %0d", addr_b, i, dout_b);
            if (dout_b !== i[11:0]) $display("  FAIL at index %0d", i);
        end

        $display("\n=== Frame Buffer Testbench Complete ===");
        $finish;
    end

    //------------------------------------------------------------------------
    // Dump waveforms
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_frame_buffer.vcd");
        $dumpvars(0, tb_frame_buffer);
    end

endmodule
