//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_dbg_page.sv - diagnostic overlay: pages of text and numbers that read
//  upright however the picture is turned
//
//  N_PAGES pages of up to N_ROWS rows; page holds ROWS rows (5 bits a page,
//  page 0 first). A row is COLS = 9 + 3 x FW character cells (8 x 8
//  pixels, the 5 x 7 glyphs of it8_dbg_text.sv plus a minus sign): a line
//  of fixed text (TEXT, COLS characters a row, page 0 row 0 first, every
//  page N_ROWS rows) with up to three numbers over it, right-aligned in
//  FW-character fields at columns 7, 8 + FW and 9 + 2 x FW. FMT gives each
//  field's format, two bits a field, A (the left one) first, page 0 row 0
//  first:
//    0  none (the text shows)
//    1  signed decimal, -(10^(FW-1) - 1) to 10^FW - 1 (beyond shows the limit)
//    2  unsigned decimal, 0 to 10^FW - 1
//    3  hex, the low FW digits
//  vals carries three 32-bit values a row, A first, page 0 row 0 at the top
//  of the bus. page picks the page shown; it is taken at the frame pulse.
//
//  Once a frame, from the frame pulse (the start of vertical blanking), a
//  formatter writes the page into a character RAM, one character a clock and
//  22 clocks a decimal conversion: under 3000 clocks, well inside the
//  blanking. Each value is read once, so a number never tears.
//
//  The raster may be turned on its way to the viewer: by MiSTer's rotation
//  on HDMI, or by a monitor stood on its side, after Vertical Flip has
//  turned the picture 180 degrees on the analog output. rot says how the
//  viewer sees the raster: 0 as it is, 1 turned 90 degrees anticlockwise
//  (MAME ROT270), 2 turned clockwise (ROT90). Each raster pixel is mapped to
//  the viewer's (u, v) and the page is drawn there, so it reads upright
//  with the game. The turns need the raster's visible width and height,
//  measured from the previous frame (de).
//
//  The page sits at (BOX_X, BOX_Y) of the viewer's picture, as tall as its
//  rows. Output is two clocks behind vis_x / vis_y, as it8_dbg_text's.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_dbg_page #(
	parameter N_PAGES = 1,
	parameter N_ROWS  = 16,                // rows a page, at most (N_PAGES x N_ROWS at most 32)
	parameter FW      = 6,                 // field width, 2 to 6
	parameter BOX_X   = 8,
	parameter BOX_Y   = 8,
	parameter [8*(9+3*FW)*N_PAGES*N_ROWS-1:0] TEXT = {(N_PAGES*N_ROWS){{(9+3*FW){" "}}}},
	parameter [6*N_PAGES*N_ROWS-1:0]          FMT  = {(N_PAGES*N_ROWS){6'd0}},
	parameter [5*N_PAGES-1:0]                 ROWS = {N_PAGES{N_ROWS[4:0]}}
)(
	input                            clk,
	input                            frame,   // one clock at the start of vertical blanking
	input                            ce,      // pixel clock enable
	input                            de,      // the pixel on ce is visible
	input                      [8:0] vis_x,
	input                      [7:0] vis_y,
	input                      [1:0] rot,     // 0 none, 1 viewer sees it turned anticlockwise, 2 clockwise
	input                      [1:0] page,
	input  [96*N_PAGES*N_ROWS-1:0]   vals,
	output reg                       pix,     // glyph pixel: draw white
	output reg                       in_box   // inside the panel: draw black
);

localparam COLS  = 9 + 3 * FW;
localparam NROWS = N_PAGES * N_ROWS;     // rows on the buses
localparam NCH   = NROWS * COLS;
localparam BOX_W = COLS * 8;
localparam K0    = 6 - FW;               // first of the converter's six digits shown

function integer pow10(input integer n);
	integer i;
	begin
		pow10 = 1;
		for (i = 0; i < n; i = i + 1) pow10 = pow10 * 10;
	end
endfunction

localparam integer POS_MAX = pow10(FW) - 1;
localparam integer NEG_MAX = pow10(FW - 1) - 1;
localparam  [19:0] POS_LIM = POS_MAX[19:0];
localparam  [19:0] NEG_LIM = NEG_MAX[19:0];
localparam integer FSTEP_I = FW + 1;
localparam   [4:0] K0_5    = K0[4:0];
localparam   [2:0] K0_3    = K0[2:0];
localparam   [4:0] FSTEP   = FSTEP_I[4:0];
localparam   [2:0] NPG     = N_PAGES[2:0];
localparam  [12:0] NCH13   = NCH[12:0];

localparam [5:0] G_SPACE = 6'd36;
localparam [5:0] G_MINUS = 6'd37;

// 5 x 7 glyphs for 0-9, A-Z, space and minus. Glyph g occupies bits
// [35*(37-g) +: 35], row-major, MSB = top-left.
localparam [38*35-1:0] FONT = 1330'b0111010001100111010111001100010111000100011000010000100001000010001110011101000100001000100010001000111111111100010001000001000001100010111000010001100101010010111110001000010111111000011110000010000110001011100011001000100001111010001100010111011111000010001000100010000100001000011101000110001011101000110001011100111010001100010111100001000100110001110100011000111111100011000110001111101000110001111101000110001111100111010001100001000010000100010111011100100101000110001100011001011100111111000010000111101000010000111111111110000100001111010000100001000001110100011000010111100011000101111100011000110001111111000110001100010111000100001000010000100001000111000111000100001000010000101001001100100011001010100110001010010010100011000010000100001000010000100001111110001110111010110101100011000110001100011100110101100111000110001100010111010001100011000110001100010111011110100011000111110100001000010000011101000110001100011010110010011011111010001100011111010100100101000101111100001000001110000010000111110111110010000100001000010000100001001000110001100011000110001100010111010001100011000110001100010101000100100011000110001101011010111011100011000110001010100010001010100011000110001100010101000100001000010000100111110000100010001000100010000111110000000000000000000000000000000000000000000000000011111000000000000000;

// ASCII to glyph code (anything else is a space).
function [5:0] glyph_of(input [7:0] c);
	if (c >= "0" && c <= "9")      glyph_of = c[5:0] - 6'd48;
	else if (c >= "A" && c <= "Z") glyph_of = c[5:0] - 6'd55;
	else if (c == "-")             glyph_of = G_MINUS;
	else                           glyph_of = G_SPACE;
endfunction

// The fixed text as glyph codes, character n (row-major from page 0 row 0)
// at [6*(NCH-1-n) +: 6].
function [6*NCH-1:0] glyphs(input [8*NCH-1:0] t);
	integer i;
	begin
		glyphs = {6*NCH{1'b0}};
		for (i = 0; i < NCH; i = i + 1)
			glyphs[6*i +: 6] = glyph_of(t[8*i +: 8]);
	end
endfunction

localparam [6*NCH-1:0] TPL = glyphs(TEXT);

// ---------------------------------------------------------------------------
// Character RAM: 32 rows of 32 cells, {row, column}.

reg  [5:0] cram[0:1023];
reg        wr_en;
reg  [9:0] wr_addr;
reg  [5:0] wr_data;
wire [9:0] rd_addr;
reg  [5:0] rd_q;

always @(posedge clk) begin
	if (wr_en) cram[wr_addr] <= wr_data;
	rd_q <= cram[rd_addr];
end

// ---------------------------------------------------------------------------
// Formatter.

localparam [2:0] S_IDLE = 3'd0, S_TEXT = 3'd1, S_FIELD = 3'd2, S_LOAD = 3'd3, S_DABBLE = 3'd4, S_WRITE = 3'd5;

reg  [2:0] st = S_IDLE;
reg  [1:0] pg = 2'd0;                    // the page being written and shown
reg  [4:0] f_row;
reg  [4:0] f_col;
reg  [1:0] f_fld;
reg  [2:0] f_k;
reg  [4:0] f_n;
reg        f_neg, f_hex;
reg  [1:0] f_fmt;
reg [31:0] f_val;
reg [19:0] dd_bin;
reg [23:0] dd_bcd;

// Rows of page p.
function [4:0] rows_of(input [1:0] p);
	integer i;
	begin
		rows_of = ROWS[5*(N_PAGES-1) +: 5];
		for (i = 0; i < N_PAGES; i = i + 1)
			if (p == i[1:0]) rows_of = ROWS[5*(N_PAGES-1-i) +: 5];
	end
endfunction

wire [4:0]  pg_rows = rows_of(pg);
wire [4:0]  last    = pg_rows - 5'd1;
wire [6:0]  pg_base = {5'd0, pg} * N_ROWS[6:0];
wire [4:0]  row_all = pg_base[4:0] + f_row;
wire [4:0]  row_up  = NROWS[4:0] - 5'd1 - row_all;               // row from the bottom of the buses
wire [1:0]  fld_up  = 2'd2 - f_fld;
wire [7:0]  fmt_i   = 8'd6 * {3'd0, row_up} + {5'd0, fld_up, 1'b0};
wire [11:0] val_i   = 12'd96 * {7'd0, row_up} + {5'd0, fld_up, 5'd0};
wire [1:0]  fmt_cur = FMT[fmt_i +: 2];
wire [31:0] val_cur = vals[val_i +: 32];
wire [31:0] val_neg = 32'd0 - f_val;
wire [9:0]  tpl_n   = {5'd0, row_all} * COLS[9:0] + {5'd0, f_col};
wire [12:0] tpl_i   = 13'd6 * (NCH13 - 13'd1 - {3'd0, tpl_n});
wire [4:0]  fld_col = 5'd7 + {3'd0, f_fld} * FSTEP;             // 7, 8 + FW, 9 + 2 x FW

// One double-dabble step: add 3 to each digit of 5 or more.
function [23:0] dd_adj(input [23:0] b);
	integer i;
	begin
		for (i = 0; i < 6; i = i + 1)
			dd_adj[4*i +: 4] = (b[4*i +: 4] >= 4'd5) ? b[4*i +: 4] + 4'd3 : b[4*i +: 4];
	end
endfunction

// Leading zero digits of six, at most 5 (the last digit always shows).
reg [2:0] lz;
always @(*) begin
	lz = 3'd5;
	if      (dd_bcd[23:20] != 4'd0) lz = 3'd0;
	else if (dd_bcd[19:16] != 4'd0) lz = 3'd1;
	else if (dd_bcd[15:12] != 4'd0) lz = 3'd2;
	else if (dd_bcd[11:8]  != 4'd0) lz = 3'd3;
	else if (dd_bcd[7:4]   != 4'd0) lz = 3'd4;
end

wire [43:0] dd_next = {dd_adj(dd_bcd), dd_bin} << 1;

wire [3:0] digit_k = dd_bcd[4*(3'd5-f_k) +: 4];
wire [5:0] char_k  = f_hex ? {2'd0, digit_k} :
                     (f_k < lz) ? ((f_neg && f_k == lz - 3'd1) ? G_MINUS : G_SPACE) :
                     {2'd0, digit_k};

always @(posedge clk) begin
	wr_en <= 1'b0;
	case (st)
		S_IDLE: if (frame) begin
			pg    <= ({1'b0, page} < NPG) ? page : 2'd0;
			f_row <= 5'd0;
			f_col <= 5'd0;
			st    <= S_TEXT;
		end

		S_TEXT: begin
			wr_en   <= 1'b1;
			wr_addr <= {f_row, f_col};
			wr_data <= TPL[tpl_i +: 6];
			if (f_col == COLS[4:0] - 5'd1) begin
				f_fld <= 2'd0;
				st    <= S_FIELD;
			end
			else f_col <= f_col + 5'd1;
		end

		S_FIELD: begin
			f_k <= K0_3;
			f_n <= 5'd0;
			if (fmt_cur == 2'd0) begin
				if (f_fld == 2'd2) begin
					f_col <= 5'd0;
					if (f_row == last) st <= S_IDLE;
					else begin
						f_row <= f_row + 5'd1;
						st    <= S_TEXT;
					end
				end
				else f_fld <= f_fld + 2'd1;
			end
			else begin
				// the value and its format, registered before they are used
				f_fmt <= fmt_cur;
				f_val <= val_cur;
				st    <= S_LOAD;
			end
		end

		S_LOAD: begin
			if (f_fmt == 2'd3) begin
				f_hex  <= 1'b1;
				f_neg  <= 1'b0;
				dd_bcd <= f_val[23:0];
				st     <= S_WRITE;
			end
			else begin
				f_hex  <= 1'b0;
				dd_bcd <= 24'd0;
				if (f_fmt == 2'd1 && f_val[31]) begin
					f_neg  <= 1'b1;
					dd_bin <= (val_neg > {12'd0, NEG_LIM}) ? NEG_LIM : val_neg[19:0];
				end
				else begin
					f_neg  <= 1'b0;
					dd_bin <= (f_val > {12'd0, POS_LIM}) ? POS_LIM : f_val[19:0];
				end
				st <= S_DABBLE;
			end
		end

		S_DABBLE: begin
			{dd_bcd, dd_bin} <= dd_next;
			f_n <= f_n + 5'd1;
			if (f_n == 5'd19) st <= S_WRITE;
		end

		S_WRITE: begin
			wr_en   <= 1'b1;
			wr_addr <= {f_row, fld_col + {2'd0, f_k} - K0_5};
			wr_data <= char_k;
			f_k     <= f_k + 3'd1;
			if (f_k == 3'd5) begin
				if (f_fld == 2'd2) begin
					f_col <= 5'd0;
					if (f_row == last) st <= S_IDLE;
					else begin
						f_row <= f_row + 5'd1;
						st    <= S_TEXT;
					end
				end
				else begin
					f_fld <= f_fld + 2'd1;
					st    <= S_FIELD;
				end
			end
		end

		default: st <= S_IDLE;
	endcase
end

// ---------------------------------------------------------------------------
// The raster's visible size, last frame (largest x and y of a visible pixel).

reg [8:0] wm1 = 9'd255, wcur = 9'd0;
reg [7:0] hm1 = 8'd239, hcur = 8'd0;

always @(posedge clk) begin
	if (frame) begin
		wm1  <= wcur;
		hm1  <= hcur;
		wcur <= 9'd0;
		hcur <= 8'd0;
	end
	else if (ce && de) begin
		if (vis_x > wcur) wcur <= vis_x;
		if (vis_y > hcur) hcur <= vis_y;
	end
end

// ---------------------------------------------------------------------------
// Renderer. (u, v): where this raster pixel is in the viewer's picture. A
// pixel off the viewer's picture wraps to 512 or more, outside the panel.

reg [9:0] u, v;
always @(*) begin
	case (rot)
		2'd1:    begin u = {2'd0, vis_y};       v = {1'b0, wm1} - {1'b0, vis_x}; end
		2'd2:    begin u = {2'd0, hm1} - {2'd0, vis_y}; v = {1'b0, vis_x};       end
		default: begin u = {1'b0, vis_x};       v = {2'd0, vis_y};               end
	endcase
end

wire [9:0] box_h = {2'd0, pg_rows, 3'd0};
wire [9:0] px = u - BOX_X[9:0];
wire [9:0] py = v - BOX_Y[9:0];
wire       in_panel = (u >= BOX_X[9:0]) && (px < BOX_W[9:0]) &&
                      (v >= BOX_Y[9:0]) && (py < box_h);
wire [2:0] ox = px[2:0];
wire [2:0] oy = py[2:0];
wire       glyph_area = (ox >= 3'd1) && (ox < 3'd6) && (oy < 3'd7);

assign rd_addr = {py[7:3], px[7:3]};

// Stage 1: the character (RAM) and position; stage 2: the font bit.
reg  [2:0] gx_r, gy_r;
reg        glyph_r, box_r;

always @(posedge clk) begin
	gx_r    <= ox - 3'd1;
	gy_r    <= oy;
	glyph_r <= in_panel && glyph_area;
	box_r   <= in_panel;

	pix    <= glyph_r && (rd_q <= G_MINUS) && FONT[35*(6'd37-rd_q) + (6'd34 - ({3'd0, gy_r}*6'd5 + {3'd0, gx_r}))];
	in_box <= box_r;
end

endmodule
