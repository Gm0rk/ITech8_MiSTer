//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_dbg_cal.sv - debug build: trackball calibration (D-044, D-045)
//
//  OSD Debug > Calibrate trackball. The player makes three throws (or golf
//  swings) as hard as in play; each is measured the way the game measures a
//  throw, in mouse counts, and the gain is chosen that puts the median a
//  little past the most the game uses. In the bowling games three sideways
//  rolls follow, and a sideways gain is chosen that carries the ball about
//  half the lane with the median roll. Both gains are written to the OSD
//  (Debug > Trackball gain, Trackball sideways gain) through hps_io's
//  status_set, and cb_trackball uses them for the mouse in place of
//  Trackball Speed and Trackball Sideways.
//
//  What the games use (their program ROMs, factory settings):
//    kind 1  Capcom / Coors Light Bowling, Strata Bowling: the forward counts
//            of the last 8 frames; top speed at 80 (TRACKBALL TYPE 3,
//            SENSITIVITY factory). Goal 100 game counts in the best 8 frames.
//            Sideways 0.25 of a lane unit a count: Capcom Bowling's lane is
//            384 counts edge to edge, Strata Bowling's 196 from the middle to
//            an edge. Sideways goal 192 a roll.
//    kind 2  Bowl-O-Rama: the last 4 frames times the trackball size factor;
//            top speed at 77 counts (2.5 INCH). Goal 96 in the best 4. The
//            lane is 186 counts: sideways goal 93.
//    kind 3  Golden Tee Golf and Golden Tee Golf II (trackball): the counts
//            in the frame the club reaches the ball; full power at 27.
//            Goal 70 in the best 2 frames (35 a frame). No sideways step:
//            sideways follows the forward gain.
//  A throw starts with the first forward or back movement and ends after
//  half a second without any; its result is the best window of its forward
//  (Y) counts. A sideways roll starts with the first sideways movement and
//  ends the same way; its result is its sideways (X) total. Under 8 counts
//  it is too slow and is asked again.
//
//  Gain step n (1-49): 2^((n-25)/8) of Normal, 12 % to 800 %; game counts
//  per mouse count x 256 = 128 x that (gain_of).
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_dbg_cal
(
	input             clk,
	input             reset,
	input             start,          // one clock: begin
	input             frame,          // one clock a frame
	input             ev,             // a mouse report
	input      [15:0] dy,             // its forward counts, signed
	input      [15:0] dx,             // its sideways counts, signed
	input       [1:0] kind,           // 0 not a trackball game, 1-3 as above
	output reg        active = 1'b0,  // show the calibration page
	output reg  [3:0] msg_a = 4'd0,   // page lines (it8_dbg_ctrl's MSGS)
	output reg  [3:0] msg_b = 4'd0,
	output     [31:0] v_live,         // the throw or roll under way: forward
	output     [31:0] v_live_x,       //   or sideways (the other 0)
	output     [31:0] v_r1,
	output     [31:0] v_r2,
	output     [31:0] v_r3,
	output     [31:0] v_s1,
	output     [31:0] v_s2,
	output     [31:0] v_s3,
	output     [31:0] v_goal,
	output     [31:0] v_goal_x,
	output     [31:0] v_gain,
	output     [31:0] v_gain_x,
	output reg  [5:0] gain_n = 6'd0,
	output reg  [5:0] gain_x_n = 6'd0,  // 0: off (golf)
	output reg        wr = 1'b0,      // one clock: write gain_n and gain_x_n to the OSD

	input       [5:0] sel,            // the OSD's gain steps (0 off)
	input       [5:0] sel_x,
	output     [10:0] sel_gain,       // their game counts per mouse count x 256, 0 off
	output     [10:0] sel_gain_x
);

// Messages (it8_dbg_ctrl.sv MSGS).
localparam [3:0] M_NONE = 4'd0, M_NOTB = 4'd1, M_BOWL = 4'd2, M_BOR = 4'd3, M_GOLF = 4'd4,
                 M_THROW = 4'd5, M_SWING = 4'd6, M_SLOW = 4'd7, M_DONE = 4'd8, M_SIDE = 4'd9;

