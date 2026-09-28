//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_ramdac.sv - MS176 / IMSG176 colour palette (6 bits per gun)
//
//  Four CPU registers: 0 write address, 1 colour data (red, green, blue in
//  turn, then the address advances), 2 pixel read mask, 3 read address.
//  The mask is ANDed with the pixel value before the table lookup.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_ramdac
(
	input             clk,
	input             reset,

	input             reg_we,         // pulse
	input             reg_re,         // pulse: read with side effects
	input       [1:0] reg_idx,
	input       [7:0] reg_wdata,
	output reg  [7:0] reg_rdata,      // read value for reg_idx, before reg_re's side effects

	input             pix_ce,
	input       [7:0] pix_in,         // pixel value, sampled on pix_ce
	output     [17:0] pix_rgb         // {r6, g6, b6}, one pix_ce after pix_in
);

reg  [7:0] waddr, raddr, pmask;
reg  [1:0] widx, ridx;
reg  [5:0] wbuf_r, wbuf_g;
reg [17:0] rbuf;

// Port A: CPU writes, and reads the entry at raddr for read-back.
wire        a_we   = reg_we && (reg_idx == 2'd1) && (widx == 2'd2);
wire  [7:0] a_addr = a_we ? waddr : raddr;
wire [17:0] a_dout;

reg   [7:0] b_addr;

it8_dpram #(.AW(8), .DW(18)) pal
(
	.clk    (clk),
	.a_addr (a_addr),
	.a_din  ({wbuf_r, wbuf_g, reg_wdata[5:0]}),
	.a_we   (a_we),
	.a_dout (a_dout),
	.b_addr (b_addr),
	.b_din  (18'd0),
	.b_we   (1'b0),
	.b_dout (pix_rgb)
);

always @(posedge clk) begin
	if (pix_ce) b_addr <= pix_in & pmask;
end

// Read value, combinational, so the bus captures it in the same clock as
// reg_re and sees the state before the read advances it.
always @(*) begin
	case (reg_idx)
		2'd0: reg_rdata = waddr;
		2'd1: reg_rdata = (ridx == 2'd0) ? {2'b00, a_dout[17:12]} :
		                  (ridx == 2'd1) ? {2'b00, rbuf[11:6]}    :
		                                   {2'b00, rbuf[5:0]};
		2'd2: reg_rdata = pmask;
		default: reg_rdata = raddr;
	endcase
end

always @(posedge clk) begin
	if (reset) begin
		waddr <= 8'd0;
		raddr <= 8'd0;
		pmask <= 8'hFF;
		widx  <= 2'd0;
		ridx  <= 2'd0;
	end
	else begin
		if (reg_we) begin
			case (reg_idx)
				2'd0: begin
					waddr <= reg_wdata;
					widx  <= 2'd0;
				end
				2'd1: begin
					case (widx)
						2'd0: wbuf_r <= reg_wdata[5:0];
						2'd1: wbuf_g <= reg_wdata[5:0];
						default: waddr <= waddr + 8'd1;
					endcase
					widx <= (widx == 2'd2) ? 2'd0 : widx + 2'd1;
				end
				2'd2: pmask <= reg_wdata;
				2'd3: begin
					raddr <= reg_wdata;
					ridx  <= 2'd0;
				end
			endcase
		end

		// Data reads: the first of a triplet latches the whole entry, the
		// third advances the read address.
		if (reg_re && reg_idx == 2'd1) begin
			if (ridx == 2'd0) rbuf <= a_dout;
			if (ridx == 2'd2) raddr <= raddr + 8'd1;
			ridx <= (ridx == 2'd2) ? 2'd0 : ridx + 2'd1;
		end
	end
end

endmodule
