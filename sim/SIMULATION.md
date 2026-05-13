# FPGA Video Processing System - Simulation & Test Suite

This document describes the Verilog simulation environment and the purpose of each testbench in the project.

## 1. Overview
The test suite is designed for use with **Xilinx Vivado Simulator** or **Icarus Verilog**. It verifies individual modules (Unit Testing) and the overall system integration (Smoke Testing).

## 2. Verilog Testbenches (`/sim`)

| Testbench File | Target Module | Description |
| :--- | :--- | :--- |
| **`tb_top.v`** | `top.v` | **System Smoke Test**. Verifies that the MMCM locks, camera initialization begins, and VGA sync signals are generated correctly. |
| **`tb_vga_display.v`** | `vga_display.v` | **Display & Filter Test**. Verifies the bilinear upscaling math, 4-pixel averaging (overflow fix), and coordinate mapping. |
| **`tb_ov7670_init.v`** | `ov7670_init.v` | **Init Sequencer Test**. Verifies the power-on FSM (Hardware Reset -> Software Reset -> Configuration ROM). |
| **`tb_ov7670_capture.v`** | `ov7670_capture.v` | **Capture Test**. Simulates camera byte streams and verifies RGB565 to RGB444 conversion and timing. |
| **`tb_image_filter.v`** | `image_filter.v` | **Filter Logic Test**. Tests the combinational logic for Inversion, Red Isolation, and Thresholding. |
| **`tb_vga_sync.v`** | `vga_sync.v` | **VGA Timing Test**. Verifies pixel counters and sync pulse widths for 640x480 @ 60Hz. |
| **`tb_sccb_master.v`** | `sccb_master.v` | **Protocol Test**. Verifies the SCCB serial bit-banging and transaction completion. |

## 3. Running Simulations

### Using Vivado GUI
1.  Open your Vivado project.
2.  Add the source file and the corresponding testbench to the project.
3.  Right-click the testbench in the **Sources** window and select **Set as Top**.
4.  Click **Run Simulation** -> **Run Behavioral Simulation**.

### Using Icarus Verilog (CLI)
```bash
# Example for testing the VGA display
iverilog -o sim.out src/vga_display.v sim/tb_vga_display.v
vvp sim.out
gtkwave tb_vga_display.vcd
```

## 4. Simulation Optimization
*   **`SIMULATION` Parameter**: To avoid waiting for real-world hardware delays (like the 300ms camera settling time), set the `SIMULATION` parameter to `1` when instantiating modules in your testbench. This is already done in `tb_top.v` and `tb_ov7670_init.v`.
*   **Clock Wizard Model**: `clk_wiz.v` includes a simplified behavioral model for simulation that is active when the simulator defines `COCOTB_SIM` or `SIMULATION`.

---
*Created for HWSyn Final Project.*
