//============================================================================
// Module: vga_display
// Description: Frame Buffer Reader + VGA Output Driver
//              Implements:
//              1. 90-degree CW Image Rotation (transposed BRAM addressing)
//              2. Bilinear Upscaling (320x240 -> 640x480)
//              3. Real-time Image Filters
//
// Architecture:
//   For 2x integer upscaling with rotation, we use a simple approach:
//   - Each source pixel maps to a 2x2 block of VGA pixels.
//   - We cache the previous source pixel horizontally and vertically
//     to blend edges.
//
//   Pipeline (4-cycle latency):
//     Cycle 0: Generate BRAM address for current source pixel
//     Cycle 1: BRAM returns data (1-cycle read latency)
//     Cycle 2: Register the pixel, compute bilinear blend
//     Cycle 3: Output register (VGA DAC)
//
//   Rotation mapping:
//     For 90 CW rotation of a 320x240 source:
//       src_col = 319 - cam_y   (cam_y = vcount/2, 0..239)
//       src_row = cam_x         (cam_x = hcount/2, 0..239, clamped)
//     BRAM addr = src_row * 320 + src_col
//
//   Bilinear:
//     For exact 2x upscaling, fractional position is 0 or 0.5.
//     We blend adjacent pixels with simple (A+B)>>1 or (A+B+C+D)>>2.
//     We cache the "previous row" pixel and "previous column" pixel.
//============================================================================

