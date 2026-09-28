//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_video.sv - video section of the Ninja Clowns main board
//
//  TMS34061, eight VRAMs, ITV4400 blitter and MS176 RAMDAC, plus the display
//  path. Ninja Clowns uses the "2 page large" layout (MAME
//  screen_update_2page_large): two 512 x 256 pages, each byte holding two
//  4-bit pixels whose upper colour nibbles come from the latch byte.
//
//  At the start of every visible line the whole VRAM row is copied into a
//  line buffer, as the real VRAM transfers the row into its serial port.
//  The display column for character count h is (h - HESYNC): the serial
//  port starts shifting when horizontal sync ends, which puts the first
//  visible byte at column 32 with the game's settings (MAME's visarea 64).
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
	input             page_sel,       // displayed page (bit 7 of 0x100180 write)
	input       [7:0] grom_bank,

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

wire [15:0] xyaddress, xyoffset, dispstart;
wire  [7:0] latch;
wire  [9:0] hcnt, vcnt, h_end_sync;
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
	.op_start     (tms_start),
	.op_offs      (tms_offs),
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
	.dispstart    (dispstart),
	.display_on   (display_on),
	.irq          ()
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
// Line fetch: at the end of each line, load the row for the next one.

reg   [7:0] col_off;

always @(posedge clk) begin
	fetch_start <= 1'b0;
	if (reset) col_off <= 8'd0;
	else if (line_start && next_visible) begin
		fetch_start <= 1'b1;
		fetch_row   <= {page_sel, dispstart[9:2] + next_y};
		col_off     <= {dispstart[1:0], 6'd0};
	end
end

// ---------------------------------------------------------------------------
// Line buffer and display pipeline

wire  [7:0] disp_col = hcnt[7:0] - h_end_sync[7:0] + col_off;
reg   [2:0] lane;
wire [127:0] lb_rdata;

it8_sdpram #(.AW(5), .DW(128)) line_buf
(
	.clk     (clk),
	.rd_addr (disp_col[7:3]),
	.rd_data (lb_rdata),
	.wr_addr (lb_waddr),
	.wr_data (lb_wdata),
	.wr_en   (lb_we)
);

always @(posedge clk) lane <= disp_col[2:0];
wire [15:0] lb_cell = lb_rdata[16*lane +: 16];   // {vram, latch} for this character

// Stage 1 (on pix_ce): pixel value and raster flags for this dot.
reg   [7:0] s1_pix;
reg         s1_hs, s1_vs, s1_hb, s1_vb, s1_on;
wire  [7:0] pix_val = pix_left ? {lb_cell[7:4], lb_cell[15:12]} : {lb_cell[3:0], lb_cell[11:8]};

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
		else begin
			r <= {rgb6[17:12], rgb6[17:16]};
			g <= {rgb6[11:6],  rgb6[11:10]};
			b <= {rgb6[5:0],   rgb6[5:4]};
		end
	end
end

endmodule
