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
// Only 8 registers differ from hardware defaults; all others left at default.
//============================================================================

module ov7670_init #(
    parameter SIMULATION = 1'b0
) (
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
    localparam DELAY_1MS   = SIMULATION ? 24'd100        : 24'd100_000;
    localparam DELAY_300MS = SIMULATION ? 28'd1000       : 28'd30_000_000;

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
    wire [15:0] current_entry_wire = get_reg_entry(reg_index); // Avoids select-on-function-call error

    //------------------------------------------------------------------------
    // Register initialization ROM table
    // Format: {8'h_addr, 8'h_data}
    // Total entries: 66 registers + 1 end marker
    // The software reset (COM7=0x80) is sent separately before this table.
    //------------------------------------------------------------------------
    localparam NUM_REGS = 7'd97; // Number of register entries (de-noise regs 97-100 commented out)


    //------------------------------------------------------------------------
    // ROM read: return {addr, data} for given index
    // Only registers that differ from hardware default are included.
    // All other registers remain at their datasheet default values.
    //------------------------------------------------------------------------
    function [15:0] get_reg_entry;
        input [6:0] index;
        begin
            case (index)
                // === Core format: RGB565 QVGA ===
                7'd0:  get_reg_entry = {8'h12, 8'h14}; // COM7: QVGA + RGB mode
                7'd1:  get_reg_entry = {8'h40, 8'hD0}; // COM15: RGB565 output range [00-FF]
                7'd2:  get_reg_entry = {8'h3A, 8'h04}; // TSLB: normal byte order
                7'd3:  get_reg_entry = {8'h3D, 8'hC8}; // COM13: gamma enable, UV auto, swap UV

                // === Clock: NO PLL, use XCLK directly ===
                7'd4:  get_reg_entry = {8'h11, 8'h80}; // CLKRC: use external clock directly
                7'd5:  get_reg_entry = {8'h6B, 8'h00}; // DBLV: PLL BYPASS (was 0x4A=4x, caused PCLK too fast!)
                7'd6:  get_reg_entry = {8'h1E, 8'h31}; // MVFP: mirror + flip

                // === Framing: QVGA window ===
                7'd7:  get_reg_entry = {8'h17, 8'h16}; // HSTART (shifted right +24px total)
                7'd8:  get_reg_entry = {8'h18, 8'h04}; // HSTOP
                7'd9:  get_reg_entry = {8'h32, 8'hB6}; // HREF
                7'd10: get_reg_entry = {8'h19, 8'h03}; // VSTRT (shifted down)
                7'd11: get_reg_entry = {8'h1A, 8'h7B}; // VSTOP
                7'd12: get_reg_entry = {8'h03, 8'h0A}; // VREF

                // === Scaling: NO DCW (direct QVGA output) ===
                7'd13: get_reg_entry = {8'h0C, 8'h00}; // COM3: no scaling (was 0x0C = DCW enabled!)
                7'd14: get_reg_entry = {8'h3E, 8'h00}; // COM14: no prescaler (was 0x19!)
                7'd15: get_reg_entry = {8'h70, 8'h00}; // SCALING_XSC: default (was 0x3A)
                7'd16: get_reg_entry = {8'h71, 8'h00}; // SCALING_YSC: default (was 0x35)
                7'd17: get_reg_entry = {8'h72, 8'h11}; // SCALING_DCWCTR
                7'd18: get_reg_entry = {8'h73, 8'h00}; // SCALING_PCLK_DIV (was 0xF1!)
                7'd19: get_reg_entry = {8'hA2, 8'h02}; // SCALING_PCLK_DELAY

                // === Pixel clock ===
                7'd20: get_reg_entry = {8'h15, 8'h00}; // COM10: PCLK always toggles

                // === Gamma curve (from reference) ===
                7'd21: get_reg_entry = {8'h7A, 8'h20}; // SLOP
                7'd22: get_reg_entry = {8'h7B, 8'h1C}; // GAM1
                7'd23: get_reg_entry = {8'h7C, 8'h28}; // GAM2
                7'd24: get_reg_entry = {8'h7D, 8'h3C}; // GAM3
                7'd25: get_reg_entry = {8'h7E, 8'h55}; // GAM4
                7'd26: get_reg_entry = {8'h7F, 8'h68}; // GAM5
                7'd27: get_reg_entry = {8'h80, 8'h76}; // GAM6
                7'd28: get_reg_entry = {8'h81, 8'h80}; // GAM7
                7'd29: get_reg_entry = {8'h82, 8'h88}; // GAM8
                7'd30: get_reg_entry = {8'h83, 8'h8F}; // GAM9
                7'd31: get_reg_entry = {8'h84, 8'h96}; // GAM10
                7'd32: get_reg_entry = {8'h85, 8'hA3}; // GAM11
                7'd33: get_reg_entry = {8'h86, 8'hAF}; // GAM12
                7'd34: get_reg_entry = {8'h87, 8'hC4}; // GAM13
                7'd35: get_reg_entry = {8'h88, 8'hD7}; // GAM14
                7'd36: get_reg_entry = {8'h89, 8'hE8}; // GAM15

                // === AGC / AEC / AWB (from reference) ===
                7'd37: get_reg_entry = {8'h13, 8'hE0}; // COM8: disable AGC/AWB/AEC first
                7'd38: get_reg_entry = {8'h00, 8'h00}; // GAIN
                7'd39: get_reg_entry = {8'h10, 8'h00}; // AECH
                7'd40: get_reg_entry = {8'h0D, 8'h00}; // COM4
                7'd41: get_reg_entry = {8'h14, 8'h18}; // COM9: 2x AGC ceiling (reduced from 4x to lower noise)
                7'd42: get_reg_entry = {8'hA5, 8'h05}; // BD50MAX
                7'd43: get_reg_entry = {8'hAB, 8'h07}; // BD60MAX
                7'd44: get_reg_entry = {8'h24, 8'h75}; // AEW: AGC/AEC stable upper limit
                7'd45: get_reg_entry = {8'h25, 8'h63}; // AEB: AGC/AEC stable lower limit
                7'd46: get_reg_entry = {8'h26, 8'hA5}; // VPT: fast mode operating region
                7'd47: get_reg_entry = {8'h9F, 8'h78}; // HAECC1
                7'd48: get_reg_entry = {8'hA0, 8'h68}; // HAECC2
                7'd49: get_reg_entry = {8'hA1, 8'h03}; // Magic
                7'd50: get_reg_entry = {8'hA6, 8'hDF}; // HAECC3
                7'd51: get_reg_entry = {8'hA7, 8'hDF}; // HAECC4
                7'd52: get_reg_entry = {8'hA8, 8'hF0}; // HAECC5
                7'd53: get_reg_entry = {8'hA9, 8'h90}; // HAECC6
                7'd54: get_reg_entry = {8'hAA, 8'h94}; // HAECC7
                7'd55: get_reg_entry = {8'h13, 8'hEF}; // COM8: re-enable AGC/AWB (not AEC)
                7'd56: get_reg_entry = {8'h0E, 8'h61}; // COM5
                7'd57: get_reg_entry = {8'h0F, 8'h4B}; // COM6
                7'd58: get_reg_entry = {8'hB0, 8'h84}; // Color magic (was Reserved)

                // === Color matrix (for correct RGB565 colors) ===
                7'd59: get_reg_entry = {8'h4F, 8'hB3}; // MTX1
                7'd60: get_reg_entry = {8'h50, 8'hB3}; // MTX2
                7'd61: get_reg_entry = {8'h51, 8'h00}; // MTX3
                7'd62: get_reg_entry = {8'h52, 8'h3D}; // MTX4
                7'd63: get_reg_entry = {8'h53, 8'hA7}; // MTX5
                7'd64: get_reg_entry = {8'h54, 8'hE4}; // MTX6
                7'd65: get_reg_entry = {8'h58, 8'h9E}; // MTXS

                // === AWB (from reference) ===
                7'd66: get_reg_entry = {8'h6C, 8'h0A}; // AWBCTR3
                7'd67: get_reg_entry = {8'h6D, 8'h55}; // AWBCTR2
                7'd68: get_reg_entry = {8'h6E, 8'h11}; // AWBCTR1
                7'd69: get_reg_entry = {8'h6F, 8'h9F}; // AWBCTR0
                7'd70: get_reg_entry = {8'h01, 8'h96}; // BLUE gain (Boosted to combat green tint)
                7'd71: get_reg_entry = {8'h02, 8'h8C}; // RED gain (Boosted to combat green tint)
                // === EEVblog Calibration & Magic Registers ===
                7'd72: get_reg_entry = {8'h16, 8'h02}; // Reserved magic
                7'd73: get_reg_entry = {8'h21, 8'h02}; // AEC/AGC tuning
                7'd74: get_reg_entry = {8'h22, 8'h91}; // AEC/AGC tuning
                7'd75: get_reg_entry = {8'h29, 8'h07}; // AEC/AGC tuning
                7'd76: get_reg_entry = {8'h33, 8'h0B}; // Array control
                7'd77: get_reg_entry = {8'h35, 8'h0B}; // Array control
                7'd78: get_reg_entry = {8'h37, 8'h1D}; // ADC control
                7'd79: get_reg_entry = {8'h38, 8'h71}; // ADC control
                7'd80: get_reg_entry = {8'h39, 8'h2A}; // ADC control
                7'd81: get_reg_entry = {8'h3C, 8'h78}; // COM12: magic reserved
                7'd82: get_reg_entry = {8'h4D, 8'h40}; // MTX7: Matrix extension
                7'd83: get_reg_entry = {8'h4E, 8'h20}; // MTX8: Matrix extension
                7'd84: get_reg_entry = {8'h69, 8'h00}; // GFIX: gain control
                7'd85: get_reg_entry = {8'h74, 8'h10}; // REG74: magic reserved
                7'd86: get_reg_entry = {8'h8D, 8'h4F}; // Magic reserved
                7'd87: get_reg_entry = {8'h8E, 8'h00}; // Magic reserved
                7'd88: get_reg_entry = {8'h8F, 8'h00}; // Magic reserved
                7'd89: get_reg_entry = {8'h90, 8'h00}; // Magic reserved
                7'd90: get_reg_entry = {8'h91, 8'h00}; // Magic reserved
                7'd91: get_reg_entry = {8'h96, 8'h00}; // Magic reserved
                7'd92: get_reg_entry = {8'h9A, 8'h00}; // Magic reserved
                7'd93: get_reg_entry = {8'hB1, 8'h0C}; // Magic reserved
                7'd94: get_reg_entry = {8'hB2, 8'h0E}; // Magic reserved
                7'd95: get_reg_entry = {8'hB3, 8'h82}; // Magic reserved
                7'd96: get_reg_entry = {8'hB8, 8'h0A}; // Magic reserved
                // 7'd97: get_reg_entry = {8'h41, 8'h3E}; // COM16: Matrix ENABLED, De-noise ENABLED, Edge Enhancement ENABLED
                // 7'd98: get_reg_entry = {8'h76, 8'hE1}; // REG76: De-noise ENABLED
                // 7'd99: get_reg_entry = {8'h77, 8'h11}; // REG77: De-noise offset (increased)
                // 7'd100:get_reg_entry = {8'h4C, 8'h10}; // DNSTH: De-noise strength (maximized for noise reduction)

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
                //------------------------------------------------------------
                ST_SWRESET_WAIT: begin
                    if (sccb_done) begin
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
                        // Load register entry from ROM via continuous wire assignment
                        sccb_addr    <= current_entry_wire[15:8];
                        sccb_data    <= current_entry_wire[7:0];
                        sccb_start   <= 1'b1;
                        state        <= ST_WAIT_SCCB;
                    end
                end

                //------------------------------------------------------------
                // Wait for SCCB transaction to complete
                //------------------------------------------------------------
                ST_WAIT_SCCB: begin
                    if (sccb_done) begin
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
