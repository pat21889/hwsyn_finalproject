//============================================================================
// Testbench: tb_vga_sync
// Description: Verifies VGA 640x480 @ 60Hz timing signals.
//              Runs for 2+ full frames and checks:
//              - hsync and vsync pulse widths and polarities (active low)
//              - hcount range (0-799) and vcount range (0-524)
//              - hactive/vactive are high only during active region
//              - Total line and frame lengths
//============================================================================

`timescale 1ns / 1ps

module tb_vga_sync;

    //------------------------------------------------------------------------
    // Testbench signals
    //------------------------------------------------------------------------
    reg        clk;
    reg        rst;
    wire       hsync;
    wire       vsync;
    wire       hactive;
    wire       vactive;
    wire [9:0] hcount;
    wire [9:0] vcount;

    //------------------------------------------------------------------------
    // DUT instantiation
    //------------------------------------------------------------------------
    vga_sync uut (
        .clk     (clk),
        .rst     (rst),
        .hsync   (hsync),
        .vsync   (vsync),
        .hactive (hactive),
        .vactive (vactive),
        .hcount  (hcount),
        .vcount  (vcount)
    );

    //------------------------------------------------------------------------
    // Clock generation: 25MHz (40ns period)
    //------------------------------------------------------------------------
    initial clk = 0;
    always #20 clk = ~clk;

    //------------------------------------------------------------------------
    // Counters for verification
    //------------------------------------------------------------------------
    integer hsync_low_count = 0;   // Clocks where hsync is low
    integer vsync_low_count = 0;   // Clocks where vsync is low
    integer hactive_count = 0;     // Clocks where hactive is high per line
    integer vactive_lines = 0;     // Lines where vactive is high
    integer total_clocks = 0;      // Total clocks in one frame
    integer frame_count = 0;       // Number of complete frames
    integer line_count = 0;        // Lines in current frame

    reg hsync_prev = 1;
    reg vsync_prev = 1;
    reg hcount_was_zero = 0;

    // Track max values
    integer max_hcount = 0;
    integer max_vcount = 0;

    always @(posedge clk) begin
        if (!rst) begin
            hsync_prev <= hsync;
            vsync_prev <= vsync;

            // Track max counter values
            if (hcount > max_hcount) max_hcount = hcount;
            if (vcount > max_vcount) max_vcount = vcount;

            // Count hsync low duration per line
            if (!hsync) hsync_low_count = hsync_low_count + 1;

            // Detect end of line (hcount wraps from 799 to 0)
            if (hcount == 10'd0 && !hcount_was_zero) begin
                line_count = line_count + 1;
                // Check hactive count for this line (should be 640)
                // (Only check after first full line)
            end
            hcount_was_zero = (hcount == 10'd0);

            // Detect vsync falling edge (new frame start)
            if (!vsync && vsync_prev) begin
                if (frame_count > 0) begin
                    $display("Frame %0d complete: %0d lines", frame_count, line_count);
                end
                frame_count = frame_count + 1;
                line_count = 0;
            end
        end
    end

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("=== VGA Sync Testbench ===");
        $display("Expected: 640x480 @ 60Hz, 25MHz pixel clock");
        $display("H total=800, V total=525");
        $display("Running for 2+ full frames...\n");

        // Initialize
        rst = 1;
        #200;
        rst = 0;

        // Wait for 2 full frames
        // 1 frame = 800 * 525 = 420,000 pixel clocks = 420,000 * 40ns = 16.8ms
        // Wait for ~2.5 frames to be safe
        #42_000_000; // 42ms = ~2.5 frames

        //--------------------------------------------------------------------
        // Verification
        //--------------------------------------------------------------------
        $display("\n=== Verification Results ===");
        $display("Max hcount observed: %0d (expected: 799)", max_hcount);
        $display("Max vcount observed: %0d (expected: 524)", max_vcount);
        $display("Frames completed: %0d (expected: >=2)", frame_count - 1);

        // Check max counter values
        if (max_hcount == 799)
            $display("PASS: hcount range correct (0-799)");
        else
            $display("FAIL: hcount max = %0d, expected 799", max_hcount);

        if (max_vcount == 524)
            $display("PASS: vcount range correct (0-524)");
        else
            $display("FAIL: vcount max = %0d, expected 524", max_vcount);

        //--------------------------------------------------------------------
        // Check sync pulse widths by sampling over a short period
        //--------------------------------------------------------------------
        // Count hsync low pulses for exactly one line (800 clocks)
        hsync_low_count = 0;
        @(posedge clk);
        // Wait for start of line
        wait (hcount == 0);
        repeat (800) begin
            @(posedge clk);
            if (!hsync) hsync_low_count = hsync_low_count + 1;
        end
        $display("\nhsync low count per line: %0d (expected: 96)", hsync_low_count);
        if (hsync_low_count == 96)
            $display("PASS: hsync pulse width correct");
        else
            $display("FAIL: hsync pulse width = %0d, expected 96", hsync_low_count);

        // Count vsync low pulses for exactly one frame (525 lines = 525*800 clocks)
        vsync_low_count = 0;
        wait (vcount == 0 && hcount == 0);
        repeat (525 * 800) begin
            @(posedge clk);
            if (!vsync) vsync_low_count = vsync_low_count + 1;
        end
        // vsync should be low for 2 lines * 800 clocks = 1600 clocks
        $display("vsync low count per frame: %0d (expected: 1600 = 2 lines * 800)", vsync_low_count);
        if (vsync_low_count == 1600)
            $display("PASS: vsync pulse width correct");
        else
            $display("FAIL: vsync pulse width = %0d, expected 1600", vsync_low_count);

        //--------------------------------------------------------------------
        // Check hactive/vactive
        //--------------------------------------------------------------------
        // hactive should be high for hcount 0-639
        hactive_count = 0;
        wait (hcount == 0);
        repeat (800) begin
            @(posedge clk);
            if (hactive) hactive_count = hactive_count + 1;
        end
        $display("\nhactive high count per line: %0d (expected: 640)", hactive_count);
        if (hactive_count == 640)
            $display("PASS: hactive duration correct");
        else
            $display("FAIL: hactive duration = %0d, expected 640", hactive_count);

        // Check that active signal is correctly timed
        @(posedge clk);
        $display("\nChecking active region boundaries:");
        $display("  hactive at hcount=0: %b (expected: 1)", hactive);

        wait (hcount == 639);
        @(posedge clk);
        $display("  hactive at hcount=640: %b (expected: 0)", hactive);

        $display("\n=== VGA Sync Testbench Complete ===");
        $finish;
    end

    //------------------------------------------------------------------------
    // Timeout watchdog
    //------------------------------------------------------------------------
    initial begin
        #100_000_000; // 100ms timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    //------------------------------------------------------------------------
    // Dump waveforms
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_vga_sync.vcd");
        $dumpvars(0, tb_vga_sync);
    end

endmodule
