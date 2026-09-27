/*
 * My RISC-V RV32I CPU
 *   FPGA uart input/output Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2025 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module io_nanodec(
    input clk,
    input rst_n,
    output [128:0] nanodec,

	// from/to IO bus
    input dma_io_we,
    input [15:2] dma_io_wadr,
    input [31:0] dma_io_wdata,
    input [15:2] dma_io_radr,
    input dma_io_radr_en,
    input [31:0] dma_io_rdata_in,
    output [31:0] dma_io_rdata

	);

`define SYS_NANOD_REG 14'h3800

wire we_nanodec_char = dma_io_we      & (dma_io_wadr == `SYS_NANOD_REG);
wire re_nanodec_char = dma_io_radr_en & (dma_io_radr == `SYS_NANOD_REG);

// write part
reg [7:0] nanodec_reg;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        nanodec_reg <= 8'd0 ;
    else if ( we_nanodec_char )
        nanodec_reg <= dma_io_wdata[7:0];
end


// read part

reg re_nanodec_rdflg_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        re_nanodec_rdflg_dly <= 1'b0 ;
    else
        re_nanodec_rdflg_dly <= re_nanodec_char;
end

assign dma_io_rdata = re_nanodec_rdflg_dly ? { 24'd0, nanodec_reg } : dma_io_rdata_in;

// nano decoder

// global enable signal
assign nanodec[128] = nanodec_reg[7];

// upper 4 bits decoder
wire [15:0] nanodec_upper;

assign nanodec_upper[0] = (nanodec_reg[6:3] == 4'd0);
assign nanodec_upper[1] = (nanodec_reg[6:3] == 4'd1);
assign nanodec_upper[2] = (nanodec_reg[6:3] == 4'd2);
assign nanodec_upper[3] = (nanodec_reg[6:3] == 4'd3);
assign nanodec_upper[4] = (nanodec_reg[6:3] == 4'd4);
assign nanodec_upper[5] = (nanodec_reg[6:3] == 4'd5);
assign nanodec_upper[6] = (nanodec_reg[6:3] == 4'd6);
assign nanodec_upper[7] = (nanodec_reg[6:3] == 4'd7);
assign nanodec_upper[8] = (nanodec_reg[6:3] == 4'd8);
assign nanodec_upper[9] = (nanodec_reg[6:3] == 4'd9);
assign nanodec_upper[10] = (nanodec_reg[6:3] == 4'd10);
assign nanodec_upper[11] = (nanodec_reg[6:3] == 4'd11);
assign nanodec_upper[12] = (nanodec_reg[6:3] == 4'd12);
assign nanodec_upper[13] = (nanodec_reg[6:3] == 4'd13);
assign nanodec_upper[14] = (nanodec_reg[6:3] == 4'd14);
assign nanodec_upper[15] = (nanodec_reg[6:3] == 4'd15);


function [7:0] nanolowdec;
input nanodec_sel;
input [2:0] nanodec_lower;
begin
	if (nanodec_sel) begin
		case(nanodec_lower)
			3'd0: nanolowdec = 8'b0000_0001;
			3'd1: nanolowdec = 8'b0000_0010;
			3'd2: nanolowdec = 8'b0000_0100;
			3'd3: nanolowdec = 8'b0000_1000;
			3'd4: nanolowdec = 8'b0001_0000;
			3'd5: nanolowdec = 8'b0010_0000;
			3'd6: nanolowdec = 8'b0100_0000;
			3'd7: nanolowdec = 8'b1000_0000;
			default : nanolowdec = 8'b0000_0001;
		endcase
	end
	else begin
		nanolowdec = 8'b0000_0000;
	end
end
endfunction

assign nanodec[7:0] = nanolowdec(  nanodec_upper[0], nanodec_reg[2:0] );
assign nanodec[15:8] = nanolowdec(  nanodec_upper[1], nanodec_reg[2:0] );
assign nanodec[23:16] = nanolowdec(  nanodec_upper[2], nanodec_reg[2:0] );
assign nanodec[31:24] = nanolowdec(  nanodec_upper[3], nanodec_reg[2:0] );
assign nanodec[39:32] = nanolowdec(  nanodec_upper[4], nanodec_reg[2:0] );
assign nanodec[47:40] = nanolowdec(  nanodec_upper[5], nanodec_reg[2:0] );
assign nanodec[55:48] = nanolowdec(  nanodec_upper[6], nanodec_reg[2:0] );
assign nanodec[63:56] = nanolowdec(  nanodec_upper[7], nanodec_reg[2:0] );
assign nanodec[71:64] = nanolowdec(  nanodec_upper[8], nanodec_reg[2:0] );
assign nanodec[79:72] = nanolowdec(  nanodec_upper[9], nanodec_reg[2:0] );
assign nanodec[87:80] = nanolowdec(  nanodec_upper[10], nanodec_reg[2:0] );
assign nanodec[95:88] = nanolowdec(  nanodec_upper[11], nanodec_reg[2:0] );
assign nanodec[103:96] = nanolowdec(  nanodec_upper[12], nanodec_reg[2:0] );
assign nanodec[111:104] = nanolowdec(  nanodec_upper[13], nanodec_reg[2:0] );
assign nanodec[119:112] = nanolowdec(  nanodec_upper[14], nanodec_reg[2:0] );
assign nanodec[127:120] = nanolowdec(  nanodec_upper[15], nanodec_reg[2:0] );


endmodule
