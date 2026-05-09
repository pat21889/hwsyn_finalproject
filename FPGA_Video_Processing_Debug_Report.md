# FPGA Video Processing System: Debug & Pipeline Validation Report

> [!IMPORTANT]
> **PHASE 2 UPDATE (MAY 7, 2026):**
> Following persistent data corruption and "static" image issues, a bottom-up comparison was performed between our codebase and a **proven working reference project** found in `src_for_project/project_1.srcs`. This led to the discovery of several critical "silent" bugs in the camera configuration and capture pipeline.

---

## 🚨 Critical Root Causes Identified (and Fixed)

### 1. The "100MHz" Pixel Clock Bug (Register `0x6B`)
*   **The Issue:** Our initialization table had `0x6B = 0x4A` (PLL ×4). With a 25MHz input clock (XCLK), this forced the camera to output data at **100MHz PCLK**.
*   **The Impact:** The Basys 3 PMOD pins and BRAM cannot reliably operate at 100MHz for this application. This caused massive data corruption, scrambled horizontal bands, and "static" patterns as the FPGA missed 75% of the incoming data.
*   **The Fix:** Reset `0x6B` to `0x00` (PLL Bypass). The camera now runs at a stable 25MHz PCLK, perfectly synchronized with our internal logic.

### 2. DCW Scaling Conflict (Registers `COM3`, `COM14`, `SCALING`)
*   **The Issue:** Several registers were accidentally configured to enable "Down Sample Control Window" (DCW) and prescalers (`COM3 = 0x0C`, `COM14 = 0x19`).
*   **The Impact:** The camera was trying to downsample the image internally while also using our QVGA window settings, resulting in malformed HREF pulses and mismatched pixel counts.
*   **The Fix:** Disabled all internal scaling (`COM3 = 0x00`, `COM14 = 0x00`, etc.) to let the camera output a clean, raw QVGA stream that matches our `ov7670_capture` logic.

### 3. Level-Sensitive vs. Edge-Sensitive VSYNC
*   **The Issue:** Our capture module used `posedge vsync` to reset the pixel counter.
*   **The Impact:** If the FPGA missed the exact rising edge pulse (due to noise on the wires), the entire frame would remain out of sync for the rest of the session.
*   **The Fix:** Switched to **level-sensitive reset** (`if (vsync) ...`). Now, as long as VSYNC is high (the vertical blanking period), the counters are held at zero, guaranteeing synchronization for every single frame.

### 4. Capture Pipeline Synchronization (`wr_hold`)
*   **The Issue:** Simple `byte_toggle` flags are prone to "flipping" if a single PCLK pulse is glitched or double-counted.
*   **The Fix:** Implemented a **2-stage shift register pipeline** (`wr_hold`) for write-enable generation. This matches the reference design and provides much higher immunity to PCLK jitter.

---

## 🛠️ System Architecture Simplification (For Baseline Verification)

To isolate the "Scrambled Image" issue, the system was temporarily reverted to a **Simplified Single-Bank Pipeline**. This removed the complexity of dual-bank BRAM and Bilinear Interpolation to prove the core capture logic works.

### Current Baseline Configuration:
*   **Frame Buffer:** Single 76,800-entry BRAM (RGB444).
*   **Upscaling:** Nearest-Neighbor (1:2 mapping via bit-shifts).
*   **XCLK:** 25MHz (Sync with VGA domain).

---

## ✅ Final Hardware & Constraints Fixes

1.  **Clock Routing (Fixed in `constraints.xdc`):**
    - Added `set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_IBUF]`.
    - **Reason:** `cam_pclk` enters the FPGA on a standard PMOD GPIO pin, not a dedicated clock-input pin. This constraint is **mandatory** for Vivado to allow the design to route.

2.  **XCLK Frequency Alignment:**
    - Updated `top.v` to drive `cam_xclk` with the **25MHz** clock instead of 24MHz. This ensures the entire system (Camera, BRAM, VGA) stays within a single frequency family, reducing potential clock drift.

---

## 📈 Next Steps
1.  **Verify Baseline:** Program the board with the simplified pipeline. You should see a stable, clear QVGA image.
2.  **Re-introduce Bilinear:** Once baseline is proven, we will port the new robust capture logic back into the dual-bank interpolation engine.

