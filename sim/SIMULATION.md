# FPGA Video Processing System - Simulation & Test Suite

This document describes the Verilog simulation environment and the purpose of each testbench in the project.

## 1. Overview
The test suite is designed for use with **Xilinx Vivado Simulator** or **Icarus Verilog**. It verifies individual modules (Unit Testing) and the overall system integration (Smoke Testing).

## 2. Verilog Testbenches (`/sim`)

| Testbench File | Target Module | Description |
| :--- | :--- | :--- |
| **`tb_top.v`** | `top.v` | **System Smoke Test**. Verifies MMCM lock, camera initialization, VGA sync, filter switching, and overflow resilience (330-pixel line). |
| **`tb_vga_display.v`** | `vga_display.v` | **Display & Bilinear Test**. Verifies the synchronized p_temp pipeline, d4 fractional delays, left-edge boundary handling (src_col_d2==0), blanking, and filter modes. |
| **`tb_ov7670_init.v`** | `ov7670_init.v` | **Init Sequencer Test**. Verifies HW reset, SW reset, first/last config register, register count (97 active), and init_done assertion. |
| **`tb_ov7670_capture.v`** | `ov7670_capture.v` | **Capture Test**. Verifies href edge detection (x resets on rising, y increments on falling), x clipping at 320, RGB565→RGB444 conversion, and overflow protection. |
| **`tb_image_filter.v`** | `image_filter.v` | **Filter Logic Test**. Tests combinational logic for Inversion, Red Isolation, and Thresholding with edge cases. |
| **`tb_vga_sync.v`** | `vga_sync.v` | **VGA Timing Test**. Verifies pixel counters, sync pulse widths, and active region flags for 640x480 @ 60Hz. |
| **`tb_sccb_master.v`** | `sccb_master.v` | **Protocol Test**. Verifies SCCB serial bit-banging, 27 SCL cycles (3 phases × 9 bits), and done signal. |
| **`tb_frame_buffer.v`** | `frame_buffer.v` | **BRAM Test**. Verifies cross-clock-domain write/read, address boundaries, and burst operations. |

## 3. Running Simulations

### Using Vivado GUI
1.  Open your Vivado project.
2.  Add the source file and the corresponding testbench to the project.
3.  Right-click the testbench in the **Sources** window and select **Set as Top**.
4.  Click **Run Simulation** -> **Run Behavioral Simulation**.

### Using Icarus Verilog (CLI)
```bash
# Example for testing the VGA display
iverilog -o sim.out src/vga_display.v src/image_filter.v sim/tb_vga_display.v
vvp sim.out
gtkwave tb_vga_display.vcd
```

## 4. Simulation Optimization
*   **`SIMULATION` Parameter**: To avoid waiting for real-world hardware delays (like the 300ms camera settling time), set the `SIMULATION` parameter to `1` when instantiating modules in your testbench. This is already done in `tb_top.v` and `tb_ov7670_init.v`.
*   **Clock Wizard Model**: `clk_wiz.v` includes a simplified behavioral model for simulation that is active when the simulator defines `COCOTB_SIM` or `SIMULATION`.

## 5. Key Design Changes (May 2026)

| Module | Change | Impact on Testbench |
| :--- | :--- | :--- |
| `ov7670_capture.v` | href edge detection; x clips at 320 | `tb_ov7670_capture.v` — new overflow test (Test 6) |
| `vga_display.v` | Synchronized p_temp pipeline; d4 delays; src_col boundary | `tb_vga_display.v` — complete rewrite for new pipeline |
| `ov7670_init.v` | De-noise regs commented out; NUM_REGS=97 | `tb_ov7670_init.v` — verifies register count & last reg |

---
*Created for HWSyn Final Project.*
