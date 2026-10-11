/*
 * My RISC-V RV32I CPU
 *   FPGA Top module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2025 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

`define FPGA_MODE

module fpga_top (
	input clkin,
	input rst_n,
`ifndef FPGA_MODE
	input mclkin,     // scratch RAM clock (asynchronous to clkin)
`endif // FPGA_MODE

	input interrupt_0,

	output sck,
	output [2:0] ce_n,
`ifdef FPGA_MODE
	inout [3:0] sio,
`else // FPGA_MODE
	input [3:0] sio_i,
	output [3:0] sio_o,
	output sio_en,
`endif // FPGA_MODE

	input rx,
	output tx,
	output [2:0] rgb_led,
`ifdef FPGA_MODE
	inout [3:0] gpio,
`else // FPGA_MODE
	input [3:0] gpio_i,
	output [3:0] gpio_o,
	output [3:0] gpio_en,
`endif // FPGA_MODE

`ifndef FPGA_MODE
	// sram port
	output sram_gwen_0,
	output [9:0] sram_a_0,
	output [7:0] sram_d_0,
	input [7:0] sram_q_0,
	
	output sram_gwen_1,
	output [9:0] sram_a_1,
	output [7:0] sram_d_1,
	input [7:0] sram_q_1,
	
	output sram_gwen_2,
	output [9:0] sram_a_2,
	output [7:0] sram_d_2,
	input [7:0] sram_q_2,
	
	output sram_gwen_3,
	output [9:0] sram_a_3,
	output [7:0] sram_d_3,
	input [7:0] sram_q_3,

	output sram_gwen_4,
	output [9:0] sram_a_4,
	output [7:0] sram_d_4,
	input [7:0] sram_q_4,

	output sram_gwen_5,
	output [9:0] sram_a_5,
	output [7:0] sram_d_5,
	input [7:0] sram_q_5,

	output sram_gwen_6,
	output [9:0] sram_a_6,
	output [7:0] sram_d_6,
	input [7:0] sram_q_6,

	output sram_gwen_7,
	output [9:0] sram_a_7,
	output [7:0] sram_d_7,
	input [7:0] sram_q_7,

	output sram_gwen_8,
	output [9:0] sram_a_8,
	output [7:0] sram_d_8,
	input [7:0] sram_q_8,

	output sram_gwen_9,
	output [9:0] sram_a_9,
	output [7:0] sram_d_9,
	input [7:0] sram_q_9,

	output sram_gwen_10,
	output [9:0] sram_a_10,
	output [7:0] sram_d_10,
	input [7:0] sram_q_10,

	output sram_gwen_11,
	output [9:0] sram_a_11,
	output [7:0] sram_d_11,
	input [7:0] sram_q_11,
`endif // FPGA_MODE

`ifdef FPGA_MODE
	 inout [1:0] init_latency,
`else // FPGA_MODE
	input [1:0] init_latency_i,
	output [1:0] init_latency_o,
	output init_latency_en,
`endif // FPGA_MODE

	input init_qspicmd,
	input init_cpu_start,
	input [1:0] init_uart

	);

wire clk;
wire locked;
// cpu
wire [31:0] pc_data; // input NAI!
wire cmd_ld_ma;
wire cmd_st_ma;
wire [31:0] rd_data_ma;
wire cpu_start; // input
wire quit_cmd; // output NAI!
wire [31:2] cpu_start_adr;
wire i_read_req; // output
wire i_read_w; // output
wire i_read_hw; // output
wire [31:0] i_read_adr; // output
wire d_read_req; // output
wire d_read_w; // output
wire d_read_hw; // output
wire read_valid; // input
wire [31:0] d_read_adr; // output
wire [31:0] read_data; // input
wire d_write_req; // output
wire d_write_w; // output
wire d_write_hw; // output
wire write_finish; // input
wire [31:0] d_write_adr; // output
wire [31:0] d_write_data; // output

// qspi
wire read_req; // output
wire read_w; // output
wire read_hw; // output
wire [31:0] read_adr; // output
wire write_req; // output
wire write_w; // output
wire write_hw; // output
wire [31:0] write_adr; // output
wire [31:0] write_data; // output

// scratch RAM (12KB, mapped at 0x03000000 via qspi_if; scratch2 64B at 0x03003000)
// built from twelve 1024x8 banks + 4 scratch2 lanes, interleaved by byte lane
// (bank b = group * 4 + lane, lane = byte address[1:0]) so a word access is one RAM cycle;
// The RAMs run on mclk (mclkin). qspi_if (clk) hands every access over to
// scratch_mif (mclk) with a toggle req/ack handshake; per lane address / data,
// bank wen decode and read data mux live inside scratch_mif.
wire sc_req; // output of qspi_if, toggle
wire sc_wr;
wire [1:0] sc_last;
wire [13:0] sc_adr;
wire [31:0] sc_wdata;
wire sc_ack; // output of scratch_mif, toggle
wire [31:0] sc_mrdata;
wire [39:0] sc_ram_adr; // output, lane l : [l*10 +: 10]
wire [31:0] sc_ram_wdata; // output, lane l : [l*8 +: 8]
wire [15:0] sc_ram_wen; // output, bank b
wire [127:0] sc_ram_rdata; // input, bank b : [b*8 +: 8]

// outside sram i/f : sram_N is bank N (lane N % 4, group N / 4)
`ifndef FPGA_MODE
assign sram_gwen_0 = ~sc_ram_wen[0];
assign sram_a_0 = sc_ram_adr[9:0];
assign sram_d_0 = sc_ram_wdata[7:0];
assign sc_ram_rdata[7:0] = sram_q_0; // input

assign sram_gwen_1 = ~sc_ram_wen[1];
assign sram_a_1 = sc_ram_adr[19:10];
assign sram_d_1 = sc_ram_wdata[15:8];
assign sc_ram_rdata[15:8] = sram_q_1; // input

assign sram_gwen_2 = ~sc_ram_wen[2];
assign sram_a_2 = sc_ram_adr[29:20];
assign sram_d_2 = sc_ram_wdata[23:16];
assign sc_ram_rdata[23:16] = sram_q_2; // input

assign sram_gwen_3 = ~sc_ram_wen[3];
assign sram_a_3 = sc_ram_adr[39:30];
assign sram_d_3 = sc_ram_wdata[31:24];
assign sc_ram_rdata[31:24] = sram_q_3; // input

assign sram_gwen_4 = ~sc_ram_wen[4];
assign sram_a_4 = sc_ram_adr[9:0];
assign sram_d_4 = sc_ram_wdata[7:0];
assign sc_ram_rdata[39:32] = sram_q_4; // input

assign sram_gwen_5 = ~sc_ram_wen[5];
assign sram_a_5 = sc_ram_adr[19:10];
assign sram_d_5 = sc_ram_wdata[15:8];
assign sc_ram_rdata[47:40] = sram_q_5; // input

assign sram_gwen_6 = ~sc_ram_wen[6];
assign sram_a_6 = sc_ram_adr[29:20];
assign sram_d_6 = sc_ram_wdata[23:16];
assign sc_ram_rdata[55:48] = sram_q_6; // input

assign sram_gwen_7 = ~sc_ram_wen[7];
assign sram_a_7 = sc_ram_adr[39:30];
assign sram_d_7 = sc_ram_wdata[31:24];
assign sc_ram_rdata[63:56] = sram_q_7; // input

assign sram_gwen_8 = ~sc_ram_wen[8];
assign sram_a_8 = sc_ram_adr[9:0];
assign sram_d_8 = sc_ram_wdata[7:0];
assign sc_ram_rdata[71:64] = sram_q_8; // input

assign sram_gwen_9 = ~sc_ram_wen[9];
assign sram_a_9 = sc_ram_adr[19:10];
assign sram_d_9 = sc_ram_wdata[15:8];
assign sc_ram_rdata[79:72] = sram_q_9; // input

assign sram_gwen_10 = ~sc_ram_wen[10];
assign sram_a_10 = sc_ram_adr[29:20];
assign sram_d_10 = sc_ram_wdata[23:16];
assign sc_ram_rdata[87:80] = sram_q_10; // input

assign sram_gwen_11 = ~sc_ram_wen[11];
assign sram_a_11 = sc_ram_adr[39:30];
assign sram_d_11 = sc_ram_wdata[31:24];
assign sc_ram_rdata[95:88] = sram_q_11; // input
`endif // FPGA_MODE

// uart
wire u_read_req; // input
wire u_read_w; // input
wire [31:0] u_read_adr; // input
wire u_write_req; // input
wire u_write_w; // input
wire [31:0] u_write_adr; // input
wire [31:0] u_write_data; // input

// uart IO
wire [7:0] uart_io_char; // input
wire uart_io_we; // input
wire uart_io_full; // output
wire [15:0] uart_term;
wire rout_en;
wire [7:0] rout;
wire cpu_run_state;

// io bus for cpu
wire dma_io_we_c; // output
wire [15:2] dma_io_wadr_c; // output
wire [31:0] dma_io_wdata_c; // output
wire [15:2] dma_io_radr_c; // output
wire dma_io_radr_en_c; // output
// io bus for uart
wire dma_io_we_u; // output
wire [15:2] dma_io_wadr_u; // output
wire [31:0] dma_io_wdata_u; // output
wire [15:2] dma_io_radr_u; // output
wire dma_io_radr_en_u; // output
// io bus read datat
wire [31:0] dma_io_rdata; // input
wire [31:0] dma_io_rdata_in = 32'hdeadbeef; // input
//wire [31:0] dma_io_rdata_in = 32'd0; // input
wire [31:0] dma_io_rdata_in_2; // input
wire [31:0] dma_io_rdata_in_3; // input
wire [31:0] dma_io_rdata_in_4; // input
wire [31:0] dma_io_rdata_in_5; // input
wire [31:0] dma_io_rdata_in_6; // input
wire [31:0] dma_io_rdata_in_7; // input

// csr monitor bus
wire csr_radr_en_mon; // output
wire [11:0] csr_radr_mon; // output
wire [11:0] csr_wadr_mon; // output
wire csr_we_mon; // output
wire [31:0] csr_wdata_mon; // output
wire [31:0] csr_rdata_mon; // input
// rf monitor bus
wire rf_radr_en_mon; // output
wire [4:0] rf_radr_mon; // output
wire [4:0] rf_wadr_mon; // output
wire rf_we_mon; // output
wire [31:0] rf_wdata_mon; // output
wire [31:0] rf_rdata_mon; // input

// for free run counter signals
wire csr_mtie;
wire frc_cntr_val_leq;
//wire interrupt_clear;
wire ext_uart_interrpt_1shot;
wire csr_rmie;
wire csr_meie;
wire g_interrupt_1shot;
wire g_interrupt;

// uart rx 
wire rx_disable_echoback;

// spi IO signals
wire spi_select_io; // output
wire spi_sck; // output
wire [1:0] spi_csn; // output
wire spi_mosi; // output
wire [2:0] rgb_led_org;

// break point debug singal
wire [2:0] dbg_bpoint_en;
wire [2:0] dbg_bpoint;

// spi IO selector
assign rgb_led = spi_select_io ? { spi_mosi, spi_csn[0], spi_sck } : rgb_led_org;
wire spi_miso = init_qspicmd; // input

// uart2 IO selector

wire rx2 = init_latency[0]; // input
wire tx2; // output
wire uart2_io_en; // output
wire ext_uart2_interrpt_1shot;

`ifdef FPGA_MODE
assign init_latency = uart2_io_en ? { tx2, 1'bz } : 2'bzz;
`else // FPGA_MODE
wire [1:0] init_latency = init_latency_i;
assign init_latency_o = { tx2, 1'b0 };
assign init_latency_en = uart2_io_en;
`endif // FPGA_MODE

// io bus logics
wire dma_io_we = dma_io_we_c | dma_io_we_u;
wire [15:2] dma_io_wadr = dma_io_we_u ? dma_io_wadr_u : dma_io_wadr_c;
wire [31:0] dma_io_wdata = dma_io_we_u ? dma_io_wdata_u : dma_io_wdata_c;
wire dma_io_radr_en = dma_io_radr_en_c | dma_io_radr_en_u;
wire [15:2] dma_io_radr = dma_io_radr_en_u ? dma_io_radr_u : dma_io_radr_c;

`ifdef FPGA_MODE
clk_wiz_0 clk_wiz_0 (
	.clk_out1(clk),
	.reset(~rst_n),
	.locked(locked),
	.clk_in1(clkin)
	);
wire mclk = clk;
`else // FPGA_MODE
assign clk = clkin;
wire mclk = mclkin;
`endif // FPGA_MODE

cpu_top cpu_top (
	.clk(clk),
	.rst_n(rst_n),
	.cpu_start(cpu_start),
	.init_cpu_start(init_cpu_start),
	.quit_cmd(quit_cmd),
	.cpu_start_adr(cpu_start_adr),
	.pc_data(pc_data),
	.cmd_ld_ma(cmd_ld_ma),
	.cmd_st_ma(cmd_st_ma),
	.rd_data_ma(rd_data_ma),
	.csr_mtie(csr_mtie),
	.frc_cntr_val_leq(frc_cntr_val_leq),
	.cpu_run_state(cpu_run_state),
	.csr_meie(csr_meie),
	.csr_rmie(csr_rmie),
	.g_interrupt_1shot(g_interrupt_1shot),
	.g_interrupt(g_interrupt),
	.i_read_req(i_read_req),
	.i_read_w(i_read_w),
	.i_read_hw(i_read_hw),
	.i_read_adr(i_read_adr),
	.d_read_req(d_read_req),
	.d_read_w(d_read_w),
	.d_read_hw(d_read_hw),
	.read_valid(read_valid),
	.d_read_adr(d_read_adr),
	.read_data(read_data),
	.d_write_req(d_write_req),
	.d_write_w(d_write_w),
	.d_write_hw(d_write_hw),
	.write_finish(write_finish),
	.d_write_adr(d_write_adr),
	.d_write_data(d_write_data),
	.dma_io_we(dma_io_we_c),
	.dma_io_wadr(dma_io_wadr_c),
	.dma_io_wdata(dma_io_wdata_c),
	.dma_io_radr(dma_io_radr_c),
	.dma_io_radr_en(dma_io_radr_en_c),
	.dma_io_rdata(dma_io_rdata),
	.csr_radr_en_mon(csr_radr_en_mon),
	.csr_radr_mon(csr_radr_mon),
	.csr_wadr_mon(csr_wadr_mon),
	.csr_we_mon(csr_we_mon),
	.csr_wdata_mon(csr_wdata_mon),
	.csr_rdata_mon(csr_rdata_mon),
	.rf_radr_en_mon(rf_radr_en_mon),
	.rf_radr_mon(rf_radr_mon),
	.rf_wadr_mon(rf_wadr_mon),
	.rf_we_mon(rf_we_mon),
	.rf_wdata_mon(rf_wdata_mon),
	.rf_rdata_mon(rf_rdata_mon)
	);

bus_gather bus_gather (
	.clk(clk),
	.rst_n(rst_n),
	.i_read_req(i_read_req),
	.i_read_w(i_read_w),
	.i_read_hw(i_read_hw),
	.i_read_adr(i_read_adr),
	.d_read_req(d_read_req),
	.d_read_w(d_read_w),
	.d_read_hw(d_read_hw),
	.d_read_adr(d_read_adr),
	.d_write_req(d_write_req),
	.d_write_w(d_write_w),
	.d_write_hw(d_write_hw),
	.d_write_adr(d_write_adr),
	.d_write_data(d_write_data),
	.u_read_req(u_read_req),
	.u_read_w(u_read_w),
	.u_read_adr(u_read_adr),
	.u_write_req(u_write_req),
	.u_write_w(u_write_w),
	.u_write_adr(u_write_adr),
	.u_write_data(u_write_data),
	.read_req(read_req),
	.read_w(read_w),
	.read_hw(read_hw),
	.read_adr(read_adr),
	.write_req(write_req),
	.write_w(write_w),
	.write_hw(write_hw),
	.write_adr(write_adr),
	.write_data(write_data)
	);

uart_top uart_top (
	.clk(clk),
	.rst_n(rst_n),
	.rx(rx),
	.tx(tx),
	.u_read_req(u_read_req),
	.u_read_w(u_read_w),
	.read_valid(read_valid),
	.u_read_adr(u_read_adr),
	.read_data(read_data),
	.u_write_req(u_write_req),
	.u_write_w(u_write_w),
	.write_finish(write_finish),
	.u_write_adr(u_write_adr),
	.u_write_data(u_write_data),
	.dma_io_we(dma_io_we_u),
	.dma_io_wadr(dma_io_wadr_u),
	.dma_io_wdata(dma_io_wdata_u),
	.dma_io_radr(dma_io_radr_u),
	.dma_io_radr_en(dma_io_radr_en_u),
	.dma_io_rdata_in(dma_io_rdata),
	.csr_radr_en_mon(csr_radr_en_mon),
	.csr_radr_mon(csr_radr_mon),
	.csr_wadr_mon(csr_wadr_mon),
	.csr_we_mon(csr_we_mon),
	.csr_wdata_mon(csr_wdata_mon),
	.csr_rdata_mon(csr_rdata_mon),
	.rf_radr_en_mon(rf_radr_en_mon),
	.rf_radr_mon(rf_radr_mon),
	.rf_wadr_mon(rf_wadr_mon),
	.rf_we_mon(rf_we_mon),
	.rf_wdata_mon(rf_wdata_mon),
	.rf_rdata_mon(rf_rdata_mon),
	.pc_data(pc_data),
	.cmd_ld_ma(cmd_ld_ma),
	.cmd_st_ma(cmd_st_ma),
	.rd_data_ma(rd_data_ma),
	.dbg_bpoint(dbg_bpoint),
	.cpu_start(cpu_start),
	.cpu_run_state(cpu_run_state),
	.quit_cmd(quit_cmd),
	.start_adr(cpu_start_adr),
	.uart_io_char(uart_io_char),
	.uart_io_we(uart_io_we),
	.uart_io_full(uart_io_full),
	.uart_term(uart_term),
	.rout_en(rout_en),
	.rout(rout),
	.rx_disable_echoback(rx_disable_echoback)
	);

qspi_if qspi_if (
	.clk(clk),
	.rst_n(rst_n),
	.sck(sck),
	.ce_n(ce_n),
`ifdef FPGA_MODE
	.sio(sio),
`else // FPGA_MODE
	.sio_i(sio_i),
	.sio_o(sio_o),
	.sio_en(sio_en),
`endif // FPGA_MODE
	.dbg_bpoint_en(dbg_bpoint_en),
	.init_latency(init_latency),
	.init_qspicmd(init_qspicmd),
	.read_req(read_req),
	.read_w(read_w),
	.read_hw(read_hw),
	.read_valid(read_valid),
	.read_adr(read_adr),
	.read_data(read_data),
	.write_req(write_req),
	.write_w(write_w),
	.write_hw(write_hw),
	.write_finish(write_finish),
	.write_adr(write_adr),
	.write_data(write_data),
	.sc_req(sc_req),
	.sc_wr(sc_wr),
	.sc_last(sc_last),
	.sc_adr(sc_adr),
	.sc_wdata(sc_wdata),
	.sc_ack(sc_ack),
	.sc_mrdata(sc_mrdata),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_4),
	.dma_io_rdata(dma_io_rdata_in_5)
	);

// mclk domain reset : asynchronous assert, deassert synchronized to mclk
reg mrst_n_m1;
reg mrst_n;

always @ (posedge mclk or negedge rst_n) begin
	if (~rst_n) begin
		mrst_n_m1 <= 1'b0;
		mrst_n <= 1'b0;
	end
	else begin
		mrst_n_m1 <= 1'b1;
		mrst_n <= mrst_n_m1;
	end
end

scratch_mif scratch_mif (
	.mclk(mclk),
	.mrst_n(mrst_n),
	.sc_req(sc_req),
	.sc_wr(sc_wr),
	.sc_last(sc_last),
	.sc_adr(sc_adr),
	.sc_wdata(sc_wdata),
	.sc_ack(sc_ack),
	.sc_rdata(sc_mrdata),
	.sc_ram_adr(sc_ram_adr),
	.sc_ram_wdata(sc_ram_wdata),
	.sc_ram_wen(sc_ram_wen),
	.sc_ram_rdata(sc_ram_rdata)
	);

`ifdef FPGA_MODE
scratch_1r1w scratch_1r1w_0 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[9:0]),
	.ram_rdata(sc_ram_rdata[7:0]),
	.ram_wadr(sc_ram_adr[9:0]),
	.ram_wdata(sc_ram_wdata[7:0]),
	.ram_wen(sc_ram_wen[0])
	);

scratch_1r1w scratch_1r1w_1 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[19:10]),
	.ram_rdata(sc_ram_rdata[15:8]),
	.ram_wadr(sc_ram_adr[19:10]),
	.ram_wdata(sc_ram_wdata[15:8]),
	.ram_wen(sc_ram_wen[1])
	);

scratch_1r1w scratch_1r1w_2 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[29:20]),
	.ram_rdata(sc_ram_rdata[23:16]),
	.ram_wadr(sc_ram_adr[29:20]),
	.ram_wdata(sc_ram_wdata[23:16]),
	.ram_wen(sc_ram_wen[2])
	);

scratch_1r1w scratch_1r1w_3 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[39:30]),
	.ram_rdata(sc_ram_rdata[31:24]),
	.ram_wadr(sc_ram_adr[39:30]),
	.ram_wdata(sc_ram_wdata[31:24]),
	.ram_wen(sc_ram_wen[3])
	);

scratch_1r1w scratch_1r1w_4 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[9:0]),
	.ram_rdata(sc_ram_rdata[39:32]),
	.ram_wadr(sc_ram_adr[9:0]),
	.ram_wdata(sc_ram_wdata[7:0]),
	.ram_wen(sc_ram_wen[4])
	);

scratch_1r1w scratch_1r1w_5 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[19:10]),
	.ram_rdata(sc_ram_rdata[47:40]),
	.ram_wadr(sc_ram_adr[19:10]),
	.ram_wdata(sc_ram_wdata[15:8]),
	.ram_wen(sc_ram_wen[5])
	);

scratch_1r1w scratch_1r1w_6 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[29:20]),
	.ram_rdata(sc_ram_rdata[55:48]),
	.ram_wadr(sc_ram_adr[29:20]),
	.ram_wdata(sc_ram_wdata[23:16]),
	.ram_wen(sc_ram_wen[6])
	);

scratch_1r1w scratch_1r1w_7 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[39:30]),
	.ram_rdata(sc_ram_rdata[63:56]),
	.ram_wadr(sc_ram_adr[39:30]),
	.ram_wdata(sc_ram_wdata[31:24]),
	.ram_wen(sc_ram_wen[7])
	);

scratch_1r1w scratch_1r1w_8 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[9:0]),
	.ram_rdata(sc_ram_rdata[71:64]),
	.ram_wadr(sc_ram_adr[9:0]),
	.ram_wdata(sc_ram_wdata[7:0]),
	.ram_wen(sc_ram_wen[8])
	);

scratch_1r1w scratch_1r1w_9 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[19:10]),
	.ram_rdata(sc_ram_rdata[79:72]),
	.ram_wadr(sc_ram_adr[19:10]),
	.ram_wdata(sc_ram_wdata[15:8]),
	.ram_wen(sc_ram_wen[9])
	);

scratch_1r1w scratch_1r1w_10 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[29:20]),
	.ram_rdata(sc_ram_rdata[87:80]),
	.ram_wadr(sc_ram_adr[29:20]),
	.ram_wdata(sc_ram_wdata[23:16]),
	.ram_wen(sc_ram_wen[10])
	);

scratch_1r1w scratch_1r1w_11 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[39:30]),
	.ram_rdata(sc_ram_rdata[95:88]),
	.ram_wadr(sc_ram_adr[39:30]),
	.ram_wdata(sc_ram_wdata[31:24]),
	.ram_wen(sc_ram_wen[11])
	);
`endif // FPGA_MODE

// scratch2 : bank 12-15 = lane 0-3 of group 3 (16x8 each, 64B in total)
scratch2_1r1w scratch2_1r1w_0 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[3:0]),
	.ram_rdata(sc_ram_rdata[103:96]),
	.ram_wadr(sc_ram_adr[3:0]),
	.ram_wdata(sc_ram_wdata[7:0]),
	.ram_wen(sc_ram_wen[12])
	);

scratch2_1r1w scratch2_1r1w_1 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[13:10]),
	.ram_rdata(sc_ram_rdata[111:104]),
	.ram_wadr(sc_ram_adr[13:10]),
	.ram_wdata(sc_ram_wdata[15:8]),
	.ram_wen(sc_ram_wen[13])
	);

scratch2_1r1w scratch2_1r1w_2 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[23:20]),
	.ram_rdata(sc_ram_rdata[119:112]),
	.ram_wadr(sc_ram_adr[23:20]),
	.ram_wdata(sc_ram_wdata[23:16]),
	.ram_wen(sc_ram_wen[14])
	);

scratch2_1r1w scratch2_1r1w_3 (
	.clk(mclk),
	.ram_radr(sc_ram_adr[33:30]),
	.ram_rdata(sc_ram_rdata[127:120]),
	.ram_wadr(sc_ram_adr[33:30]),
	.ram_wdata(sc_ram_wdata[31:24]),
	.ram_wen(sc_ram_wen[15])
	);

io_led io_led (
	.clk(clk),
	.rst_n(rst_n),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_2),
	.dma_io_rdata(dma_io_rdata_in_3),
	.rgb_led(rgb_led_org),
	.dbg_bpoint_en(dbg_bpoint_en),
	.dbg_bpoint(dbg_bpoint),
	.cpu_start(cpu_start),
	.init_uart(init_uart),
	.init_latency(init_latency),
	.init_cpu_start(init_cpu_start),
	.gpi_in(init_qspicmd),
`ifdef FPGA_MODE
	.gpio(gpio)
`else // FPGA_MODE
	.gpio_i(gpio_i),
	.gpio_o(gpio_o),
	.gpio_en(gpio_en)
`endif // FPGA_MODE
	);

io_uart_out io_uart_out (
	.clk(clk),
	.rst_n(rst_n),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in),
	.dma_io_rdata(dma_io_rdata_in_2),
	.uart_io_char(uart_io_char),
	.uart_io_we(uart_io_we),
	.uart_io_full(uart_io_full),
	.init_uart(init_uart),
	.uart_term(uart_term),
	.cpu_run_state(cpu_run_state),
	.rout_en(rout_en),
	.rout(rout),
	.ext_uart_interrpt_1shot(ext_uart_interrpt_1shot),
	.rx_disable_echoback(rx_disable_echoback)
	);


io_frc io_frc (
	.clk(clk),
	.rst_n(rst_n),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_3),
	.dma_io_rdata(dma_io_rdata_in_4),
	.csr_mtie(csr_mtie),
	.frc_cntr_val_leq(frc_cntr_val_leq)
	);

interrupter interrupter (
	.clk(clk),
	.rst_n(rst_n),
	.interrupt_0(interrupt_0),
	.ext_uart_interrpt_1shot(ext_uart_interrpt_1shot),
        .ext_uart2_interrpt_1shot(ext_uart2_interrpt_1shot),
	.csr_rmie(csr_rmie),
	.csr_meie(csr_meie),
	.g_interrupt_1shot(g_interrupt_1shot),
	.g_interrupt(g_interrupt),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_5),
	.dma_io_rdata(dma_io_rdata_in_6)
	);

io_spi_lite io_spi_lite(
	.clk(clk),
	.rst_n(rst_n),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_6),
	.dma_io_rdata(dma_io_rdata_in_7),
	.spi_select_io(spi_select_io),
	.spi_sck(spi_sck),
	.spi_csn(spi_csn),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso)
	);

io_uart2 io_uart2 (
        .clk(clk),
        .rst_n(rst_n),
        .rx2(rx2),
        .tx2(tx2),
        .dma_io_we(dma_io_we),
        .dma_io_wadr(dma_io_wadr),
        .dma_io_wdata(dma_io_wdata),
        .dma_io_radr(dma_io_radr),
        .dma_io_radr_en(dma_io_radr_en),
        .dma_io_rdata_in(dma_io_rdata_in_7),
        .dma_io_rdata(dma_io_rdata),
        .ext_uart2_interrpt_1shot(ext_uart2_interrpt_1shot),
        .uart2_io_en(uart2_io_en)
        );


endmodule
