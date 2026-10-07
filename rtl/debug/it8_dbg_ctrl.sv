//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_dbg_ctrl.sv - diagnostic overlay, Controls page: what the trackball,
//  spinner, paddle and analog sticks send, and what reaches the game
//
//  Debug build only (OSD Debug > Diagnostic overlay > Trackball or
//  Analog). For setting up a trackball, spinner or analog controller: roll,
//  spin or push it and read the counts. Two pages of 24 columns, drawn by
//  it8_dbg_page.sv, so they read upright on vertical games too; numbers in
//  five characters (-9999 to 99999).
//
//  Trackball (16 rows):
//    MOUSE      X     Y  SPIN    MiSTer's mouse (ps2_mouse: trackballs and
//    FRAME                       most USB spinners) and its spinner input
//    PEAK                        (spinner_0: a device MiSTer.ini names in
//    ROLL                        spinner_vid/pid). As sent: FRAME in the
//    TOTAL                       last frame; PEAK the most in one frame;
//    MAXREP                      ROLL in the current or last roll
//    RATE                        (movement with no gap of 6 frames or
//                                more); TOTAL since cleared; MAXREP the
//                                largest single report; RATE reports a
//                                second.
//    GAME       X     Y          The trackball counters the game reads
//    FRAME                       (cb_trackball, mouse and stick), as
//    PEAK                        above, in the game's counts. DROP: mouse
//    ROLL                        counts dropped because more than a
//    TOTAL                       frame's worth was waiting (after the
//    DROP                        sideways multiplier). DIV: mouse counts
//    DIV                         per game count (OSD Trackball Speed);
//    SIDE                        SIDE: the sideways multiplier.
//
//  Analog (10 rows):
//    ANALOG   NOW   MIN   MAX    Paddle 0 to 255, sticks -127 to 127
//    PADDLE                      (MiSTer's joystick_l/r_analog of
//    P1 LX ... P2 RY             controllers 1 and 2, left and right
//                                sticks), now and the range since
//                                cleared.
//
//  clear zeroes the counts and restarts the ranges (OSD Clear control
//  counters, and every reset).
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_dbg_ctrl #(
	parameter CLK_HZ = 48000000,
	parameter BOX_X  = 8,
	parameter BOX_Y  = 8
)(
	input         clk,
	input         clear,
	input         frame,          // one clock at the start of vertical blanking

	input  [24:0] ps2_mouse,      // hps_io: [24] toggles per report
	input   [8:0] spinner,        // hps_io: [8] toggles per update, [7:0] signed
	input   [7:0] paddle,
	input  [15:0] ana_l0,         // hps_io: Y [15:8], X [7:0], signed
	input  [15:0] ana_r0,
	input  [15:0] ana_l1,
	input  [15:0] ana_r1,

	input   [7:0] track_x,        // cb_trackball
	input   [7:0] track_y,
	input  [15:0] drop_x,
	input  [15:0] drop_y,
	input   [3:0] div,
	input   [2:0] side,

	input         ce,             // raster, as it8_dbg_page
	input         de,
	input   [8:0] vis_x,
	input   [7:0] vis_y,
	input   [1:0] rot,
	input         page,           // 0 Trackball, 1 Analog
	output        pix,
	output        in_box
);

// ---------------------------------------------------------------------------
// Inputs.

reg        m_tog = 1'b0, s_tog = 1'b0;
reg  [7:0] tx_d = 8'd0, ty_d = 8'd0;

always @(posedge clk) begin
	m_tog <= ps2_mouse[24];
	s_tog <= spinner[8];
	tx_d  <= track_x;
	ty_d  <= track_y;
end

wire        m_ev = ps2_mouse[24] != m_tog;
wire        s_ev = spinner[8] != s_tog;
wire [15:0] m_dx = {{8{ps2_mouse[4]}}, ps2_mouse[15:8]};
wire [15:0] m_dy = {{8{ps2_mouse[5]}}, ps2_mouse[23:16]};
wire [15:0] s_d  = {{8{spinner[7]}}, spinner[7:0]};
wire  [7:0] t_dx = track_x - tx_d;
wire  [7:0] t_dy = track_y - ty_d;

