/*
 * My RISC-V RV32I CPU
 *   FPGA uart input/output Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2025 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module io_uart2(
	input clk,
	input rst_n,
	// outside if
	input rx2,
	output tx2,

	// from/to IO bus
    input dma_io_we,
    input [15:2] dma_io_wadr,
    input [31:0] dma_io_wdata,
    input [15:2] dma_io_radr,
    input dma_io_radr_en,
    input [31:0] dma_io_rdata_in,
    output [31:0] dma_io_rdata,

	output ext_uart2_interrpt_1shot,
	output reg uart2_io_en

	);

// misc signals
reg [15:0] uart_term;
reg [7:0] uart_io_char;
reg uart_io_we;
wire uart_io_full;
//input [1:0] init_uart,

//wire rx_disable_echoback;

wire tx_fifo_overrun; // output
wire tx_fifo_underrun; // output

wire rx_fifo_dvalid; // output
wire rout_en; // input
wire [7:0] rout; // input
wire rx_fifo_full; // output
wire rx_fifo_overrun; // output
wire rx_fifo_underrun; // output

`define SYS_UART2_OUTC 14'h3CC0
`define SYS_UART2_ENBL 14'h3CC1
`define SYS_UART2_TERM 14'h3CC2
`define SYS_UART2_RXCH 14'h3CC3
`define SYS_UART2_RXEC 14'h3CC4

wire we_uart_char = dma_io_we      & (dma_io_wadr == `SYS_UART2_OUTC);
wire re_uart_char = dma_io_radr_en & (dma_io_radr == `SYS_UART2_OUTC);

wire we_uart_full = dma_io_we      & (dma_io_wadr == `SYS_UART2_ENBL);
wire re_uart_full = dma_io_radr_en & (dma_io_radr == `SYS_UART2_ENBL);

wire we_uart_term = dma_io_we      & (dma_io_wadr == `SYS_UART2_TERM);
wire re_uart_term = dma_io_radr_en & (dma_io_radr == `SYS_UART2_TERM);

wire we_uart_rxch = dma_io_we      & (dma_io_wadr == `SYS_UART2_RXCH);
wire re_uart_rxch = dma_io_radr_en & (dma_io_radr == `SYS_UART2_RXCH);

wire we_uart_rxec = dma_io_we      & (dma_io_wadr == `SYS_UART2_RXEC);
wire re_uart_rxec = dma_io_radr_en & (dma_io_radr == `SYS_UART2_RXEC);

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        uart_io_char <= 8'd0 ;
	else if ( we_uart_char )
		uart_io_char <= dma_io_wdata[7:0];
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        uart_io_we <= 1'b0 ;
	else
        uart_io_we <= we_uart_char & ~uart_io_full;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        uart2_io_en <= 1'b0;
	else if ( we_uart_full )
		uart2_io_en <= dma_io_wdata[0];
end

// for fifo reset
// for debugging sample
//(* MARK_DEBUG = "true" *) wire tx_fifo_rst;
//(* MARK_DEBUG = "true" *) wire rx_fifo_rst;
wire tx_fifo_rst;
wire rx_fifo_rst;

assign tx_fifo_rst = we_uart_full & dma_io_wdata[16];
assign rx_fifo_rst = we_uart_rxch & dma_io_wdata[16];

// UART term reset values
// for tiny tapeout

// clk 1MHz - 4MHz, 8MHz, 4800 - 19200bps, 38400bps
//`define U2TERM_0 16'd209
// test1 5MHz, 10MHz  19200bps, 38400bps
//`define U2TERM_1 16'd261
// clk:3MHz,6MHz,9MHz 19200bps, 38400bps, 57600bps
//`define U2TERM_2 16'd156
// clk:7MHz, 38400bps
//`define U2TERM_3 16'd184


// for fpga *** please comment out for tiny tapeout ***

// clk 50MHz, 9600bps
`define U2TERM_1 16'd5208
// clk 50MHz, 921600bps
//`define U2TERM_1 16'd54
// test1 6MHz 38400bps
//`define U2TERM_1 16'd156
// test2 5MHz 19200bps
//`define U2TERM_1 16'd261
// test3 7MHz 384000bps
//`define U2TERM_1 16'd184
// test4 8MHz 384000bps
//`define U2TERM_1 16'd209
// test5 16MHz 576000bps
//`define U2TERM_1 16'd278
// test6 17MHz 576000bps
//`define U2TERM_1 16'd295
// test7 14MHz 576000bps
//`define U2TERM_1 16'd243
// test8 20MHz 576000bps
//`define U2TERM_1 16'd348
// test10 13MHz 576000bps
//`define U2TERM_1 16'd226
	
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        uart_term <= `U2TERM_1;
	else if ( we_uart_term )
		uart_term <= dma_io_wdata[15:0];
end

// rx data : latch rx char when data valid and red
reg [7:0] rx_data_latch;
reg rx_first_read;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rx_data_latch <= 8'd0 ;
	else if ( rout_en & ~rx_first_read )
		rx_data_latch <= rout;
end

assign ext_uart2_interrpt_1shot = rout_en;

// polling bit for rx data
reg [4:0] re_uart_rdflg_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rx_first_read <= 1'b0 ;
    else if (rx_fifo_rst)
        rx_first_read <= 1'b0 ;
	else if ( re_uart_rdflg_dly[3] ) // clear when read
        rx_first_read <= 1'b0 ;
	else if ( rout_en ) // set when write
        rx_first_read <= 1'b1 ;
end

// wirte when not read error bit
//reg rx_write_error;

//always @ (posedge clk or negedge rst_n) begin
    //if (~rst_n)
        //rx_write_error <= 1'b0 ;
    //else if (rx_fifo_rst)
        //rx_write_error <= 1'b0 ;
	//else if ( re_uart_rdflg_dly[3] ) // clear when read
        //rx_write_error <= 1'b0 ;
	//else if ( rout_en & rx_first_read ) // set when write on not read data
        //rx_write_error <= 1'b1 ;
//end

// disable echo back bit
reg rx_disable_echoback_value;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rx_disable_echoback_value <= 1'b0 ;
	else if ( we_uart_rxec )
		rx_disable_echoback_value <= dma_io_wdata[0];
end


// read part


always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        re_uart_rdflg_dly <= 5'd0 ;
	else
        re_uart_rdflg_dly <= { re_uart_rxec, re_uart_rxch, re_uart_term, re_uart_full, re_uart_char };
end

assign dma_io_rdata = (re_uart_rdflg_dly[0]) ? { 24'd0, uart_io_char } :
                      (re_uart_rdflg_dly[1]) ? { 28'd0, tx_fifo_underrun, tx_fifo_overrun, uart_io_full, uart2_io_en } :
                      (re_uart_rdflg_dly[2]) ? { 16'd0, uart_term } :
                      (re_uart_rdflg_dly[3]) ? { 20'd0, rx_fifo_underrun, rx_fifo_overrun, rx_fifo_full, rx_first_read, rx_data_latch } :
                      (re_uart_rdflg_dly[4]) ? { 31'd0, rx_disable_echoback_value } : dma_io_rdata_in;

// instance
// need to control logics

assign rout_en = rx_fifo_dvalid & ~rx_first_read;
wire [7:0] tx_wdata = uart_io_char;
wire tx_wten = uart_io_we;

io_uart2_if io_uart2_if (
	.clk(clk),
	.rst_n(rst_n),
	.rx(rx2),
	.tx(tx2),
	.rx_rden(rout_en),
	.rx_rdata(rout),
	.rx_fifo_full(rx_fifo_full),
	.rx_fifo_dvalid(rx_fifo_dvalid),
	.rx_fifo_overrun(rx_fifo_overrun),
	.rx_fifo_underrun(rx_fifo_underrun),
	.rx_fifo_rst(rx_fifo_rst),
	.tx_wdata(tx_wdata),
	.tx_wten(tx_wten),
	.tx_fifo_full(uart_io_full),
	.tx_fifo_overrun(tx_fifo_overrun),
	.tx_fifo_underrun(tx_fifo_underrun),
	.tx_fifo_rst(tx_fifo_rst),
	.rx_disable_echoback_value(rx_disable_echoback_value),
	//.rx_fifo_rcntrs(rx_fifo_rcntrs),
	.uart_term(uart_term)
	);

endmodule
