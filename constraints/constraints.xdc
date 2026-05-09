## ============================================================================
## Constraints file for Real-Time Video Capture and Processing System
## Target: Basys 3 (Xilinx Artix-7 xc7a35tcpg236-1)
## ============================================================================

# === Basys 3 System Clock (100MHz) ===
set_property PACKAGE_PIN W5 [get_ports clk100]
set_property IOSTANDARD LVCMOS33 [get_ports clk100]
create_clock -period 10.000 -name sys_clk [get_ports clk100]

# === Camera Data Pins (D[7:0]) ===
# Connected to Pmod JA and JB headers
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

# SDA needs pullup for open-drain SCCB
set_property PULLUP true [get_ports cam_sda]

# === Camera PCLK as input clock ===
# OV7670 PCLK is typically ~24MHz (period ~41.667ns)
create_clock -period 40.000 -name cam_pclk_clk [get_ports cam_pclk]

# === Clock Domain Crossing ===
# PCLK and sys_clk/VGA clocks are asynchronous
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks cam_pclk_clk]

# Also set MMCM-generated clocks as asynchronous to PCLK
# (Vivado should auto-derive these, but explicit is safer)
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_pins u_clk_wiz/u_mmcm/CLKOUT0]] \
    -group [get_clocks cam_pclk_clk]

# PCLK comes from a regular GPIO pin, not a clock-capable pin.
# Must tell Vivado not to use the dedicated clock routing network.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ *cam_pclk*}]

# === VGA Pins (Basys 3 standard VGA DAC) ===
# Red channel (4 bits)
set_property PACKAGE_PIN G19 [get_ports {vga_r[0]}]
set_property PACKAGE_PIN H19 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN J19 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN N19 [get_ports {vga_r[3]}]
# Green channel (4 bits)
set_property PACKAGE_PIN J17 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN H17 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN G17 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D17 [get_ports {vga_g[3]}]
# Blue channel (4 bits)
set_property PACKAGE_PIN N18 [get_ports {vga_b[0]}]
set_property PACKAGE_PIN L18 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN K18 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN J18 [get_ports {vga_b[3]}]
# Sync signals
set_property PACKAGE_PIN P19 [get_ports vga_hsync]
set_property PACKAGE_PIN R19 [get_ports vga_vsync]
# IO standard for all VGA pins
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]

# === Slide Switches (Filter Select) ===
set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
set_property PACKAGE_PIN V16 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

# === LEDs (Hardware Debugging) ===
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# === Bitstream Configuration ===
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