function [10:0] gain_of(input [5:0] n);
	case (n)
		6'd1: gain_of = 11'd16;
		6'd2: gain_of = 11'd17;
		6'd3: gain_of = 11'd19;
		6'd4: gain_of = 11'd21;
		6'd5: gain_of = 11'd23;
		6'd6: gain_of = 11'd25;
		6'd7: gain_of = 11'd27;
		6'd8: gain_of = 11'd29;
		6'd9: gain_of = 11'd32;
		6'd10: gain_of = 11'd35;
		6'd11: gain_of = 11'd38;
		6'd12: gain_of = 11'd41;
		6'd13: gain_of = 11'd45;
		6'd14: gain_of = 11'd49;
		6'd15: gain_of = 11'd54;
		6'd16: gain_of = 11'd59;
		6'd17: gain_of = 11'd64;
		6'd18: gain_of = 11'd70;
		6'd19: gain_of = 11'd76;
		6'd20: gain_of = 11'd83;
		6'd21: gain_of = 11'd91;
		6'd22: gain_of = 11'd99;
		6'd23: gain_of = 11'd108;
		6'd24: gain_of = 11'd117;
		6'd25: gain_of = 11'd128;
		6'd26: gain_of = 11'd140;
		6'd27: gain_of = 11'd152;
		6'd28: gain_of = 11'd166;
		6'd29: gain_of = 11'd181;
		6'd30: gain_of = 11'd197;
		6'd31: gain_of = 11'd215;
		6'd32: gain_of = 11'd235;
		6'd33: gain_of = 11'd256;
		6'd34: gain_of = 11'd279;
		6'd35: gain_of = 11'd304;
		6'd36: gain_of = 11'd332;
		6'd37: gain_of = 11'd362;
		6'd38: gain_of = 11'd395;
		6'd39: gain_of = 11'd431;
		6'd40: gain_of = 11'd470;
		6'd41: gain_of = 11'd512;
		6'd42: gain_of = 11'd558;
		6'd43: gain_of = 11'd609;
		6'd44: gain_of = 11'd664;
		6'd45: gain_of = 11'd724;
		6'd46: gain_of = 11'd790;
		6'd47: gain_of = 11'd861;
		6'd48: gain_of = 11'd939;
		6'd49: gain_of = 11'd1024;
		default: gain_of = 11'd128;
	endcase
endfunction

function [9:0] pct_of(input [5:0] n);
	case (n)
		6'd1: pct_of = 10'd12;
		6'd2: pct_of = 10'd14;
		6'd3: pct_of = 10'd15;
		6'd4: pct_of = 10'd16;
		6'd5: pct_of = 10'd18;
		6'd6: pct_of = 10'd19;
		6'd7: pct_of = 10'd21;
		6'd8: pct_of = 10'd23;
		6'd9: pct_of = 10'd25;
		6'd10: pct_of = 10'd27;
		6'd11: pct_of = 10'd30;
		6'd12: pct_of = 10'd32;
		6'd13: pct_of = 10'd35;
		6'd14: pct_of = 10'd39;
		6'd15: pct_of = 10'd42;
		6'd16: pct_of = 10'd46;
		6'd17: pct_of = 10'd50;
		6'd18: pct_of = 10'd55;
		6'd19: pct_of = 10'd59;
		6'd20: pct_of = 10'd65;
		6'd21: pct_of = 10'd71;
		6'd22: pct_of = 10'd77;
		6'd23: pct_of = 10'd84;
		6'd24: pct_of = 10'd92;
		6'd25: pct_of = 10'd100;
		6'd26: pct_of = 10'd109;
		6'd27: pct_of = 10'd119;
		6'd28: pct_of = 10'd130;
		6'd29: pct_of = 10'd141;
		6'd30: pct_of = 10'd154;
		6'd31: pct_of = 10'd168;
		6'd32: pct_of = 10'd183;
		6'd33: pct_of = 10'd200;
		6'd34: pct_of = 10'd218;
		6'd35: pct_of = 10'd238;
		6'd36: pct_of = 10'd259;
		6'd37: pct_of = 10'd283;
		6'd38: pct_of = 10'd308;
		6'd39: pct_of = 10'd336;
		6'd40: pct_of = 10'd367;
		6'd41: pct_of = 10'd400;
		6'd42: pct_of = 10'd436;
		6'd43: pct_of = 10'd476;
		6'd44: pct_of = 10'd519;
		6'd45: pct_of = 10'd566;
		6'd46: pct_of = 10'd617;
		6'd47: pct_of = 10'd673;
		6'd48: pct_of = 10'd734;
		6'd49: pct_of = 10'd800;
		default: pct_of = 10'd0;
	endcase
