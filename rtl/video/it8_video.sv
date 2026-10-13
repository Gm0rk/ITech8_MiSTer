//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_video.sv - video section of the Ninja Clowns main board
//
//  TMS34061, eight VRAMs, ITV4400 blitter and MS176 RAMDAC, plus the display
//  path, shared by the 68000 board and the 6809 boards. Two layouts:
//
//  * Ninja Clowns, "2 page large" (MAME screen_update_2page_large): two
//    512 x 256 pages, each byte holding two 4-bit pixels whose upper colour
//    nibbles come from the latch byte. 8 MHz dots, 4 MHz characters. The
//    display column for character count h is (h - HESYNC): the serial port
//    starts shifting when horizontal sync ends, which puts the first visible
//    byte at column 32 with the game's settings (MAME's visarea 64).
//
//  * two_layer, Strata Bowling (MAME screen_update_2layer): one byte per
//    pixel, 256 x 256. The bottom layer is page 1 (VRAM 0x20000), a full
//    8-bit pixel; the top layer is the low nibble of page 0 (0x00000), shown
//    instead wherever it is not 0. 6 MHz dots, one per character count;
//    column 0 is shown at the first visible count (END BLANK), as MAME.
//
//  * page8, Poker Dice (MAME screen_update_2page): one byte per pixel,
//    256 x 256, the page chosen by page_sel; timed as two_layer (6 MHz,
//    column 0 at END BLANK).
//
//  * gm, Grudge Match (MAME grmatch_state::screen_update, D-048): two
//    4-bit layers, two pixels a byte (upper nibble first) as 2 page large,
//    and timed as it (8 MHz, column 0 at END BLANK). Page 0 is the top
//    layer, shown wherever its pixel is not 0, page 1 the bottom layer.
//    Each layer has its own TMS34070 palette of 16 12-bit colours, which
//    the hardware loads from video RAM: the first 32 bytes at the display
//    start of each page (R = byte 0 bits 3-0, G and B = byte 1). gm_scroll
//    is ORed into the display start's low byte. A line starting at column
//    c of a row runs on into the next row (MAME reads the bytes in a row,
//    as here: 200 bytes from c).
//
//  The 6809 games of Hot Shots Tennis style use the Ninja Clowns layout
//  (2 page large) with the page bit the other way round (it8_top inverts
//  it), but, as every 6809 board, show column 0 at END BLANK (col_eb).
//
//  At the start of every visible line the whole VRAM row is copied into a
//  line buffer, as the real VRAM transfers the row into its serial port; in
//  two_layer mode the page 0 row follows into a second buffer (nibbles).
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_video
(
	input             clk,
	input             reset,
	input             pix_ce,         // 8 MHz
	input             chr_ce,         // 4 MHz, coincides with every second pix_ce
	input             pix_left,       // pix_ce of the left dot of a character

	// Board registers
	input             two_layer,      // Strata Bowling display (see above)
	input             page8,          // Poker Dice display (see above)
	input             gm,             // Grudge Match display (see above)
	input       [7:0] gm_palctl,      // palette control (bit 7: load the palettes)
	input       [7:0] gm_scroll,      // X scroll
	input             col_eb,         // 2 page large: column 0 at END BLANK
	input             page_sel,       // displayed page (bit 7 of 0x100180 write)
	input       [7:0] grom_bank,
	input      [23:0] grom_size,      // graphics ROM region in bytes
	input      [31:0] an,             // blitter registers 12-15 (input ports)
	output            tms_irq,        // TMS34061 vertical interrupt

	// CPU access to the TMS34061 (one byte lane).
	input             tms_start,
	input      [11:0] tms_offs,
	input             tms_we,
	input       [7:0] tms_wdata,
	output            tms_done,
	output      [7:0] tms_rdata,
	input             latch_we,
	input       [7:0] latch_wdata,

	// CPU access to the blitter registers.
	input             blt_we,
	input             blt_re,
	input       [3:0] blt_idx,
	input       [7:0] blt_wdata,
	output      [7:0] blt_rdata,
	output            blt_irq,

	// CPU access to the RAMDAC.
	input             dac_we,
	input             dac_re,
	input       [1:0] dac_idx,
	input       [7:0] dac_wdata,
	output      [7:0] dac_rdata,

	// Graphics ROM (SDRAM), toggle handshake.
	output     [23:0] rom_addr,
	output            rom_req,
	input             rom_ack,
	input      [15:0] rom_data,

	// Display
	output reg        ce_pix,         // one clock after the colour changes
	output reg  [7:0] r,
	output reg  [7:0] g,
	output reg  [7:0] b,
	output reg        hs,             // active high
	output reg        vs,             // active high
	output reg        hblank,
	output reg        vblank,
	output            vblank_start,   // pulse: level 3 interrupt

	// Debug
	output      [9:0] dbg_vcnt,
	output     [15:0] dbg_blits,
	output     [15:0] dbg_blit_late,
	output     [15:0] dbg_vram_drop
);

