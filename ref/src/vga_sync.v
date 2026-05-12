//============================================================================
// Module: vga_sync
// Description: VGA sync signal generator for 640x480 @ 60Hz
//              Uses a 25MHz pixel clock to generate standard VGA timing.
//
// VGA 640x480 @ 60Hz Timing Parameters:
//   Pixel clock:    25 MHz
//   H active:       640 pixels
//   H front porch:  16 pixels
//   H sync pulse:   96 pixels (active low)
//   H back porch:   48 pixels
//   H total:        800 pixels
//   V active:       480 lines
//   V front porch:  10 lines
//   V sync pulse:   2 lines (active low)
//   V back porch:   33 lines
//   V total:        525 lines
//============================================================================

module vga_sync (
    input  wire       clk,      // 25MHz pixel clock
    input  wire       rst,      // Synchronous reset (active high)
    output wire       hsync,    // Horizontal sync (active low)
    output wire       vsync,    // Vertical sync (active low)
    output wire       hactive,  // High during horizontal active region
    output wire       vactive,  // High during vertical active region
    output reg  [9:0] hcount,   // Horizontal pixel counter (0-799)
    output reg  [9:0] vcount    // Vertical line counter (0-524)
);

    //------------------------------------------------------------------------
    // VGA Timing Parameters (640x480 @ 60Hz)
    //------------------------------------------------------------------------
    localparam H_ACTIVE      = 10'd640;
    localparam H_FRONT_PORCH = 10'd16;
    localparam H_SYNC_PULSE  = 10'd96;
    localparam H_BACK_PORCH  = 10'd48;
    localparam H_TOTAL       = 10'd800;  // 640+16+96+48

    localparam V_ACTIVE      = 10'd480;
    localparam V_FRONT_PORCH = 10'd10;
    localparam V_SYNC_PULSE  = 10'd2;
    localparam V_BACK_PORCH  = 10'd33;
    localparam V_TOTAL       = 10'd525;  // 480+10+2+33

    // Sync pulse start/end positions
    localparam H_SYNC_START = H_ACTIVE + H_FRONT_PORCH;          // 656
    localparam H_SYNC_END   = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE; // 752
    localparam V_SYNC_START = V_ACTIVE + V_FRONT_PORCH;          // 490
    localparam V_SYNC_END   = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE; // 492

    //------------------------------------------------------------------------
    // Horizontal counter: counts 0 to H_TOTAL-1 (0 to 799)
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            hcount <= 10'd0;
        end else begin
            if (hcount == H_TOTAL - 1)
                hcount <= 10'd0;
            else
                hcount <= hcount + 10'd1;
        end
    end

    //------------------------------------------------------------------------
    // Vertical counter: increments at end of each horizontal line
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            vcount <= 10'd0;
        end else if (hcount == H_TOTAL - 1) begin
            if (vcount == V_TOTAL - 1)
                vcount <= 10'd0;
            else
                vcount <= vcount + 10'd1;
        end
    end

    //------------------------------------------------------------------------
    // Sync signals (active low)
    //------------------------------------------------------------------------
    // HSYNC is low during horizontal sync pulse region
    assign hsync = ~((hcount >= H_SYNC_START) && (hcount < H_SYNC_END));

    // VSYNC is low during vertical sync pulse region
    assign vsync = ~((vcount >= V_SYNC_START) && (vcount < V_SYNC_END));

    //------------------------------------------------------------------------
    // Active region flags
    //------------------------------------------------------------------------
    assign hactive = (hcount < H_ACTIVE);
    assign vactive = (vcount < V_ACTIVE);

endmodule
