# Deep Root Cause Analysis: Persistent Magenta + Red Sparkle Corruption

**Date:** 2026-05-09
**Status:** Unsolved after fixing COM15=0xD0, addr register offset, VGA sync timing.

## Symptom Description

- Image structure is **clearly recognizable** (person/cat at keyboard visible)
- Overall heavy **magenta tint** (high red + high blue, very low green)
- **Red pixel flickering / sparkle** scattered throughout the frame
- Brighter scene areas have more colored noise; darker areas relatively clean
- Pattern is **frame-to-frame inconsistent** (pixels flicker between frames)
- All 3 image filters (inversion, red isolation, B&W threshold) reportedly work
- Image is **identical** before and after applying COM15=0xC0→0xD0 fix

## Key Diagnostic Facts

| Fact | Implication |
|------|-------------|
| Bitstream timestamp newer than source files | The fix IS in the programmed bitstream |
| Image structure visible & geometrically correct | PCLK works, VSYNC works, capture timing OK |
| COM15 change had ZERO visible effect | Either SCCB never reaches camera, OR camera ignores that register |
| Magenta + speckle is a *signature* artifact | Strongly suggests YUV-as-RGB565 misinterpretation |
| Scene has correct aspect ratio (4:3) | Camera is in QVGA (320x240), so SOME SCCB writes work |

## Hypotheses Ranked by Likelihood

---

### #1 — SCCB Partial Failure (HIGH likelihood)

**Theory:** Some SCCB writes succeed (COM7=0x14 → QVGA), others fail silently (COM15, color matrix). The camera is in QVGA mode but still outputting **YUV422 (YUYV)** because COM15 didn't get through to switch format.

**Why this fits:**
- Image has correct QVGA aspect ratio → COM7=0x14 was written
- COM15 change had no effect → COM15 never reaches camera
- Magenta + sparkle = textbook YUV-as-RGB565 artifact
- Bytes Y0,Cb,Y1,Cr decoded as RGB565 give: R≈Y/16, G≈1, B≈Cb/Cr LSBs → magenta cast with chroma sparkle

**Why writes might fail intermittently:**
- FPGA internal pull-up on SDA (~24kΩ) too weak for the bus capacitance
- Slow SDA rise times → camera samples before SDA reaches VIH
- The Don't-Care 9th bit may be especially sensitive
- Some registers happen to fall on a "good" timing window, others don't

**How to confirm:**
- Probe SDA with oscilloscope — look for slow rise times, missed transitions
- Add LEDs to count successful SCCB writes vs total
- Check LED[0] (init_done) — if HIGH, FSM completed but doesn't prove writes succeeded

**Fixes to try:**
- ✅ **Already done:** Slow SCCB to 50kHz (CLK_DIV=1000)
- Add **external 4.7kΩ pull-up resistor** from SDA → 3.3V (most reliable fix)
- Verify physical wiring — bad solder joint or jumper wire on SDA
- Use a different Pmod pin if A15 is damaged

---

### #2 — Camera in YUV422 Mode (Default After Reset) (HIGH likelihood)

**Theory:** Even if SCCB works, the OV7670 might not properly transition from YUV (default) to RGB565 mode because:
- COM7[2]=1 alone isn't sufficient on this OV7670 clone
- The order of writes matters and is wrong
- The clone module ignores certain registers
- The sensor needs additional registers (e.g., COM3, COM14) to fully enter RGB mode

**Pixel-level evidence:**
For YUYV bytes captured as RGB565:
```
Byte 0 (Y0=0xC8 bright pixel) shifted to d_latch[15:8]
Byte 1 (Cb=0x80 neutral)      shifted to d_latch[7:0]
Extract: R=d_latch[15:12]={1,1,0,0}=12  ← VERY HIGH RED
         G=d_latch[10:7]={0,0,0,1}=1    ← almost no green
         B=d_latch[4:1]={0,0,0,0}=0     ← no blue (most pixels)
```
Result: Bright pixels become bright red. Adjacent pixel uses Cr instead → small red variation = "flicker".

**Fixes to try:**
- Add `RGB444 = 0x02` then `RGB444 = 0x00` (toggle to force RGB mode reset)
- Try writing COM7=0x14 **twice** with delay between
- Try the alternate sequence: COM7=0x80 → wait → COM7=0x04 (VGA RGB) → COM3=0x04 (DCW) → scaling regs for QVGA
- Implement **YUV422 → RGB conversion in the FPGA** (workaround that bypasses SCCB issue entirely)

---

### #3 — Byte Order Endianness Mismatch (MEDIUM likelihood)