endfunction

// ---------------------------------------------------------------------------
// Forward counts of the last 8 frames, newest first, and the last frame's
// sideways counts.

reg  [15:0] facc = 16'd0, xacc = 16'd0, hx0 = 16'd0;
reg  [15:0] h0 = 16'd0, h1 = 16'd0, h2 = 16'd0, h3 = 16'd0, h4 = 16'd0, h5 = 16'd0, h6 = 16'd0, h7 = 16'd0;
reg         fr_d = 1'b0;

always @(posedge clk) begin
	fr_d <= frame;
	if (frame) begin
		facc <= ev ? dy : 16'd0;
		xacc <= ev ? dx : 16'd0;
		hx0  <= xacc;
		{h7, h6, h5, h4, h3, h2, h1, h0} <= {h6, h5, h4, h3, h2, h1, h0, facc};
	end
	else if (ev) begin
		facc <= facc + dy;
		xacc <= xacc + dx;
	end
end

function [19:0] sx(input [15:0] v);
	sx = {{4{v[15]}}, v};
endfunction

wire [19:0] sum2 = sx(h0) + sx(h1);
wire [19:0] sum4 = sum2 + sx(h2) + sx(h3);
wire [19:0] sum8 = sum4 + sx(h4) + sx(h5) + sx(h6) + sx(h7);
wire [19:0] win  = (kind == 2'd3) ? sum2 : (kind == 2'd2) ? sum4 : sum8;
wire [15:0] winp = win[19] ? 16'd0 : (win[19:16] != 4'd0) ? 16'hFFFF : win[15:0];   // forward part, clipped

