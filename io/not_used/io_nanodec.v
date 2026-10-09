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

	input inv_en,
	input out_en,
	input hi_sel,
	input [3:0] select,
	output [3:0] mon_out,
	output mon_out_en,
	
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
reg val_en_1shot;
reg hi_sel_smpl;
reg [3:0] select_smpl;

reg [7:0] nanodec_reg;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        nanodec_reg <= 8'd0 ;
    else if ( val_en_1shot & ~hi_sel_smpl )
        nanodec_reg <= { nanodec_reg[7:4], select_smpl };
    else if ( val_en_1shot &  hi_sel_smpl )
        nanodec_reg <= { select_smpl, nanodec_reg[3:0] };
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

// signal enable
reg out_en_smpl;
reg inv_en_level1;

//wire nanodec_en = out_en_smpl & inv_en_level1;
wire nanodec_en = out_en_smpl;

// global enable signal
assign nanodec[128] = nanodec_reg[7] & nanodec_en;

// upper 4 bits decoder
wire [15:0] nanodec_upper;

assign nanodec_upper[0] = (nanodec_reg[6:3] == 4'd0) & nanodec_en;
assign nanodec_upper[1] = (nanodec_reg[6:3] == 4'd1) & nanodec_en;
assign nanodec_upper[2] = (nanodec_reg[6:3] == 4'd2) & nanodec_en;
assign nanodec_upper[3] = (nanodec_reg[6:3] == 4'd3) & nanodec_en;
assign nanodec_upper[4] = (nanodec_reg[6:3] == 4'd4) & nanodec_en;
assign nanodec_upper[5] = (nanodec_reg[6:3] == 4'd5) & nanodec_en;
assign nanodec_upper[6] = (nanodec_reg[6:3] == 4'd6) & nanodec_en;
assign nanodec_upper[7] = (nanodec_reg[6:3] == 4'd7) & nanodec_en;
assign nanodec_upper[8] = (nanodec_reg[6:3] == 4'd8) & nanodec_en;
assign nanodec_upper[9] = (nanodec_reg[6:3] == 4'd9) & nanodec_en;
assign nanodec_upper[10] = (nanodec_reg[6:3] == 4'd10) & nanodec_en;
assign nanodec_upper[11] = (nanodec_reg[6:3] == 4'd11) & nanodec_en;
assign nanodec_upper[12] = (nanodec_reg[6:3] == 4'd12) & nanodec_en;
assign nanodec_upper[13] = (nanodec_reg[6:3] == 4'd13) & nanodec_en;
assign nanodec_upper[14] = (nanodec_reg[6:3] == 4'd14) & nanodec_en;
assign nanodec_upper[15] = (nanodec_reg[6:3] == 4'd15) & nanodec_en;


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

// inverter input
// synchronizser
reg inv_en_lat1;
reg inv_en_lat2;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        inv_en_lat1 <= 1'b0;
        inv_en_lat2 <= 1'b0;
    end
    else begin
        inv_en_lat1 <= inv_en;
        inv_en_lat2 <= inv_en_lat1;
    end
end

// chataring
// free cntr for sampler
// 20.97ms @ 50MHz
reg [19:0] ccntr;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ccntr <= 20'd0;
    else
        ccntr <= ccntr + 20'd1;
end

// chat sampler
reg inv_en_level2;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        out_en_smpl <= 1'b0;
        hi_sel_smpl <= 1'b0;
        inv_en_level1 <= 1'b0;
	end
    else if (ccntr == 20'd0) begin
        out_en_smpl <= out_en;
        hi_sel_smpl <= hi_sel;
        inv_en_level1 <= inv_en_lat2;
	end
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        inv_en_level2 <= 1'b0;
    else
        inv_en_level2 <= inv_en_level1;
end

wire inv_en_1shot = inv_en_level1 & ~inv_en_level2;


always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        val_en_1shot <= 1'b0;
    else
        val_en_1shot <= inv_en_1shot;
end

// signal sampler
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        select_smpl <= 4'd0;
    end
    else if (inv_en_1shot) begin
        select_smpl <= select;
    end
end

// output
assign mon_out = hi_sel_smpl ? nanodec_reg[7:4] : nanodec_reg[3:0];

assign mon_out_en = out_en_smpl;


endmodule
