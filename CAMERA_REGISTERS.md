# OV7670 Camera Register Configuration Summary

This document details the specific register settings used to initialize the OV7670 camera sensor for the High-Fidelity Video Processing system.

## 1. Core Format & Output (RGB565 QVGA)
These registers define the primary pixel format and resolution.

| Register | Address | Value | Description |
| :--- | :--- | :--- | :--- |
| **COM7** | `0x12` | `0x14` | Sets output to **QVGA** (320x240) and **RGB** mode. |
| **COM15** | `0x40` | `0xD0` | Configures **RGB565** with full output range [00-FF]. |
| **TSLB** | `0x3A` | `0x04` | Sets normal byte order for RGB565 (High byte first). |
| **COM13** | `0x3D` | `0xC8` | Enables Gamma, UV auto-threshold, and UV swapping. |

## 2. Clock & Display Control
Controls the timing and orientation of the image.

| Register | Address | Value | Description |
| :--- | :--- | :--- | :--- |
| **CLKRC** | `0x11` | `0x80` | Use external clock (XCLK) directly (No internal divider). |
| **DBLV** | `0x6B` | `0x00` | **PLL Bypass**. Prevents PCLK from running too fast for the BRAM. |
| **MVFP** | `0x1E` | `0x31` | **Mirror + Flip**. Corrects image orientation for most PMOD mounts. |
| **COM10** | `0x15` | `0x00` | Ensures PCLK toggles continuously (even during blanking). |

## 3. Framing & Windowing
Defines the active area of the sensor to be captured.

| Register | Address | Value | Description |
| :--- | :--- | :--- | :--- |
| **HSTART** | `0x17` | `0x13` | Horizontal frame start high bits. |
| **HSTOP** | `0x18` | `0x01` | Horizontal frame stop high bits. |
| **HREF** | `0x32` | `0xB6` | Horizontal boundary control (low bits). |
| **VSTRT** | `0x19` | `0x02` | Vertical frame start high bits. |
| **VSTOP** | `0x1A` | `0x7A` | Vertical frame stop high bits. |
| **VREF** | `0x03` | `0x0A` | Vertical boundary control (low bits). |

## 4. Scaling & Downsampling
Registers used to ensure direct QVGA output without additional hardware scaling.

| Register | Address | Value | Description |
| :--- | :--- | :--- | :--- |
| **COM3** | `0x0C` | `0x00` | Disables DCW (Digital Clocks Wizard) scaling. |
| **COM14** | `0x3E` | `0x00` | Disables PCLK divider prescaler. |
| **DCWCTR** | `0x72` | `0x11` | Digital Clocks Wizard Control (standard setting). |
| **PCLK_DIV** | `0x73` | `0x00` | No additional PCLK division. |

## 5. Color Matrix & Calibration
Custom settings to achieve high color fidelity and fix the "greenish" sensor bias.

| Register Group | Addresses | Purpose |
| :--- | :--- | :--- |
| **Color Matrix** | `0x4F` - `0x54`, `0x58` | Maps raw sensor data to accurate RGB colors. |
| **Gamma Curve** | `0x7A` - `0x89` | 15-point curve to improve contrast and shadow detail. |
| **White Balance** | `0x01`, `0x02`, `0x6C`-`0x6F` | Custom Red/Blue gains to balance colors. |
| **De-noise** | `0x41`, `0x76`, `0x77`, `0x4C` | Enables hardware noise reduction and smoothing. |

## 6. Initialization Sequence
The `ov7670_init.v` module follows this strict timing for stability:
1.  **Hardware Reset**: `cam_rst` held low for 1ms.
2.  **Settle Delay**: 1ms wait after reset release.
3.  **Software Reset**: Command `0x12 = 0x80` sent via SCCB.
4.  **Register Settle**: **300ms wait** (Crucial for the sensor internal FSM).
5.  **Batch Config**: Sequential write of the 101 registers listed above.

---
*Refer to the OV7670 Datasheet for full bit-level definitions of these registers.*
