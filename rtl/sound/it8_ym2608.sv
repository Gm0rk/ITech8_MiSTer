//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_ym2608.sv - YM2608 (OPNA) for Grudge Match's sound board (D-048)
//
//  The parts of the YM2608 the game uses, at 8 MHz:
//
//    FM and timers   JT12 (jt12_top: six channels, LFO, the YM2203's mono
//                    accumulator, prescaler registers 2D-2F)
//    SSG             only its I/O port B (registers 07 and 0F): the sound
//                    board's feedback bit to the main CPU. The game plays
//                    no SSG tones, so there is no tone generator.
//    rhythm          the six drum sounds of the chip's internal ROM (MAME
//                    ym2608.zip, 8 KB, loaded with the game), ADPCM-A
//                    style, registers 10-1D
//    ADPCM-B         one channel playing from the board's 128 KB sample ROM,
//                    registers 100-110, status port B
//
//  The rhythm and ADPCM-B sections follow ymfm (Aaron Giles, BSD-3), as MAME
//  0.264 runs them: per FM sample (clock / 144, 55.5 kHz) ADPCM-B steps its
//  position by delta-N and decodes a nibble on each overflow; every third
//  sample the rhythm channels decode one nibble each (tom and rim shot every
//  sixth). The output is ymfm's L + R (each clamped to 16 bits): FM as 13
//  bits a channel, centred (the game pans every channel to both sides), the
//  rhythm channels and ADPCM-B as their pan registers say.
//
//  Not modelled, as the game does not use them: SSG tones and noise, ADPCM-B
//  recording, CPU-driven data and the DAC, the ADPCM IRQs (register 29's
//  mask is ignored: the timers' IRQ is JT12's, which the game enables there
//  as well), 3-channel mode (register 29 bit 7), the flag reset of register
//  110 bit 7, and reads of SSG registers.
//
//  Sample memory (mem_*): byte address, 00000-1FFFF the ADPCM-B ROM, 20000-
//  21FFF the rhythm ROM. A read is asked for with mem_req (held) and answered
//  by mem_ack with mem_data. Bytes are fetched ahead of use; a channel that
//  needs a byte that has not arrived waits for it, which only delays this
//  sample's output.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_ym2608
(
	input                    clk,           // 48 MHz
	input                    rst,
	input                    cen,           // 8 MHz, the chip's clock

	input              [1:0] addr,
	input                    wr,            // one clock: write din to addr
	input              [7:0] din,
	output reg         [7:0] dout,          // read data of addr (one clock late)
	output                   irq_n,

	output             [7:0] iob,           // SSG port B (register 0F)
	output                   iob_oe,        // port B is an output (register 07 bit 7)

	output reg               mem_req,
	output reg        [17:0] mem_addr,
	input                    mem_ack,
	input              [7:0] mem_data,

	output reg signed [16:0] snd,           // L + R, as ymfm
	output reg signed [16:0] snd_fm,        // the FM part of it
	output reg signed [16:0] snd_pcm,       // the rhythm and ADPCM-B part
	output reg               sample         // one clock: snd updated
);

// ---------------------------------------------------------------------------
// FM and timers (JT12)

wire        [7:0] fm_dout;
wire signed [15:0] fm_mono;
wire              fm_zero;

// JT12 clears its operators' state (envelope, key on) only in the slots
// that pass through its shift registers while reset is held, one slot every
// six clocks: 144 clocks for all 24. Whatever the length of rst, it is held
// for 256 clocks more (32 us; the sound program's first write comes tens of
// milliseconds after reset), so no slot starts with an open envelope.
reg   [8:0] fm_rcnt;
reg         fm_rst = 1'b1;

always @(posedge clk) begin
	if (rst)                     fm_rcnt <= 9'd0;
	else if (cen && !fm_rcnt[8]) fm_rcnt <= fm_rcnt + 9'd1;
	fm_rst <= rst | ~fm_rcnt[8];
end

