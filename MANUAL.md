# Real-Time Video Capture and Processing System - User Manual

This manual provides instructions for setting up and operating the High-Fidelity Real-Time Video Capture system on a Digilent Basys 3 FPGA board using an OV7670 camera sensor.

## 1. Hardware Requirements
*   **FPGA Board**: Digilent Basys 3 (Artix-7).
*   **Camera Sensor**: OV7670 (non-FIFO version).
*   **Display**: VGA-compatible monitor and VGA cable.
*   **Power**: Micro-USB cable for programming and power.
*   **Wiring**: Jumper wires (keep PCLK and XCLK wires as short as possible).

## 2. Hardware Setup & Wiring
The camera must be connected to the Basys 3 PMOD headers. Based on the project constraints (`constraints.xdc`), please follow this mapping:

### PMOD Connection Table

| Camera Pin | Basys 3 Pin | PMOD Header Pin | Note |
| :--- | :--- | :--- | :--- |
| **D0** | P17 | **JC-9** | Data Bit 0 |
| **D1** | N17 | **JC-3** | Data Bit 1 |
| **D2** | M19 | **JC-8** | Data Bit 2 |
| **D3** | M18 | **JC-2** | Data Bit 3 |
| **D4** | L17 | **JC-7** | Data Bit 4 |
| **D5** | K17 | **JC-1** | Data Bit 5 |
| **D6** | C16 | **JB-8** | Data Bit 6 |
| **D7** | B16 | **JB-4** | Data Bit 7 |
| **PCLK** | A16 | **JB-2** | Pixel Clock |
| **HREF** | A17 | **JB-6** | Horizontal Reference |
| **VSYNC** | B15 | **JB-3** | Vertical Sync |
| **XCLK** | C15 | **JB-7** | System Clock (25MHz Output) |
| **SCL** | A14 | **JB-1** | SCCB Clock |
| **SDA** | A15 | **JB-5** | SCCB Data |
| **RST** | P18 | **JC-4** | Hardware Reset |
| **PWDN** | R18 | **JC-10** | Power Down (Tied Low) |
| **VCC** | 3.3V | VCC Pin | Connect to 3.3V |
| **GND** | GND | GND Pin | Connect to Ground |

> [!IMPORTANT]
> Ensure **VCC** is connected to **3.3V** and **GND** is connected. Do not use 5V as it may damage the camera or FPGA.

## 3. Getting Started
1.  **Synthesize and Program**:
    *   Open the project in Xilinx Vivado.
    *   Ensure all files in the `src` directory are included in the project.
    *   Run **Synthesis** and **Implementation**.
    *   Generate the **Bitstream** (`.bit` file) and program the Basys 3.
2.  **Initialization (High-Fidelity Update)**:
    *   The system uses an advanced **98-register initialization sequence**.
    *   This includes a calibrated **Color Matrix** and **DSP tuning** to ensure accurate RGB565 reproduction and eliminate the common "green tint" issue.
    *   **VSYNC Stability**: The capture logic now uses level-sensitive synchronization, making it extremely robust against noise and ensuring the frame never "scrambles" once locked.
    *   **LED[0]** will turn ON once the initialization sequence is successfully completed via SCCB.

## 4. Operating Instructions
The system supports four real-time video modes selected via slide switches **SW[1]** and **SW[0]**.

| SW[1] | SW[0] | Mode | Description |
| :---: | :---: | :--- | :--- |
| **0** | **0** | **Raw Video** | High-fidelity color stream with calibrated RGB matrix. |
| **0** | **1** | **Inversion** | Color negative effect (Digital Inversion). |
| **1** | **0** | **Red Isolation** | Grayscale background with only Red channel preserved. |
| **1** | **1** | **B&W Threshold** | High-contrast Binary (Black & White) based on calculated luminance. |

### Advanced Features
*   **Bilinear Interpolation**: This system implements a real-time bilinear upscaling algorithm in the VGA display pipeline. It smooths the transition between pixels when upscaling the 320x240 camera feed to the 640x480 VGA display, removing the "blocky" look of nearest-neighbor scaling.
*   **Synchronous Clocking**: The entire system (XCLK, BRAM, and VGA) is driven by a unified 25MHz clock domain, ensuring perfect synchronization and eliminating drift or tearing.
*   **Noise Reduction**: The camera is configured with active de-noise logic (Registers 0x41, 0x76, 0x77) to provide a cleaner image in low-light conditions.
*   **Hardware Debugging LEDs**:
    *   **LED[0]**: Initialization Done (SCCB sequence finished).
    *   **LED[1]**: VSYNC signal active (Camera is outputting frames).
    *   **LED[2]**: HREF signal active (Camera is outputting lines).
    *   **LED[3]**: PCLK signal active (Pixel clock is running).

## 5. Troubleshooting
*   **Black Screen**:
    *   Check if **LED[0]** is ON. If not, the SCCB initialization failed (check SCL/SDA wiring).
    *   Check if **LED[1-3]** are flickering/ON. If not, the camera is not receiving XCLK or is powered down.
*   **Corrupted Colors/Tearing**:
    *   Verify PCLK wiring. This signal is high-speed; keep wires short and away from power lines.
    *   Ensure the ground connection between the Basys 3 and the camera is solid.
*   **Blurry Image**:
    *   The OV7670 lens is manual. Rotate the lens housing to focus. The bilinear filtering helps smooth edges, but optical focus is still required.

---
*Updated for HWSyn Final Project - May 2026.*
