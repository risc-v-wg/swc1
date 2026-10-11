/*
 * My RISC-V RV32I CPU
 *   scratch RAM interface (mclk domain side)
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module scratch_mif (
	input mclk,
	input mrst_n,      // already synchronized to mclk (async assert / sync deassert)

	// request bundle from qspi_if (clk domain). sc_req is a toggle; the bundle
	// is held stable by qspi_if from the toggle until sc_ack comes back.
	input sc_req,
	input sc_wr,
	input [1:0] sc_last,  // number of bytes - 1
	input [13:0] sc_adr,
	input [31:0] sc_wdata,

	// answer to qspi_if (clk domain). sc_ack is a toggle; sc_rdata is held
	// stable from the toggle until the next request.
	output reg sc_ack,
	output reg [31:0] sc_rdata,

	// 16 byte wide banks interleaved by byte lane : bank b = group * 4 + lane
	output [39:0] sc_ram_adr,     // lane l : [l*10 +: 10]
	output [31:0] sc_ram_wdata,   // lane l : [l*8 +: 8]
	output [15:0] sc_ram_wen,     // bank b
	input [127:0] sc_ram_rdata    // bank b : [b*8 +: 8]
	);

// request toggle synchronizer (2FF) + edge detect
reg sc_req_m1;
reg sc_req_m2;
reg sc_req_m3;

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n) begin
		sc_req_m1 <= 1'b0;
		sc_req_m2 <= 1'b0;
		sc_req_m3 <= 1'b0;
	end
	else begin
		sc_req_m1 <= sc_req;
		sc_req_m2 <= sc_req_m1;
		sc_req_m3 <= sc_req_m2;
	end
end

// RAM cycle sequencer (same timing as the old single clock version)
//   write : start -> 1 write cycle -> ack
//   read  : start -> address issue -> data capture -> ack
reg m_busy;
reg m_wr;
reg [1:0] m_last;
reg [1:0] m_step;
reg [13:0] m_adr;
reg [31:0] m_wdata;

wire m_start = (sc_req_m2 ^ sc_req_m3) & ~m_busy;
wire m_wr_last = m_busy & m_wr;
wire m_rd_done = m_busy & ~m_wr & (m_step == 2'd2);
wire m_rd_cap = m_busy & ~m_wr & (m_step == 2'd1);

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n) begin
		m_busy <= 1'b0;
		m_wr <= 1'b0;
		m_last <= 2'd0;
		m_step <= 2'd0;
		m_adr <= 14'd0;
		m_wdata <= 32'd0;
	end
	else if (m_start) begin
		m_busy <= 1'b1;
		m_wr <= sc_wr;
		m_last <= sc_last;
		m_step <= 2'd0;
		m_adr <= sc_adr;
		m_wdata <= sc_wdata;
	end
	else if (m_wr_last | m_rd_done) begin
		m_busy <= 1'b0;
		m_step <= 2'd0;
	end
	else if (m_busy) begin
		m_step <= m_step + 2'd1;
	end
end

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		sc_ack <= 1'b0;
	else if (m_wr_last | m_rd_done)
		sc_ack <= ~sc_ack;
end

// per lane address / data / enable
//   lane l holds byte k = (l - adr[1:0]) & 3 of the access, at word address + (l < adr[1:0])
wire [1:0] m_ofs = m_adr[1:0];
wire [11:0] m_word = m_adr[13:2];
wire [11:0] m_word_p1 = m_word + 12'd1;

wire [31:0] m_lane_rdata;

genvar l;
generate
for (l = 0; l < 4; l = l + 1) begin : sc_lane
	localparam [1:0] LANE = l;
	wire [1:0] k = LANE - m_ofs;
	wire [11:0] word = (LANE < m_ofs) ? m_word_p1 : m_word;
	wire en = (k <= m_last);
	wire [1:0] grp = word[11:10];

	assign sc_ram_adr[l*10 +: 10] = word[9:0];
	assign sc_ram_wdata[l*8 +: 8] = m_wdata[{ k, 3'd0 } +: 8];
	assign sc_ram_wen[0*4 + l] = m_wr_last & en & (grp == 2'd0);
	assign sc_ram_wen[1*4 + l] = m_wr_last & en & (grp == 2'd1);
	assign sc_ram_wen[2*4 + l] = m_wr_last & en & (grp == 2'd2);
	assign sc_ram_wen[3*4 + l] = m_wr_last & en & (grp == 2'd3);

	reg [1:0] grp_dly;

	always @ (posedge mclk or negedge mrst_n) begin
		if (~mrst_n)
			grp_dly <= 2'd0;
		else
			grp_dly <= grp;
	end

	assign m_lane_rdata[l*8 +: 8] = sc_ram_rdata[{ grp_dly, LANE, 3'd0 } +: 8];
end
endgenerate

// lane order -> byte order (rotate right by the start lane), then clear the unused bytes
wire [63:0] m_lane_rdata2 = { m_lane_rdata, m_lane_rdata };
wire [31:0] m_rdata_rot = m_lane_rdata2[{ 1'b0, m_ofs, 3'd0 } +: 32];
wire [31:0] m_rdata_mask = (m_last == 2'd3) ? 32'hffffffff :
                           (m_last == 2'd1) ? 32'h0000ffff : 32'h000000ff;

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		sc_rdata <= 32'd0;
	else if (m_rd_cap)
		sc_rdata <= m_rdata_rot & m_rdata_mask;
end

endmodule
