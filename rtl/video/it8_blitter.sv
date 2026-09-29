//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_blitter.sv - ITV4400 blitter
//
//  A register-for-register port of MAME's itech8_state::perform_blit. The
//  blitter copies graphics ROM data, raw or run-length encoded, into VRAM at
//  the TMS34061 XY address, with the TMS34061 latch supplying the upper
//  colour nibbles. Rows are drawn in alternating directions (the source is
//  stored serpentine), and four skip counts clip the image on each side.
//
//    reg  function                      reg  function
//    0/1  source address high/low        8   pixels to skip before each row
//    2    flags: 4 transparent,          9   rows to draw
//         3 RLE, 2 Y flip, 1 X flip,    10   pixels to skip after each row
//         0 nibble shift                11   rows to skip at the end
//    3    write: start / read: status   12-15 input ports (trackball on
//                                             the 6809 bowling boards)
//    4/5  width (bytes) / height (rows)
//    6    source data mask
//    7    output: bit 6 selects 4 bpp transparency
//
//  The status bit and the completion interrupt follow MAME's timing: busy
//  for (width x height + 12) ticks of 3 MHz, or until the drawing engine
//  has actually finished, whichever is later. The engine needs about five
//  clocks per pixel against the sixteen that timing allows: source bytes
//  come from a two-word window that prefetches the next ROM word, and VRAM
//  writes are posted so the next pixel is fetched while one is written.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_blitter
(
	input             clk,
	input             reset,

	// CPU register access (one byte lane at a time).
	input             reg_we,         // pulse
	input             reg_re,         // pulse: read with side effects
	input       [3:0] reg_idx,
	input       [7:0] reg_wdata,
	output      [7:0] reg_rdata,      // valid for the current reg_idx
	input       [7:0] grom_bank,      // 0x100100 bank register
	input      [23:0] grom_size,      // graphics ROM region in bytes (MAME: offset % length)
	input      [31:0] an,             // registers 12-15 read these bytes: {15, 14, 13, 12}

	// TMS34061 state sampled at the start of a blit.
	input      [15:0] xyaddress,
	input      [15:0] xyoffset,
	input       [7:0] latch,

	// Graphics ROM (SDRAM bank 1), toggle handshake, 16-bit big-endian words.
	output reg [23:0] rom_addr,
	output reg        rom_req,
	input             rom_ack,
	input      [15:0] rom_data,

	// VRAM nibble writes (it8_vram).
	output reg        vr_start,
	output reg [17:0] vr_addr,
	output reg  [7:0] vr_vdata,
	output reg  [7:0] vr_vmask,
	output reg  [7:0] vr_ldata,
	output reg  [7:0] vr_lmask,
	input             vr_done,

	output reg        irq,            // level 2 on the 68000
	output            busy,

	output reg [15:0] dbg_blits,      // blits started
	output reg [15:0] dbg_late        // blits where drawing outlasted MAME's timing
);

wire       [23:0] GROM_SIZE  = grom_size;
wire       [19:0] GROM_WORDS = grom_size[20:1];
localparam [23:0] GROM_BASE  = 24'h400000;   // SDRAM word address of bank 1

reg [7:0] breg[0:15];