module vga_display (
    input  wire        clk,       // 25MHz VGA pixel clock
    input  wire        rst,       // Synchronous reset (active high)
    // VGA sync signals
    input  wire [9:0]  hcount,    // Horizontal pixel counter (0-799)
    input  wire [9:0]  vcount,    // Vertical line counter (0-524)
    input  wire        hactive,   // Horizontal active region
    input  wire        vactive,   // Vertical active region
    // Filter select
    input  wire [1:0]  sw,        // SW[1:0] for filter mode
    // Single-bank Frame buffer read port
    output reg  [16:0] rd_addr,   // Read address
    input  wire [11:0] rd_data,   // Read data (RGB444)
    // VGA color outputs
    output reg  [3:0]  vga_r,     // VGA red channel
    output reg  [3:0]  vga_g,     // VGA green channel
    output reg  [3:0]  vga_b      // VGA blue channel
);

    //------------------------------------------------------------------------
    // 1. Source coordinate calculation (with rotation)
    //------------------------------------------------------------------------
    // No rotation (Standard 320x240 display)
    // cam_x = hcount/2 (0..319), cam_y = vcount/2 (0..239)
    wire [8:0] cam_x = hcount[9:1]; // 0..319
    wire [8:0] cam_y = {1'b0, vcount[9:1]}; // 0..239

    wire [8:0] src_row = cam_y;
    wire [8:0] src_col = cam_x;

    // Previous row/col for bilinear neighbor access
    wire [8:0] src_row_prev = (src_row == 0) ? 9'd0 : (src_row - 9'd1);
    wire [8:0] src_col_prev = (src_col == 0) ? 9'd0 : (src_col - 9'd1);

    // Multiply helpers: row * 320 = row * 256 + row * 64
    // src_row max = 239, so 8 bits is sufficient
    // For current row
    wire [16:0] row_base = ({1'b0, src_row[7:0], 8'd0}) + ({3'b0, src_row[7:0], 6'd0});
    // For previous row  
    wire [16:0] row_prev_base = ({1'b0, src_row_prev[7:0], 8'd0}) + ({3'b0, src_row_prev[7:0], 6'd0});

    // Fractional bits for bilinear
    wire h_frac = hcount[0]; // 0=even pixel (copy), 1=odd pixel (blend)
    wire v_frac = vcount[0]; // 0=even line (copy), 1=odd line (blend)

    //------------------------------------------------------------------------
    // 2. BRAM Read Address — time-multiplexed
    //------------------------------------------------------------------------
    // We need up to 4 pixels for full bilinear, but only have 1 read port.
    // Strategy: Read the "current" pixel on every cycle. Use registers to
    // cache the "previous column" and "previous row" pixels from prior cycles.
    //
    // For 2x upscaling, each source pixel is displayed for 2 VGA clocks.
    // On the FIRST clock of each pair (h_frac=0): read P(row, col)
    // On the SECOND clock (h_frac=1): read P(row_prev, col) for vertical blend
    // We cache P(row, col-1) and P(row_prev, col-1) from the previous pair.
    //------------------------------------------------------------------------
    always @(*) begin
        if (h_frac == 1'b0) begin
            // Even pixel: fetch current position P(row, col)
            rd_addr = row_base + {8'd0, src_col};
        end else begin
            // Odd pixel: fetch vertical neighbor P(row-1, col) for v-blend
            rd_addr = row_prev_base + {8'd0, src_col};
        end
    end

    //------------------------------------------------------------------------
    // 3. Pixel Cache Pipeline
    //------------------------------------------------------------------------
    // Stage 1: Register BRAM output (arrives 1 cycle after address)
    reg [11:0] p_temp;         // Temporary storage for P(row, col)
    reg        h_frac_d1, h_frac_d2, h_frac_d3, h_frac_d4;
    reg [8:0]  src_col_d1, src_col_d2, src_col_d3;
    reg        v_frac_d1, v_frac_d2, v_frac_d3, v_frac_d4;

    // The 4 pixels for the bilinear neighborhood:
    //   p_curr     = P(row, col)       — current source pixel
    //   p_left     = P(row, col_prev)  — previous column (horizontal neighbor)
    //   p_above    = P(row_prev, col)  — previous row (vertical neighbor)
    //   p_diag     = P(row_prev, col_prev) — diagonal neighbor
    reg [11:0] p_curr, p_left;
    reg [11:0] p_above, p_diag;

    always @(posedge clk) begin
        if (rst) begin
            p_temp     <= 12'd0;
            h_frac_d1  <= 1'b0;
            h_frac_d2  <= 1'b0;
            h_frac_d3  <= 1'b0;
            h_frac_d4  <= 1'b0;
            src_col_d1 <= 9'd0;
            src_col_d2 <= 9'd0;
            src_col_d3 <= 9'd0;
            v_frac_d1  <= 1'b0;
            v_frac_d2  <= 1'b0;
            v_frac_d3  <= 1'b0;
            v_frac_d4  <= 1'b0;
            p_curr     <= 12'd0;
            p_left     <= 12'd0;
            p_above    <= 12'd0;
            p_diag     <= 12'd0;
        end else begin
            // Pipeline delays for fractional bits
            h_frac_d1  <= h_frac;
            h_frac_d2  <= h_frac_d1;
            h_frac_d3  <= h_frac_d2;
            h_frac_d4  <= h_frac_d3;
            src_col_d1 <= src_col;
            src_col_d2 <= src_col_d1;
            src_col_d3 <= src_col_d2;
            v_frac_d1  <= v_frac;
            v_frac_d2  <= v_frac_d1;
            v_frac_d3  <= v_frac_d2;
            v_frac_d4  <= v_frac_d3;
 
            // BRAM data arrives 1 cycle after address
            // Use h_frac_d1 to decide what to do with incoming rd_data
            if (h_frac_d1 == 1'b0) begin
                // Just received P(row, col). Cache it.
                p_temp <= rd_data;
            end else begin
                // Just received P(row_prev, col). 
                // Now we have both pixels for the current column.
                // Update the entire 4-pixel neighborhood at once.
                if (src_col_d2 == 9'd0) begin
                    p_left <= p_temp;
                    p_diag <= rd_data;
                end else begin
                    p_left <= p_curr;
                    p_diag <= p_above;
                end
                p_curr  <= p_temp;
                p_above <= rd_data;
            end
        end
    end

    //------------------------------------------------------------------------
    // 4. Bilinear Interpolation (combinational, uses registered pixels)
    //------------------------------------------------------------------------
    // Use h_frac_d4 and v_frac_d4 (aligned with the registered pixel data)
    wire [4:0] rc = p_curr[11:8],  rl = p_left[11:8],  ra = p_above[11:8],  rd_pix = p_diag[11:8];
    wire [4:0] gc = p_curr[7:4],   gl = p_left[7:4],   ga = p_above[7:4],   gd = p_diag[7:4];
    wire [4:0] bc = p_curr[3:0],   bl = p_left[3:0],   ba = p_above[3:0],   bd = p_diag[3:0];

    reg [3:0] r_out, g_out, b_out;

    always @(*) begin
        case ({v_frac_d4, h_frac_d4})
            2'b00: begin // Even X, Even Y: direct copy
                r_out = rc[3:0];
                g_out = gc[3:0];
                b_out = bc[3:0];
            end
            2'b01: begin // Odd X, Even Y: horizontal blend
                r_out = (rc + rl) >> 1;
                g_out = (gc + gl) >> 1;
                b_out = (bc + bl) >> 1;
            end
            2'b10: begin // Even X, Odd Y: vertical blend
                r_out = (rc + ra) >> 1;
                g_out = (gc + ga) >> 1;
                b_out = (bc + ba) >> 1;
            end
            2'b11: begin // Odd X, Odd Y: 4-way blend
                r_out = (rc + rl + ra + rd_pix) >> 2;
                g_out = (gc + gl + ga + gd) >> 2;
                b_out = (bc + bl + ba + bd) >> 2;
            end
        endcase
    end

    wire [11:0] interp_pixel = {r_out, g_out, b_out};

    //------------------------------------------------------------------------
    // 5. Image Filter
    //------------------------------------------------------------------------
    wire [11:0] filtered_pixel;

    image_filter u_filter (
        .pixel_in  (interp_pixel),
        .sw        (sw),
        .pixel_out (filtered_pixel)
    );

    //------------------------------------------------------------------------
    // 6. Output Stage
    //------------------------------------------------------------------------
    // Pipeline active signals to match total latency (4 cycles)
    reg [3:0] hactive_pipe, vactive_pipe;

    always @(posedge clk) begin
        if (rst) begin
            hactive_pipe <= 4'd0;
            vactive_pipe <= 4'd0;
        end else begin
            hactive_pipe <= {hactive_pipe[2:0], hactive};
            vactive_pipe <= {vactive_pipe[2:0], vactive};
        end
    end

    // Rotated image is 240 source cols → 480 VGA pixels wide.
    // cam_x > 239 is out of valid source range → black.
    reg [9:0] hcount_d1, hcount_d2, hcount_d3;
    always @(posedge clk) begin
        if (rst) begin
            hcount_d1 <= 10'd0;
            hcount_d2 <= 10'd0;
            hcount_d3 <= 10'd0;
        end else begin
            hcount_d1 <= hcount;
            hcount_d2 <= hcount_d1;
            hcount_d3 <= hcount_d2;
        end
    end
    // Standard image is 320 source cols -> 640 VGA pixels wide.
    wire out_in_range = (hcount_d3 < 10'd640);
    wire out_valid = hactive_pipe[3] && vactive_pipe[3] && out_in_range;

    always @(posedge clk) begin
        if (rst) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else begin
            if (out_valid) begin
                vga_r <= filtered_pixel[11:8];
                vga_g <= filtered_pixel[7:4];
                vga_b <= filtered_pixel[3:0];
            end else begin
                vga_r <= 4'h0;
                vga_g <= 4'h0;
                vga_b <= 4'h0;
            end
        end
    end

endmodule