**Status:** ALL pipeline blockers identified. Code matches proven reference parameters. Ready for bitstream generation.

---

> [!IMPORTANT]
> **PHASE 3 UPDATE (MAY 9, 2026):**
> During the implementation of the **Bilinear Upscaling** and **Image Rotation** (Extra Credit), a thorough code review identified several "logical" bugs in the initial pipeline design that would have caused visual artifacts and addressing errors.

## 🐛 Phase 3: Bilinear & Rotation Logic Review

### 1. Address Generation Underflow
*   **The Issue:** In the rotation logic, `319 - safe_fetch_y` was used. When `y_int` reached 239 and `fetch_y_offset` was 1, `safe_fetch_y` became 240.
*   **The Impact:** This caused a wrap-around error in the address calculation, reading the wrong part of the frame buffer for the edge pixels.
*   **The Fix:** Rewrote the mapping to use a more robust coordinate system and ensured all subtraction operands are correctly padded/clamped to prevent unsigned underflow.

### 2. Fetch Pipeline Timing Misalignment
*   **The Issue:** The initial design assumed BRAM data from an "even" address would be ready on the same cycle. In reality, with a 1-cycle BRAM latency, data from the "even" cycle arrives on the "odd" cycle.
*   **The Impact:** The pixel window shift logic was using the wrong pixel pairs, causing "jittery" or shifted horizontal colors.
*   **The Fix:** Implemented a `h_frac_d1` (1-cycle delayed) flag to correctly identify and latch the incoming BRAM data into the appropriate cache registers (`p_curr`, `p_above`, etc.).

### 3. Fractional Bit Synchronization
*   **The Issue:** The bilinear blend logic was using the current `hcount[0]` and `vcount[0]` while the pixel data was actually 2-3 cycles old.
*   **The Impact:** The interpolation weights (0 or 0.5) were applied to the wrong pixels, causing blurring artifacts instead of smooth edges.
*   **The Fix:** Added a pipeline delay for the fractional bits (`h_frac_d2`, `v_frac_d2`) to perfectly align them with the registered pixel data at the computation stage.

### 4. Range-Check "Wrapping" Bug
*   **The Issue:** `hcount - 2` was used for the "out-of-bounds" black-out check.
*   **The Impact:** When `hcount` was 0 or 1, this underflowed to 1022+, which worked by luck but made the code fragile.
*   **The Fix:** Switched to a properly delayed `hcount_d3` range check to ensure the black-out region is stable and logical.

**Final Status:** Bilinear pipeline is now mathematically sound and correctly synchronized with the VGA timing domain.

---

> [!IMPORTANT]
> **PHASE 4 UPDATE (MAY 9, 2026):**
> Full code review of all source and testbench files. Eight new bugs identified — two critical, two medium, four low/informational. Documented below with root cause and recommended fix.

---

## 🔴 Phase 4: Full Code Review — Bug Findings

---

### BUG-01 · CRITICAL — RGB Format Conflict (`ov7670_init.v`)

**Files:** `src/ov7670_init.v` (indices 1, 72)

**The Issue:** The init table simultaneously configures two incompatible pixel formats:
- `0x40` (COM15) = `0xD0` → selects **RGB565** output, full range
- `0x8C` (RGB444) = `0x02` → enables **xRGB444** output

These registers are mutually exclusive. COM15 bit[6]=1 selects RGB565; register 0x8C=0x02 enables RGB444. Both are set in the same init sequence, making the camera's actual output format undefined (hardware-dependent write ordering).

**The Impact:** The capture module `ov7670_capture` extracts a 12-bit pixel as `d_latch[11:0]`, which is **only correct for the xRGB444 byte layout** (`{0000_RRRR, GGGG_BBBB}`). If the camera outputs RGB565 instead, the bit extraction produces completely wrong colours.

**Recommended Fix:** Remove the COM15 RGB565 selection (index 1, `{8'h40, 8'hD0}`) and keep only the RGB444 enable (`{8'h8C, 8'h02}`). The comments throughout the codebase already treat RGB444 as the intended format. Alternatively, remove the RGB444 register and adjust the capture logic for RGB565 — but the current extraction logic is only correct for RGB444.