wire [15:0] goal   = (kind == 2'd3) ? 16'd70 : (kind == 2'd2) ? 16'd96 : 16'd100;
wire [15:0] goal_x = (kind == 2'd3) ? 16'd0  : (kind == 2'd2) ? 16'd93 : 16'd192;

// ---------------------------------------------------------------------------
// The sequence: three throws (ph 0), then three sideways rolls (ph 1).

localparam [2:0] S_IDLE = 3'd0, S_WAIT = 3'd1, S_MOVE = 3'd2, S_CALC = 3'd3, S_DONE = 3'd4;

reg   [2:0] st = S_IDLE;
reg         ph = 1'b0;
reg   [1:0] k = 2'd0;
reg  [15:0] best = 16'd0;
reg  [19:0] xsum = 20'd0;
reg  [15:0] r1 = 16'd0, r2 = 16'd0, r3 = 16'd0, s1 = 16'd0, s2 = 16'd0, s3 = 16'd0, med = 16'd0;
reg   [4:0] quiet = 5'd0;
reg   [9:0] hold = 10'd0;              // frames the result stays up
reg   [5:0] n = 6'd1, nbest = 6'd25;
reg  [31:0] ebest = 32'hFFFFFFFF;
reg         cx = 1'b0;                 // searching for the sideways step

function [15:0] median3(input [15:0] a, input [15:0] b, input [15:0] c);
	reg [15:0] lo, hi;
	begin
		lo = (a < b) ? a : b;
		hi = (a < b) ? b : a;
		median3 = (c < lo) ? lo : (c > hi) ? hi : c;
	end
endfunction

wire [19:0] xmag  = xsum[19] ? 20'd0 - xsum : xsum;
wire [15:0] xmagc = (xmag[19:16] != 4'd0) ? 16'hFFFF : xmag[15:0];

wire [31:0] prod = {16'd0, med} * {21'd0, gain_of(n)};
wire [31:0] want = {8'd0, cx ? goal_x : goal, 8'd0};
wire [31:0] err  = (prod > want) ? prod - want : want - prod;

wire [3:0] m_prompt = ph ? M_SIDE : (kind == 2'd3) ? M_SWING : M_THROW;
wire       moved    = ph ? (hx0 != 16'd0) : (h0 != 16'd0);

always @(posedge clk) begin
	wr <= 1'b0;
	if (reset) begin
		st     <= S_IDLE;
		active <= 1'b0;
	end
	else if (start) begin
		active <= 1'b1;
		ph     <= 1'b0;
		k      <= 2'd0;
		{r1, r2, r3, s1, s2, s3} <= 96'd0;
		best   <= 16'd0;
		if (kind == 2'd0) begin
			msg_a <= M_NOTB;
			msg_b <= M_NONE;
			hold  <= 10'd300;
			st    <= S_DONE;
		end
		else begin
			msg_a <= (kind == 2'd3) ? M_GOLF : (kind == 2'd2) ? M_BOR : M_BOWL;
			msg_b <= (kind == 2'd3) ? M_SWING : M_THROW;
			st    <= S_WAIT;
		end
	end
	else case (st)
		S_WAIT: if (fr_d && moved) begin
			best  <= ph ? ((hx0[15] ? 16'd0 - hx0 : hx0)) : winp;
			xsum  <= sx(hx0);
			quiet <= 5'd0;
			msg_b <= m_prompt;
			st    <= S_MOVE;
		end

		S_MOVE: if (fr_d) begin
			if (ph) begin
				xsum <= xsum + sx(hx0);
				best <= xmagc;
			end
			else if (winp > best) best <= winp;
			if (moved) quiet <= 5'd0;
			else if (quiet != 5'd29) quiet <= quiet + 5'd1;
			else if (best < 16'd8) begin
				msg_b <= M_SLOW;
				st    <= S_WAIT;
			end
			else begin
				case ({ph, k})
					3'd0:    r1 <= best;
					3'd1:    r2 <= best;
					3'd2:    r3 <= best;
					3'd4:    s1 <= best;
					3'd5:    s2 <= best;
					default: s3 <= best;
				endcase
				if (k != 2'd2) begin
					k  <= k + 2'd1;
					st <= S_WAIT;
				end
				else if (!ph && kind != 2'd3) begin
					ph    <= 1'b1;
					k     <= 2'd0;
					best  <= 16'd0;
					msg_b <= M_SIDE;
					st    <= S_WAIT;
				end
				else begin
					cx <= 1'b0;
					n  <= 6'd0;
					st <= S_CALC;
				end
			end
		end

		// n 0 takes the median; 1-49 try each gain step. Forward first, then
		// (bowling) sideways.
		S_CALC: begin
			if (n == 6'd0) begin
				med   <= cx ? median3(s1, s2, s3) : median3(r1, r2, r3);
				ebest <= 32'hFFFFFFFF;
				n     <= 6'd1;
			end
			else begin
				if (err < ebest) begin
					ebest <= err;
					nbest <= n;
				end
				if (n != 6'd49) n <= n + 6'd1;
				else if (!cx) begin
					gain_n <= (err < ebest) ? n : nbest;
					if (kind == 2'd3) begin
						gain_x_n <= 6'd0;
						wr       <= 1'b1;
						msg_b    <= M_DONE;
						hold     <= 10'd600;
						st       <= S_DONE;
					end
					else begin
						cx <= 1'b1;
						n  <= 6'd0;
					end
				end
				else begin
					gain_x_n <= (err < ebest) ? n : nbest;
					wr       <= 1'b1;
					msg_b    <= M_DONE;
					hold     <= 10'd600;
					st       <= S_DONE;
				end
			end
		end

		S_DONE: if (fr_d) begin
			if (hold != 10'd0) hold <= hold - 10'd1;
			else begin
				active <= 1'b0;
				st     <= S_IDLE;
			end
		end

		default: ;
	endcase
end

assign sel_gain   = (sel   == 6'd0) ? 11'd0 : gain_of((sel   > 6'd49) ? 6'd49 : sel);
assign sel_gain_x = (sel_x == 6'd0) ? 11'd0 : gain_of((sel_x > 6'd49) ? 6'd49 : sel_x);

assign v_live   = ph ? 32'd0 : {16'd0, best};
assign v_live_x = ph ? {16'd0, best} : 32'd0;
assign v_r1     = {16'd0, r1};
assign v_r2     = {16'd0, r2};
assign v_r3     = {16'd0, r3};
assign v_s1     = {16'd0, s1};
assign v_s2     = {16'd0, s2};
assign v_s3     = {16'd0, s3};
assign v_goal   = {16'd0, goal};
assign v_goal_x = {16'd0, goal_x};
assign v_gain   = {22'd0, pct_of(gain_n)};
assign v_gain_x = {22'd0, pct_of(gain_x_n)};

endmodule