// ---------------------------------------------------------------------------
// TMS34061

wire byte_dots = two_layer | page8;   // one byte per dot, 6 MHz
wire [15:0] xyaddress, xyoffset, dispstart;
wire  [7:0] latch;
wire  [9:0] hcnt, vcnt, h_end_sync, h_end_blank;
wire        t_hs, t_vs, t_hb, t_vb, line_start, display_on;
wire        next_visible;
wire  [7:0] next_y;

wire        vr_start, vr_we, vr_done;
wire [17:0] vr_addr;
wire  [7:0] vr_vdata, vr_ldata, vr_rdata;
wire        cp_start, cp_done;
wire  [9:0] cp_src, cp_dst;
wire  [7:0] cp_fill;

it8_tms34061 tms
(
	.clk          (clk),
	.reset        (reset),
	.chr_ce       (chr_ce),
	.raster09     (byte_dots),
	.op_start     (tms_start),
	.op_offs      (tms_offs),
	.op_row       (8'hFF),
	.op_we        (tms_we),
	.op_wdata     (tms_wdata),
	.op_done      (tms_done),
	.op_rdata     (tms_rdata),
	.latch_we     (latch_we),
	.latch_wdata  (latch_wdata),
	.latch        (latch),
	.xyaddress    (xyaddress),
	.xyoffset     (xyoffset),
	.vr_start     (vr_start),
	.vr_addr      (vr_addr),
	.vr_we        (vr_we),
	.vr_vdata     (vr_vdata),
	.vr_ldata     (vr_ldata),
	.vr_done      (vr_done),
	.vr_rdata     (vr_rdata),
	.cp_start     (cp_start),
	.cp_src       (cp_src),
	.cp_dst       (cp_dst),
	.cp_fill      (cp_fill),
	.cp_done      (cp_done),
	.hcnt         (hcnt),
	.vcnt         (vcnt),
	.hsync        (t_hs),
	.vsync        (t_vs),
	.hblank       (t_hb),
	.vblank       (t_vb),
	.line_start   (line_start),
	.next_visible (next_visible),
	.next_y       (next_y),
	.vblank_start (vblank_start),
	.h_end_sync   (h_end_sync),
	.h_end_blank  (h_end_blank),
	.dispstart    (dispstart),
	.display_on   (display_on),
	.irq          (tms_irq)
);

assign dbg_vcnt = vcnt;

// ---------------------------------------------------------------------------
// Blitter

wire        b_start, b_done;
wire [17:0] b_addr;
wire  [7:0] b_vdata, b_vmask, b_ldata, b_lmask;

it8_blitter blitter
(
	.clk       (clk),
	.reset     (reset),
	.reg_we    (blt_we),
	.reg_re    (blt_re),
	.reg_idx   (blt_idx),
	.reg_wdata (blt_wdata),
	.reg_rdata (blt_rdata),
	.grom_bank (grom_bank),
	.grom_size (grom_size),
	.an        (an),
	.xyaddress (xyaddress),
	.xyoffset  (xyoffset),
	.latch     (latch),
	.rom_addr  (rom_addr),
	.rom_req   (rom_req),
	.rom_ack   (rom_ack),
	.rom_data  (rom_data),
	.vr_start  (b_start),
	.vr_addr   (b_addr),
	.vr_vdata  (b_vdata),
	.vr_vmask  (b_vmask),
	.vr_ldata  (b_ldata),
	.vr_lmask  (b_lmask),
	.vr_done   (b_done),
	.irq       (blt_irq),
	.busy      (),
	.dbg_blits (dbg_blits),
	.dbg_late  (dbg_blit_late)
);

// ---------------------------------------------------------------------------
// VRAM

reg         fetch_start;
reg   [8:0] fetch_row;
wire        lb_we;
wire  [4:0] lb_waddr;
wire [127:0] lb_wdata;

it8_vram vram
(
	.clk         (clk),
	.reset       (reset),
	.fetch_start (fetch_start),
	.fetch_row   (fetch_row),
	.lb_we       (lb_we),
	.lb_addr     (lb_waddr),
	.lb_data     (lb_wdata),
	.tms_start   (vr_start),
	.tms_addr    (vr_addr),
	.tms_we      (vr_we),
	.tms_vdata   (vr_vdata),
	.tms_ldata   (vr_ldata),
	.tms_done    (vr_done),
	.tms_rdata   (vr_rdata),
	.copy_start  (cp_start),
	.copy_src    (cp_src),
	.copy_dst    (cp_dst),
	.copy_fill   (cp_fill),
	.copy_done   (cp_done),
	.blt_start   (b_start),
	.blt_addr    (b_addr),
	.blt_vdata   (b_vdata),
	.blt_vmask   (b_vmask),
	.blt_ldata   (b_ldata),
	.blt_lmask   (b_lmask),
	.blt_done    (b_done),
	.dbg_dropped (dbg_vram_drop)
);

// ---------------------------------------------------------------------------
// Line fetch: at the end of each line, load the row for the next one. In
// two_layer mode the bottom layer's row (page 1) comes first, then, once its
// last chunk is written, the top layer's (page 0) into the nibble buffer.

reg   [7:0] col_off;
reg   [7:0] top_row;
reg         top_next;             // the top layer's fetch is still to start
reg         top_fill;             // line buffer writes go to the top buffer

// gm: rows r and r + 1 of page 1, then of page 0, for the next line (gm_st
// 1-4), then the palette rows of both pages for the line after (5-8). The
// palette fetch runs at the start of every line, visible or not.
wire [15:0] gm_po = {dispstart[9:0], 6'd0} | {8'd0, gm_scroll};
reg   [3:0] gm_st;                // fetch now running (0 = none)
reg   [7:0] gm_row, gm_prow;      // display row r, palette row
reg   [7:0] gm_c0, gm_pc0;        // their start columns
reg         gm_disp;              // the display rows are fetched too
wire        gm_chunk_end = lb_we && lb_waddr == 5'd31;

function [3:0] gm_next(input [3:0] st, input disp, input pal);
	if (st == 4'd0)      gm_next = disp ? 4'd1 : pal ? 4'd5 : 4'd0;
	else if (st == 4'd4) gm_next = pal ? 4'd5 : 4'd0;
	else if (st == 4'd8) gm_next = 4'd0;
	else                 gm_next = st + 4'd1;
endfunction

reg   [3:0] gm_nx;
always @(*) gm_nx = gm_next(gm_st, gm_disp, gm_palctl[7]);
reg         gm_kick;              // the clock after line_start
always @(posedge clk) gm_kick <= gm && line_start;

always @(posedge clk) begin
	fetch_start <= 1'b0;
	if (reset) begin
		col_off  <= 8'd0;
		top_next <= 1'b0;
		top_fill <= 1'b0;
		gm_st    <= 4'd0;
	end
	else if (gm) begin
		top_next <= 1'b0;
		top_fill <= 1'b0;
		if (line_start) begin
			gm_disp <= next_visible;
			gm_row  <= gm_po[15:8] + next_y;
			gm_prow <= gm_po[15:8];
			gm_c0   <= gm_po[7:0];
			gm_pc0  <= gm_po[7:0];
			gm_st   <= 4'd0;
		end
		// start the first fetch the clock after line_start, each next one
		// when the last chunk of the previous one is written
		if ((gm_st == 4'd0 && gm_kick) || (gm_st != 4'd0 && gm_chunk_end)) begin
			gm_st <= gm_nx;
			if (gm_nx != 4'd0) begin
				fetch_start <= 1'b1;
				case (gm_nx)
					4'd1: fetch_row <= {1'b1, gm_row};
					4'd2: fetch_row <= {1'b1, gm_row + 8'd1};
					4'd3: fetch_row <= {1'b0, gm_row};
					4'd4: fetch_row <= {1'b0, gm_row + 8'd1};
					4'd5: fetch_row <= {1'b0, gm_prow};
					4'd6: fetch_row <= {1'b0, gm_prow + 8'd1};
					4'd7: fetch_row <= {1'b1, gm_prow};
					default: fetch_row <= {1'b1, gm_prow + 8'd1};
				endcase
			end
		end
	end
	else if (line_start && next_visible) begin
		fetch_start <= 1'b1;
		fetch_row   <= {two_layer | page_sel, dispstart[9:2] + next_y};
		col_off     <= {dispstart[1:0], 6'd0};
		top_row     <= dispstart[9:2] + next_y;
		top_next    <= two_layer;
		top_fill    <= 1'b0;
	end
	else if (top_next && lb_we && lb_waddr == 5'd31) begin
		fetch_start <= 1'b1;
		fetch_row   <= {1'b0, top_row};
		top_next    <= 1'b0;
		top_fill    <= 1'b1;
	end
end

// gm line buffers: two rows (64 chunks of 8 VRAM bytes) for each page.
wire        gm_lb_we = gm && lb_we && gm_st != 4'd0 && gm_st <= 4'd4;
wire  [5:0] gm_lb_wa = {~gm_st[0], lb_waddr};     // 1, 3: row r; 2, 4: row r + 1
wire [63:0] gm_lb_wd;
genvar gl;
generate
	for (gl = 0; gl < 8; gl = gl + 1) begin : gm_lane
		assign gm_lb_wd[8*gl +: 8] = lb_wdata[16*gl+8 +: 8];
	end
endgenerate

wire  [8:0] gm_col = (hcnt[8:0] - h_end_blank[8:0]) + {1'b0, gm_c0};
wire [63:0] gm_bg_q, gm_fg_q;

it8_sdpram #(.AW(6), .DW(64)) gm_bg_buf
(
	.clk     (clk),
	.rd_addr (gm_col[8:3]),
	.rd_data (gm_bg_q),
	.wr_addr (gm_lb_wa),
	.wr_data (gm_lb_wd),
	.wr_en   (gm_lb_we & (gm_st == 4'd1 || gm_st == 4'd2))
);

it8_sdpram #(.AW(6), .DW(64)) gm_fg_buf
(
	.clk     (clk),
	.rd_addr (gm_col[8:3]),
	.rd_data (gm_fg_q),
	.wr_addr (gm_lb_wa),
	.wr_data (gm_lb_wd),
	.wr_en   (gm_lb_we & (gm_st == 4'd3 || gm_st == 4'd4))
);

reg  [2:0] gm_lane_q;
always @(posedge clk) gm_lane_q <= gm_col[2:0];
wire [7:0] gm_fg_byte = gm_fg_q[8*gm_lane_q +: 8];
wire [7:0] gm_bg_byte = gm_bg_q[8*gm_lane_q +: 8];
wire [7:0] gm_pix     = pix_left ? {gm_fg_byte[7:4], gm_bg_byte[7:4]} : {gm_fg_byte[3:0], gm_bg_byte[3:0]};

// gm palettes: the fetch of a palette row writes the bytes that fall in the
// 32 from its start column into a staging copy; it becomes the palette at
// the next line start. Entry e: byte 2e = R (bits 3-0), byte 2e + 1 = G, B.
reg  [3:0] gm_sr [0:31];          // staging, index {page, entry}
reg  [7:0] gm_sgb[0:31];
reg  [3:0] gm_pr [0:31];          // palettes in use
reg  [7:0] gm_pgb[0:31];
reg        gm_staged;
wire       gm_pal_we = gm && lb_we && gm_st >= 4'd5;
wire       gm_pal_pg = (gm_st >= 4'd7);            // 5, 6: page 0; 7, 8: page 1
wire       gm_pal_hi = ~gm_st[0];                  // 6, 8: row + 1
wire [8:0] gm_kbase  = {gm_pal_hi, lb_waddr, 3'b000} - {1'b0, gm_pc0};
wire [8:0] gm_k [0:7];                             // byte of lane l from the start column
generate
	for (gl = 0; gl < 8; gl = gl + 1) begin : gm_klane
		assign gm_k[gl] = gm_kbase + gl;
	end
endgenerate
integer    gp, ge;

always @(posedge clk) begin
	if (reset) gm_staged <= 1'b0;
	else begin
		if (gm_pal_we) begin
			gm_staged <= 1'b1;
			for (gp = 0; gp < 8; gp = gp + 1) begin
				if (gm_k[gp] < 9'd32) begin
					if (!gm_k[gp][0]) gm_sr [{gm_pal_pg, gm_k[gp][4:1]}] <= lb_wdata[16*gp+8 +: 4];
					else              gm_sgb[{gm_pal_pg, gm_k[gp][4:1]}] <= lb_wdata[16*gp+8 +: 8];
				end
			end
		end
		if (line_start && gm_staged) begin
			gm_staged <= 1'b0;
			for (ge = 0; ge < 32; ge = ge + 1) begin
				gm_pr [ge] <= gm_sr [ge];
				gm_pgb[ge] <= gm_sgb[ge];
			end
		end
	end
end

// Colour of a gm dot, one pix_ce after its value (as the RAMDAC's).
reg [11:0] gm_rgb;
always @(posedge clk) begin
	if (pix_ce) begin
		if (gm_pix[7:4] != 4'h0) gm_rgb <= {gm_pr[{1'b0, gm_pix[7:4]}], gm_pgb[{1'b0, gm_pix[7:4]}]};
		else                     gm_rgb <= {gm_pr[{1'b1, gm_pix[3:0]}], gm_pgb[{1'b1, gm_pix[3:0]}]};
	end
end

// ---------------------------------------------------------------------------
// Line buffer and display pipeline

wire  [7:0] disp_col = hcnt[7:0] - ((byte_dots | col_eb) ? h_end_blank[7:0] : h_end_sync[7:0]) + col_off;
reg   [2:0] lane;
wire [127:0] lb_rdata;
wire  [31:0] tb_rdata;

it8_sdpram #(.AW(5), .DW(128)) line_buf
(
	.clk     (clk),
	.rd_addr (disp_col[7:3]),
	.rd_data (lb_rdata),
	.wr_addr (lb_waddr),
	.wr_data (lb_wdata),
	.wr_en   (lb_we & ~top_fill)
);

// Top layer: the low nibble of each page 0 byte, eight per chunk.
wire [31:0] tb_wdata;
genvar tl;
generate
	for (tl = 0; tl < 8; tl = tl + 1) begin : top_lane
		assign tb_wdata[4*tl +: 4] = lb_wdata[16*tl+8 +: 4];
	end
endgenerate

it8_sdpram #(.AW(5), .DW(32)) top_buf
(
	.clk     (clk),
	.rd_addr (disp_col[7:3]),
	.rd_data (tb_rdata),
	.wr_addr (lb_waddr),
	.wr_data (tb_wdata),
	.wr_en   (lb_we & top_fill)
);

always @(posedge clk) lane <= disp_col[2:0];
wire [15:0] lb_cell = lb_rdata[16*lane +: 16];   // {vram, latch} for this character
wire  [3:0] tb_nib  = tb_rdata[4*lane +: 4];

// Stage 1 (on pix_ce): pixel value and raster flags for this dot.
reg   [7:0] s1_pix;
reg         s1_hs, s1_vs, s1_hb, s1_vb, s1_on;
wire  [7:0] pix_val = two_layer ? ((tb_nib != 4'h0) ? {4'h0, tb_nib} : lb_cell[15:8]) :
                      page8     ? lb_cell[15:8] :
                      pix_left  ? {lb_cell[7:4], lb_cell[15:12]} : {lb_cell[3:0], lb_cell[11:8]};

always @(posedge clk) begin
	if (pix_ce) begin
		s1_pix <= pix_val;
		s1_hs  <= t_hs;
		s1_vs  <= t_vs;
		s1_hb  <= t_hb;
		s1_vb  <= t_vb;
		s1_on  <= display_on;
	end
end

// Stage 2 (next pix_ce): palette output.
wire [17:0] rgb6;

it8_ramdac ramdac
(
	.clk       (clk),
	.reset     (reset),
	.reg_we    (dac_we),
	.reg_re    (dac_re),
	.reg_idx   (dac_idx),
	.reg_wdata (dac_wdata),
	.reg_rdata (dac_rdata),
	.pix_ce    (pix_ce),
	.pix_in    (pix_val),
	.pix_rgb   (rgb6)
);

always @(posedge clk) begin
	ce_pix <= pix_ce;
	if (pix_ce) begin
		hs     <= s1_hs;
		vs     <= s1_vs;
		hblank <= s1_hb;
		vblank <= s1_vb;
		if (s1_hb || s1_vb || !s1_on) {r, g, b} <= 24'd0;
		else if (gm) begin
			r <= {gm_rgb[11:8], gm_rgb[11:8]};
			g <= {gm_rgb[7:4],  gm_rgb[7:4]};
			b <= {gm_rgb[3:0],  gm_rgb[3:0]};
		end
		else begin
			r <= {rgb6[17:12], rgb6[17:16]};
			g <= {rgb6[11:6],  rgb6[11:10]};
			b <= {rgb6[5:0],   rgb6[5:4]};
		end
	end
end

endmodule