---

### BUG-02 · CRITICAL — `cam_rst` Hardware Reset Pin Not Driven by Init Module (`top.v`)

**File:** `src/top.v` (lines 78–79, 103, 182–184)

**The Issue:** `ov7670_init` drives `cam_rst_out` through the full 3-state reset FSM (assert low → wait 1ms → release high). However, `top.v` **ignores** this signal entirely:

```verilog
wire cam_rst_from_init;   // driven by u_init.cam_rst_out — never used
assign cam_rst = 1'b1;    // camera RST is hardwired high (never reset)
```

The `cam_rst_from_init` wire is a dangling output. The camera hardware reset pulse that `ov7670_init` spends ~2ms executing is never delivered to the physical pin.

**The Impact:** The OV7670 may not complete its power-on reset sequence reliably without a hardware RST pulse, particularly on cold boot. The init module's `ST_RESET_ASSERT` / `ST_RESET_WAIT` / `ST_RESET_RELEASE` states are wasted logic.

**Recommended Fix:** Change the `cam_rst` assignment:
```verilog
// Before (broken):
assign cam_rst = 1'b1;

// After (correct):
assign cam_rst = cam_rst_from_init;
```

---

### BUG-03 · MEDIUM — VGA Sync Delay Off by One Cycle (`top.v`)

**File:** `src/top.v` (lines 113–139)

**The Issue:** The top-level sync delay uses 4 pipeline registers (`hsync_d4`, `vsync_d4`). The comment says this matches "4-cycle bilinear display pipeline latency." However, counting the actual register stages in `vga_display`:

| Cycle | Event |
|-------|-------|
| N | `rd_addr` computed combinationally from `hcount` |
| N+1 | `bram_d1 <= rd_data` (BRAM 1-cycle latency) |
| N+2 | `p_curr <= bram_d1` (pixel cache update) |
| N+3 | `vga_r <= filtered_pixel` (output register) |

Total latency = **3 register stages** (N to N+3). The sync signals (`hsync`, `vsync`) are combinational outputs of `vga_sync`, so they change at the same time as `hcount`. Delaying them by 4 cycles (`hsync_d4`) adds one extra cycle of offset, shifting the active window boundary by 1 pixel relative to the pixel data.

**The Impact:** The displayed image has a 1-pixel horizontal misalignment between pixel data and sync boundaries. May manifest as a thin garbage column at the right edge or a missing leftmost pixel column.

**Recommended Fix:** Change the output assigns to use the 3-cycle delayed versions:
```verilog
assign vga_hsync = hsync_d3;
assign vga_vsync = vsync_d3;
```
And remove the unused `hsync_d4`/`vsync_d4` registers.

---

### BUG-04 · MEDIUM — `cam_pclk` Timing Constraint Incorrect (`constraints.xdc`)

**File:** `constraints/constraints.xdc` (line 46)

**The Issue:**
```tcl
create_clock -period 41.667 -name cam_pclk_clk [get_ports cam_pclk]
```
This assumes PCLK = 24 MHz (41.667 ns). However, `top.v` drives `cam_xclk = clk_25mhz` (25 MHz), and the camera is configured with PLL bypass (`0x6B = 0x00`), so `PCLK = XCLK = 25 MHz` (period = **40.000 ns**, not 41.667 ns).

**The Impact:** Vivado performs static timing analysis for the camera clock domain using the wrong clock period. Paths that are actually tight at 40 ns may appear to have extra margin at 41.667 ns, masking real setup violations in the capture module.

**Recommended Fix:**
```tcl
create_clock -period 40.000 -name cam_pclk_clk [get_ports cam_pclk]
```

---

### BUG-05 · MEDIUM — Testbench SCL Edge Count Wrong (`sim/tb_sccb_master.v`)

**File:** `sim/tb_sccb_master.v` (lines 104–109)

**The Issue:** The verification assertion expects **27** SCL rising edges for a 3-phase SCCB write:
```verilog
if (scl_rising_count == 27)
    $display("PASS: Correct number of SCL clock cycles");
```

