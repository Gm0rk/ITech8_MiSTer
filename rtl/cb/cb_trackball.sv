//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  cb_trackball.sv - trackball counters for the Capcom Bowling board
//
//  The game reads a 4-bit count difference four times a frame (7000/7800,
//  reset at 6800), so the counters must not move more than 7 between two
//  reads or the difference wraps into the wrong direction. Mouse movement is
//  therefore collected and paid out at most one count per 0.6 ms per axis
//  (at most 7 per read); a big flick plays out over a few frames instead of
//  being lost. Joystick directions step the counters at a fixed rate.
//
//  Directions as MAME (capbowl.cpp): Y is reversed, so moving the mouse or
//  stick up counts Y up; right counts X up.
//
//  per_frame is for Strata Bowling, which reads 8-bit counts once a frame
//  (its NMI handler) and clears them: up to about 100 counts per frame are
//  paid out (one per 0.17 ms), and the stick steps every 0.5 ms.
//
//  speed: 0 normal (2 mouse counts per step), 1 fast (1), 2 slow (4).
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
	input            per_frame,       // Strata Bowling pacing (see above)
	output reg [7:0] x,
	output reg [7:0] y
);

localparam [15:0] PACE    = 16'd28800;        // 0.6 ms: one mouse step
localparam [17:0] JOY     = 18'd57600;        // 1.2 ms: one joystick step (normal)
localparam [15:0] PACE_PF = 16'd8000;         // per_frame: 0.17 ms
localparam [17:0] JOY_PF  = 18'd24000;        // per_frame: 0.5 ms

wire [15:0] pace_len = per_frame ? PACE_PF : PACE;
wire [17:0] joy_base = per_frame ? JOY_PF  : JOY;

wire [3:0] div = (speed == 2'd1) ? 4'd1 : (speed == 2'd2) ? 4'd4 : 4'd2;
wire [17:0] joy_period = (speed == 2'd1) ? (joy_base >> 1) : (speed == 2'd2) ? (joy_base << 1) : joy_base;

reg        tog_d;
reg signed [11:0] acc_x, acc_y;
reg [15:0] pace;
reg [17:0] jcnt;

wire signed [11:0] mdx = {{3{ps2_mouse[4]}}, ps2_mouse[4], ps2_mouse[15:8]};
wire signed [11:0] mdy = {{3{ps2_mouse[5]}}, ps2_mouse[5], ps2_mouse[23:16]};
wire signed [11:0] dv  = $signed({8'd0, div});

function signed [11:0] clamp(input signed [12:0] v);
	clamp = (v > 13'sd1023) ? 12'sd1023 : (v < -13'sd1023) ? -12'sd1023 : v[11:0];
endfunction

always @(posedge clk) begin
	tog_d <= ps2_mouse[24];
	if (reset) begin
		acc_x <= 12'sd0;
		acc_y <= 12'sd0;
		pace  <= 16'd0;
		jcnt  <= 18'd0;
	end
	else begin
		pace <= (pace >= pace_len - 16'd1) ? 16'd0 : pace + 16'd1;
		jcnt <= (jcnt >= joy_period - 18'd1) ? 18'd0 : jcnt + 18'd1;

		if (ps2_mouse[24] != tog_d) begin
			acc_x <= clamp(acc_x + mdx);
			acc_y <= clamp(acc_y + mdy);
		end
		else if (pace == 16'd0) begin
			if (acc_x >= dv)       begin x <= x + 8'd1; acc_x <= acc_x - dv; end
			else if (acc_x <= -dv) begin x <= x - 8'd1; acc_x <= acc_x + dv; end
			if (acc_y >= dv)       begin y <= y + 8'd1; acc_y <= acc_y - dv; end
			else if (acc_y <= -dv) begin y <= y - 8'd1; acc_y <= acc_y + dv; end
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