// ---------------------------------------------------------------------------
// Counts.

wire [31:0] mx_fr, mx_pk, mx_rl, mx_to, mx_big;
wire [31:0] my_fr, my_pk, my_rl, my_to, my_big;
wire [31:0] sp_fr, sp_pk, sp_rl, sp_to, sp_big;
wire [31:0] gx_fr, gx_pk, gx_rl, gx_to;
wire [31:0] gy_fr, gy_pk, gy_rl, gy_to;

it8_dbg_axis ax_mx (.clk(clk), .clear(clear), .frame(frame), .ev(m_ev), .d(m_dx),
                    .fr(mx_fr), .peak(mx_pk), .roll(mx_rl), .total(mx_to), .big(mx_big));
it8_dbg_axis ax_my (.clk(clk), .clear(clear), .frame(frame), .ev(m_ev), .d(m_dy),
                    .fr(my_fr), .peak(my_pk), .roll(my_rl), .total(my_to), .big(my_big));
it8_dbg_axis ax_sp (.clk(clk), .clear(clear), .frame(frame), .ev(s_ev), .d(s_d),
                    .fr(sp_fr), .peak(sp_pk), .roll(sp_rl), .total(sp_to), .big(sp_big));
it8_dbg_axis ax_gx (.clk(clk), .clear(clear), .frame(frame), .ev(t_dx != 8'd0), .d({{8{t_dx[7]}}, t_dx}),
                    .fr(gx_fr), .peak(gx_pk), .roll(gx_rl), .total(gx_to), .big());
it8_dbg_axis ax_gy (.clk(clk), .clear(clear), .frame(frame), .ev(t_dy != 8'd0), .d({{8{t_dy[7]}}, t_dy}),
                    .fr(gy_fr), .peak(gy_pk), .roll(gy_rl), .total(gy_to), .big());

// Dropped mouse counts since cleared, taken at the frame pulse.
reg [15:0] dx_f = 16'd0, dy_f = 16'd0;
reg [31:0] dropx_t = 32'd0, dropy_t = 32'd0;

always @(posedge clk) begin
	if (clear) begin
		dx_f    <= drop_x;
		dy_f    <= drop_y;
		dropx_t <= 32'd0;
		dropy_t <= 32'd0;
	end
	else if (frame) begin
		dx_f    <= drop_x;
		dy_f    <= drop_y;
		dropx_t <= dropx_t + {16'd0, drop_x - dx_f};
		dropy_t <= dropy_t + {16'd0, drop_y - dy_f};
	end
end

// Reports a second.
localparam [25:0] SEC = CLK_HZ - 1;
reg [25:0] sec = 26'd0;
reg [15:0] m_cnt = 16'd0, s_cnt = 16'd0, m_rate = 16'd0, s_rate = 16'd0;

always @(posedge clk) begin
	if (sec == SEC) begin
		sec    <= 26'd0;
		m_rate <= m_cnt;
		s_rate <= s_cnt;
		m_cnt  <= {15'd0, m_ev};
		s_cnt  <= {15'd0, s_ev};
	end
	else begin
		sec   <= sec + 26'd1;
		m_cnt <= m_cnt + {15'd0, m_ev};
		s_cnt <= s_cnt + {15'd0, s_ev};
	end
end

// Analog ranges. Eight sticks' axes, in the page's order: controller 1 left
// X, Y, right X, Y, then controller 2's; 8 bits each, the first at the top.
wire  [7:0] pd_lo, pd_hi;
wire [63:0] a_now = {ana_l0[7:0], ana_l0[15:8], ana_r0[7:0], ana_r0[15:8],
                     ana_l1[7:0], ana_l1[15:8], ana_r1[7:0], ana_r1[15:8]};
wire [63:0] a_lo, a_hi;

it8_dbg_minmax #(.SIGNED(0)) mm_pd (.clk(clk), .clear(clear), .v(paddle), .lo(pd_lo), .hi(pd_hi));

// One page row a stick axis: now, lowest, highest, sign-extended.
wire [767:0] sticks;

genvar gi;
generate
	for (gi = 0; gi < 8; gi = gi + 1) begin : g_ana
		wire [7:0] now = a_now[8*(7-gi) +: 8];
		wire [7:0] lo, hi;
		it8_dbg_minmax #(.SIGNED(1)) mm (.clk(clk), .clear(clear), .v(now), .lo(lo), .hi(hi));
		assign a_lo[8*(7-gi) +: 8] = lo;
		assign a_hi[8*(7-gi) +: 8] = hi;
		assign sticks[96*(7-gi) +: 96] = {{24{now[7]}}, now, {24{lo[7]}}, lo, {24{hi[7]}}, hi};
	end
endgenerate

// ---------------------------------------------------------------------------
// The pages: 0 Trackball, 1 Analog; 24 columns, five-character numbers.

localparam [1:0] F_NO = 2'd0, F_S = 2'd1, F_U = 2'd2;
localparam [31:0] Z = 32'd0;

localparam N_ROWS = 16;
localparam FW     = 5;

localparam [8*24*2*N_ROWS-1:0] TEXT = {
	// Trackball page (16 rows)
	"MOUSE      X     Y  SPIN",
	"FRAME                   ",
	"PEAK                    ",
	"ROLL                    ",
	"TOTAL                   ",
	"MAXREP                  ",
	"RATE                    ",
	"                        ",
	"GAME       X     Y      ",
	"FRAME                   ",
	"PEAK                    ",
	"ROLL                    ",
	"TOTAL                   ",
	"DROP                    ",
	"DIV                     ",
	"SIDE                    ",
	// Analog page (10 rows, the rest unused)
	"ANALOG   NOW   MIN   MAX",
	"PADDLE                  ",
	"P1 LX                   ",
	"P1 LY                   ",
	"P1 RX                   ",
	"P1 RY                   ",
	"P2 LX                   ",
	"P2 LY                   ",
	"P2 RX                   ",
	"P2 RY                   ",
	"                        ",
	"                        ",
	"                        ",
	"                        ",
	"                        ",
	"                        "
};

localparam [6*2*N_ROWS-1:0] FMT = {
	// Trackball
	F_NO, F_NO, F_NO,
	F_S,  F_S,  F_S,
	F_U,  F_U,  F_U,
	F_S,  F_S,  F_S,
	F_S,  F_S,  F_S,
	F_U,  F_U,  F_U,
	F_U,  F_NO, F_U,
	F_NO, F_NO, F_NO,
	F_NO, F_NO, F_NO,
	F_S,  F_S,  F_NO,
	F_U,  F_U,  F_NO,
	F_S,  F_S,  F_NO,
	F_S,  F_S,  F_NO,
	F_U,  F_U,  F_NO,
	F_U,  F_U,  F_NO,
	F_U,  F_NO, F_NO,
	// Analog
	F_NO, F_NO, F_NO,
	F_U,  F_U,  F_U,
	F_S,  F_S,  F_S,
	F_S,  F_S,  F_S,
	F_S,  F_S,  F_S,
	F_S,  F_S,  F_S,
	F_S,  F_S,  F_S,
	F_S,  F_S,  F_S,
	F_S,  F_S,  F_S,
	F_S,  F_S,  F_S,
	{6{F_NO, F_NO, F_NO}}
};

wire [96*2*N_ROWS-1:0] vals = {
	// Trackball
	Z, Z, Z,
	mx_fr,  my_fr,  sp_fr,
	mx_pk,  my_pk,  sp_pk,
	mx_rl,  my_rl,  sp_rl,
	mx_to,  my_to,  sp_to,
	mx_big, my_big, sp_big,
	{16'd0, m_rate}, Z, {16'd0, s_rate},
	Z, Z, Z,
	Z, Z, Z,
	gx_fr,  gy_fr,  Z,
	gx_pk,  gy_pk,  Z,
	gx_rl,  gy_rl,  Z,
	gx_to,  gy_to,  Z,
	dropx_t, dropy_t, Z,
	{28'd0, div}, {28'd0, div}, Z,
	{29'd0, side}, Z, Z,
	// Analog
	Z, Z, Z,
	{24'd0, paddle}, {24'd0, pd_lo}, {24'd0, pd_hi},
	sticks,
	{6{Z, Z, Z}}
};

// The page is written two clocks after the frame pulse, once the frame's
// counts above have settled.
reg [1:0] frame_d = 2'b00;
always @(posedge clk) frame_d <= {frame_d[0], frame};

it8_dbg_page #(
	.N_PAGES (2),
	.N_ROWS  (N_ROWS),
	.FW      (FW),
	.BOX_X   (BOX_X),
	.BOX_Y   (BOX_Y),
	.TEXT    (TEXT),
	.FMT     (FMT),
	.ROWS    ({5'd16, 5'd10})
) pages (
	.clk    (clk),
	.frame  (frame_d[1]),
	.ce     (ce),
	.de     (de),
	.vis_x  (vis_x),
	.vis_y  (vis_y),
	.rot    (rot),
	.page   ({1'b0, page}),
	.vals   (vals),
	.pix    (pix),
	.in_box (in_box)
);

endmodule

//============================================================================
// One axis of counts: the last frame's sum, the largest frame (magnitude),
// the current or last roll (frames with movement, ended by 6 still frames),
// the total and the largest single step (magnitude). All are taken at the
// frame pulse, so the page's numbers agree with each other.

module it8_dbg_axis
(
	input             clk,
	input             clear,
	input             frame,
	input             ev,
	input      [15:0] d,              // signed step, on ev
	output reg [31:0] fr = 32'd0,     // signed
	output reg [31:0] peak = 32'd0,
	output reg [31:0] roll = 32'd0,   // signed
	output reg [31:0] total = 32'd0,  // signed
	output reg [31:0] big = 32'd0
);

reg  [31:0] acc = 32'd0;
reg  [31:0] tot = 32'd0, bigl = 32'd0;
reg   [2:0] quiet = 3'd6;

wire [31:0] d32  = {{16{d[15]}}, d};
wire [31:0] dmag = d[15] ? 32'd0 - d32 : d32;
wire [31:0] amag = acc[31] ? 32'd0 - acc : acc;

always @(posedge clk) begin
	if (clear) begin
		acc   <= 32'd0;
		fr    <= 32'd0;
		peak  <= 32'd0;
		roll  <= 32'd0;
		total <= 32'd0;
		big   <= 32'd0;
		tot   <= 32'd0;
		bigl  <= 32'd0;
		quiet <= 3'd6;
	end
	else begin
		if (ev) begin
			tot <= tot + d32;
			if (dmag > bigl) bigl <= dmag;
		end
		if (frame) begin
			acc   <= ev ? d32 : 32'd0;
			fr    <= acc;
			total <= tot;
			big   <= bigl;
			if (amag > peak) peak <= amag;
			if (acc != 32'd0) begin
				roll  <= (quiet == 3'd6) ? acc : roll + acc;
				quiet <= 3'd0;
			end
			else if (quiet != 3'd6) quiet <= quiet + 3'd1;
		end
		else if (ev) acc <= acc + d32;
	end
end

endmodule

//============================================================================
// Range of an 8-bit value since cleared (clear starts it at the value now).

module it8_dbg_minmax #(parameter SIGNED = 1)
(
	input        clk,
	input        clear,
	input  [7:0] v,
	output [7:0] lo,
	output [7:0] hi
);

// Compared as offset binary, so signed and unsigned share the compare.
localparam [7:0] OFS = SIGNED ? 8'h80 : 8'h00;

wire [7:0] vo = v ^ OFS;
reg  [7:0] lo_o = OFS, hi_o = OFS;          // 0

always @(posedge clk) begin
	if (clear) begin
		lo_o <= vo;
		hi_o <= vo;
	end
	else begin
		if (vo < lo_o) lo_o <= vo;
		if (vo > hi_o) hi_o <= vo;
	end
end

assign lo = lo_o ^ OFS;
assign hi = hi_o ^ OFS;

endmodule
