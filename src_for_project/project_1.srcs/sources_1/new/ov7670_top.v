`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: SYSU
// Engineer: liuzs
// 
// Create Date: 2018/12/03 21:37:38
// Design Name: 
// Module Name: ov7670_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ov7670_top(
input  clk100,
input  OV7670_VSYNC, //SCCBЭ��ʵ�ֳ�ͬ���ź�����
input  OV7670_HREF,  //SCCBЭ��ʵ����ͬ���ź�����
input  OV7670_PCLK,  //����ʱ������
output OV7670_XCLK,  //����ͷ����ʱ��
output OV7670_SIOC, 
inout  OV7670_SIOD,
input [7:0] OV7670_D, //���ݴ�����

output[3:0] LED,
output[3:0] vga_red,
output[3:0] vga_green,
output[3:0] vga_blue,
output vga_hsync, //��ֱͬ��
output vga_vsync, //��ͬ��
input btn,
output pwdn,
output reset,
input [11:0] sw
);
wire [16:0] frame_addr;
wire [16:0] capture_addr;   
wire  capture_we;  
wire  config_finished;  
wire  clk25; 
wire  clk50;
wire  clk;     
wire  resend;        
wire [11:0] frame_pixel;  
wire [11:0]  data_16;
  
assign pwdn = 0; //0Ϊ����������1Ϊ�͹���ģʽ
assign reset = 1;
  

assign LED = {3'b0,config_finished};
assign  	OV7670_XCLK = clk25;  
debounce   btn_debounce(
		.clk(clk50),
		.i(btn),
		.o(resend)
);
 
 vga   vga_display (
		.clk25       (clk25),
		.vga_red    (vga_red),
		.vga_green   (vga_green),
		.vga_blue    (vga_blue),
		.vga_hsync   (vga_hsync),
		.vga_vsync  (vga_vsync),
		.HCnt       (),
		.VCnt       (),

		.frame_addr   (frame_addr),
		.frame_pixel  (frame_pixel)//replace with frame_pixel
 );
 
 blk_mem_gen_0 u_frame_buffer(
		.clka (OV7670_PCLK),
		.wea  (capture_we),
		.addra (capture_addr),
		.dina  (data_16),

		.clkb   (clk25),
		.addrb (frame_addr),
		.doutb (frame_pixel)
 );
 

 ov7670_capture capture(         //����ov7670����ͷ����
 		.pclk  (OV7670_PCLK),    //�������ʱ��
 		.vsync (OV7670_VSYNC),   //��ͬ��
 		.href  (OV7670_HREF),    //��ֱͬ�� 
 		.d     ( OV7670_D),      //ͼ���������
 		.addr  (capture_addr),   //�洢��ĵ�ַ
 		.dout (data_16),         //12λ�������
 		.we   (capture_we)
 	);
 
I2C_AV_Config IIC(                 //����ͷSCCBЭ���ʵ��
 		.iCLK   ( clk25),          //����25MHzʱ��
 		.iRST_N (! resend),        //��λ
 		.Config_Done ( config_finished),    //��ov7670�ļĴ�������������ɺ󣬷���config_finished�ź�
 		.I2C_SDAT  ( OV7670_SIOD),   //�������� 
 		.I2C_SCLK  ( OV7670_SIOC),   //����ʱ������
 		.LUT_INDEX (),
 		.I2C_RDATA ()
 		); 
		
clk_wiz_0 clk_div(
		.clk_in1 (clk100),
		.clk_out1 (clk50),
		.clk_out2 (clk25),
		.clk_out3 (clk)
);

ila ila_out(
        .clk(clk),
        .probe0(vga_hsync),
        .probe1(vga_vsync),
        .probe2(frame_addr),
        .probe3(capture_addr),
        .probe4(data_16)
        
);
endmodule