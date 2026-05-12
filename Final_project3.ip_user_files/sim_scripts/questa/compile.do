vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xpm
vlib questa_lib/msim/xil_defaultlib

vmap xpm questa_lib/msim/xpm
vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xpm  -incr -mfcu  -sv "+incdir+../../../../../../../../AMDVivado/2025.2/Vivado/data/rsb/busdef" \
"W:/AMDVivado/2025.2/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"W:/AMDVivado/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm  -93  \
"W:/AMDVivado/2025.2/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../../../../../AMDVivado/2025.2/Vivado/data/rsb/busdef" \
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

