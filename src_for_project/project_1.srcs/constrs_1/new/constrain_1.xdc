set_property PACKAGE_PIN G19 [get_ports {vga_red[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_red[0]}]
set_property PACKAGE_PIN H19 [get_ports {vga_red[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_red[1]}]
set_property PACKAGE_PIN J19 [get_ports {vga_red[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_red[2]}]
set_property PACKAGE_PIN N19 [get_ports {vga_red[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_red[3]}]
set_property PACKAGE_PIN J17 [get_ports {vga_green[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_green[0]}]
set_property PACKAGE_PIN H17 [get_ports {vga_green[1]}]
set_property PACKAGE_PIN G17 [get_ports {vga_green[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_blue[3]}]
set_property PACKAGE_PIN D17 [get_ports {vga_green[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_green[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_green[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_green[2]}]
set_property PACKAGE_PIN N18 [get_ports {vga_blue[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_blue[0]}]
set_property PACKAGE_PIN L18 [get_ports {vga_blue[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_blue[1]}]
set_property PACKAGE_PIN K18 [get_ports {vga_blue[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_blue[2]}]
set_property PACKAGE_PIN J18 [get_ports {vga_blue[3]}]
set_property PACKAGE_PIN P19 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property PACKAGE_PIN R19 [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]


set_property PACKAGE_PIN W5 [get_ports clk100]
set_property IOSTANDARD LVCMOS33 [get_ports clk100]
set_property PACKAGE_PIN U16 [get_ports {LED[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[0]}]
set_property PACKAGE_PIN E19 [get_ports {LED[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[1]}]
set_property PACKAGE_PIN U19 [get_ports {LED[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[2]}]
set_property PACKAGE_PIN V19 [get_ports {LED[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports OV7670_SIOC]
set_property IOSTANDARD LVCMOS33 [get_ports {OV7670_D[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {OV7670_D[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {OV7670_D[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {OV7670_D[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {OV7670_D[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {OV7670_D[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {OV7670_D[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports OV7670_HREF]
set_property IOSTANDARD LVCMOS33 [get_ports OV7670_PCLK]
set_property IOSTANDARD LVCMOS33 [get_ports OV7670_SIOD]
set_property IOSTANDARD LVCMOS33 [get_ports OV7670_VSYNC]
set_property PACKAGE_PIN  [get_ports OV7670_XCLK] // FIX
set_property IOSTANDARD LVCMOS33 [get_ports OV7670_XCLK]
set_property PACKAGE_PIN U18 [get_ports btn]
set_property IOSTANDARD LVCMOS33 [get_ports btn]
set_property IOSTANDARD LVCMOS33 [get_ports pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports {OV7670_D[0]}]

set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN W17   IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN V2    IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN T3    IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN T2    IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN R3    IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]




set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets OV7670_PCLK_IBUF]




set_property PACKAGE_PIN  [get_ports {OV7670_D[4]}] // FIX
set_property PACKAGE_PIN  [get_ports {OV7670_D[2]}] // FIX
set_property PACKAGE_PIN  [get_ports {OV7670_D[0]}] // FIX
set_property PACKAGE_PIN  [get_ports {OV7670_D[5]}] // FIX
set_property PACKAGE_PIN  [get_ports {OV7670_D[3]}] // FIX
set_property PACKAGE_PIN  [get_ports {OV7670_D[1]}] // FIX
set_property PACKAGE_PIN  [get_ports reset] // FIX


set_property PACKAGE_PIN  [get_ports {OV7670_D[7]}] // FIX
set_property PACKAGE_PIN  [get_ports {OV7670_D[6]}] // FIX
set_property PACKAGE_PIN  [get_ports OV7670_SIOD]// is scl
set_property PACKAGE_PIN  [get_ports OV7670_SIOC]//is sda
set_property PACKAGE_PIN  [get_ports pwdn] // FIX
set_property PACKAGE_PIN  [get_ports OV7670_HREF] // FIX
set_property PACKAGE_PIN  [get_ports OV7670_VSYNC] // FIX
set_property PACKAGE_PIN  [get_ports OV7670_PCLK] // FIX
