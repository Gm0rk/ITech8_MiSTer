//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  cb_trackball.sv - trackball counters for the Capcom Bowling board
//
//  The game reads a 4-bit count difference four times a frame (7000/7800,
//  reset at 6800), so the counters must not move more than 7 between two
//  reads or the difference wraps into the wrong direction. Mouse movement is
//  therefore collected and paid out at most one count per 0.6 ms per axis
//  (at most 7 per read), which is the fastest movement the game can see.
//  At most one frame's worth (28 counts, 17 ms) is kept waiting: anything
//  beyond is dropped, so the ball stops within a frame of the mouse instead
//  of playing out a backlog for up to 0.6 s, while a mouse that reports only
//  every 8 ms (125 Hz) still keeps the counters moving at full rate (D-030).
//  Joystick directions step the counters at a fixed rate.
//
//  Directions as MAME (capbowl.cpp): Y is reversed, so moving the mouse or
//  stick up counts Y up; right counts X up.
//
//  per_frame is for Strata Bowling, which reads 8-bit counts once a frame
//  (its NMI handler) and clears them: up to about 100 counts per frame are
//  paid out (one per 0.17 ms), with at most a frame's worth (100) waiting,
//  and the stick steps every 0.5 ms.
//
//  speed: 0 normal (2 mouse counts per step), 1 fast (1), 2 slow (4).
//  gain, when not 0, replaces it for the mouse: game counts per mouse count
//  in 1/256 (128 = Normal), the debug build's calibrated gain (D-044);
//  gain_x, when not 0, replaces gain and the sideways multiplier for the
//  mouse's X (the calibrated sideways gain, D-045). The
//  mouse is collected in 1/256 game counts either way: a report adds its
//  counts times the gain (256 / speed's mouse counts per step), and a step
//  is paid out for each 256, which is exactly the old arithmetic scaled up
//  for the three speeds.
//
//  drop_x / drop_y count the game counts the frame's-worth limit dropped
//  (after the sideways multiplier), wrapping, for the debug build's
//  Trackball page (it8_dbg_ctrl.sv); nothing else uses them.
//
//  side multiplies the mouse's sideways (X) counts by 1 to 4 before they
//  are paid out (OSD Trackball Sideways, D-040), for the bowling games that
//  halve the sideways axis themselves. The pacing above still applies, so
//  the counters never move faster than the game can read them; only slower
//  movement gains. The stick is not affected.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module cb_trackball
(
	input            clk,             // 48 MHz
	input            reset,
	input     [24:0] ps2_mouse,       // hps_io: [24] toggles per packet
	input            up,
	input            down,
	input            left,
	input            right,
	input      [1:0] speed,
	input     [10:0] gain,            // 0: speed; else game counts per mouse count x 256
	input     [10:0] gain_x,          // 0: gain and side; else X's own gain, as gain
	input      [1:0] side,            // sideways multiplier - 1 (0: x1 .. 3: x4)
	input            per_frame,       // Strata Bowling pacing (see above)
	output reg [7:0] x,
	output reg [7:0] y,
	output    [15:0] drop_x,
	output    [15:0] drop_y
);

localparam [15:0] PACE    = 16'd28800;        // 0.6 ms: one mouse step
localparam [17:0] JOY     = 18'd57600;        // 1.2 ms: one joystick step (normal)
localparam [15:0] PACE_PF = 16'd8000;         // per_frame: 0.17 ms
localparam [17:0] JOY_PF  = 18'd24000;        // per_frame: 0.5 ms

wire [15:0] pace_len = per_frame ? PACE_PF : PACE;
wire [17:0] joy_base = per_frame ? JOY_PF  : JOY;

wire [17:0] joy_period = (speed == 2'd1) ? (joy_base >> 1) : (speed == 2'd2) ? (joy_base << 1) : joy_base;

// Game counts per mouse count, x 256: the gain, or Fast 256, Normal 128,
// Slow 64.
wire [10:0] g = (gain != 11'd0)   ? gain :
                (speed == 2'd1)   ? 11'd256 :
                (speed == 2'd2)   ? 11'd64 : 11'd128;

reg        tog_d;
reg signed [15:0] acc_x, acc_y;               // waiting game counts x 256
reg [15:0] pace;
reg [17:0] jcnt;
reg [23:0] drop_xf = 24'd0, drop_yf = 24'd0;  // dropped game counts x 256

assign drop_x = drop_xf[23:8];
assign drop_y = drop_yf[23:8];

wire signed [11:0] mdx1 = {{3{ps2_mouse[4]}}, ps2_mouse[4], ps2_mouse[15:8]};
wire signed [11:0] mdx  = (side == 2'd0) ? mdx1 :
                          (side == 2'd1) ? (mdx1 <<< 1) :
                          (side == 2'd2) ? (mdx1 + (mdx1 <<< 1)) : (mdx1 <<< 2);
wire signed [11:0] mdy  = {{3{ps2_mouse[5]}}, ps2_mouse[5], ps2_mouse[23:16]};

wire signed [22:0] gx = (gain_x != 11'd0) ? mdx1 * $signed({1'b0, gain_x}) : mdx * $signed({1'b0, g});
wire signed [22:0] gy = mdy * $signed({1'b0, g});

// Most kept waiting: a frame's worth of steps (28, or 100 with per_frame).
wire signed [22:0] lim = per_frame ? 23'sd25600 : 23'sd7168;

wire signed [22:0] sum_x = {{7{acc_x[15]}}, acc_x} + gx;
wire signed [22:0] sum_y = {{7{acc_y[15]}}, acc_y} + gy;

function signed [15:0] clamp(input signed [22:0] v, input signed [22:0] l);
	clamp = (v > l) ? l[15:0] : (v < -l) ? -l[15:0] : v[15:0];
endfunction

// What the limit cuts off a new sum.
function [23:0] excess(input signed [22:0] v, input signed [22:0] l);
	reg signed [22:0] e;
	begin
		e = (v > l) ? v - l : (v < -l) ? -l - v : 23'sd0;
		excess = {1'b0, e};
	end
endfunction

always @(posedge clk) begin
	tog_d <= ps2_mouse[24];
	if (reset) begin
		acc_x <= 16'sd0;
		acc_y <= 16'sd0;
		pace  <= 16'd0;
		jcnt  <= 18'd0;
	end
	else begin
		pace <= (pace >= pace_len - 16'd1) ? 16'd0 : pace + 16'd1;
		jcnt <= (jcnt >= joy_period - 18'd1) ? 18'd0 : jcnt + 18'd1;

		if (ps2_mouse[24] != tog_d) begin
			acc_x   <= clamp(sum_x, lim);
			acc_y   <= clamp(sum_y, lim);
			drop_xf <= drop_xf + excess(sum_x, lim);
			drop_yf <= drop_yf + excess(sum_y, lim);
		end
		else if (pace == 16'd0) begin
			if (acc_x >= 16'sd256)       begin x <= x + 8'd1; acc_x <= acc_x - 16'sd256; end
			else if (acc_x <= -16'sd256) begin x <= x - 8'd1; acc_x <= acc_x + 16'sd256; end
			if (acc_y >= 16'sd256)       begin y <= y + 8'd1; acc_y <= acc_y - 16'sd256; end
			else if (acc_y <= -16'sd256) begin y <= y - 8'd1; acc_y <= acc_y + 16'sd256; end
		end

		if (jcnt == 18'd0) begin
			if (right && !left) x <= x + 8'd1;
			if (left && !right) x <= x - 8'd1;
			if (up && !down)    y <= y + 8'd1;
			if (down && !up)    y <= y - 8'd1;
		end
	end
end

endmodule
