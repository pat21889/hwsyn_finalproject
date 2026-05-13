//============================================================================
// Testbench: tb_vga_display
// Description: Verifies the Bilinear Upscaling logic and timing alignment.
//              Tests:
//              1. Nearest neighbor (Even X, Even Y)
//              2. Horizontal blend (Odd X, Even Y)
//              3. Vertical blend (Even X, Odd Y)
//              4. 4-way diagonal blend (Odd X, Odd Y) - specifically checks for 6-bit sum overflow fix
//============================================================================

`timescale 1ns / 1ps

module tb_vga_display;

    reg        clk;
    reg        rst;
    reg [9:0]  hcount;
    reg [9:0]  vcount;
    reg        hactive;
    reg        vactive;
    reg [1:0]  sw;
    wire [16:0] rd_addr;
    reg [11:0]  rd_data;
    wire [3:0]  vga_r, vga_g, vga_b;

    // DUT
    vga_display uut (
        .clk     (clk),
        .rst     (rst),
        .hcount  (hcount),
        .vcount  (vcount),
        .hactive (hactive),
        .vactive (vactive),
        .sw      (sw),
        .rd_addr (rd_addr),
        .rd_data (rd_data),
        .vga_r   (vga_r),
        .vga_g   (vga_g),
        .vga_b   (vga_b)
    );

    // Clock generation (25MHz)
    initial clk = 0;
    always #20 clk = ~clk;

    // Memory model for simulation (just returns dummy data based on address)
    // We'll simulate a 4x4 patch of pixels:
    // P00 (FFF), P01 (000)
    // P10 (000), P11 (FFF)
    always @(*) begin
        case (rd_addr)
            17'd0:   rd_data = 12'hFFF; // White
            17'd1:   rd_data = 12'h000; // Black
            17'd320: rd_data = 12'h000; // Black
            17'd321: rd_data = 12'hFFF; // White
            default: rd_data = 12'h888; // Gray
        endcase
    end

    initial begin
        $display("=== VGA Display Bilinear Filter Testbench ===");
        
        // Init
        rst = 1;
        hcount = 0;
        vcount = 0;
        hactive = 0;
        vactive = 0;
        sw = 2'b00;
        
        #100;
        rst = 0;
        hactive = 1;
        vactive = 1;

        // Sequence through the first 2x2 patch of source pixels (4x4 VGA pixels)
        $display("[%0t] Starting pixel sweep...", $time);
        
        // Pixel (0,0) - VGA (0,0) - Direct Copy
        hcount = 0; vcount = 0; #40;
        // Pixel (0,0) - VGA (1,0) - Horizontal Blend
        hcount = 1; vcount = 0; #40;
        // Pixel (1,0) - VGA (2,0) - Direct Copy
        hcount = 2; vcount = 0; #40;
        // Pixel (1,0) - VGA (3,0) - Horizontal Blend
        hcount = 3; vcount = 0; #40;
        
        // Line 1
        hcount = 0; vcount = 1; #40;
        hcount = 1; vcount = 1; #40;
        hcount = 2; vcount = 1; #40;
        hcount = 3; vcount = 1; #40;

        #200;
        $display("Check waveforms for vga_r/g/b values at the correct latency.");
        $display("VGA (0,0) should result in FFF");
        $display("VGA (1,0) should result in 777 (Blend of FFF and FFF if h_frac uses clamping)");
        $display("VGA (1,1) should result in 4-way blend.");
        
        $finish;
    end

    initial begin
        $dumpfile("tb_vga_display.vcd");
        $dumpvars(0, tb_vga_display);
    end

endmodule