assign reg_rdata = (reg_idx == 4'd3)  ? {busy, breg[3][6:0]} :
                   (reg_idx >= 4'd12) ? an[8*reg_idx[1:0] +: 8] :
                                        breg[reg_idx];

// ---------------------------------------------------------------------------
// Trigger snapshot. A start while the engine is still drawing is held and
// run afterwards; its parameters are taken at the time it was written.

reg        trig_pend;
reg [17:0] s_addr;
reg  [7:0] s_color;
reg [23:0] s_src;
reg  [7:0] s_flags, s_w, s_h, s_mask, s_out, s_xstart, s_ycount, s_xstop, s_yskip;

reg [20:0] timer;          // MAME busy time, in 48 MHz clocks
reg        eng_busy;
assign busy = eng_busy | trig_pend | (timer != 21'd0);

// ---------------------------------------------------------------------------
// Source window: two consecutive ROM words, t0 and t0 + 1. The engine reads
// the byte at off; moving into the second word slides the window and the
// word after it is prefetched.

reg [23:0] off;            // graphics ROM byte offset, kept below GROM_SIZE
reg [19:0] t0;
reg [15:0] w0, w1;
reg        v0, v1;
reg        rq_busy;        // a ROM read is outstanding
reg        rq_slot;        // ... for word 0 or word 1
reg [19:0] rq_tag;

wire [19:0] ow    = off[20:1];
wire [19:0] t0n   = (t0 == GROM_WORDS - 20'd1) ? 20'd0 : t0 + 20'd1;
wire        hit0  = v0 && (ow == t0);
wire        hit1  = v1 && (ow == t0n);
wire        hit   = hit0 | hit1;
wire [15:0] hw    = hit0 ? w0 : w1;
wire  [7:0] byte_ = off[0] ? hw[7:0] : hw[15:8];

function [23:0] wrap_add(input [23:0] a, input [8:0] n);
	reg [23:0] s;
	begin
		s = a + {15'd0, n};
		wrap_add = (s >= GROM_SIZE) ? s - GROM_SIZE : s;
	end
endfunction

// ---------------------------------------------------------------------------
// Engine state

localparam [3:0]
	E_IDLE = 4'd0,  E_MOD  = 4'd1,  E_SET1 = 4'd2,  E_SET2 = 4'd3,
	E_TOP  = 4'd4,  E_TOPN = 4'd5,  E_ROW  = 4'd6,  E_ROWA = 4'd7,
	E_PIX  = 4'd8,  E_DRAW = 4'd9,  E_LO   = 4'd10, E_ROWN = 4'd11,
	E_END  = 4'd12, C_LOOP = 4'd13;

reg  [3:0] st;
reg  [3:0] ret_c;          // return state after a consume

reg [17:0] addr;
reg  [7:0] color, mask;
reg        f_shift, f_xflip, f_yflip, f_rle, f_trans, tm4;
reg        xdir_neg;       // current row direction: 1 = right to left
reg  [7:0] w8;
reg  [7:0] skip0, skip1, skip2;
reg signed [10:0] width, height;
reg signed [10:0] y;
reg  [7:0] ytop;
reg signed [10:0] x;

reg  [7:0] rle_cnt;
reg        rle_lit;
reg  [7:0] rle_val;
reg        hdr_loaded;     // fetch: header read, value/pixel still to come
reg        need_val;       // a run header's value byte is still to be read
reg  [8:0] cons_n;         // bytes left to consume
reg  [7:0] pix_raw;
reg        vr_busy;        // a posted VRAM write has not completed

// Pixel byte after X-flip nibble swap and the source mask.
wire [7:0] pix   = ((f_xflip && tm4) ? {pix_raw[3:0], pix_raw[7:4]} : pix_raw) & mask;
wire       hi_en = !f_trans || ((pix & (tm4 ? 8'hF0 : 8'hFF)) != 8'h00);
wire       lo_en = !f_trans || ((pix & (tm4 ? 8'h0F : 8'hFF)) != 8'h00);

wire [17:0] xstep1   = xdir_neg ? 18'h3FFFF : 18'h00001;
wire [17:0] row_next = (xdir_neg ? addr + 18'd1 : addr - 18'd1) + (f_yflip ? 18'h3FF00 : 18'h00100);

function [17:0] step_x(input [17:0] a, input neg, input [8:0] n);
	step_x = neg ? a - {9'd0, n} : a + {9'd0, n};
endfunction

wire [15:0] wh = s_w * s_h;

always @(posedge clk) begin
	vr_start <= 1'b0;

	if (timer != 21'd0) timer <= timer - 21'd1;
	if (vr_done) vr_busy <= 1'b0;

	if (reset) irq <= 1'b0;
	else if (reg_re && reg_idx == 4'd3) irq <= 1'b0;

	if (reg_we) begin
		breg[reg_idx] <= reg_wdata;
		if (reg_idx == 4'd3) begin
			trig_pend <= 1'b1;
			s_addr    <= {xyoffset[9:8], xyaddress};
			s_color   <= latch;
			s_src     <= {grom_bank, breg[0], breg[1]};
			s_flags   <= breg[2];
			s_w       <= breg[4];
			s_h       <= breg[5];
			s_mask    <= breg[6];
			s_out     <= breg[7];
			s_xstart  <= breg[8];
			s_ycount  <= breg[9];
			s_xstop   <= breg[10];
			s_yskip   <= breg[11];
		end
	end

	// ----- source window: slide, demand fetch, prefetch -----
	if (!reset) begin
		if (rq_busy) begin
			if (rom_req == rom_ack) begin
				rq_busy <= 1'b0;
				if (!rq_slot && rq_tag == t0) begin
					w0 <= rom_data;
					v0 <= 1'b1;
				end
				else if (rq_slot && rq_tag == t0n) begin
					w1 <= rom_data;
					v1 <= 1'b1;
				end
			end
		end
		else if (st != E_IDLE && st != E_MOD) begin
			if (!hit0 && hit1) begin
				// Moved into the second word: slide the window.
				t0 <= t0n;
				w0 <= w1;
				v0 <= 1'b1;
				v1 <= 1'b0;
			end
			else if (!hit) begin
				// Jumped outside the window: fetch the word at off.
				t0       <= ow;
				v0       <= 1'b0;
				v1       <= 1'b0;
				rom_addr <= GROM_BASE + {4'd0, ow};
				rom_req  <= ~rom_req;
				rq_busy  <= 1'b1;
				rq_slot  <= 1'b0;
				rq_tag   <= ow;
			end
			else if (!v1) begin
				rom_addr <= GROM_BASE + {4'd0, t0n};
				rom_req  <= ~rom_req;
				rq_busy  <= 1'b1;
				rq_slot  <= 1'b1;
				rq_tag   <= t0n;
			end
		end
	end

	if (reset) begin
		st        <= E_IDLE;
		eng_busy  <= 1'b0;
		trig_pend <= 1'b0;
		timer     <= 21'd0;
		v0        <= 1'b0;
		v1        <= 1'b0;
		rq_busy   <= 1'b0;
		vr_busy   <= 1'b0;
		dbg_blits <= 16'd0;
		dbg_late  <= 16'd0;
	end
	else case (st)
		E_IDLE: begin
			if (eng_busy && timer == 21'd0 && !trig_pend) begin
				// Drawing and the MAME busy period are both over.
				eng_busy <= 1'b0;
				irq      <= 1'b1;
			end
			if (trig_pend && !(reg_we && reg_idx == 4'd3)) begin
				trig_pend  <= 1'b0;
				eng_busy   <= 1'b1;
				dbg_blits  <= dbg_blits + 16'd1;
				timer      <= {1'b0, wh + 16'd12, 4'd0};
				addr       <= s_addr;
				color      <= s_color;
				mask       <= s_mask;
				f_shift    <= s_flags[0];
				f_xflip    <= s_flags[1];
				f_yflip    <= s_flags[2];
				f_rle      <= s_flags[3];
				f_trans    <= s_flags[4];
				tm4        <= s_out[6];
				xdir_neg   <= s_flags[1];
				w8         <= s_w;
				off        <= s_src + (s_flags[3] ? 24'd2 : 24'd0);
				rle_cnt    <= 8'd0;
				hdr_loaded <= 1'b0;
				need_val   <= 1'b0;
				st         <= E_MOD;
			end
		end

		// Bring the source offset into range (MAME: offset % grom length).
		E_MOD: begin
			if (off >= GROM_SIZE) off <= off - GROM_SIZE;
			else st <= E_SET1;
		end

		E_SET1: begin
			if (s_flags[1]) begin
				skip0 <= (s_w <= s_xstop) ? 8'd0 : s_w - 8'd1 - s_xstop;
				skip1 <= s_xstart;
			end
			else begin
				skip0 <= s_xstart;
				skip1 <= (s_w <= s_xstop) ? 8'd0 : s_w - 8'd1 - s_xstop;
			end
			if (!s_flags[2]) begin
				skip2  <= (s_h <= s_ycount) ? 8'd0 : s_h - s_ycount;
				height <= (s_yskip > 8'd1) ? $signed({3'd0, s_h}) - $signed({3'd0, s_yskip}) + 11'sd1 : $signed({3'd0, s_h});
			end
			else begin
				skip2  <= (s_h <= s_yskip) ? 8'd0 : s_h - s_yskip;
				height <= (s_ycount > 8'd1) ? $signed({3'd0, s_h}) - $signed({3'd0, s_ycount}) + 11'sd1 : $signed({3'd0, s_h});
			end
			st <= E_SET2;
		end

		E_SET2: begin
			width <= $signed({3'd0, w8}) - $signed({3'd0, skip0}) - $signed({3'd0, skip1});
			ytop  <= 8'd0;
			st    <= E_TOP;
		end

		// Rows above the drawn area: skip source and destination.
		E_TOP: begin
			if (ytop < skip2) begin
				addr   <= step_x(addr, xdir_neg, {1'b0, w8});
				cons_n <= {1'b0, w8};
				ret_c  <= E_TOPN;
				st     <= C_LOOP;
			end
			else begin
				y  <= $signed({3'd0, skip2});
				st <= E_ROW;
			end
		end

		E_TOPN: begin
			addr     <= row_next;
			xdir_neg <= ~xdir_neg;
			ytop     <= ytop + 8'd1;
			st       <= E_TOP;
		end

		// Start of a drawn row: leading skip on this side.
		E_ROW: begin
			if (y < height) begin
				addr   <= step_x(addr, xdir_neg, {1'b0, y[0] ? skip1 : skip0});
				cons_n <= {1'b0, y[0] ? skip1 : skip0};
				ret_c  <= E_ROWA;
				st     <= C_LOOP;
			end
			else st <= E_END;
		end

		E_ROWA: begin
			x  <= 11'sd0;
			st <= E_PIX;
		end

		// Fetch the next source pixel (MAME fetch_next_raw / fetch_next_rle),
		// one source byte per clock while the window has it.
		E_PIX: begin
			if (x >= width) begin
				addr   <= step_x(addr, xdir_neg, {1'b0, y[0] ? skip0 : skip1});
				cons_n <= {1'b0, y[0] ? skip0 : skip1};
				ret_c  <= E_ROWN;
				st     <= C_LOOP;
			end
			else if (!f_rle) begin
				if (hit) begin
					pix_raw <= byte_;
					off     <= wrap_add(off, 9'd1);
					st      <= E_DRAW;
				end
			end
			else if (rle_cnt == 8'd0 && !hdr_loaded) begin
				if (hit) begin
					rle_lit    <= byte_[7];
					rle_cnt    <= {1'b0, byte_[6:0]};
					need_val   <= !byte_[7];
					hdr_loaded <= 1'b1;
					off        <= wrap_add(off, 9'd1);
				end
			end
			else if (need_val) begin
				if (hit) begin
					rle_val  <= byte_;
					need_val <= 1'b0;
					off      <= wrap_add(off, 9'd1);
				end
			end
			else if (rle_lit) begin
				if (hit) begin
					pix_raw    <= byte_;
					rle_val    <= byte_;
					rle_cnt    <= rle_cnt - 8'd1;
					hdr_loaded <= 1'b0;
					off        <= wrap_add(off, 9'd1);
					st         <= E_DRAW;
				end
			end
			else begin
				pix_raw    <= rle_val;
				rle_cnt    <= rle_cnt - 8'd1;
				hdr_loaded <= 1'b0;
				st         <= E_DRAW;
			end
		end

		// Post the VRAM write(s) for this pixel once the last one is done.
		E_DRAW: if (!vr_busy) begin
			if (!f_shift) begin
				vr_addr  <= addr;
				vr_vdata <= pix;
				vr_ldata <= color;
				vr_vmask <= {hi_en ? 4'hF : 4'h0, lo_en ? 4'hF : 4'h0};
				vr_lmask <= {hi_en ? 4'hF : 4'h0, lo_en ? 4'hF : 4'h0};
				if (hi_en || lo_en) begin
					vr_start <= 1'b1;
					vr_busy  <= 1'b1;
				end
				addr <= addr + xstep1;
				x    <= x + 11'sd1;
				st   <= E_PIX;
			end
			else begin
				// Nibble shift: upper nibble to the low half of addr, lower
				// nibble to the high half of addr + 1.
				vr_addr  <= addr;
				vr_vdata <= {4'h0, pix[7:4]};
				vr_ldata <= {4'h0, color[7:4]};
				vr_vmask <= 8'h0F;
				vr_lmask <= 8'h0F;
				if (hi_en) begin
					vr_start <= 1'b1;
					vr_busy  <= 1'b1;
				end
				if (lo_en) st <= E_LO;
				else begin
					addr <= addr + xstep1;
					x    <= x + 11'sd1;
					st   <= E_PIX;
				end
			end
		end

		E_LO: if (!vr_busy && !vr_start) begin
			vr_addr  <= addr + 18'd1;
			vr_vdata <= {pix[3:0], 4'h0};
			vr_ldata <= {color[3:0], 4'h0};
			vr_vmask <= 8'hF0;
			vr_lmask <= 8'hF0;
			vr_start <= 1'b1;
			vr_busy  <= 1'b1;
			addr     <= addr + xstep1;
			x        <= x + 11'sd1;
			st       <= E_PIX;
		end

		// End of a drawn row: step to the next row, reverse direction.
		E_ROWN: begin
			addr     <= row_next;
			xdir_neg <= ~xdir_neg;
			y        <= y + 11'sd1;
			st       <= E_ROW;
		end

		// Wait for the last posted write before reporting completion.
		E_END: if (!vr_busy && !vr_start) st <= E_IDLE;

		// ----- consume cons_n source bytes (MAME consume_raw / consume_rle) -----
		C_LOOP: begin
			if (!f_rle) begin
				off <= wrap_add(off, cons_n);
				st  <= ret_c;
			end
			else if (need_val) begin
				if (hit) begin
					rle_val  <= byte_;
					need_val <= 1'b0;
					off      <= wrap_add(off, 9'd1);
				end
			end
			else if (cons_n == 9'd0) st <= ret_c;
			else if (rle_cnt == 8'd0) begin
				if (hit) begin
					rle_lit  <= byte_[7];
					rle_cnt  <= {1'b0, byte_[6:0]};
					need_val <= !byte_[7];
					off      <= wrap_add(off, 9'd1);
				end
			end
			else if ({1'b0, rle_cnt} <= cons_n) begin
				cons_n  <= cons_n - {1'b0, rle_cnt};
				rle_cnt <= 8'd0;
				if (rle_lit) off <= wrap_add(off, {1'b0, rle_cnt});
			end
			else begin
				rle_cnt <= rle_cnt - cons_n[7:0];
				cons_n  <= 9'd0;
				if (rle_lit) off <= wrap_add(off, cons_n);
			end
		end

		default: st <= E_IDLE;
	endcase

	// Drawing still running when the MAME busy period ends.
	if (!reset && eng_busy && st != E_IDLE && timer == 21'd1) dbg_late <= dbg_late + 16'd1;
end

endmodule
