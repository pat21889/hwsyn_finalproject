//============================================================================
// Testbench: tb_ov7670_init
// Description: Verifies the camera initialization FSM and register table.
//              Uses SIMULATION=1 to skip the long hardware delays.
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

    // SCCB Master mock: completes every transaction after a few cycles
    initial sccb_done = 0;
    always @(posedge clk) begin
        if (sccb_start) begin
            repeat (5) @(posedge clk);
            sccb_done <= 1;
            @(posedge clk);
            sccb_done <= 0;
        end
    end

    initial begin
        $display("=== OV7670 Initialization Testbench ===");
        
        rst = 1;
        #100;
        rst = 0;

        $display("[%0t] Waiting for hardware reset sequence...", $time);
        wait (cam_rst_out == 1);
        $display("[%0t] Hardware reset released.", $time);

        $display("[%0t] Waiting for software reset (Register 0x12)...", $time);
        wait (sccb_start && sccb_addr == 8'h12 && sccb_data == 8'h80);
        $display("[%0t] Software reset sent.", $time);

        $display("[%0t] Waiting for register sequence to start...", $time);
        // Wait for the settle delay to pass
        wait (sccb_start && sccb_addr == 8'h12 && sccb_data == 8'h14); // First reg in table
        $display("[%0t] First configuration register sent.", $time);

        $display("[%0t] Waiting for init_done...", $time);
        wait (init_done == 1);
        $display("[%0t] Initialization complete!", $time);
        
        $finish;
    end

    initial begin
        $dumpfile("tb_ov7670_init.vcd");
        $dumpvars(0, tb_ov7670_init);
    end

endmodule
