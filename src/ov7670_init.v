//============================================================================
// Module: ov7670_init
// Description: OV7670 Camera Initialization Sequencer
//              Performs the complete power-on initialization sequence:
//              1. Assert hardware reset (RST low) for >= 1ms
//              2. Wait >= 1ms after RST release before SCCB communication
//              3. Send software reset (COM7 = 0x80) via SCCB
//              4. Wait 300ms for registers to settle
//              5. Sequentially send full register init table via SCCB
//
// Uses a ROM-style init table with {addr, data} pairs.
// Configured for RGB565 QVGA (320x240) output.
//
// CRITICAL FIX: Uses edge detection on sccb_done to prevent
//   double-advancing when done is a level instead of a pulse.
//============================================================================

module ov7670_init (
    input  wire       clk,       // System clock (100MHz)
    input  wire       rst,       // Synchronous reset (active high)
    // SCCB master interface
    output reg        sccb_start, // Pulse to start SCCB write
    output reg  [7:0] sccb_addr,  // Register address to write
    output reg  [7:0] sccb_data,  // Register data to write
    input  wire       sccb_done,  // SCCB transaction complete
    // Camera reset control
    output reg        cam_rst_out, // Camera RST pin (active low)
    // Status
    output reg        init_done   // High when initialization is complete
);

    //------------------------------------------------------------------------
    // Timing constants at 100MHz (1 tick = 10ns)
    //------------------------------------------------------------------------
    localparam DELAY_1MS   = 24'd100_000;      // 1ms = 100,000 ticks @ 100MHz
    localparam DELAY_300MS = 28'd30_000_000;    // 300ms = 30,000,000 ticks @ 100MHz

    //------------------------------------------------------------------------
    // FSM States
    //------------------------------------------------------------------------
    localparam [3:0] ST_RESET_ASSERT  = 4'd0;  // Assert camera RST low
    localparam [3:0] ST_RESET_WAIT    = 4'd1;  // Wait 1ms with RST low
    localparam [3:0] ST_RESET_RELEASE = 4'd2;  // Release RST (set high)
    localparam [3:0] ST_POST_RESET    = 4'd3;  // Wait 1ms after RST release
    localparam [3:0] ST_SWRESET_SEND  = 4'd4;  // Send software reset (COM7=0x80)
    localparam [3:0] ST_SWRESET_WAIT  = 4'd5;  // Wait for SCCB done
    localparam [3:0] ST_SETTLE_WAIT   = 4'd6;  // Wait 300ms for registers to settle
    localparam [3:0] ST_SEND_REG      = 4'd7;  // Send next register from init table
    localparam [3:0] ST_WAIT_SCCB     = 4'd8;  // Wait for SCCB done
    localparam [3:0] ST_NEXT_REG      = 4'd9;  // Advance to next register entry
    localparam [3:0] ST_INIT_DONE     = 4'd10; // Initialization complete

    reg [3:0]  state;
    reg [27:0] delay_count;  // General-purpose delay counter
    reg [6:0]  reg_index;    // Index into the register init table

    //------------------------------------------------------------------------
    // Edge detection on sccb_done
    // CRITICAL: prevents double-advancing if done stays high for >1 cycle
    //------------------------------------------------------------------------
    reg sccb_done_prev;
    wire sccb_done_rising = sccb_done & ~sccb_done_prev;

    always @(posedge clk) begin
        if (rst)
            sccb_done_prev <= 1'b0;
        else
            sccb_done_prev <= sccb_done;
    end

    //------------------------------------------------------------------------
    // Register initialization ROM table
    // Format: {8'h_addr, 8'h_data}
    // Total entries: 66 registers + 1 end marker
    // The software reset (COM7=0x80) is sent separately before this table.
    //------------------------------------------------------------------------
    localparam NUM_REGS = 7'd66;  // Number of register entries (excluding end marker)

    wire [15:0] current_entry_wire = get_reg_entry(reg_index);

    //------------------------------------------------------------------------
    // ROM read: return {addr, data} for given index
    //------------------------------------------------------------------------
    function [15:0] get_reg_entry;
        input [6:0] index;
        begin
            case (index)
                // Output format: RGB565
                7'd0:  get_reg_entry = {8'h12, 8'h14}; // COM7: QVGA + RGB mode
                7'd1:  get_reg_entry = {8'h40, 8'hD0}; // COM15: RGB565 output range
                7'd2:  get_reg_entry = {8'h8C, 8'h00}; // RGB444: disable RGB444

                // Clock
                7'd3:  get_reg_entry = {8'h11, 8'h80}; // CLKRC: use external clock directly
                7'd4:  get_reg_entry = {8'h6B, 8'h4A}; // DBLV: PLL x4

                // Image format and DCW for QVGA
                7'd5:  get_reg_entry = {8'h0C, 8'h0C}; // COM3: scale enable + DCW enable
                7'd6:  get_reg_entry = {8'h3E, 8'h19}; // COM14: DCW+scaling PCLK, divider /2
                7'd7:  get_reg_entry = {8'h72, 8'h11}; // SCALING_DCWCTR: H and V downsample by 2
                7'd8:  get_reg_entry = {8'h73, 8'hF1}; // SCALING_PCLK_DIV: bypass clock divider

                // Window / framing for QVGA
                7'd9:  get_reg_entry = {8'h17, 8'h16}; // HSTART
                7'd10: get_reg_entry = {8'h18, 8'h04}; // HSTOP
                7'd11: get_reg_entry = {8'h32, 8'hA4}; // HREF
                7'd12: get_reg_entry = {8'h19, 8'h02}; // VSTRT
                7'd13: get_reg_entry = {8'h1A, 8'h7A}; // VSTOP
                7'd14: get_reg_entry = {8'h03, 8'h0A}; // VREF

                // Pixel clock options
                // COM10 = 0x20: PCLK does not toggle during horizontal blank
                // This prevents spurious data captures during blanking
                7'd15: get_reg_entry = {8'h15, 8'h20}; // COM10: PCLK no toggle during hblank

                // Disable test pattern
                7'd16: get_reg_entry = {8'h70, 8'h3A}; // SCALING_XSC: test_pattern[0]=0
                7'd17: get_reg_entry = {8'h71, 8'h35}; // SCALING_YSC: test_pattern[1]=0

                // Color matrix for RGB
                7'd18: get_reg_entry = {8'h4F, 8'h40}; // MTX1
                7'd19: get_reg_entry = {8'h50, 8'h34}; // MTX2
                7'd20: get_reg_entry = {8'h51, 8'h0C}; // MTX3
                7'd21: get_reg_entry = {8'h52, 8'h17}; // MTX4
                7'd22: get_reg_entry = {8'h53, 8'h29}; // MTX5
                7'd23: get_reg_entry = {8'h54, 8'h40}; // MTX6
                7'd24: get_reg_entry = {8'h58, 8'h1E}; // MTXS

                // AGC / AEC / AWB
                7'd25: get_reg_entry = {8'h13, 8'hE7}; // COM8: fast AGC, AEC, banding, AGC+AWB+AEC
                7'd26: get_reg_entry = {8'h00, 8'h00}; // GAIN: AGC gain = 0
                7'd27: get_reg_entry = {8'h10, 8'h40}; // AECH: exposure
                7'd28: get_reg_entry = {8'h01, 8'h80}; // BLUE: AWB blue gain
                7'd29: get_reg_entry = {8'h02, 8'h80}; // RED: AWB red gain
                7'd30: get_reg_entry = {8'h0E, 8'h01}; // COM5: reserved default
                7'd31: get_reg_entry = {8'h0F, 8'h4B}; // COM6: reset timing on format change

                // Gamma curve
                7'd32: get_reg_entry = {8'h7A, 8'h24}; // SLOP
                7'd33: get_reg_entry = {8'h7B, 8'h04}; // GAM1
                7'd34: get_reg_entry = {8'h7C, 8'h07}; // GAM2
                7'd35: get_reg_entry = {8'h7D, 8'h10}; // GAM3
                7'd36: get_reg_entry = {8'h7E, 8'h28}; // GAM4
                7'd37: get_reg_entry = {8'h7F, 8'h36}; // GAM5
                7'd38: get_reg_entry = {8'h80, 8'h44}; // GAM6
                7'd39: get_reg_entry = {8'h81, 8'h52}; // GAM7
                7'd40: get_reg_entry = {8'h82, 8'h60}; // GAM8
                7'd41: get_reg_entry = {8'h83, 8'h6C}; // GAM9
                7'd42: get_reg_entry = {8'h84, 8'h78}; // GAM10
                7'd43: get_reg_entry = {8'h85, 8'h8C}; // GAM11
                7'd44: get_reg_entry = {8'h86, 8'h9E}; // GAM12
                7'd45: get_reg_entry = {8'h87, 8'hBB}; // GAM13
                7'd46: get_reg_entry = {8'h88, 8'hD2}; // GAM14
                7'd47: get_reg_entry = {8'h89, 8'hE5}; // GAM15

                // AWB advanced
                7'd48: get_reg_entry = {8'h6C, 8'h02}; // AWBCTR3
                7'd49: get_reg_entry = {8'h6D, 8'h55}; // AWBCTR2
                7'd50: get_reg_entry = {8'h6E, 8'hC0}; // AWBCTR1
                7'd51: get_reg_entry = {8'h6F, 8'h9A}; // AWBCTR0

                // Lens correction off
                7'd52: get_reg_entry = {8'h66, 8'h00}; // LCC5: lens correction disable

                // De-noise and edge
                7'd53: get_reg_entry = {8'h4C, 8'h00}; // DNSTH
                7'd54: get_reg_entry = {8'h3F, 8'h00}; // EDGE
                7'd55: get_reg_entry = {8'h41, 8'h08}; // COM16: default

                // UV / saturation
                7'd56: get_reg_entry = {8'h3D, 8'h88}; // COM13: gamma enable, UV auto adjust
                7'd57: get_reg_entry = {8'h3A, 8'h04}; // TSLB: YUYV sequence, auto window off

                // Banding filter (50Hz for Thailand)
                7'd58: get_reg_entry = {8'h3B, 8'h0A}; // COM11: 50Hz auto detect + banding ON
                7'd59: get_reg_entry = {8'h9D, 8'h99}; // BD50ST: 50Hz banding value
                7'd60: get_reg_entry = {8'hA5, 8'h0F}; // BD50MAX

                // Histogram AEC
                7'd61: get_reg_entry = {8'hAA, 8'h94}; // HAECC7: histogram-based AEC

                // Additional recommended settings
                7'd62: get_reg_entry = {8'hB0, 8'h84}; // UNDOC: recommended by app note
                7'd63: get_reg_entry = {8'hB1, 8'h0C}; // ABLC1: auto black level compensation
                7'd64: get_reg_entry = {8'hB2, 8'h0E}; // UNDOC: recommended
                7'd65: get_reg_entry = {8'hB3, 8'h80}; // THL_ST: ABLC target

                default: get_reg_entry = {8'hFF, 8'hFF}; // End marker
            endcase
        end
    endfunction

    //------------------------------------------------------------------------
    // Main FSM
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state       <= ST_RESET_ASSERT;
            delay_count <= 28'd0;
            reg_index   <= 7'd0;
            sccb_start  <= 1'b0;
            sccb_addr   <= 8'd0;
            sccb_data   <= 8'd0;
            cam_rst_out <= 1'b0;   // Assert camera reset (active low)
            init_done   <= 1'b0;
        end else begin
            sccb_start <= 1'b0; // Default: de-assert start pulse

            case (state)
                //------------------------------------------------------------
                // Assert hardware reset — cam_rst_out = 0 (active low)
                //------------------------------------------------------------
                ST_RESET_ASSERT: begin
                    cam_rst_out <= 1'b0;    // Hold camera in reset
                    delay_count <= 28'd0;
                    state       <= ST_RESET_WAIT;
                end

                //------------------------------------------------------------
                // Wait 1ms with RST asserted
                //------------------------------------------------------------
                ST_RESET_WAIT: begin
                    delay_count <= delay_count + 28'd1;
                    if (delay_count >= DELAY_1MS) begin
                        state       <= ST_RESET_RELEASE;
                        delay_count <= 28'd0;
                    end
                end

                //------------------------------------------------------------
                // Release hardware reset — cam_rst_out = 1
                //------------------------------------------------------------
                ST_RESET_RELEASE: begin
                    cam_rst_out <= 1'b1;    // Release camera from reset
                    delay_count <= 28'd0;
                    state       <= ST_POST_RESET;
                end

                //------------------------------------------------------------
                // Wait 1ms after RST release before SCCB communication
                //------------------------------------------------------------
                ST_POST_RESET: begin
                    delay_count <= delay_count + 28'd1;
                    if (delay_count >= DELAY_1MS) begin
                        state       <= ST_SWRESET_SEND;
                        delay_count <= 28'd0;
                    end
                end

                //------------------------------------------------------------
                // Send software reset: COM7 (0x12) = 0x80
                //------------------------------------------------------------
                ST_SWRESET_SEND: begin
                    sccb_addr  <= 8'h12;
                    sccb_data  <= 8'h80;
                    sccb_start <= 1'b1;
                    state      <= ST_SWRESET_WAIT;
                end

                //------------------------------------------------------------
                // Wait for software reset SCCB transaction to complete
                // Uses edge detection to prevent glitches
                //------------------------------------------------------------
                ST_SWRESET_WAIT: begin
                    if (sccb_done_rising) begin
                        state       <= ST_SETTLE_WAIT;
                        delay_count <= 28'd0;
                    end
                end

                //------------------------------------------------------------
                // Wait 300ms for all registers to settle after software reset
                //------------------------------------------------------------
                ST_SETTLE_WAIT: begin
                    delay_count <= delay_count + 28'd1;
                    if (delay_count >= DELAY_300MS) begin
                        state       <= ST_SEND_REG;
                        delay_count <= 28'd0;
                        reg_index   <= 7'd0;
                    end
                end

                //------------------------------------------------------------
                // Send next register from the init table
                //------------------------------------------------------------
                ST_SEND_REG: begin
                    if (reg_index >= NUM_REGS) begin
                        // All registers sent
                        state <= ST_INIT_DONE;
                    end else begin
                        // Load register entry from ROM
                        sccb_addr    <= current_entry_wire[15:8];
                        sccb_data    <= current_entry_wire[7:0];
                        sccb_start   <= 1'b1;
                        state        <= ST_WAIT_SCCB;
                    end
                end

                //------------------------------------------------------------
                // Wait for SCCB transaction to complete
                // Uses edge detection for robustness
                //------------------------------------------------------------
                ST_WAIT_SCCB: begin
                    if (sccb_done_rising) begin
                        state <= ST_NEXT_REG;
                    end
                end

                //------------------------------------------------------------
                // Advance to next register entry with small delay
                //------------------------------------------------------------
                ST_NEXT_REG: begin
                    delay_count <= delay_count + 28'd1;
                    // Small delay between consecutive SCCB writes (~1ms)
                    if (delay_count >= DELAY_1MS) begin
                        reg_index   <= reg_index + 7'd1;
                        delay_count <= 28'd0;
                        state       <= ST_SEND_REG;
                    end
                end

                //------------------------------------------------------------
                // Initialization complete
                //------------------------------------------------------------
                ST_INIT_DONE: begin
                    init_done <= 1'b1;
                    // Stay in this state forever
                end

                default: state <= ST_RESET_ASSERT;
            endcase
        end
    end

endmodule