**Theory:** This OV7670 clone variant outputs RGB565 with **LSB byte first** (G2:G0 + B4:B0 first, then R4:R0 + G5:G3 second), opposite of the datasheet-standard order our code assumes.

**How to test:**
Modify ov7670_capture.v extraction to assume swapped order:
```verilog
// Assuming first byte = LSB byte (G2:G0,B4:B0):
//   d_latch[15:8] = LSB byte
//   d_latch[7:0]  = MSB byte
dout_reg <= {
    d_latch[7:4],                            // R[4:1]
    {d_latch[2:0], d_latch[15]},             // G[5:2] (spans byte boundary)
    d_latch[12:9]                             // B[4:1]
};
```

**If byte swap fixes it:** done. If not, rule out this hypothesis.

---

### #4 — Camera in Bayer Raw Mode (MEDIUM likelihood)

**Theory:** Camera is outputting raw Bayer pattern (one color per pixel, alternating GRGRGR / BGBGBG) instead of demosaiced RGB565. When pairs of Bayer pixels get packed into RGB565 words, you get magenta-ish noise.

**Why possible:**
- COM7[0]=1 enables raw RGB mode (different from cooked RGB565)
- After software reset, some clones default to raw output
- The DSP pipeline (demosaic + matrix) may not be enabled

**How to test:**
- Probe HREF/PCLK timing — Bayer raw has different pixel rate than RGB565
- Try explicit register writes to enable DSP: COM7 raw bit MUST be 0

**Fixes:**
- Verify COM7[0]=0 (already correct in our config: 0x14 → bit0=0)
- Add explicit DSP enable register if needed for this clone

---

### #5 — AWB Instability / Saturated Color Matrix (MEDIUM likelihood)

**Theory:** Auto White Balance is converging to wrong values, pumping red gain very high. The "flickering red pixels" are AWB readjustments frame-to-frame.

**Why possible:**
- COM8 = 0xE7 enables AEC + AGC + AWB
- If lighting is unusual (indoor LED + tungsten mix), AWB can oscillate
- Default initial blue/red gain (0x80) may be far from correct for this scene
- AWB frame-to-frame adjustment causes the "flicker"

**How to test:**
- Disable AWB: COM8 = 0xC5 (AEC + AGC only, no AWB)
- Set fixed manual gains: BLUE=0x40, RED=0x40
- Cover camera with hand for 10 seconds (force darkness) — does color recover when uncovered?

**Fixes to try:**
```verilog
// Manual white balance (replace AWB enable):
{8'h13, 8'hC5},  // COM8: AEC+AGC only, no AWB
{8'h01, 8'h40},  // BLUE gain manual
{8'h02, 8'h40},  // RED gain manual
```

---

### #6 — Wrong PCLK Edge / Setup-Hold Violation (LOW likelihood)

**Theory:** Although OV7670_Summary.md confirms posedge PCLK is correct (data stable on rising edge), Pmod jumper wires can introduce skew that breaks setup/hold.

**Why likely NOT the cause:**
- The image has clear structure (not pixel-level garbage)
- Bit errors from setup/hold violations would scramble the geometry, not just colors
- The corruption is too systematic for random metastability

**Sanity check (if all else fails):**
- Try sampling on negedge pclk (we know this was wrong before, but worth confirming)
- Add an IDELAY block to shift PCLK timing relative to data
- Use a BUFG-routed PCLK with explicit constraints

---

### #7 — VGA DAC Bit Mapping Wrong (LOW likelihood)

**Theory:** VGA color outputs are connected backwards (e.g., vga_r drives blue, vga_b drives red on the Basys 3 hardware DAC).

**Why likely NOT:**
- All 3 filters work correctly per user — inversion would visually fail if R/B swapped
- The Basys 3 schematic uses standard ordering and the XDC matches

