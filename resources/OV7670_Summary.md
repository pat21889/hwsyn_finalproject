# OV7670/OV7171 CMOS VGA Sensor Summary & Analysis

## Overview
The **OV7670** is a low-voltage CMOS image sensor that provides full-frame, sub-sampled, or windowed 8-bit images in a wide range of formats (VGA, QVGA, CIF). It is controlled entirely through the SCCB interface and includes a complex internal Image Signal Processor (ISP).

## Internal Pipeline
1. **Image Array:** Raw Bayer pattern data (640x480 active pixels).
2. **Analog Processing:** Automatic Gain Control (AGC) and Automatic White Balance (AWB).
3. **A/D Conversion:** Converts analog signals to 10-bit digital data.
4. **Digital Signal Processor (DSP):** This is the core of the color issues. It performs:
   - Color space conversion (Raw -> YUV -> RGB).
   - RGB Matrix cross-talk elimination.
   - Saturation, hue, and gamma control.
5. **Image Scaler:** Scales VGA down to QVGA or other formats.
6. **Video Port:** Outputs the data over 8 pins (`D[7:0]`) synchronized with `PCLK`, `HREF`, and `VSYNC`.

---

# 🚨 Root Cause Analysis of the Color Scrambling

The datasheet contains the exact answer as to why our last fix completely broke the image (resulting in the heavily corrupted "gray and red" artifacting). 

### The Timing Specifications (Page 6 & 7)
According to the AC Characteristics table:
- **`tPDV` (PCLK[↓] to Data-out Valid):** 5 ns
- **`tSU` (D[7:0] Setup time):** 15 ns
- **`tHD` (D[7:0] Hold time):** 8 ns

**What this means:** 
The OV7670 changes the physical voltage of its data pins (`D0-D7`) exactly on the **Falling Edge** of `PCLK`. For 5 nanoseconds after the falling edge, the data is completely unstable and transitioning. 

Because the data transitions on the falling edge, it is perfectly stable during the **Rising Edge** (`posedge PCLK`).

### Why My Last Fix Failed
In my previous attempt, I changed our capture module to sample on the falling edge (`always @(negedge pclk)`). I hypothesized that we were sampling during a transition. 
The datasheet proves this was **the exact opposite of what we should do**. By forcing the FPGA to sample on `negedge pclk`, we intentionally forced the FPGA to read the bits at the exact nanosecond they were changing state (violating setup and hold times). This scrambled the bits at the hardware level, completely destroying the RGB565 data and causing the heavily glitched "gray and red" image you saw.

### The True Conclusion
1. **The Original Clocking Was Correct:** `always @(posedge pclk)` is electrically perfect for this sensor.
2. **The New `ov7670_init.v` is Correct:** The clean 20-register pure RGB565 sequence I provided earlier is correct. The only reason it looked corrupted in your last test was because I simultaneously introduced the `negedge pclk` hardware bug.
3. **The Fix:** We simply need to revert `ov7670_capture.v` back to `always @(posedge pclk)`. With the clock phase fixed, the clean RGB565 configuration will finally be captured correctly!
