# Antigravity Agent Prompt — Complete Final Project: Real-Time Video Capture and Processing System

You are an expert FPGA/Verilog engineer. Before doing anything else, **read and acknowledge every file in the `/resources` folder** at the root of this project. This includes:

- `HW_Synthesis_Lab_I_2025_2_-_Final_Project__Real-Time_Video_Capture_and_Processing_System.md` — the full project spec and grading rubric
- `OV7670_2006.pdf` — the OV7670 camera sensor datasheet (register map, timing diagrams, output formats, pin descriptions)
- `SCCBSpec_AN.pdf` — the OmniVision SCCB protocol specification (I2C-like, 2-wire mode, 3-phase write transmission, timing constraints)

Summarize what you have read from each file before writing any code. Confirm you understand the grading rubric, the three required filters, the pin mapping, and the VGA timing requirements before proceeding.

---

## Project Context

This is a university FPGA final project worth 30 points. The target hardware is:

- **FPGA Board:** Basys 3 (Xilinx Artix-7, 100MHz onboard clock, 1800 Kbits BRAM)
- **Camera:** OV7670 (VGA CMOS sensor, configured via SCCB 2-wire protocol)
- **Output:** VGA monitor via the Basys 3's VGA port (4-bit per channel: `vga_r[3:0]`, `vga_g[3:0]`, `vga_b[3:0]`)

**Pin mapping — use these exactly in the `.xdc` constraints file:**

| FPGA Pin | Camera Signal |
|----------|---------------|
| P17      | D0            |
| N17      | D1            |
| M19      | D2            |
| M18      | D3            |
| L17      | D4            |
| K17      | D5            |
| C16      | D6            |
| B16      | D7            |
| A17      | HREF          |
| A16      | PCLK          |
| R18      | PWDN          |
| P18      | RST           |
| A14      | SCL (SIO_C)   |
| A15      | SDA (SIO_D)   |
| B15      | VSYNC         |
| C15      | XCLK          |

**Filter selection via Basys 3 slide switches:**

| Switch | Mode               |
|--------|--------------------|
| SW[1:0] = 00 | Raw video feed (no filter) |
| SW[1:0] = 01 | Filter 1: Color Inversion (Negative) |
| SW[1:0] = 10 | Filter 2: Red Channel Isolation |
| SW[1:0] = 11 | Filter 3: Thresholding (Binary / Black & White) |

---

## Full Deliverables — Implement Every Module Below

Implement all modules in synthesizable Verilog (`.v`) or SystemVerilog (`.sv`). Every module must be well-commented. Every state machine must have named states and clearly commented transitions. Flag uncertain register values with `// TODO: verify`.

---

### 1. `clk_wiz` — Clock Management (Xilinx IP)

- Input: 100MHz onboard oscillator
- Output 1: **25MHz** — VGA pixel clock
- Output 2: **24MHz** — XCLK for OV7670 (datasheet range: 10–48MHz, typical 24MHz)
- Use Xilinx Clocking Wizard IP or instantiate an MMCM primitive directly
- Provide the `.xci` or the MMCM instantiation code

---

### 2. `sccb_master.v` — SCCB Controller

Implement the 2-wire SCCB protocol per `SCCBSpec_AN.pdf`:

- **3-phase write transmission:** ID address (phase 1) → sub-address (phase 2) → write data (phase 3)
- Each phase is 9 bits: 8 data bits MSB-first, followed by 1 Don't-Care bit
- Start condition: SDA goes low while SCL is high
- Stop condition: SDA goes high while SCL is high
- Timing constraints to respect:
  - `tCYC` ≥ 10µs per bit (clock ≤ 100kHz)
  - `tPRA` ≥ 1.25µs (pre-active time of SCCB_E before SDA goes low)
  - `tPRC` ≥ 15ns (pre-charge time of SDA)
  - `tmack` ≥ 1.25µs (SDA_OE de-assertion time around Don't-Care bit)
- OV7670 slave write address: `0x42` (7-bit ID `0x21`, R/W bit = 0)
- Interface ports: `clk`, `rst`, `start`, `addr [7:0]`, `data [7:0]`, `done`, `scl`, `sda`
- Implement as a clean FSM: IDLE → START → SEND_PHASE1 → DONTCARE1 → SEND_PHASE2 → DONTCARE2 → SEND_PHASE3 → DONTCARE3 → STOP → DONE

---

### 3. `ov7670_init.v` — Camera Initialization Sequencer

- On power-on, assert RST low for at least 1ms, then release
- Wait at least 1ms after RST release before SCCB communication (`tS:RESET`)
- Send software reset: write `0x80` to register `COM7` (`0x12`) via SCCB
- Wait 300ms for all registers to settle (`tS:REG` = 10 frames)
- Then sequentially send the full register init table below via the `sccb_master` module
- Use a ROM-style init table: an array of `[8'h_addr, 8'h_data]` pairs iterated by a counter FSM

**Complete OV7670 register initialization sequence for RGB565 QVGA output:**

```
// Reset all registers
{8'h12, 8'h80}  // COM7: software reset

// After 300ms delay, send the following:

// Output format: RGB565
{8'h12, 8'h14}  // COM7: QVGA + RGB mode (bit4=QVGA, bit2=RGB)
{8'h40, 8'hD0}  // COM15: RGB565 output range [00]~[FF]
{8'h8C, 8'h00}  // RGB444: disable RGB444

// Clock
{8'h11, 8'h80}  // CLKRC: use external clock directly (no prescale)
{8'h6B, 8'h4A}  // DBLV: PLL x4 (to get 24MHz*4 internally if needed)

// Image format and DCW for QVGA
{8'h0C, 8'h0C}  // COM3: scale enable + DCW enable
{8'h3E, 8'h19}  // COM14: DCW+scaling PCLK enable, PCLK divider /2
{8'h72, 8'h11}  // SCALING_DCWCTR: H and V downsample by 2
{8'h73, 8'hF1}  // SCALING_PCLK_DIV: bypass clock divider

// Window / framing for QVGA
{8'h17, 8'h16}  // HSTART
{8'h18, 8'h04}  // HSTOP
{8'h32, 8'hA4}  // HREF
{8'h19, 8'h02}  // VSTRT
{8'h1A, 8'h7A}  // VSTOP
{8'h03, 8'h0A}  // VREF

// Pixel clock options
{8'h15, 8'h20}  // COM10: PCLK does not toggle during hblank

// Disable test pattern
{8'h70, 8'h3A}  // SCALING_XSC: test_pattern[0]=0
{8'h71, 8'h35}  // SCALING_YSC: test_pattern[1]=0

// Color matrix for RGB
{8'h4F, 8'h40}  // MTX1
{8'h50, 8'h34}  // MTX2
{8'h51, 8'h0C}  // MTX3
{8'h52, 8'h17}  // MTX4
{8'h53, 8'h29}  // MTX5
{8'h54, 8'h40}  // MTX6
{8'h58, 8'h1E}  // MTXS

// AGC / AEC / AWB
{8'h13, 8'hE7}  // COM8: fast AGC, AEC step unlimited, banding ON, AGC+AWB+AEC enable
{8'h00, 8'h00}  // GAIN: AGC gain = 0
{8'h10, 8'h40}  // AECH: exposure
{8'h01, 8'h80}  // BLUE: AWB blue gain
{8'h02, 8'h80}  // RED: AWB red gain
{8'h0E, 8'h01}  // COM5: reserved default
{8'h0F, 8'h4B}  // COM6: reset timing on format change

// Gamma
{8'h7A, 8'h24}  // SLOP
{8'h7B, 8'h04}  // GAM1
{8'h7C, 8'h07}  // GAM2
{8'h7D, 8'h10}  // GAM3
{8'h7E, 8'h28}  // GAM4
{8'h7F, 8'h36}  // GAM5
{8'h80, 8'h44}  // GAM6
{8'h81, 8'h52}  // GAM7
{8'h82, 8'h60}  // GAM8
{8'h83, 8'h6C}  // GAM9
{8'h84, 8'h78}  // GAM10
{8'h85, 8'h8C}  // GAM11
{8'h86, 8'h9E}  // GAM12
{8'h87, 8'hBB}  // GAM13
{8'h88, 8'hD2}  // GAM14
{8'h89, 8'hE5}  // GAM15

// AWB advanced
{8'h6C, 8'h02}  // AWBCTR3
{8'h6D, 8'h55}  // AWBCTR2
{8'h6E, 8'hC0}  // AWBCTR1
{8'h6F, 8'h9A}  // AWBCTR0

// Lens correction off
{8'h66, 8'h00}  // LCC5: lens correction disable

// De-noise and edge
{8'h4C, 8'h00}  // DNSTH
{8'h3F, 8'h00}  // EDGE
{8'h41, 8'h08}  // COM16: default

// UV / saturation
{8'h3D, 8'h88}  // COM13: gamma enable, UV auto adjust
{8'h3A, 8'h04}  // TSLB: YUYV sequence, auto window off

// Banding filter (50Hz for Thailand)
{8'h3B, 8'h0A}  // COM11: 50Hz auto detect + banding ON
{8'h9D, 8'h99}  // BD50ST: 50Hz banding value
{8'hA5, 8'h0F}  // BD50MAX

// Histogram AEC
{8'hAA, 8'h94}  // HAECC7: histogram-based AEC

// End marker (use a special value like 8'hFF, 8'hFF to signal done)
{8'hFF, 8'hFF}  // END OF INIT TABLE
```

> **Note:** Flag any register value you are uncertain about with `// TODO: verify`. Cross-check every address and value against the OV7670 register table in `OV7670_2006.pdf`.

---

### 4. `ov7670_capture.v` — Pixel Capture / Frame Buffer Writer

- Sample `D[7:0]` on the **falling edge of PCLK** (per OV7670 datasheet `tPDV` timing)
- Gate valid data with `HREF` (data valid only when `HREF = 1`)
- Use `VSYNC` rising edge to reset write address to 0 (start of new frame)
- **RGB565 byte handling:** camera sends 2 bytes per pixel on consecutive PCLK cycles
  - Byte 1 (first PCLK when HREF=1): `[R4:R0, G5:G3]`
  - Byte 2 (next PCLK): `[G2:G0, B4:B0]`
  - Combine: `pixel_rgb565 = {byte1, byte2}` = 16 bits
  - Downsample to 12-bit RGB444 for BRAM storage: `{R[4:1], G[5:2], B[4:1]}`
- **BRAM addressing:** `write_addr = row * 320 + col`, range 0–76799
- Frame buffer size: 320 × 240 × 12 bits = 921,600 bits ≈ 922 Kbits (fits in 1800 Kbits)
- Ports: `pclk`, `rst`, `href`, `vsync`, `d[7:0]`, `wr_addr[16:0]`, `wr_data[11:0]`, `wr_en`

---

### 5. `frame_buffer.v` — Dual-Port Block RAM

- Instantiate a true dual-port BRAM using Xilinx RAMB36 primitive or Vivado Block Memory Generator IP
- **Port A (write):** clocked on PCLK, written by `ov7670_capture`
  - Width: 12 bits, depth: 76,800 addresses
- **Port B (read):** clocked on 25MHz VGA clock, read by `vga_display`
  - Width: 12 bits, depth: 76,800 addresses
- This dual-port architecture safely crosses the PCLK → VGA clock domain boundary
- If using ping-pong buffering for cleaner frames, implement two BRAMs and a swap signal on VSYNC

---

### 6. `vga_sync.v` — VGA Sync Signal Generator

Generate standard **640×480 @ 60Hz** VGA timing using a 25MHz pixel clock:

| Parameter         | Value                                      |
|-------------------|--------------------------------------------|
| Pixel clock       | 25 MHz                                     |
| H active          | 640 pixels                                 |
| H front porch     | 16 pixels                                  |
| H sync pulse      | 96 pixels (active low)                     |
| H back porch      | 48 pixels                                  |
| H total           | 800 pixels                                 |
| V active          | 480 lines                                  |
| V front porch     | 10 lines                                   |
| V sync pulse      | 2 lines (active low)                       |
| V back porch      | 33 lines                                   |
| V total           | 525 lines                                  |

- Output signals: `hsync`, `vsync`, `hactive`, `vactive`, `hcount [9:0]`, `vcount [9:0]`
- `hactive` and `vactive` are both high only during the active display region

---

### 7. `image_filter.v` — Real-Time Image Filter Module

Implement all three filters as combinational logic. Select via `sw[1:0]` input.

**Input:** `pixel_in [11:0]` = RGB444 formatted as `{R[3:0], G[3:0], B[3:0]}`
**Output:** `pixel_out [11:0]` = filtered RGB444

```
Filter select (sw[1:0]):
  2'b00 → Raw (pass-through): pixel_out = pixel_in

  2'b01 → Color Inversion (Negative):
           R_out = 4'hF - R_in
           G_out = 4'hF - G_in
           B_out = 4'hF - B_in

  2'b10 → Red Channel Isolation:
           R_out = R_in
           G_out = 4'h0
           B_out = 4'h0

  2'b11 → Thresholding (Binary / Black & White):
           // Compute luminance approximation:
           // luma = (R*5 + G*9 + B*2) >> 4  (integer approximation of 0.299R+0.587G+0.114B scaled to 4-bit)
           // If luma >= threshold (e.g. 4'h8): output white (4'hF, 4'hF, 4'hF)
           // Else: output black (4'h0, 4'h0, 4'h0)
```

- All filter logic must be **purely combinational** — no registers, no clock
- Make the threshold for filter 3 a parameter so it can be tuned easily

---

### 8. `vga_display.v` — Frame Buffer Reader + Filter + VGA Output

- Compute BRAM read address from VGA scan position with pixel doubling:
  ```
  bram_col = hcount >> 1   // divide by 2 (pixel doubling horizontal)
  bram_row = vcount >> 1   // divide by 2 (pixel doubling vertical)
  rd_addr  = bram_row * 320 + bram_col
  ```
- Read 12-bit RGB444 pixel from BRAM at `rd_addr`
- Pass pixel through `image_filter` module with current `sw[1:0]` selection
- Drive VGA color outputs:
  ```
  vga_r = (hactive & vactive) ? filtered_pixel[11:8] : 4'h0
  vga_g = (hactive & vactive) ? filtered_pixel[7:4]  : 4'h0
  vga_b = (hactive & vactive) ? filtered_pixel[3:0]  : 4'h0
  ```
- Output black during any blanking interval

---

### 9. `top.v` — Top-Level Module

Wire all modules together. The top-level ports must include:

```verilog
module top (
    input  wire        clk100,        // Basys 3 100MHz oscillator
    // Camera inputs
    input  wire        cam_pclk,
    input  wire        cam_href,
    input  wire        cam_vsync,
    input  wire [7:0]  cam_d,
    // Camera outputs
    output wire        cam_xclk,
    output wire        cam_pwdn,
    output wire        cam_rst,
    output wire        cam_scl,
    inout  wire        cam_sda,
    // VGA outputs
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    // User controls
    input  wire [1:0]  sw            // SW[1:0] for filter select
);
```

Internal wiring checklist:
- `clk_wiz` → `clk_25mhz` (to VGA), `clk_24mhz` (to cam_xclk)
- `ov7670_init` → `sccb_master` → `cam_scl`, `cam_sda`
- `ov7670_capture` (clocked on `cam_pclk`) → `frame_buffer` port A
- `frame_buffer` port B → `vga_display` (clocked on `clk_25mhz`)
- `vga_sync` → `vga_display` → `vga_r/g/b`, `vga_hsync`, `vga_vsync`
- `image_filter` instantiated inside `vga_display`
- `cam_pwdn` = 0 (always active/normal mode)
- `cam_rst` = 1 after reset sequence (active low reset released)

---

### 10. `constraints.xdc` — Full Constraint File

Include all of the following:

```tcl
# === Basys 3 System Clock ===
set_property PACKAGE_PIN W5 [get_ports clk100]
set_property IOSTANDARD LVCMOS33 [get_ports clk100]
create_clock -period 10.000 -name sys_clk [get_ports clk100]

# === Camera Data Pins ===
set_property PACKAGE_PIN P17 [get_ports {cam_d[0]}]
set_property PACKAGE_PIN N17 [get_ports {cam_d[1]}]
set_property PACKAGE_PIN M19 [get_ports {cam_d[2]}]
set_property PACKAGE_PIN M18 [get_ports {cam_d[3]}]
set_property PACKAGE_PIN L17 [get_ports {cam_d[4]}]
set_property PACKAGE_PIN K17 [get_ports {cam_d[5]}]
set_property PACKAGE_PIN C16 [get_ports {cam_d[6]}]
set_property PACKAGE_PIN B16 [get_ports {cam_d[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_d[*]}]

# === Camera Control Pins ===
set_property PACKAGE_PIN A17 [get_ports cam_href]
set_property PACKAGE_PIN A16 [get_ports cam_pclk]
set_property PACKAGE_PIN R18 [get_ports cam_pwdn]
set_property PACKAGE_PIN P18 [get_ports cam_rst]
set_property PACKAGE_PIN A14 [get_ports cam_scl]
set_property PACKAGE_PIN A15 [get_ports cam_sda]
set_property PACKAGE_PIN B15 [get_ports cam_vsync]
set_property PACKAGE_PIN C15 [get_ports cam_xclk]
set_property IOSTANDARD LVCMOS33 [get_ports cam_href]
set_property IOSTANDARD LVCMOS33 [get_ports cam_pclk]
set_property IOSTANDARD LVCMOS33 [get_ports cam_pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports cam_rst]
set_property IOSTANDARD LVCMOS33 [get_ports cam_scl]
set_property IOSTANDARD LVCMOS33 [get_ports cam_sda]
set_property IOSTANDARD LVCMOS33 [get_ports cam_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports cam_xclk]

# === Camera PCLK as input clock (treat as ~24MHz) ===
create_clock -period 41.667 -name cam_pclk_clk [get_ports cam_pclk]
set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks cam_pclk_clk]

# === VGA Pins (Basys 3 standard) ===
set_property PACKAGE_PIN G19 [get_ports {vga_r[0]}]
set_property PACKAGE_PIN H19 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN J19 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN N19 [get_ports {vga_r[3]}]
set_property PACKAGE_PIN J17 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN H17 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN G17 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D17 [get_ports {vga_g[3]}]
set_property PACKAGE_PIN N18 [get_ports {vga_b[0]}]
set_property PACKAGE_PIN L18 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN K18 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN J18 [get_ports {vga_b[3]}]
set_property PACKAGE_PIN P19 [get_ports vga_hsync]
set_property PACKAGE_PIN R19 [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]

# === Slide Switches ===
set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
set_property PACKAGE_PIN V16 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]
```

---

### 11. Testbenches — One Per Major Module

Provide a simulation testbench for each of the following. Each testbench must demonstrate correct logical behavior via waveforms **before synthesis.**

#### `tb_sccb_master.v`
- Drive `start`, `addr`, `data`
- Verify `scl` and `sda` toggle correctly per SCCB protocol
- Check: start condition → 3 phases of 9 bits each → stop condition
- Verify `done` goes high after transmission completes

#### `tb_ov7670_capture.v`
- Simulate PCLK, HREF, VSYNC, and D[7:0] stimulus mimicking OV7670 RGB565 output
- Verify correct byte-pairing and RGB444 conversion
- Verify write address increments correctly per pixel and resets on VSYNC

#### `tb_vga_sync.v`
- Run for at least 2 full frames (2 × 525 × 800 pixel clocks)
- Verify `hsync` and `vsync` pulse widths and polarities
- Verify `hcount` and `vcount` ranges
- Verify `hactive` and `vactive` are high only during active region

#### `tb_image_filter.v`
- Apply known RGB444 input values for all 4 switch positions
- Verify pass-through, inversion math, red isolation, and threshold logic
- Test edge cases: all-black input, all-white input, mid-gray input

#### `tb_top.v` (integration)
- Simplified top-level smoke test
- Provide basic camera stimulus and verify VGA sync signals are generated
- Does not need to be cycle-accurate — just confirms no X-propagation at outputs

---

## Implementation & Code Quality Requirements

- All RTL code must be **fully synthesizable**: no `#delay`, no `initial` blocks outside testbenches, no `$display` in RTL
- Use **synchronous resets** (reset sampled on clock edge) throughout all modules
- Every FSM must use a `localparam` or `parameter` for each state name — no magic numbers for states
- Use **`always_ff`** for sequential logic and **`always_comb`** for combinational logic if writing SystemVerilog; or `always @(posedge clk)` / `always @(*)` if writing Verilog
- Separate concerns cleanly: one module per file, one responsibility per module
- The filter module must be purely combinational with no latency
- The BRAM must be inferred or instantiated as a true dual-port memory — do not use registers for the frame buffer

---

## Step-by-Step Vivado Guide

After generating all source files, provide a numbered guide covering:

1. **Create Vivado project** — target: Basys 3 (xc7a35tcpg236-1)
2. **Add all source files** — `.v`/`.sv` files and the `.xdc` constraint file
3. **Generate Clock Wizard IP** — configure for 25MHz and 24MHz outputs from 100MHz input; show exact settings
4. **Generate Block Memory Generator IP** (if not using primitive) — true dual-port, 12-bit wide, 76800 deep
5. **Run Synthesis** — expected warnings to ignore vs. warnings that indicate real problems
6. **Run Implementation** — check timing report: confirm setup/hold met on both clock domains
7. **Generate Bitstream**
8. **Program the Basys 3** via Vivado Hardware Manager
9. **Functional verification checklist:**
   - [ ] Monitor displays a live, recognizable image
   - [ ] SW[1:0]=00 shows raw color image
   - [ ] SW[1:0]=01 shows color-inverted image
   - [ ] SW[1:0]=10 shows red-channel-only image
   - [ ] SW[1:0]=11 shows black-and-white thresholded image
   - [ ] Image updates in real time (no frozen frames)
   - [ ] No severe tearing or color corruption

---

## File Structure to Produce

```
/src
  top.v
  clk_wiz.v              (or use IP — provide both options)
  sccb_master.v
  ov7670_init.v
  ov7670_capture.v
  frame_buffer.v
  vga_sync.v
  image_filter.v
  vga_display.v
/sim
  tb_sccb_master.v
  tb_ov7670_capture.v
  tb_vga_sync.v
  tb_image_filter.v
  tb_top.v
/constraints
  constraints.xdc
```

Implement every file completely. Do not leave placeholder comments in place of actual logic. After all files are written, do a final self-review pass and flag any potential timing issues, undriven signals, or missing connections.
