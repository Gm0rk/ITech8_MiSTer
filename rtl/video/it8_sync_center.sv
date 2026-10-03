//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_sync_center.sv - sync placed so the picture is centred on a CRT
//
//  The boards put their sync pulses where the game programs the TMS34061,
//  each a little differently, so on a standard 15 kHz screen their pictures
//  sat up to 2 us left of centre and up to 4 lines off (D-035). This module
//  makes new sync pulses at the standard place around the picture the board
//  is showing, and leaves the picture alone:
//
//  * HSync: 4.75 us (38 dots at 8 MHz, 28 at 6 MHz), starting 35.75 us
//    before the middle of the active line, as broadcast timing puts the
//    middle of a 52.7 us picture 9.4 + 26.3 us after the sync's leading edge.
//  * VSync: 3 lines, starting 138 lines before the middle of the active
//    lines, as 240-line broadcast timing does (3 of sync, 15 of back porch,
//    then 120 lines to the middle), its edges on HSync's leading edges;
//    a line later with vlate, for a picture sent a line late.
//
//  pic_dots is the width of the picture in dots, for CRT Adjust's Auto-Fill.
//
//  vb_out is VBlank for the output line each new HSync begins, set with the
//  pulse: what a line buffer that samples VBlank at HSync needs (CRT Adjust),
//  now that HSync comes before the board's line starts.
//
//  Positions come from the board's own blanking: the line length and the
//  active dots are measured every line (from the board's HSync), the frame
//  length and the active lines every frame (from the board's VBlank, taken
//  at the first active dot of each line). A new pulse never starts inside
//  the picture. Until a line and a frame have been measured, and whenever
//  the measurements stop making sense, the board's own sync passes through.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_sync_center
(
	input             clk,
	input             ce,             // dot enable; inputs stable while high
	input             dot6,           // 6 MHz dots (6809 boards), else 8 MHz
	input             hs_in,          // the board's sync and blanking
	input             vs_in,
	input             hb_in,
	input             vb_in,
	input             vlate,          // the picture is sent a line late (CRT Adjust)
	output            hs_out,         // centred sync (or hs_in / vs_in)
	output            vs_out,
	output            vb_out,         // VBlank of the line hs_out begins
	output            centred,        // the outputs are the new pulses
	output reg [10:0] pic_dots        // dots in the picture's line, 0 until measured
);

localparam [11:0] T2_8 = 12'd572;     // 2 x 35.75 us in 8 MHz dots
localparam [11:0] T2_6 = 12'd429;     // 2 x 35.75 us in 6 MHz dots
localparam [10:0] HW_8 = 11'd38;      // HSync width, 4.75 us
localparam [10:0] HW_6 = 11'd28;      // 4.67 us
localparam [9:0]  VC   = 10'd138;     // lines from VSync to the middle
localparam [1:0]  VW   = 2'd3;        // VSync lines

// ---------------------------------------------------------------------------
// Horizontal measurement, in dots from the board's HSync leading edge.

reg        hs_d = 1'b0, hb_d = 1'b1;
reg [10:0] p   = 11'd0;               // this dot's position
reg [10:0] len = 11'd0;               // dots in the last whole line
reg [10:0] a0  = 11'd0;               // first active dot
reg [10:0] a1  = 11'd0;               // first blank dot after the picture
reg  [1:0] n_len = 2'd0;              // HSync leading edges seen (to 2)
reg        got_a0 = 1'b0, got_a1 = 1'b0;

wire        hs_rise = hs_in & ~hs_d;
wire [10:0] pos     = hs_rise ? 11'd0 : p + 11'd1;