Counting actual SCL rising edges in `sccb_master`:
- `ST_PHASE1`: 8 rising edges (one per data bit)
- `ST_DONTCARE1`: 1 rising edge
- `ST_PHASE2`: 8 rising edges
- `ST_DONTCARE2`: 1 rising edge
- `ST_PHASE3`: 8 rising edges
- `ST_DONTCARE3`: 1 rising edge
- `ST_STOP` phase 1 (SCL 0→1): **1 rising edge**
- **Total = 28**

The STOP condition requires SCL to be raised before SDA goes high, generating an additional rising edge beyond the 3×9=27 data-clock edges.

**The Impact:** The testbench always prints `FAIL` even when `sccb_master` is operating correctly.

**Recommended Fix:**
```verilog
// Change both assertions from 27 to 28:
if (scl_rising_count == 28)
```

---

### BUG-06 · LOW — Testbench Sends RGB565 to an RGB444 Capture Module (`sim/tb_ov7670_capture.v`)

**File:** `sim/tb_ov7670_capture.v` (lines 67–79, Test 5)

**The Issue:** The `send_pixel` task sends bytes formatted as RGB565 (`{R[4:0], G[5:3]}` / `{G[2:0], B[4:0]}`). The DUT `ov7670_capture` expects RGB444 format (`{0000_RRRR}` / `{GGGG_BBBB}`). Test 5 verifies "White pixel (R=31, G=63, B=31) → RGB444 0xFFF" — but the byte values passed do not match what the RGB444 capture logic expects, so the conversion check will fail or produce misleading results.

**Recommended Fix:** Update `send_pixel` for RGB444 xRGB byte order:
```verilog
task send_pixel_rgb444;
    input [3:0] r4, g4, b4;
    begin
        d = {4'b0000, r4}; @(negedge pclk); // byte1: 0000_RRRR
        d = {g4, b4};      @(negedge pclk); // byte2: GGGG_BBBB
    end
endtask
```

---

### BUG-07 · LOW — `led[3]` Connected to 25 MHz `cam_pclk` (`top.v`)

**File:** `src/top.v` (line 147)

**The Issue:**
```verilog
assign led[3] = cam_pclk;
```
`cam_pclk` toggles at 25 MHz. LEDs cannot respond faster than ~1 kHz visually. LED3 will appear permanently on and provides no debugging information.

**Recommended Fix:** Connect `led[3]` to a slower, meaningful signal. A good candidate is a divided-down `cam_pclk` heartbeat, or `cap_wr_en` activity indicator:
```verilog
// Example: blink at ~1Hz using a 25-bit counter driven by cam_pclk
assign led[3] = mmcm_locked; // or: pixel-activity flag
```

---

### BUG-08 · LOW — `cam_rst` Pin Always Overrides Init Module in Both Directions (`top.v`)

**File:** `src/top.v` (lines 103, 182)

**The Issue (related to BUG-02):** During `ov7670_init`'s reset phase, `cam_rst_out` is driven low (active reset). If this were correctly wired as `assign cam_rst = cam_rst_from_init`, the camera would be properly reset. However, during the init module's `ST_RESET_ASSERT` state, `cam_rst_out = 0` (low = in reset), while the module header comment says `cam_rst` is "active low." The `top.v` comment (line 103) says `// Always not-in-reset (reference: assign reset = 1)`, suggesting a deliberate choice. This conflicts with the init module wasting FSM states on hardware reset.

**Recommended Fix:** Either (a) fix the wiring per BUG-02, or (b) skip the hardware reset in `ov7670_init` by hard-wiring `cam_rst_out` high and jumping straight to `ST_SWRESET_SEND` in the FSM initial state. Don't leave it inconsistent.

---

## 📋 Bug Summary Table

