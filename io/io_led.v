/*
 * My RISC-V RV32I CPU
 *   FPGA LED output and GPIO Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2025 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

`define FPGA_MODE

module io_led(
	input clk,
	input rst_n,
	// from/to IO bus

    input dma_io_we,
    input [15:2] dma_io_wadr,
    input [31:0] dma_io_wdata,
    input [15:2] dma_io_radr,
    input dma_io_radr_en,
    input [31:0] dma_io_rdata_in,
    output [31:0] dma_io_rdata,
	// from SPIO output
    (* mark_debug = "true", keep = "true" *) input wire spi_mosi,
    (* mark_debug = "true", keep = "true" *) input wire [1:0] spi_csn,
    (* mark_debug = "true", keep = "true" *) input wire spi_sck,
    (* mark_debug = "true", keep = "true" *) input wire spi_select_io,
    //input wire spi_mosi,
	//input [1:0] spi_csn,
	//input spi_sck,
	//input spi_select_io,
	// for gpo extention
	input uart2_io_en,
	output rx2_org,
	input tx2_org,
`ifdef FPGA_MODE
    //(* mark_debug = "true", keep = "true" *) output [2:0] rgb_led,
	inout [2:0] rgb_led,
	inout rx2,
	inout tx2,
`else // FPGA_MODE
	input [2:0] rgb_led_i,
	output [2:0] rgb_led_o,
	output [2:0] rgb_led_en,
	input rx2_i,
	output rx2_o,
	output rx2_en,
	input tx2_i,
	output tx2_o,
	output tx2_en,
`endif // FPGA_MODE
	input [2:0] dbg_bpoint_en,
	input [2:0] dbg_bpoint,
	input cpu_start,
	// for reading input
	input [1:0] init_uart,
	input [1:0] init_latency,
	input init_cpu_start,
	input gpi_in,
	// gpios
`ifdef FPGA_MODE
	inout [5:0] gpio
`else // FPGA_MODE
	input [5:0] gpio_i,
	output [5:0] gpio_o,
	output [5:0] gpio_en
`endif // FPGA_MODE
	);




`define SYS_LED_IO   14'h3F80
`define SYS_GPI_IN   14'h3F81
`define SYS_GPIO_OUT 14'h3F84
`define SYS_GPIO_IN  14'h3F85
`define SYS_GPIO_EN  14'h3F86
`define SYS_LED_IN   14'h3F88
`define SYS_LED_EB   14'h3F89

wire we_led_value = dma_io_we      & (dma_io_wadr == `SYS_LED_IO);
wire re_led_value = dma_io_radr_en & (dma_io_radr == `SYS_LED_IO);

wire re_gpi_value = dma_io_radr_en & (dma_io_radr == `SYS_GPI_IN);

wire we_gpio_out_value = dma_io_we      & (dma_io_wadr == `SYS_GPIO_OUT);
wire re_gpio_out_value = dma_io_radr_en & (dma_io_radr == `SYS_GPIO_OUT);

wire re_gpio_in_value = dma_io_radr_en & (dma_io_radr == `SYS_GPIO_IN);

wire we_gpio_en_value = dma_io_we      & (dma_io_wadr == `SYS_GPIO_EN);
wire re_gpio_en_value = dma_io_radr_en & (dma_io_radr == `SYS_GPIO_EN);

wire re_led_in_value = dma_io_radr_en & (dma_io_radr == `SYS_LED_IN);

wire we_led_en_value = dma_io_we      & (dma_io_wadr == `SYS_LED_EB);
wire re_led_en_value = dma_io_radr_en & (dma_io_radr == `SYS_LED_EB);

reg [4:0] led_value;
reg [4:0] led_en_value;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        led_value <= 5'd0 ;
	else if ( we_led_value )
		led_value <= dma_io_wdata[4:0];
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        led_en_value <= 5'h07 ; // default: rgb_led output, tx2/rx2 input
	else if ( we_led_en_value )
		led_en_value <= dma_io_wdata[4:0];
end

reg re_led_value_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        re_led_value_dly <= 1'b0 ;
	else
        re_led_value_dly <= re_led_value ;
end

//assign rgb_led[0] = led_value[0];
//assign rgb_led[1] = led_value[1];

wire dbg_bpen = |dbg_bpoint_en;
wire dbg_trgsig2 = dbg_bpoint_en[2] & dbg_bpoint[2];
wire dbg_trgsig1 = dbg_bpoint_en[1] & dbg_bpoint[1];
wire dbg_trgsig0 = dbg_bpoint_en[0] & dbg_bpoint[0];
wire dbg_trgsig = dbg_trgsig2 | dbg_trgsig1 | dbg_trgsig0;
// sampler : clear by start signal
reg dbg_smpl_trgsig;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
		dbg_smpl_trgsig <= 1'b0;
	else if ( cpu_start )
		dbg_smpl_trgsig <= 1'b0;
	else if ( dbg_trgsig )
		dbg_smpl_trgsig <= 1'b1;
end

// change to gpip[5]
//wire rgb_led_dbg = dbg_bpen ? dbg_smpl_trgsig : led_value[2];

// gpio part

reg [5:0] gpio_out_value;
reg [5:0] gpio_en_value;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        gpio_out_value <= 6'd0 ;
	else if ( we_gpio_out_value )
		gpio_out_value <= dma_io_wdata[5:0];
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        gpio_en_value <= 6'd0 ;
	else if ( we_gpio_en_value )
		gpio_en_value <= dma_io_wdata[5:0];
end

reg [5:0] re_gpio_value_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        re_gpio_value_dly <= 6'd0 ;
	else
        re_gpio_value_dly <= { re_led_en_value, re_led_in_value, re_gpio_en_value, re_gpio_in_value, re_gpio_out_value, re_gpi_value };
end

wire [5:0] gpio_in;
wire [4:0] led_in;
reg [5:0] gpi_init_lat2;
reg [5:0] gpio_in_lat2;
reg [4:0] led_in_lat2;

assign dma_io_rdata = (re_led_value_dly == 1'b1) ? { 27'd0, led_value } : 
                      (re_gpio_value_dly[0] == 1'b1) ? { 26'd0, gpi_init_lat2 } :
                      (re_gpio_value_dly[1] == 1'b1) ? { 26'd0, gpio_out_value } :
                      (re_gpio_value_dly[2] == 1'b1) ? { 26'd0, gpio_in_lat2 } :
                      (re_gpio_value_dly[3] == 1'b1) ? { 26'd0, gpio_en_value } :
                      (re_gpio_value_dly[4] == 1'b1) ? { 27'd0, led_in_lat2 } :
                      (re_gpio_value_dly[5] == 1'b1) ? { 27'd0, led_en_value } : dma_io_rdata_in;

// inout port
`ifdef FPGA_MODE
assign gpio[0] = (gpio_en_value[0]) ? gpio_out_value[0] : 1'bz;
assign gpio[1] = (gpio_en_value[1]) ? gpio_out_value[1] : 1'bz;
assign gpio[2] = (gpio_en_value[2]) ? gpio_out_value[2] : 1'bz;
assign gpio[3] = (gpio_en_value[3]) ? gpio_out_value[3] : 1'bz;
assign gpio[4] = (gpio_en_value[4]) ? gpio_out_value[4] : 1'bz;
assign gpio[5] = dbg_bpen ? dbg_smpl_trgsig : (gpio_en_value[5]) ? gpio_out_value[5] : 1'bz;

assign gpio_in = gpio; 

//assign rgb_led[0] = spi_sck;
//assign rgb_led[1] = spi_csn[0];
//assign rgb_led[2] = spi_mosi;
assign rgb_led[0] = spi_select_io ? spi_sck : (led_en_value[0]) ? led_value[0] : 1'bz;
assign rgb_led[1] = spi_select_io ? spi_csn[0] : (led_en_value[1]) ? led_value[1] : 1'bz;
assign rgb_led[2] = spi_select_io ? spi_mosi : (led_en_value[2]) ? led_value[2] : 1'bz;

assign tx2 = uart2_io_en ? tx2_org : (led_en_value[3]) ? led_value[3] : 1'bz;
assign rx2 = uart2_io_en ? 1'bz : (led_en_value[4]) ? led_value[4] : 1'bz;

wire [1:0] uart_in_mskd = uart2_io_en ? 2'd0 : {rx2, tx2};
assign led_in = {uart_in_mskd, rgb_led[2:0]};

assign rx2_org = rx2;

`else // FPGA_MODE

assign gpio_in = gpio_i;
assign gpio_o = { dbg_bpen ? dbg_smpl_trgsig : gpio_out_value[5], gpio_out_value[4:0] };
assign gpio_en = { dbg_bpen | gpio_en_value[5], gpio_en_value[4:0] };

wire [1:0] uart2_in_mskd = uart2_io_en ? 2'd0 : { rx2_i, tx2_i };
assign led_in = {uart2_in_mskd, rgb_led_i[2:0]};

assign rgb_led_o = spi_select_io ? { spi_mosi, spi_csn[0], spi_sck } : led_value[2:0];
assign rgb_led_en = { 3{ spi_select_io }} | led_en_value[2:0];

assign tx2_o = uart2_io_en ? tx2_org : led_value[3];
assign rx2_o = uart2_io_en ? 1'b0 : led_value[4];

assign tx2_en = uart2_io_en | led_en_value[3];
assign rx2_en = ~uart2_io_en & led_en_value[4];

assign rx2_org = rx2_i;

`endif // FPGA_MODE

// for uart2

// double latch for input signals
reg [5:0] gpi_init_lat1;
reg [5:0] gpio_in_lat1;
reg [4:0] led_in_lat1;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        gpi_init_lat1 <= 6'd0 ;
        gpi_init_lat2 <= 6'd0 ;
        gpio_in_lat1 <= 6'd0 ;
        gpio_in_lat2 <= 6'd0 ;
        led_in_lat1 <= 5'd0 ;
        led_in_lat2 <= 5'd0 ;
	end
	else begin
        gpi_init_lat1 <= { init_uart[1:0], init_cpu_start, init_latency[1:0], gpi_in };
        gpi_init_lat2 <= gpi_init_lat1;
        gpio_in_lat1 <= gpio_in;
        gpio_in_lat2 <= gpio_in_lat1;
        led_in_lat1 <= led_in;
        led_in_lat2 <= led_in_lat1 ;
	end
end

endmodule
