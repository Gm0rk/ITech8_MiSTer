//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_flip180.sv - the picture turned 180 degrees through a DDRAM frame buffer
//
//  None of these boards can turn its own picture, and the games redraw
//  moving objects while the screen is being scanned from the top down. A
//  display that read the VRAM from the bottom up would cross those objects
//  half redrawn (D-031). So the board's own picture is stored a frame at a
//  time, alternately in two DDRAM buffers, and each frame is shown as the
//  previous one turned 180 degrees: active line m shows stored line H-1-m,
//  read from its end. The output keeps the input's timing; only the colour
//  of the active pixels changes. The picture is one frame late.
//
//  Each active line is collected in a line buffer and written to DDRAM
//  during the next line. Each output line is read from DDRAM into a second
//  line buffer two lines ahead (lines 0 and 1 at vertical sync). A DDRAM
//  word holds two pixels of 24 bits, the even one in the low half. The
//  buffers start at byte address 0x30000000, where MiSTer cores usually keep
//  their own data (screen_rotate's are at 0x24000000-0x257FFFFF), 512 KB
//  each: line l, word w of buffer b is word b*65536 + l*256 + w. At most 256
//  lines of 512 pixels.
//
//  The output turns over at the second vertical sync after enable, when a
//  whole frame has been stored. When enable falls, a DDRAM transfer under
//  way is finished and nothing more is started; idle then says the port
//  can be handed back. Reset clears the waiting jobs but never cuts a
//  transfer short.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_flip180
(
	input             clk,
	input             reset,
	input             enable,         // the DDRAM port is ours: store and flip
	output reg        flipping,       // rgb_out is the turned picture
	output            idle,           // no DDRAM transfer under way

	// Picture in, stable while ce is high; picture out on the same timing
	input             ce,
	input      [23:0] rgb_in,
	input             hb_in,
	input             vb_in,
	input             vs_in,
	output     [23:0] rgb_out,

	// DDRAM (Avalon: a request is taken on a clock with busy low)
	input             ddr_busy,
	output reg  [7:0] ddr_burstcnt,
	output reg [28:0] ddr_addr,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,
	output reg        ddr_rd,
	output reg [63:0] ddr_din,
	output      [7:0] ddr_be,
	output reg        ddr_we,

	output reg [15:0] dbg_late        // line transfers not finished in time
);

localparam [28:0] BASE  = 29'h06000000;   // byte address 0x30000000 in 8-byte words
localparam  [8:0] BURST = 9'd64;

assign ddr_be = 8'hFF;

// ---------------------------------------------------------------------------
// Line buffers: 2 x 256 entries of two pixels, entry {half, word}

wire  [8:0] wlb_waddr, wlb_raddr, rlb_waddr, rlb_raddr;
wire [47:0] wlb_wdata, wlb_q, rlb_wdata, rlb_q;
wire        wlb_we, rlb_we;

it8_sdpram #(.AW(9), .DW(48)) wlb
(
	.clk     (clk),
	.rd_addr (wlb_raddr),
	.rd_data (wlb_q),
	.wr_addr (wlb_waddr),
	.wr_data (wlb_wdata),
	.wr_en   (wlb_we)
);

it8_sdpram #(.AW(9), .DW(48)) rlb
(
	.clk     (clk),
	.rd_addr (rlb_raddr),
	.rd_data (rlb_q),
	.wr_addr (rlb_waddr),
	.wr_data (rlb_wdata),
	.wr_en   (rlb_we)
);

// ---------------------------------------------------------------------------
// Raster: active pixels and lines, measured as they come

wire        act = !hb_in && !vb_in;
reg         act_d, vs_d;
reg   [8:0] xcnt;              // active pixels so far in this line
reg   [8:0] width;             // active pixels per line
reg   [7:0] line;              // active lines so far in this frame
reg   [8:0] height;            // active lines in the stored frame
reg         wbuf;              // buffer this frame is written to
reg   [1:0] armed;             // whole frames stored since enable (0-2)
reg  [23:0] even_px;

wire        line_end = ce && act_d && !act;
wire        frame    = ce && vs_in && !vs_d;