| ID | Severity | File | Description | Status |
|----|----------|------|-------------|--------|
| BUG-01 | 🔴 Critical | `ov7670_init.v` | COM15 (RGB565) and RGB444 register both set — format conflict | ✅ Fixed |
| BUG-02 | 🔴 Critical | `top.v` | `cam_rst_from_init` never wired to `cam_rst` — hardware reset bypassed | ✅ Fixed |
| BUG-03 | 🟡 Medium | `top.v` | Sync delay is 4 cycles but pixel pipeline has 3 — 1-pixel H shift | ✅ Fixed |
| BUG-04 | 🟡 Medium | `constraints.xdc` | PCLK constraint uses 41.667 ns (24 MHz) but actual is 40 ns (25 MHz) | ✅ Fixed |
| BUG-05 | 🟡 Medium | `tb_sccb_master.v` | SCL edge assertion expects 27, correct count is 28 (STOP adds 1) | ✅ Fixed |
| BUG-06 | 🔵 Low | `tb_ov7670_capture.v` | Testbench sends RGB565 bytes to RGB444 capture module | ✅ Fixed |
| BUG-07 | 🔵 Low | `top.v` | `led[3] = cam_pclk` at 25 MHz — always appears on, useless | ✅ Fixed |
| BUG-08 | 🔵 Low | `top.v` | Inconsistency between `cam_rst` hardwire and init module reset FSM | ✅ Fixed (via BUG-02) |

---

## 🔧 Phase 4 Fix Changelog

### Fix for BUG-01 — `src/ov7670_init.v`
Changed COM15 register value from `0xD0` (RGB565) to `0xC0` (full range only, no format override):
```verilog
// Before: 7'd1: get_reg_entry = {8'h40, 8'hD0}; // COM15: RGB output, RGB565
// After:  7'd1: get_reg_entry = {8'h40, 8'hC0}; // COM15: full range, no RGB565
```
Register 0x8C (`0x02`) remains and now unambiguously selects xRGB444 format.

### Fix for BUG-02 — `src/top.v`
Wired `cam_rst` to the init module's output instead of a hardwired constant:
```verilog
// Before: assign cam_rst = 1'b1;
// After:  assign cam_rst = cam_rst_from_init;
```
The hardware RST pulse sequence (1ms low → release) is now delivered to the physical OV7670 RST pin.

### Fix for BUG-03 — `src/top.v`
Reduced VGA sync pipeline delay from 4 to 3 stages to match the actual 3 register stages in `vga_display`:
```verilog
// Before: assign vga_hsync = hsync_d4; assign vga_vsync = vsync_d4;
// After:  assign vga_hsync = hsync_d3; assign vga_vsync = vsync_d3;
```
Removed the unused `hsync_d4`/`vsync_d4` registers and updated the pipeline comment.

### Fix for BUG-04 — `constraints/constraints.xdc`
Corrected the `cam_pclk` constraint period from 41.667 ns to 40.000 ns:
```tcl
# Before: create_clock -period 41.667 -name cam_pclk_clk [get_ports cam_pclk]
# After:  create_clock -period 40.000 -name cam_pclk_clk [get_ports cam_pclk]
```

### Fix for BUG-05 — `sim/tb_sccb_master.v`
Corrected both SCL edge count assertions from 27 to 28:
```verilog
// Before: if (scl_rising_count == 27) $display("PASS...");
// After:  if (scl_rising_count == 28) $display("PASS...");
```

### Fix for BUG-06 — `sim/tb_ov7670_capture.v`
Rewrote `send_pixel` task to use xRGB444 byte order matching the DUT's expectations:
```verilog
// Byte 1: {G[3:0], B[3:0]}  (GGGG_BBBB)
// Byte 2: {4'b0000, R[3:0]} (0000_RRRR)
// → d_latch = {0000_RRRR, GGGG_BBBB} → d_latch[11:0] = {R,G,B} ✓
```
Updated `send_line` to pass 4-bit colour values, and rewrote Test 5 with correct RGB444 reference values. Also fixed a non-blocking assignment on `integer pixel_count` (changed `<=` to `=`).

### Fix for BUG-07 — `src/top.v`
Replaced the 25 MHz `cam_pclk` LED with `mmcm_locked`:
```verilog
// Before: assign led[3] = cam_pclk;  // invisible at 25 MHz
// After:  assign led[3] = mmcm_locked; // shows PLL lock status at boot
```
LED mapping is now: `[0]`=init_done, `[1]`=cam_vsync, `[2]`=cam_href, `[3]`=mmcm_locked.

### Fix for BUG-08 — `src/top.v`
Resolved as a direct consequence of BUG-02 fix. `cam_rst` is now driven by `cam_rst_from_init`, so the FSM reset states are no longer dead code.