**Sanity check:**
- Use the **color bar test pattern** (sw=2'b11, just added) — bars MUST appear as Red | Green | Blue | White from left to right. If they appear as B | G | R | W, R/B are swapped.

---

### #8 — Vivado BRAM Inference Imperfect (LOW likelihood)

**Theory:** The 12 "unused sequential elements" in u_fbuf being removed are address mux registers that Vivado decided are simplifiable. If they're actually load-bearing for correct addressing, BRAM reads return wrong data → wrong colors.

**Why likely NOT:**
- `(* ram_style = "block" *)` forces Block RAM
- 76800x12 = 922 Kbit fits easily in 1800 Kbit available
- If BRAM addressing were broken, image would be scrambled (wrong pixels), not just wrong colors

**Sanity check:**
- Color bar test (sw=11) bypasses BRAM entirely — if bars look correct, BRAM is fine

---

### #9 — Camera Module Hardware Defect (LOW-MEDIUM likelihood)

**Theory:** This particular OV7670 module is faulty:
- ISP demosaic circuit damaged
- One of the data pins (D0-D7) has a bad bond wire
- VDD-A (analog supply) is dirty
- Sensor was thermally damaged

**How to test:**
- Try a different OV7670 module
- Try the same module on a different FPGA board
- Use a multimeter to check VDD on the camera (should be 2.5-3.3V depending on regulator)

**This is the diagnosis of LAST resort** — only after software fixes exhausted.

---

## Recommended Action Plan

### Step 1: Diagnostic via Color Bar Test ⏱ 5 min
Already added — flip sw[1:0]=11. Possibilities:
- ✅ **Bars correct (R|G|B|W)** → display pipeline confirmed fine. Issue is camera/SCCB. Skip to Step 2.
- ❌ **Bars wrong colors** → VGA/display bug. Fix that first.
- ❌ **Still see camera image** → bitstream not actually updated.

### Step 2: Implement YUV→RGB Conversion (Workaround) ⏱ 1-2 hours
**Why this is the most reliable fix:** Bypasses SCCB entirely. Even if registers never get written and camera stays in default YUV422, we'll get a correct color image.

In `ov7670_capture.v`, add a simplified YUV→RGB444 conversion:
```verilog
// Detect YUYV byte position via even/odd pixel toggle (resets on HREF)
// Y goes to luminance; Cb/Cr drive chroma (saved across pixel pairs)
// R = Y + 1.4*(Cr-128)
// G = Y - 0.34*(Cb-128) - 0.71*(Cr-128)
// B = Y + 1.77*(Cb-128)
// Use shift-add approximations to avoid multipliers
```

### Step 3: Hardware Pull-Up on SDA ⏱ 5 min
Solder or breadboard a **4.7kΩ resistor between SDA (A15) and 3.3V**. This is the standard I2C/SCCB pull-up and almost always fixes silent SCCB failures.

### Step 4: Try Manual White Balance ⏱ 10 min
Replace AWB-enabled COM8 with manual gains:
```verilog
{8'h13, 8'hC5},  // COM8: no AWB
{8'h01, 8'h40},  // BLUE manual
{8'h02, 8'h40},  // RED manual
```

### Step 5: Try Alternate Init Sequence ⏱ 30 min
Replace current init with the Mike Field reference sequence (well-known to work):
- COM7 = 0x80 (reset), wait
- COM7 = 0x04 (VGA RGB)  ← different approach: VGA + scaling
- COM3 = 0x04 (DCW enable)
- COM14 = 0x19 (PCLK divider)
- SCALING_XSC, SCALING_YSC, SCALING_DCWCTR, SCALING_PCLK_DIV
- COM15 = 0xD0
- ... rest of registers

---

## Most Pragmatic Path For Demo

**Time-constrained recommendation (final project demo approaching):**

1. Run the **color bar test** (already in code, sw=11). Confirms display works.
2. **Implement YUV→RGB conversion in ov7670_capture.v.** This guarantees a correct image regardless of SCCB state. Worth the 1-2 hour investment.
3. Document this as "extra credit" in your report — implementing a YUV422→RGB color space converter in hardware IS non-trivial signal processing and could qualify for points.

The YUV conversion approach **eliminates** dependence on the camera's internal RGB565 ISP pipeline. Even a silent SCCB failure becomes a non-issue.

---

## Code-Level Things Already Verified Correct

These have been triple-checked and are NOT the bug:
- ✅ d_latch shift register direction
- ✅ wr_hold byte alignment timing
- ✅ RGB565 → RGB444 bit extraction (when input IS RGB565)
- ✅ BRAM port A/B clock domain crossing
- ✅ VGA sync generation
- ✅ Address calculation y*320+x
- ✅ Color matrix register values (standard Linux RGB565 set)
- ✅ COM7 QVGA + RGB (0x14)
- ✅ Bilinear interpolation math
- ✅ Filter logic (inversion, red isolation, B&W threshold)

---

## Files to Modify Next (After Color Bar Test Confirms Pipeline)

| File | Change |
|------|--------|
| `src/ov7670_capture.v` | Add YUV→RGB conversion path (gated by sw or always-on) |
| `src/ov7670_init.v` | Try manual WB / alternate sequence |
| `constraints/constraints.xdc` | (Hardware) add external SDA pull-up note |
| `src/top.v` | Optional: route LED to SCCB write counter for diagnostics |
