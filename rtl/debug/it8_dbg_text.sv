//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_dbg_text.sv - diagnostic overlay: labelled hex values in a panel
//
//  N_ROWS rows of 13 character cells (8 x 8 pixels, 5 x 7 glyphs): a
//  4-character label, a gap and eight hex digits. The panel sits at
//  (BOX_X, BOX_Y); the caller draws glyph pixels white and the rest of the
//  panel black, leaving the picture outside it untouched. Same layout and
//  font as the Atari G1 core's overlay.
//
//  LABELS is an ASCII string, four characters per row, row 0 first. Row 0's
//  gap cell shows row0_msn, so BLD can show nine digits (YYMMDD + build).
//  The values are taken once per frame, while vis_y is 0 (above the panel),
//  so a counter that changes during the frame never shows a torn digit.
//
//  Output is two clocks behind vis_x / vis_y.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_dbg_text #(
	parameter N_ROWS = 16,
	parameter BOX_X  = 8,
	parameter BOX_Y  = 8,
	parameter [8*4*N_ROWS-1:0] LABELS = {N_ROWS{"    "}}
)(
	input                   clk,
	input             [8:0] vis_x,
	input             [7:0] vis_y,
	input  [32*N_ROWS-1:0]  vals,        // row 0 at the top of the bus
	input             [3:0] row0_msn,
	output reg              pix,         // glyph pixel: draw white
	output reg              in_box       // inside the panel: draw black
);

localparam COLS  = 13;
localparam BOX_W = COLS * 8;
localparam BOX_H = N_ROWS * 8;

// 5 x 7 glyphs for 0-9, A-Z and space. Glyph g occupies bits
// [35*(36-g) +: 35], row-major, MSB = top-left.
localparam [37*35-1:0] FONT = 1295'b01110100011001110101110011000101110001000110000100001000010000100011100111010001000010001000100010001111111111000100010000010000011000101110000100011001010100101111100010000101111110000111100000100001100010111000110010001000011110100011000101110111110000100010001000100001000010000111010001100010111010001100010111001110100011000101111000010001001100011101000110001111111000110001100011111010001100011111010001100011111001110100011000010000100001000101110111001001010001100011000110010111001111110000100001111010000100001111111111100001000011110100001000010000011101000110000101111000110001011111000110001100011111110001100011000101110001000010000100001000010001110001110001000010000100001010010011001000110010101001100010100100101000110000100001000010000100001000011111100011101110101101011000110001100011000111001101011001110001100011000101110100011000110001100011000101110111101000110001111101000010000100000111010001100011000110101100100110111110100011000111110101001001010001011111000010000011100000100001111101111100100001000010000100001000010010001100011000110001100011000101110100011000110001100011000101010001001000110001100011010110101110111000110001100010101000100010101000110001100011000101010001000010000100001001111100001000100010001000100001111100000000000000000000000000000000000;

wire       in_panel = (vis_x >= BOX_X) && (vis_x < BOX_X + BOX_W) &&
                      (vis_y >= BOX_Y) && (vis_y < BOX_Y + BOX_H);
wire [8:0] px = vis_x - BOX_X[8:0];
wire [7:0] py = vis_y - BOX_Y[7:0];

wire [4:0] cell_x = px[7:3];
wire [4:0] cell_y = py[7:3];
wire [2:0] ox     = px[2:0];
wire [2:0] oy     = py[2:0];
wire       glyph_area = (ox >= 3'd1) && (ox < 3'd6) && (oy < 3'd7);

// ASCII to glyph code.
function [5:0] glyph_of(input [7:0] c);
	if (c >= "0" && c <= "9")      glyph_of = c - "0";
	else if (c >= "A" && c <= "Z") glyph_of = c - "A" + 6'd10;
	else                           glyph_of = 6'd36;
endfunction

reg [32*N_ROWS-1:0] vals_q;

always @(posedge clk) if (vis_y == 8'd0) vals_q <= vals;

reg  [5:0] ch;
reg [31:0] row_val;
reg  [2:0] hex_i;

always @(*) begin
	ch      = 6'd36;
	row_val = vals_q[32*(N_ROWS-1-cell_y) +: 32];
	hex_i   = cell_x[2:0] - 3'd5;
	if (in_panel && cell_y < N_ROWS) begin
		if (cell_x < 5'd4)
			ch = glyph_of(LABELS[8*(4*(N_ROWS-1-cell_y) + (3-cell_x[1:0])) +: 8]);
		else if (cell_x == 5'd4)
			ch = (cell_y == 5'd0) ? {2'd0, row0_msn} : 6'd36;
		else
			ch = {2'd0, row_val[4*(7-hex_i) +: 4]};
	end
end

// Stage 1: character and position; stage 2: font bit.
reg  [5:0] ch_r;
reg  [2:0] gx_r, gy_r;
reg        glyph_r, box_r;

always @(posedge clk) begin
	ch_r    <= ch;
	gx_r    <= ox - 3'd1;
	gy_r    <= oy;
	glyph_r <= in_panel && glyph_area;
	box_r   <= in_panel;

	pix    <= glyph_r && FONT[35*(36-ch_r) + (34 - (gy_r*5 + gx_r))];
	in_box <= box_r;
end

endmodule
