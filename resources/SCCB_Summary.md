# OmniVision Serial Camera Control Bus (SCCB) Specification Summary

## Overview
The **SCCB (Serial Camera Control Bus)** is OmniVision's proprietary serial interface designed specifically for controlling its CAMERACHIP sensors. It is highly similar to the standard **I²C** bus and operates in a master-slave configuration, where the companion backend processor acts as the master and the camera sensor acts as the slave.

## Key Features & Pin Functions
SCCB can operate in a 3-wire or a modified 2-wire mode. The 2-wire mode is functionally equivalent to I²C.
- **SIO_C (Serial I/O Clock):** Clock signal driven by the master.
- **SIO_D (Serial I/O Data):** Bi-directional data line. Requires a pull-up resistor (or conflict-protection resistor) to prevent unknown bus states during float/contention.
- **SCCB_E (Serial Chip Select - Optional):** Active-low enable signal for the 3-wire implementation. In the 2-wire implementation, this is typically pulled low internally or omitted.

## Data Transmission Protocol
Transmissions are broken down into **phases**, where each phase consists of 9 bits: 8 bits of sequential data followed by a 9th "Don't Care" or "NA" bit (similar to the ACK/NACK bit in I²C).

### 3-Phase Write Transmission
Used by the master to write 1 byte of data to a specific register on the slave.
1. **Phase 1 (ID Address):** 7-bit Slave Address + 1-bit Read/Write selector (0 for write).
2. **Phase 2 (Sub-address):** 8-bit register address to be accessed.
3. **Phase 3 (Write Data):** 8-bit data value to overwrite the register.

### 2-Phase Read Transmission
Reading data requires a 2-Phase Write to select the register, followed immediately by a 2-Phase Read.
1. **Phase 1 (ID Address):** 7-bit Slave Address + 1-bit Read/Write selector (1 for read).
2. **Phase 2 (Read Data):** The 8-bit data driven by the slave. The 9th bit is an NA bit driven high by the master.

## The "Don't Care" Bit
Unlike standard I²C which uses strict ACK/NACK bits, the 9th bit in a master-driven SCCB transmission is defined as a "Don't Care" bit. The master drives SIO_C but does not strictly check SIO_D for an acknowledgment. This simplifies the master implementation but makes the bus more prone to silent failures if the slave is unresponsive.

## Electrical & Timing Characteristics
- **Frequency:** Typically operates around 100 KHz, with a maximum frequency of **400 KHz** (`tCYC = 2.5 µs`).
- **Start Condition:** SIO_D transitions from high to low while SIO_C is high.
- **Stop Condition:** SIO_D transitions from low to high while SIO_C is high.