// Capture: pixel pairs into the write line buffer, half line[0].
wire        odd_tail = line_end && xcnt[0];
assign wlb_we    = ce && ((act && xcnt[0]) || odd_tail);
assign wlb_waddr = {line[0], xcnt[8:1]};
assign wlb_wdata = odd_tail ? {24'd0, even_px} : {rgb_in, even_px};

// Output: pixel width-1-x of the line prefetched into half line[0].
wire  [8:0] src_x = width - 9'd1 - xcnt;
assign rlb_raddr = {line[0], src_x[8:1]};
assign rgb_out   = (flipping && act) ? (src_x[0] ? rlb_q[47:24] : rlb_q[23:0]) : rgb_in;

// ---------------------------------------------------------------------------
// Jobs for the DDRAM engine

reg         fl_req;            // write a captured line
reg         fl_buf, fl_half;
reg   [7:0] fl_line;
reg   [8:0] fl_n;              // words
reg   [1:0] pf_req;            // read a line into half h
reg   [1:0] pf_ready;          // half h holds its line
reg         pf_buf[0:1];
reg   [7:0] pf_src[0:1];
reg   [8:0] pf_n[0:1];

localparam [2:0] E_IDLE = 3'd0, E_WADDR = 3'd1, E_WDATA = 3'd2, E_WREQ = 3'd3, E_RREQ = 3'd4, E_RDATA = 3'd5;

reg   [2:0] st;
reg         eng_buf, eng_half;
reg   [7:0] eng_line;
reg   [8:0] eng_w, eng_n, iss_w;
reg   [7:0] rd_left;

assign idle = (st == E_IDLE);

// The engine is not reset: a request the port has not taken yet, or a read
// burst under way, is always finished, as the port requires. Reset only
// clears the jobs, so it goes idle after that.
initial begin
	st     = E_IDLE;
	ddr_rd = 1'b0;
	ddr_we = 1'b0;
end

wire  [8:0] lim       = eng_n - iss_w;
wire  [7:0] burst_len = (lim > BURST) ? BURST[7:0] : lim[7:0];

assign wlb_raddr = {eng_half, eng_w[7:0]};
assign rlb_we    = (st == E_RDATA) && ddr_dout_ready;
assign rlb_waddr = {eng_half, eng_w[7:0]};
assign rlb_wdata = {ddr_dout[55:32], ddr_dout[23:0]};

always @(posedge clk) begin
	if (reset) begin
		act_d    <= 1'b0;
		vs_d     <= 1'b0;
		xcnt     <= 9'd0;
		width    <= 9'd0;
		line     <= 8'd0;
		height   <= 9'd0;
		wbuf     <= 1'b0;
		armed    <= 2'd0;
		flipping <= 1'b0;
		fl_req   <= 1'b0;
		pf_req   <= 2'b00;
		pf_ready <= 2'b00;
		dbg_late <= 16'd0;
	end
	else begin
		// ---- raster and job requests (on ce)
		if (ce) begin
			act_d <= act;
			vs_d  <= vs_in;

			if (act) begin
				xcnt <= xcnt + 9'd1;
				if (!xcnt[0]) even_px <= rgb_in;
				if (flipping && xcnt == 9'd0 && !pf_ready[line[0]] && dbg_late != 16'hFFFF)
					dbg_late <= dbg_late + 16'd1;
			end

			if (line_end) begin
				xcnt  <= 9'd0;
				width <= xcnt;
				line  <= line + 8'd1;
				if (enable) begin
					// The line just captured goes to DDRAM during the next one.
					if ((fl_req || st == E_WADDR || st == E_WDATA || st == E_WREQ) && dbg_late != 16'hFFFF)
						dbg_late <= dbg_late + 16'd1;
					fl_req  <= 1'b1;
					fl_buf  <= wbuf;
					fl_line <= line;
					fl_half <= line[0];
					fl_n    <= (xcnt + 9'd1) >> 1;
					// The half this line was shown from now gets line + 2.
					if ({1'b0, line} + 9'd2 < height) begin
						pf_req[line[0]]   <= 1'b1;
						pf_ready[line[0]] <= 1'b0;
						pf_buf[line[0]]   <= ~wbuf;
						pf_src[line[0]]   <= height[7:0] - 8'd3 - line;
						pf_n[line[0]]     <= (xcnt + 9'd1) >> 1;
					end
				end
			end

			if (frame) begin
				line   <= 8'd0;
				height <= {1'b0, line};
				wbuf   <= ~wbuf;
				if (enable) begin
					flipping <= (armed != 2'd0);
					if (armed != 2'd2) armed <= armed + 2'd1;
					// Lines 0 and 1 of the frame just stored.
					pf_req      <= 2'b11;
					pf_ready    <= 2'b00;
					pf_buf[0]   <= wbuf;
					pf_buf[1]   <= wbuf;
					pf_src[0]   <= line - 8'd1;
					pf_src[1]   <= line - 8'd2;
					pf_n[0]     <= (width + 9'd1) >> 1;
					pf_n[1]     <= (width + 9'd1) >> 1;
				end
			end
		end

		if (!enable) begin
			flipping <= 1'b0;
			armed    <= 2'd0;
			fl_req   <= 1'b0;
			pf_req   <= 2'b00;
			pf_ready <= 2'b00;
		end
	end

	// ---- DDRAM engine
	case (st)
		E_IDLE:
			if (enable && !reset) begin
				if (fl_req) begin
					fl_req   <= 1'b0;
					eng_buf  <= fl_buf;
					eng_line <= fl_line;
					eng_half <= fl_half;
					eng_n    <= fl_n;
					eng_w    <= 9'd0;
					st       <= E_WADDR;
				end
				else if (pf_req != 2'b00) begin
					pf_req[pf_req[0] ? 1'b0 : 1'b1] <= 1'b0;
					eng_half <= pf_req[0] ? 1'b0 : 1'b1;
					eng_buf  <= pf_req[0] ? pf_buf[0] : pf_buf[1];
					eng_line <= pf_req[0] ? pf_src[0] : pf_src[1];
					eng_n    <= pf_req[0] ? pf_n[0] : pf_n[1];
					eng_w    <= 9'd0;
					iss_w    <= 9'd0;
					st       <= E_RREQ;
				end
			end

		// Write: one word at a time from the write line buffer.
		E_WADDR:
			if (eng_w == eng_n || !enable) st <= E_IDLE;
			else                           st <= E_WDATA;

		E_WDATA: begin
			ddr_addr     <= BASE | {12'd0, eng_buf, eng_line, eng_w[7:0]};
			ddr_din      <= {8'd0, wlb_q[47:24], 8'd0, wlb_q[23:0]};
			ddr_burstcnt <= 8'd1;
			ddr_we       <= 1'b1;
			st           <= E_WREQ;
		end

		E_WREQ:
			if (!ddr_busy) begin
				ddr_we <= 1'b0;
				eng_w  <= eng_w + 9'd1;
				st     <= enable ? E_WADDR : E_IDLE;
			end

		// Read: bursts of up to 64 words into the read line buffer.
		E_RREQ:
			if (iss_w >= eng_n) begin
				if (enable) pf_ready[eng_half] <= 1'b1;
				st <= E_IDLE;
			end
			else begin
				ddr_addr     <= BASE | {12'd0, eng_buf, eng_line, iss_w[7:0]};
				ddr_burstcnt <= burst_len;
				ddr_rd       <= 1'b1;
				rd_left      <= burst_len;
				iss_w        <= iss_w + {1'b0, burst_len};
				st           <= E_RDATA;
			end

		E_RDATA: begin
			if (ddr_rd && !ddr_busy) ddr_rd <= 1'b0;
			if (ddr_dout_ready) begin
				eng_w   <= eng_w + 9'd1;
				rd_left <= rd_left - 8'd1;
				if (rd_left == 8'd1) begin
					if (eng_w + 9'd1 == eng_n) begin
						if (enable) pf_ready[eng_half] <= 1'b1;
						st <= E_IDLE;
					end
					else st <= enable ? E_RREQ : E_IDLE;
				end
			end
		end

		default: st <= E_IDLE;
	endcase
end

endmodule