jt12_top #(
	.use_lfo(1), .use_ssg(0), .num_ch(6), .use_pcm(0), .use_adpcm(0), .mask_div(0), .latch_per_part(1)
) u_fm (
	.rst          (fm_rst),
	.clk          (clk),
	.cen          (cen),
	.din          (din),
	.addr         (addr),
	.cs_n         (~wr),
	.wr_n         (1'b0),
	.dout         (fm_dout),
	.irq_n        (irq_n),
	.en_hifi_pcm  (1'b0),
	.adpcma_addr  (),
	.adpcma_bank  (),
	.adpcma_roe_n (),
	.adpcma_data  (8'd0),
	.adpcmb_addr  (),
	.adpcmb_data  (8'd0),
	.adpcmb_roe_n (),
	.IOA_in       (8'hFF),
	.IOB_in       (8'hFF),
	.IOA_out      (),
	.IOB_out      (),
	.IOA_oe       (),
	.IOB_oe       (),
	.psg_A        (),
	.psg_B        (),
	.psg_C        (),
	.fm_snd_left  (fm_mono),
	.fm_snd_right (),
	.adpcmA_l     (),
	.adpcmA_r     (),
	.adpcmB_l     (),
	.adpcmB_r     (),
	.psg_snd      (),
	.snd_right    (),
	.snd_left     (),
	.snd_sample   (fm_zero),
	.ch_enable    (6'h3F),
	.debug_bus    (8'd0),
	.debug_view   ()
);

// ---------------------------------------------------------------------------
// Registers. One address latch for both ports, as the chip: a data write
// counts only on the side of the last address write.

reg   [7:0] areg;
reg         ahi;
reg   [7:0] r07, r0f;                    // SSG I/O
reg   [7:0] rkey;                        // 10: last key on / dump
reg   [5:0] rtl;                         // 11: rhythm total level
reg   [7:0] rlev [0:5];                  // 18-1D: pan and level
reg   [7:0] b0, b1;                      // 100, 101
reg  [15:0] bstart, bend, bdn, blimit;   // 102-105, 109-10A, 10C-10D
reg   [7:0] blevel;                      // 10B
reg   [4:0] flag_ctl;                    // 110

wire        wr_a  = wr && addr == 2'd1 && !ahi;
wire        wr_b  = wr && addr == 2'd3 &&  ahi;

assign iob    = r0f;
assign iob_oe = r07[7];

// Pulses for the sections below.
reg         key_wr;                      // 10 written (rkey)
reg         b0_wr;                       // 100 written (b0)

integer i, j;

always @(posedge clk) begin
	key_wr <= 1'b0;
	b0_wr  <= 1'b0;
	if (rst) begin
		areg     <= 8'd0;
		ahi      <= 1'b0;
		r07      <= 8'd0;
		r0f      <= 8'd0;
		rkey     <= 8'd0;
		rtl      <= 6'd0;
		for (i = 0; i < 6; i = i + 1) rlev[i] <= 8'hDF;
		b0       <= 8'd0;
		b1       <= 8'd0;
		bstart   <= 16'd0;
		bend     <= 16'd0;
		bdn      <= 16'd0;
		blimit   <= 16'hFFFF;
		blevel   <= 8'd0;
		flag_ctl <= 5'h1C;
	end
	else if (wr) begin
		if (addr == 2'd0) begin areg <= din; ahi <= 1'b0; end
		if (addr == 2'd2) begin areg <= din; ahi <= 1'b1; end
		if (wr_a) begin
			if (areg == 8'h07) r07 <= din;
			if (areg == 8'h0F) r0f <= din;
			if (areg == 8'h10) begin rkey <= din; key_wr <= 1'b1; end
			if (areg == 8'h11) rtl <= din[5:0];
			if (areg >= 8'h18 && areg <= 8'h1D) rlev[areg[2:0]] <= din;   // 18-1D: channels 0-5
		end
		if (wr_b) begin
			case (areg)
				8'h00: begin b0 <= din; b0_wr <= 1'b1; end
				8'h01: b1 <= din;
				8'h02: bstart[7:0]  <= din;
				8'h03: bstart[15:8] <= din;
				8'h04: bend[7:0]    <= din;
				8'h05: bend[15:8]   <= din;
				8'h09: bdn[7:0]     <= din;
				8'h0A: bdn[15:8]    <= din;
				8'h0B: blevel       <= din;
				8'h0C: blimit[7:0]  <= din;
				8'h0D: blimit[15:8] <= din;
				8'h10: if (!din[7]) flag_ctl <= din[4:0];
				default: ;
			endcase
		end
	end
end

// ---------------------------------------------------------------------------
// Tables

function [10:0] step_a(input [5:0] n);   // ADPCM-A step sizes
	case (n)
		6'd0:  step_a = 11'd16;   6'd1:  step_a = 11'd17;   6'd2:  step_a = 11'd19;
		6'd3:  step_a = 11'd21;   6'd4:  step_a = 11'd23;   6'd5:  step_a = 11'd25;
		6'd6:  step_a = 11'd28;   6'd7:  step_a = 11'd31;   6'd8:  step_a = 11'd34;
		6'd9:  step_a = 11'd37;   6'd10: step_a = 11'd41;   6'd11: step_a = 11'd45;
		6'd12: step_a = 11'd50;   6'd13: step_a = 11'd55;   6'd14: step_a = 11'd60;
		6'd15: step_a = 11'd66;   6'd16: step_a = 11'd73;   6'd17: step_a = 11'd80;
		6'd18: step_a = 11'd88;   6'd19: step_a = 11'd97;   6'd20: step_a = 11'd107;
		6'd21: step_a = 11'd118;  6'd22: step_a = 11'd130;  6'd23: step_a = 11'd143;
		6'd24: step_a = 11'd157;  6'd25: step_a = 11'd173;  6'd26: step_a = 11'd190;
		6'd27: step_a = 11'd209;  6'd28: step_a = 11'd230;  6'd29: step_a = 11'd253;
		6'd30: step_a = 11'd279;  6'd31: step_a = 11'd307;  6'd32: step_a = 11'd337;
		6'd33: step_a = 11'd371;  6'd34: step_a = 11'd408;  6'd35: step_a = 11'd449;
		6'd36: step_a = 11'd494;  6'd37: step_a = 11'd544;  6'd38: step_a = 11'd598;
		6'd39: step_a = 11'd658;  6'd40: step_a = 11'd724;  6'd41: step_a = 11'd796;
		6'd42: step_a = 11'd876;  6'd43: step_a = 11'd963;  6'd44: step_a = 11'd1060;
		6'd45: step_a = 11'd1166; 6'd46: step_a = 11'd1282; 6'd47: step_a = 11'd1411;
		default: step_a = 11'd1552;
	endcase
endfunction

function signed [7:0] inc_a(input [2:0] d);
	inc_a = (d == 3'd4) ? 8'sd2 : (d == 3'd5) ? 8'sd5 : (d == 3'd6) ? 8'sd7 : (d == 3'd7) ? 8'sd9 : -8'sd1;
endfunction

function [7:0] scale_b(input [2:0] d);   // ADPCM-B step scale, x 64
	scale_b = (d == 3'd4) ? 8'd77 : (d == 3'd5) ? 8'd102 : (d == 3'd6) ? 8'd128 : (d == 3'd7) ? 8'd153 : 8'd57;
endfunction

// Rhythm sounds in the internal ROM: start and end (inclusive) byte.
function [12:0] r_start(input [2:0] c);
	case (c)
		3'd0: r_start = 13'h0000; 3'd1: r_start = 13'h01C0; 3'd2: r_start = 13'h0440;
		3'd3: r_start = 13'h1B80; 3'd4: r_start = 13'h1D00; default: r_start = 13'h1F80;
	endcase
endfunction

function [13:0] r_stop(input [2:0] c);   // end + 1
	case (c)
		3'd0: r_stop = 14'h01C0; 3'd1: r_stop = 14'h0440; 3'd2: r_stop = 14'h1B80;
		3'd3: r_stop = 14'h1D00; 3'd4: r_stop = 14'h1F80; default: r_stop = 14'h2000;
	endcase
endfunction

// ---------------------------------------------------------------------------
// Channel state. Clients 0-5 are the rhythm channels, 6 ADPCM-B; each keeps
// the byte at its current address fetched ahead (pf, pf_ok).

reg         ra_on   [0:5];
reg         ra_nib  [0:5];
reg   [7:0] ra_byte [0:5];
reg  [13:0] ra_addr [0:5];
reg  [11:0] ra_acc  [0:5];
reg   [5:0] ra_step [0:5];

reg         b_play, b_eos, b_brdy, b_nib;
reg   [7:0] b_byte;
reg  [15:0] b_pos;
reg  [23:0] b_addr;
reg signed [15:0] b_acc, b_prev;
reg  [14:0] b_step;

reg   [7:0] pf    [0:6];
reg         pf_ok [0:6];

// ADPCM-B address unit: 32 bytes for ROM or 8-bit DRAM, else 4.
wire  [4:0] b_shift  = (b1[0] | b1[1]) ? 5'd5 : 5'd2;
wire [23:0] b_endad  = (({8'd0, bend}   + 24'd1) << b_shift) - 24'd1;
wire [23:0] b_limad  = (({8'd0, blimit} + 24'd1) << b_shift) - 24'd1;
wire [23:0] b_stad   = {8'd0, bstart} << b_shift;

// ---------------------------------------------------------------------------
// Memory: fetch for the lowest client whose byte is missing. A byte that
// arrives for an address the client has since left is dropped.

reg   [2:0] m_cli;
reg         m_busy;
reg  [17:0] m_want [0:6];
reg   [6:0] needv;

always @(*) begin
	for (j = 0; j < 6; j = j + 1) begin
		m_want[j] = 18'h20000 | {5'd0, ra_addr[j][12:0]};
		needv[j]  = ra_on[j] && !pf_ok[j] && ra_addr[j] != r_stop(j[2:0]);
	end
	m_want[6] = {1'b0, b_addr[16:0]};
	needv[6]  = b_play && b0[5] && !pf_ok[6];
end

// ---------------------------------------------------------------------------
// Per sample: the sequencer below clocks the sections, then mixes.

reg         zero_d;
wire        tick = fm_zero & ~zero_d;    // one FM sample

// JT12's accumulator puts out what its slots held before reset for the
// samples around the end of its reset: the FM part stays 0 until three
// samples after it.
reg   [1:0] fm_mute;

always @(posedge clk) begin
	if (fm_rst)                     fm_mute <= 2'd3;
	else if (tick && fm_mute != 0)  fm_mute <= fm_mute - 2'd1;
end
reg   [1:0] env3;                        // ymfm's envelope counter, low bits
reg         env_b2;                      // ... and bit 2

localparam [3:0] Q_IDLE = 4'd0, Q_A = 4'd1, Q_AD = 4'd2, Q_A2 = 4'd3, Q_B = 4'd4, Q_B2 = 4'd5,
                 Q_OA = 4'd6, Q_OA2 = 4'd7, Q_OB1 = 4'd8, Q_OB2 = 4'd9, Q_OB3 = 4'd10,
                 Q_OB4 = 4'd11, Q_MIX = 4'd12;

reg   [3:0] q;
reg   [2:0] ch;
reg   [5:0] amask;
reg   [3:0] dat;                         // nibble being decoded
reg signed [17:0] mA, mB;               // the shared multiplier
wire signed [35:0] mP = mA * mB;
reg signed [19:0] sumL, sumR;
reg signed [31:0] bint;                 // ADPCM-B interpolation
wire signed [31:0] b_isum = bint + $signed(mP[31:0]);
reg signed [17:0] bout;

// ADPCM-A delta: (2 d + 1) x step / 8, the accumulator wrapping at 12 bits;
// the step index moves by inc_a, 0-48.
wire [15:0] da    = {12'd0, dat[2:0], 1'b1} * {5'd0, step_a(ra_step[ch])};
wire [11:0] a_nacc = ra_acc[ch] + (dat[3] ? 12'd0 - da[14:3] : da[14:3]);
wire signed [7:0] a_nstep = $signed({2'b00, ra_step[ch]}) + inc_a(dat[2:0]);

// ADPCM-B: the same with its step, the accumulator clamped to 16 bits; the
// step scaled by scale_b / 64, 127-24576. From a restart (repeat) the step
// is 127 again.
wire [19:0] db    = {16'd0, dat[2:0], 1'b1} * {5'd0, b_step};
wire [19:0] db0   = {16'd0, dat[2:0], 1'b1} * 20'd127;
wire signed [20:0] b_sum  = $signed({{5{b_acc[15]}}, b_acc}) + (dat[3] ? -$signed({4'd0, db[19:3]}) : $signed({4'd0, db[19:3]}));
wire signed [20:0] b_sum0 = dat[3] ? -$signed({4'd0, db0[19:3]}) : $signed({4'd0, db0[19:3]});
wire [22:0] b_nstep  = ({8'd0, b_step} * {15'd0, scale_b(dat[2:0])}) >> 6;
wire [22:0] b_nstep0 = (23'd127 * {15'd0, scale_b(dat[2:0])}) >> 6;

function [15:0] clamp16(input signed [20:0] v);
	clamp16 = (v > 21'sd32767) ? 16'h7FFF : (v < -21'sd32768) ? 16'h8000 : v[15:0];
endfunction

function [14:0] clampstep(input [22:0] v);
	clampstep = (v < 23'd127) ? 15'd127 : (v > 23'd24576) ? 15'd24576 : v[14:0];
endfunction

// Rhythm volume: (level ^ 1F) + (TL ^ 3F), 0.75 dB a step.
wire  [6:0] vol   = {2'b00, rlev[ch][4:0] ^ 5'h1F} + {1'b0, rtl ^ 6'h3F};
wire  [3:0] vmul  = 4'd15 - {1'b0, vol[2:0]};
wire  [3:0] vshf  = 4'd5 + {1'b0, vol[5:3]};
wire signed [15:0] acc16 = {ra_acc[ch], 4'd0};

always @(posedge clk) begin
	zero_d <= fm_zero;
	sample <= 1'b0;

	if (rst) begin
		q      <= Q_IDLE;
		env3   <= 2'd0;
		env_b2 <= 1'b0;
		for (i = 0; i < 6; i = i + 1) begin
			ra_on[i]   <= 1'b0;
			ra_nib[i]  <= 1'b0;
			ra_acc[i]  <= 12'd0;
			ra_step[i] <= 6'd0;
			ra_addr[i] <= {1'b0, r_start(i[2:0])};
		end
		for (i = 0; i < 7; i = i + 1) pf_ok[i] <= 1'b0;
		b_play  <= 1'b0;
		b_eos   <= 1'b0;
		b_brdy  <= 1'b1;
		b_nib   <= 1'b0;
		b_pos   <= 16'd0;
		b_addr  <= 24'd0;
		b_acc   <= 16'sd0;
		b_prev  <= 16'sd0;
		b_step  <= 15'd127;
		mem_req <= 1'b0;
		m_busy  <= 1'b0;
		snd     <= 17'sd0;
		snd_fm  <= 17'sd0;
		snd_pcm <= 17'sd0;
	end
	else begin
		// ---- memory ----
		if (!m_busy) begin
			for (i = 6; i >= 0; i = i - 1)
				if (needv[i]) begin
					m_cli    <= i[2:0];
					mem_addr <= m_want[i];
					mem_req  <= 1'b1;
					m_busy   <= 1'b1;
				end
		end
		else if (mem_ack) begin
			mem_req <= 1'b0;
			m_busy  <= 1'b0;
			if (mem_addr == m_want[m_cli]) begin
				pf[m_cli]    <= mem_data;
				pf_ok[m_cli] <= 1'b1;
			end
		end

		// ---- the sample sequencer ----
		case (q)
			Q_IDLE: if (tick) begin
				// ymfm: the envelope counter's low two bits count 0-2;
				// rhythm runs when they wrap, tom and rim shot (4, 5) only
				// when bit 2 is then clear, which is every other time,
				// starting with the first time without them.
				if (env3 == 2'd2) begin
					env3   <= 2'd0;
					env_b2 <= ~env_b2;
					amask  <= env_b2 ? 6'h3F : 6'h0F;   // bit 2 after this wrap
				end
				else begin
					env3  <= env3 + 2'd1;
					amask <= 6'h00;
				end
				ch <= 3'd0;
				q  <= Q_A;
			end

			// Rhythm channel ch: one nibble.
			Q_A: begin
				if (!amask[ch]) q <= Q_A2;
				else if (!ra_on[ch]) begin
					ra_acc[ch] <= 12'd0;
					q <= Q_A2;
				end
				else if (!ra_nib[ch]) begin
					if (ra_addr[ch] == r_stop(ch)) begin
						ra_on[ch]  <= 1'b0;
						ra_acc[ch] <= 12'd0;
						q <= Q_A2;
					end
					else if (pf_ok[ch]) begin
						ra_byte[ch] <= pf[ch];
						dat         <= pf[ch][7:4];
						ra_addr[ch] <= ra_addr[ch] + 14'd1;
						pf_ok[ch]   <= 1'b0;
						ra_nib[ch]  <= 1'b1;
						q <= Q_AD;
					end
				end
				else begin
					dat        <= ra_byte[ch][3:0];
					ra_nib[ch] <= 1'b0;
					q <= Q_AD;
				end
			end

			Q_AD: begin
				ra_acc[ch]  <= a_nacc;
				ra_step[ch] <= (a_nstep < 0) ? 6'd0 : (a_nstep > 8'sd48) ? 6'd48 : a_nstep[5:0];
				q <= Q_A2;
			end

			Q_A2: begin
				if (ch == 3'd5) q <= Q_B;
				else begin
					ch <= ch + 3'd1;
					q  <= Q_A;
				end
			end

			// ADPCM-B: advance the position; decode a nibble on overflow.
			Q_B: begin
				if (!b0[7] || b0[6] || !b_play) begin
					b_play <= 1'b0;
					q <= Q_OA;
					ch <= 3'd0;
					sumL <= 20'sd0;
					sumR <= 20'sd0;
				end
				else if ({1'b0, b_pos} + {1'b0, bdn} < 17'h10000) begin
					b_pos <= b_pos + bdn;
					q <= Q_OA;
					ch <= 3'd0;
					sumL <= 20'sd0;
					sumR <= 20'sd0;
				end
				else if (!b_nib && b0[5] && !pf_ok[6]) ;          // wait for the byte
				else begin
					b_pos <= b_pos + bdn;
					if (!b_nib) begin
						if (b0[5]) b_byte <= pf[6];
						dat <= b0[5] ? pf[6][7:4] : b_byte[7:4];
					end
					else dat <= b_byte[3:0];
					b_nib <= ~b_nib;
					q <= Q_B2;
				end
			end

			Q_B2: begin
				ch <= 3'd0;
				sumL <= 20'sd0;
				sumR <= 20'sd0;
				q <= Q_OA;
				if (!b_nib && b0[5]) begin                         // second nibble done
					if (b_addr == b_endad) begin
						if (b0[4]) begin                           // repeat
							b_eos  <= 1'b0;
							b_addr <= b_stad;
							b_nib  <= 1'b0;
							b_pos  <= 16'd0;
							pf_ok[6] <= 1'b0;
							b_prev <= 16'sd0;
							// ymfm restarts the accumulator and step, then
							// decodes this nibble from there
							b_acc  <= clamp16(b_sum0);
							b_step <= clampstep(b_nstep0);
						end
						else begin
							b_acc  <= 16'sd0;
							b_prev <= 16'sd0;
							b_play <= 1'b0;
							b_eos  <= 1'b1;
						end
					end
					else begin
						b_addr   <= (b_addr == b_limad) ? 24'd0 : b_addr + 24'd1;
						pf_ok[6] <= 1'b0;
						b_prev <= b_acc;
						b_acc  <= clamp16(b_sum);
						b_step <= clampstep(b_nstep);
					end
				end
				else begin
					b_prev <= b_acc;
					b_acc  <= clamp16(b_sum);
					b_step <= clampstep(b_nstep);
				end
			end

			// Rhythm outputs.
			Q_OA: begin
				if (vol < 7'd63) begin
					mA <= {{2{acc16[15]}}, acc16};
					mB <= {14'd0, vmul};
					q  <= Q_OA2;
				end
				else if (ch == 3'd5) q <= Q_OB1;
				else ch <= ch + 3'd1;
			end

			Q_OA2: begin
				// ((acc << 4) x mul) >> shift, low two bits cleared
				if (rlev[ch][7]) sumL <= sumL + (($signed(mP[19:0]) >>> vshf) & ~20'sd3);
				if (rlev[ch][6]) sumR <= sumR + (($signed(mP[19:0]) >>> vshf) & ~20'sd3);
				if (ch == 3'd5) q <= Q_OB1;
				else begin
					ch <= ch + 3'd1;
					q  <= Q_OA;
				end
			end

			// ADPCM-B output: (prev x (10000 - pos) + acc x pos) >> 16, x level >> 9.
			Q_OB1: begin
				mA   <= {{2{b_prev[15]}}, b_prev};
				mB   <= {1'b0, 17'h10000 - {1'b0, b_pos}};
				q    <= Q_OB2;
			end
			Q_OB2: begin
				bint <= mP[31:0];
				mA   <= {{2{b_acc[15]}}, b_acc};
				mB   <= {2'b00, b_pos};
				q    <= Q_OB3;
			end
			Q_OB3: begin
				mA   <= {{2{b_isum[31]}}, b_isum[31:16]};   // >>> 16
				mB   <= {10'd0, blevel};
				q    <= Q_OB4;
			end

			Q_OB4: begin
				bout <= mP[26:9];                          // >>> 9
				q    <= Q_MIX;
			end

			Q_MIX: begin : mix
				reg signed [20:0] fmh, l, r, bl, br, sl, sr;
				fmh = (fm_mute != 2'd0) ? 21'sd0 : {{6{fm_mono[15]}}, fm_mono[15:1]};   // 13 bits a channel
				bl  = b1[7] ? {{3{bout[17]}}, bout} : 21'sd0;
				br  = b1[6] ? {{3{bout[17]}}, bout} : 21'sd0;
				l   = fmh + {sumL[19], sumL} + bl;
				r   = fmh + {sumR[19], sumR} + br;
				l   = (l > 21'sd32767) ? 21'sd32767 : (l < -21'sd32768) ? -21'sd32768 : l;
				r   = (r > 21'sd32767) ? 21'sd32767 : (r < -21'sd32768) ? -21'sd32768 : r;
				sl  = {sumL[19], sumL} + bl;
				sr  = {sumR[19], sumR} + br;
				snd     <= l[16:0] + r[16:0];
				snd_fm  <= fmh[16:0] + fmh[16:0];
				snd_pcm <= sl[16:0] + sr[16:0];
				sample  <= 1'b1;
				q       <= Q_IDLE;
			end

			default: q <= Q_IDLE;
		endcase

		// ---- register side effects (after the sequencer, so they win) ----
		if (key_wr)
			for (i = 0; i < 6; i = i + 1)
				if (rkey[i]) begin
					ra_on[i] <= !rkey[7];
					if (!rkey[7]) begin                    // key on: from the start
						ra_addr[i] <= {1'b0, r_start(i[2:0])};
						ra_nib[i]  <= 1'b0;
						ra_acc[i]  <= 12'd0;
						ra_step[i] <= 6'd0;
						pf_ok[i]   <= 1'b0;
					end
				end
		if (b0_wr) begin
			if (b0[7]) begin                           // execute: start
				b_eos  <= 1'b0;
				b_play <= 1'b1;
				b_addr <= b0[5] ? b_stad : 24'd0;
				b_nib  <= 1'b0;
				b_pos  <= 16'd0;
				b_acc  <= 16'sd0;
				b_prev <= 16'sd0;
				b_step <= 15'd127;
				pf_ok[6] <= 1'b0;
			end
			else b_eos <= 1'b0;
			if (b0[0]) begin                           // reset
				b_play <= 1'b0;
				b_eos  <= 1'b0;
				b_brdy <= 1'b1;
				b_nib  <= 1'b0;
				b_pos  <= 16'd0;
				b_addr <= 24'd0;
				b_acc  <= 16'sd0;
				b_prev <= 16'sd0;
				b_step <= 15'd127;
				pf_ok[6] <= 1'b0;
			end
		end
	end
end

// ---------------------------------------------------------------------------
// Reads: 0 status (JT12: busy, timer flags), 1 data (ID at FF), 2 status B,
// 3 ADPCM-B data (not used: 0).

wire [7:0] st_b = {1'b0, 1'b0, b_play, 1'b0, b_brdy, b_eos, fm_dout[1:0]} & ~{3'b000, flag_ctl};

always @(posedge clk) begin
	case (addr)
		2'd0:    dout <= fm_dout;
		2'd1:    dout <= (!ahi && areg == 8'hFF) ? 8'h01 : 8'h00;
		2'd2:    dout <= st_b | {fm_dout[7], 7'd0};
		default: dout <= 8'h00;
	endcase
end

endmodule
