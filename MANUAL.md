# Real-Time Video Capture and Processing System - User Manual

This manual provides instructions for setting up and operating the Real-Time Video Capture system on a Digilent Basys 3 FPGA board using an OV7670 camera sensor.

## 1. Hardware Requirements
*   **FPGA Board**: Digilent Basys 3 (Artix-7).
*   **Camera Sensor**: OV7670 (non-FIFO version).
*   **Display**: VGA-compatible monitor and VGA cable.
*   **Power**: Micro-USB cable for programming and power.
*   **Wiring**: Jumper wires.

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
| **XCLK** | C15 | **JB-7** | System Clock (Input to Cam) |
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
    *   Add all files from the `src` and `constraints` folders.
    *   Run **Synthesis** and **Implementation**.
    *   Generate the **Bitstream** (`.bit` file).
    *   Open **Hardware Manager** and program the Basys 3.
2.  **Initialization**:
    *   Once programmed, the camera undergoes an automatic initialization sequence (SCCB configuration).
    *   The monitor should display a live video feed within 1-2 seconds.

## 4. Operating Instructions
The system supports four real-time video modes selected via slide switches **SW[1]** and **SW[0]**.

| SW[1] | SW[0] | Mode | Description |
| :---: | :---: | :--- | :--- |
| **0** | **0** | **Raw Video** | Original color stream with **Bilinear Upscaling** for smooth edges. |
| **0** | **1** | **Inversion** | Color negative effect (Digital Inversion). |
| **1** | **0** | **Red Isolation** | Grayscale except for red channel intensity. |
| **1** | **1** | **B&W Threshold** | Binary Black & White based on luminance. |
| **Any** | **Any** | **Smoothing** | Bilinear interpolation is applied to all modes automatically. |

> [!NOTE]
> **Extra Credit Feature**: This system uses a dual-bank memory architecture to perform real-time bilinear interpolation. This smooths out the image, effectively removing the blocky pixels usually seen when upscaling 320x240 to 640x480.

## 5. Troubleshooting
*   **Black Screen**:
    *   Check VGA cable and monitor input.
    *   Verify the `cam_xclk` is reaching the camera (24MHz).
    *   Ensure `cam_pwdn` is pulled low.
*   **Corrupted Colors/Tearing**:
    *   Verify PCLK wiring. This signal is high-speed; keep wires short.
    *   Check for loose ground connections.
*   **Failed Initialization**:
    *   The SCCB (SDA/SCL) lines require pull-up resistors. We enable internal pull-ups, but for best results, add **physical 4.7kΩ resistors** to 3.3V on a breadboard.
*   **Blurry Image**:
    *   The OV7670 lens is manual. Rotate the lens housing to focus the image.

---
*Created for HWSyn Final Project 2025.*