always @(posedge clk) begin
	if (ce) begin
		hs_d <= hs_in;
		hb_d <= hb_in;
		p    <= pos;
		if (hs_rise) begin
			len <= p + 11'd1;
			if (n_len != 2'd2) n_len <= n_len + 2'd1;
		end
		if (!hb_in &&  hb_d) begin a0 <= pos; got_a0 <= 1'b1; end
		if ( hb_in && !hb_d) begin a1 <= pos; got_a1 <= 1'b1; end
	end
end

// New HSync position, worked out over a few clocks (the inputs change at
// most once a line): s = middle of the picture - 35.75 us, taken modulo the
// line. s < 0 (the usual case) puts the pulse in the previous line, ahead
// of the board's own sync. The register is set one dot early, so that the
// pulse is seen from dot s.
reg  [11:0] c2;
reg  signed [12:0] s2;
reg  [10:0] s_at, trig;
reg         s_neg, hvalid = 1'b0;

wire signed [11:0] s = s2[12:1];      // floor(s2 / 2)
wire        [10:0] s_wrap = len + s[10:0];

always @(posedge clk) begin
	c2     <= {1'b0, a0} + {1'b0, a1};
	s2     <= $signed({1'b0, c2}) - $signed({1'b0, dot6 ? T2_6 : T2_8});
	s_neg  <= s < 0;
	s_at   <= (s >= 0)         ? s[10:0] :
	          (s_wrap < a1)    ? a1      : s_wrap;
	trig   <= (s_at == 11'd0) ? len - 11'd1 : s_at - 11'd1;
	hvalid <= (n_len == 2'd2) && got_a0 && got_a1 && (a0 < a1) && (a1 < len) &&
	          ({1'b0, len} > {dot6 ? HW_6 : HW_8, 1'b0});
	pic_dots <= hvalid ? a1 - a0 : 11'd0;
end

// ---------------------------------------------------------------------------
// Vertical measurement, in board lines from the first active line. VBlank is
// read at the first active dot of each line, well clear of the line's edges.

reg  [9:0] q    = 10'd0;              // board lines since the first active one
reg  [9:0] fl   = 10'd0;              // lines in the last whole frame
reg  [9:0] na   = 10'd0;              // active lines
reg        vbl_d = 1'b1;
reg  [1:0] n_fl = 2'd0;               // first active lines seen (to 2)
reg        got_na = 1'b0;

always @(posedge clk) begin
	if (ce && hvalid) begin
		if (hs_rise) q <= q + 10'd1;
		else if (pos == a0) begin
			vbl_d <= vb_in;
			if (!vb_in && vbl_d) begin
				fl <= q;
				q  <= 10'd0;
				if (n_fl != 2'd2) n_fl <= n_fl + 2'd1;
			end
			if (vb_in && !vbl_d) begin
				na     <= q;
				got_na <= 1'b1;
			end
		end
	end
end

// VSync starts on output line q_vs: the middle of the picture less 138
// lines, modulo the frame, kept off the picture and its last three lines
// off the next picture; a line later when the picture itself is.
reg  [10:0] qv0;
reg   [9:0] q_vs;
reg         vvalid = 1'b0;

always @(posedge clk) begin
	qv0    <= {2'b00, na[9:1]} + {1'b0, fl} - {1'b0, VC};
	q_vs   <= ((qv0 >= {1'b0, fl})         ? qv0[9:0] - fl :
	          (qv0[9:0] < na)              ? na             :
	          (qv0[9:0] > fl - 10'd3)      ? fl - 10'd3     : qv0[9:0]) + {9'd0, vlate};
	vvalid <= (n_fl == 2'd2) && got_na && (na != 10'd0) && (fl > na + 10'd3) &&
	          ({2'b00, na[9:1]} + {1'b0, fl} >= {1'b0, VC});
end

// ---------------------------------------------------------------------------
// The new pulses. An HSync started in line n begins output line n + 1 when
// it falls before the board's own sync (s < 0), else output line n.

reg        hs_g = 1'b0, vs_g = 1'b0, vb_g = 1'b1;
reg [10:0] hw_left = 11'd0;
reg  [1:0] vw_left = 2'd0;

wire [10:0] idx_n = {1'b0, q} + (s_neg ? 11'd1 : 11'd0);
reg   [9:0] idx;                      // output line the next HSync begins

always @(posedge clk) begin
	idx <= (idx_n >= {1'b0, fl}) ? idx_n[9:0] - fl : idx_n[9:0];
	if (ce) begin
		if (hvalid && pos == trig) begin
			hs_g    <= 1'b1;
			hw_left <= (dot6 ? HW_6 : HW_8) - 11'd1;
			vb_g    <= idx >= na;
			if (vvalid && idx == q_vs) begin
				vs_g    <= 1'b1;
				vw_left <= VW - 2'd1;
			end
			else if (vw_left != 2'd0) vw_left <= vw_left - 2'd1;
			else                      vs_g    <= 1'b0;
		end
		else if (hw_left != 11'd0) hw_left <= hw_left - 11'd1;
		else                       hs_g    <= 1'b0;
	end
end

assign centred = hvalid & vvalid;
assign hs_out  = centred ? hs_g : hs_in;
assign vs_out  = centred ? vs_g : vs_in;
assign vb_out  = centred ? vb_g : vb_in;

endmodule
