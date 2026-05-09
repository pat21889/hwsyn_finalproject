//============================================================================
// Module: sccb_master
// Description: SCCB (Serial Camera Control Bus) 2-wire master controller
//              Implements the 3-phase write transmission protocol per
//              OmniVision SCCB specification (SCCBSpec_AN.pdf).
//
// Protocol: 3-phase write transmission
//   Phase 1: ID Address (8'h42 for OV7670 write) + Don't-Care bit
//   Phase 2: Sub-address (register address) + Don't-Care bit
//   Phase 3: Write data (register value) + Don't-Care bit
//
// Each phase: 8 data bits (MSB first) + 1 Don't-Care bit = 9 clocks
// Start condition: SDA goes low while SCL is high
// Stop condition:  SDA goes high while SCL is high
//
// Timing (at 100MHz system clock):
//   tCYC >= 10us per bit -> SCL clock <= 100kHz
//   Using 500 system clocks per half-period = 1000 clocks per bit = 10us @ 100MHz
//============================================================================

module sccb_master (
    input  wire       clk,     // System clock (100MHz)
    input  wire       rst,     // Synchronous reset (active high)
    input  wire       start,   // Pulse high to begin a write transaction
    input  wire [7:0] addr,    // Register sub-address (phase 2)
    input  wire [7:0] data,    // Register write data (phase 3)
    output reg        done,    // Pulses high for 1 cycle when transaction completes
    output reg        scl,     // SCCB clock output
    inout  wire       sda      // SCCB bidirectional data line
);

    //------------------------------------------------------------------------
    // SCCB Timing Parameters
    // At 100MHz, 1 clock = 10ns
    // tCYC = 10us -> need 1000 system clocks per SCL period
    // Half-period = 500 clocks
    //------------------------------------------------------------------------
    localparam CLK_DIV = 10'd1000;  // Half-period count (10us each half = 50kHz SCL)
    localparam DEVICE_ADDR = 8'h42; // OV7670 write address (7'h21 + W=0)

    //------------------------------------------------------------------------
    // FSM State Encoding
    //------------------------------------------------------------------------
    localparam [3:0] ST_IDLE      = 4'd0;   // Waiting for start command
    localparam [3:0] ST_START     = 4'd1;   // Generate start condition
    localparam [3:0] ST_PHASE1    = 4'd2;   // Send device ID address (8 bits)
    localparam [3:0] ST_DONTCARE1 = 4'd3;   // Don't-care bit after phase 1
    localparam [3:0] ST_PHASE2    = 4'd4;   // Send sub-address (8 bits)
    localparam [3:0] ST_DONTCARE2 = 4'd5;   // Don't-care bit after phase 2
    localparam [3:0] ST_PHASE3    = 4'd6;   // Send write data (8 bits)
    localparam [3:0] ST_DONTCARE3 = 4'd7;   // Don't-care bit after phase 3
    localparam [3:0] ST_STOP      = 4'd8;   // Generate stop condition
    localparam [3:0] ST_DONE      = 4'd9;   // Transaction complete

    reg [3:0] state;

    //------------------------------------------------------------------------
    // Internal registers
    //------------------------------------------------------------------------
    reg [9:0]  clk_count;      // Clock divider counter
    reg [3:0]  bit_count;      // Bit counter within a phase (0-7 for data, 8 for DC)
    reg [7:0]  shift_reg;      // Shift register for current byte being sent
    reg        sda_out;        // SDA output value
    reg        sda_oe;         // SDA output enable (1 = drive, 0 = tri-state/release)
    reg [1:0]  start_phase;    // Sub-phases within START condition
    reg [1:0]  stop_phase;     // Sub-phases within STOP condition

    // Latched address and data (captured on start)
    reg [7:0]  addr_reg;
    reg [7:0]  data_reg;

    //------------------------------------------------------------------------
    // SDA open-drain emulation
    // SCCB/I2C requires open-drain: only drive LOW, never actively drive HIGH.
    // When we want to output '0': drive the line low  (sda_oe=1, sda_out=0)
    // When we want to output '1': release the line    (external pull-up pulls high)
    // When sda_oe=0: also release (for don't-care / ACK bits)
    //------------------------------------------------------------------------
    assign sda = (sda_oe && !sda_out) ? 1'b0 : 1'bz;

    //------------------------------------------------------------------------
    // SCL clock divider tick
    //------------------------------------------------------------------------
    wire clk_tick = (clk_count == CLK_DIV - 1);

    //------------------------------------------------------------------------
    // Main FSM
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state              <= ST_IDLE;

            clk_count          <= 10'd0;
            bit_count          <= 4'd0;
            shift_reg          <= 8'd0;
            sda_out            <= 1'b1;
            sda_oe             <= 1'b0;
            scl                <= 1'b1;
            done               <= 1'b0;
            start_phase        <= 2'd0;
            stop_phase         <= 2'd0;
            addr_reg           <= 8'd0;
            data_reg           <= 8'd0;
        end else begin
            done <= 1'b0; // Default: done is a pulse

            case (state)
                //------------------------------------------------------------
                // IDLE: Wait for start pulse
                //------------------------------------------------------------
                ST_IDLE: begin
                    scl     <= 1'b1;
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b1;   // Drive SDA high in idle
                    if (start) begin
                        addr_reg    <= addr;
                        data_reg    <= data;
                        state       <= ST_START;
                        start_phase <= 2'd0;
                        clk_count   <= 10'd0;
                    end
                end

                //------------------------------------------------------------
                // START: Generate start condition
                // SDA goes low while SCL is high
                // Phase 0: Ensure SCL=1, SDA=1, wait half period
                // Phase 1: Pull SDA low while SCL is high, wait half period
                // Phase 2: Pull SCL low, proceed to Phase 1 data
                //------------------------------------------------------------
                ST_START: begin
                    clk_count <= clk_count + 10'd1;
                    case (start_phase)
                        2'd0: begin
                            // Setup: SCL high, SDA high
                            scl     <= 1'b1;
                            sda_out <= 1'b1;
                            sda_oe  <= 1'b1;
                            if (clk_tick) begin
                                clk_count   <= 10'd0;
                                start_phase <= 2'd1;
                            end
                        end
                        2'd1: begin
                            // Start condition: pull SDA low while SCL is high
                            sda_out <= 1'b0;
                            if (clk_tick) begin
                                clk_count   <= 10'd0;
                                start_phase <= 2'd2;
                            end
                        end
                        2'd2: begin
                            // Pull SCL low, setup for first data bit
                            scl <= 1'b0;
                            if (clk_tick) begin
                                clk_count <= 10'd0;
                                state     <= ST_PHASE1;
                                bit_count <= 4'd0;
                                shift_reg <= DEVICE_ADDR; // Phase 1: device address 0x42
                                sda_out   <= DEVICE_ADDR[7]; // MSB first
                            end
                        end
                        default: start_phase <= 2'd0;
                    endcase
                end

                //------------------------------------------------------------
                // PHASE 1: Send Device ID Address (8 bits, MSB first)
                //------------------------------------------------------------
                ST_PHASE1: begin
                    clk_count <= clk_count + 10'd1;
                    if (clk_tick) begin
                        clk_count <= 10'd0;
                        if (scl == 1'b0) begin
                            // Rising edge of SCL: slave samples SDA
                            scl <= 1'b1;
                        end else begin
                            // Falling edge of SCL: update SDA for next bit
                            scl <= 1'b0;
                            if (bit_count == 4'd7) begin
                                // All 8 bits sent, move to don't-care
                                state              <= ST_DONTCARE1;
                                bit_count          <= 4'd0;
                                sda_oe             <= 1'b0; // Release SDA for don't-care
                            end else begin
                                bit_count <= bit_count + 4'd1;
                                shift_reg <= {shift_reg[6:0], 1'b0};
                                sda_out   <= shift_reg[6]; // Next bit (pre-shifted)
                            end
                        end
                    end
                end

                //------------------------------------------------------------
                // DONTCARE1: 9th bit — release SDA, clock once
                //------------------------------------------------------------
                ST_DONTCARE1: begin
                    clk_count <= clk_count + 10'd1;
                    sda_oe <= 1'b0; // Tri-state SDA (don't-care bit)
                    if (clk_tick) begin
                        clk_count <= 10'd0;
                        if (scl == 1'b0) begin
                            scl <= 1'b1; // Rising edge: slave drives don't-care
                        end else begin
                            scl     <= 1'b0; // Falling edge: done with don't-care
                            sda_oe  <= 1'b1; // Re-assert SDA control
                            state   <= ST_PHASE2;
                            shift_reg <= addr_reg; // Load sub-address for phase 2
                            sda_out   <= addr_reg[7]; // MSB first
                            bit_count <= 4'd0;
                        end
                    end
                end

                //------------------------------------------------------------
                // PHASE 2: Send Sub-Address (8 bits, MSB first)
                //------------------------------------------------------------
                ST_PHASE2: begin
                    clk_count <= clk_count + 10'd1;
                    if (clk_tick) begin
                        clk_count <= 10'd0;
                        if (scl == 1'b0) begin
                            scl <= 1'b1;
                        end else begin
                            scl <= 1'b0;
                            if (bit_count == 4'd7) begin
                                state              <= ST_DONTCARE2;
                                bit_count          <= 4'd0;
                                sda_oe             <= 1'b0;
                            end else begin
                                bit_count <= bit_count + 4'd1;
                                shift_reg <= {shift_reg[6:0], 1'b0};
                                sda_out   <= shift_reg[6];
                            end
                        end
                    end
                end

                //------------------------------------------------------------
                // DONTCARE2: 9th bit — release SDA, clock once
                //------------------------------------------------------------
                ST_DONTCARE2: begin
                    clk_count <= clk_count + 10'd1;
                    sda_oe <= 1'b0;
                    if (clk_tick) begin
                        clk_count <= 10'd0;
                        if (scl == 1'b0) begin
                            scl <= 1'b1;
                        end else begin
                            scl     <= 1'b0;
                            sda_oe  <= 1'b1;
                            state   <= ST_PHASE3;
                            shift_reg <= data_reg; // Load write data for phase 3
                            sda_out   <= data_reg[7];
                            bit_count <= 4'd0;
                        end
                    end
                end

                //------------------------------------------------------------
                // PHASE 3: Send Write Data (8 bits, MSB first)
                //------------------------------------------------------------
                ST_PHASE3: begin
                    clk_count <= clk_count + 10'd1;
                    if (clk_tick) begin
                        clk_count <= 10'd0;
                        if (scl == 1'b0) begin
                            scl <= 1'b1;
                        end else begin
                            scl <= 1'b0;
                            if (bit_count == 4'd7) begin
                                state              <= ST_DONTCARE3;
                                bit_count          <= 4'd0;
                                sda_oe             <= 1'b0;
                            end else begin
                                bit_count <= bit_count + 4'd1;
                                shift_reg <= {shift_reg[6:0], 1'b0};
                                sda_out   <= shift_reg[6];
                            end
                        end
                    end
                end

                //------------------------------------------------------------
                // DONTCARE3: 9th bit — release SDA, clock once, then STOP
                //------------------------------------------------------------
                ST_DONTCARE3: begin
                    clk_count <= clk_count + 10'd1;
                    sda_oe <= 1'b0;
                    if (clk_tick) begin
                        clk_count <= 10'd0;
                        if (scl == 1'b0) begin
                            scl <= 1'b1;
                        end else begin
                            scl        <= 1'b0;
                            sda_oe     <= 1'b1;
                            sda_out    <= 1'b0; // Prepare SDA low for stop condition
                            state      <= ST_STOP;
                            stop_phase <= 2'd0;
                        end
                    end
                end

                //------------------------------------------------------------
                // STOP: Generate stop condition
                // SDA goes high while SCL is high
                // Phase 0: SCL low, SDA low — wait
                // Phase 1: SCL high, SDA low — wait
                // Phase 2: SCL high, SDA high — stop condition generated
                //------------------------------------------------------------
                ST_STOP: begin
                    clk_count <= clk_count + 10'd1;
                    case (stop_phase)
                        2'd0: begin
                            scl     <= 1'b0;
                            sda_out <= 1'b0;
                            sda_oe  <= 1'b1;
                            if (clk_tick) begin
                                clk_count  <= 10'd0;
                                stop_phase <= 2'd1;
                            end
                        end
                        2'd1: begin
                            // Raise SCL while SDA stays low
                            scl <= 1'b1;
                            if (clk_tick) begin
                                clk_count  <= 10'd0;
                                stop_phase <= 2'd2;
                            end
                        end
                        2'd2: begin
                            // Raise SDA while SCL is high = STOP condition
                            sda_out <= 1'b1;
                            if (clk_tick) begin
                                clk_count <= 10'd0;
                                state     <= ST_DONE;
                            end
                        end
                        default: stop_phase <= 2'd0;
                    endcase
                end

                //------------------------------------------------------------
                // DONE: Signal completion, return to idle
                //------------------------------------------------------------
                ST_DONE: begin
                    done    <= 1'b1;
                    scl     <= 1'b1;
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b0;
                    state   <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
