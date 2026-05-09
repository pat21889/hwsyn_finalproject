`timescale 1ns / 1ps
//============================================================================
// Module: ov7670_init
// Description: OV7670 Camera Initialization Sequencer
//              Pure, clean RGB565 configuration with Native AWB.
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
    wire [15:0] current_entry_wire = get_reg_entry(reg_index); // Avoids select-on-function-call error

    //------------------------------------------------------------------------
    // Register initialization ROM table
    // Format: {8'h_addr, 8'h_data}
    //------------------------------------------------------------------------
    localparam NUM_REGS = 7'd23;

    function [15:0] get_reg_entry;
        input [6:0] index;
        begin
            case (index)
                // === Core format: RGB565 QVGA ===
                7'd0:  get_reg_entry = {8'h12, 8'h14}; // COM7: QVGA + RGB mode
                7'd1:  get_reg_entry = {8'h40, 8'hD0}; // COM15: full range [00-FF], RGB565 (bit4=1 enables RGB565)
                7'd2:  get_reg_entry = {8'h3A, 8'h04}; // TSLB: normal byte order
                7'd3:  get_reg_entry = {8'h3D, 8'hC0}; // COM13: gamma enable, UV auto, DO NOT swap UV
                7'd4:  get_reg_entry = {8'h8C, 8'h00}; // RGB444: Disable RGB444, ensure RGB565

                // === Clock & Image Rotation ===
                7'd5:  get_reg_entry = {8'h11, 8'h80}; // CLKRC: use external clock directly
                7'd6:  get_reg_entry = {8'h1E, 8'h30}; // MVFP: Mirror + V-flip (Rotate 180 deg)
                
                // === Enable Auto White Balance, Gain, and Exposure ===
                7'd7:  get_reg_entry = {8'h13, 8'hE7}; // COM8: Enable AEC, AGC, AWB
                7'd8:  get_reg_entry = {8'h01, 8'h80}; // BLUE gain (Default, AWB will adjust)
                7'd9:  get_reg_entry = {8'h02, 8'h80}; // RED gain (Default, AWB will adjust)

                // === Framing: QVGA window ===
                7'd10: get_reg_entry = {8'h17, 8'h13}; // HSTART
                7'd11: get_reg_entry = {8'h18, 8'h01}; // HSTOP
                7'd12: get_reg_entry = {8'h32, 8'hB6}; // HREF
                7'd13: get_reg_entry = {8'h19, 8'h02}; // VSTRT
                7'd14: get_reg_entry = {8'h1A, 8'h7A}; // VSTOP
                7'd15: get_reg_entry = {8'h03, 8'h0A}; // VREF

                // === Color matrix (Standard RGB565 Linux Matrix) ===
                7'd16: get_reg_entry = {8'h4F, 8'h80}; // MTX1
                7'd17: get_reg_entry = {8'h50, 8'h80}; // MTX2
                7'd18: get_reg_entry = {8'h51, 8'h00}; // MTX3
                7'd19: get_reg_entry = {8'h52, 8'h22}; // MTX4
                7'd20: get_reg_entry = {8'h53, 8'h5E}; // MTX5
                7'd21: get_reg_entry = {8'h54, 8'h80}; // MTX6
                7'd22: get_reg_entry = {8'h58, 8'h9E}; // MTXS (CRITICAL: Fixes inverted red signs!)

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
