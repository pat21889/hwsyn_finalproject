transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xpm
vlib riviera/xil_defaultlib

vmap xpm riviera/xpm
vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xpm  -incr "+incdir+../../../../../../../../AMDVivado/2025.2/Vivado/data/rsb/busdef" -l xpm -l xil_defaultlib \
"W:/AMDVivado/2025.2/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"W:/AMDVivado/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  -incr \
"W:/AMDVivado/2025.2/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../../../../../../AMDVivado/2025.2/Vivado/data/rsb/busdef" -l xpm -l xil_defaultlib \
"../../../src/clk_wiz.v" \
"../../../src/frame_buffer.v" \
"../../../src/image_filter.v" \
"../../../src/ov7670_capture.v" \
"../../../src/ov7670_init.v" \
"../../../src/sccb_master.v" \
"../../../src/vga_display.v" \
"../../../src/vga_sync.v" \
"../../../src/top.v" \

vlog -work xil_defaultlib \
"glbl.v"

