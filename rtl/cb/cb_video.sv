//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  cb_video.sv - video section of the Capcom Bowling board
//
//  TMS34061 (wired as on this board, it8_tms34061 CB = 1) and 64 KB of VRAM:
//  256 rows of 256 bytes. Each row is one scan line. Its first 32 bytes are
//  that line's palette, 16 colours of two bytes (0000RRRR, GGGGBBBB); the
//  other 224 bytes hold 448 pixels, two per byte, high nibble first
//  (MAME capbowl.cpp screen_update).
//
//  At the start of every visible line the row is copied into a line buffer
//  (the VRAM serial port), and the palette bytes into 16 colour registers.
//  Pixel byte 32 is shown at the first visible count (END BLANK), one byte
//  per character clock. MAME shows 360 pixels (bytes 32-211); the raster
//  the game programs has room for 424, and `wide` shows them all.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module cb_video
(
	input             clk,
	input             reset,
	input             pix_ce,         // 8 MHz
	input             chr_ce,         // 4 MHz, coincides with every second pix_ce
	input             pix_left,       // pix_ce of the left dot of a character
	input             wide,           // show all 212 visible bytes, not MAME's 180

	// CPU access to the TMS34061 window 0x5800-0x5FFF (one byte).
	input             tms_start,      // pulse
	input      [10:0] tms_offs,
	input       [7:0] tms_row,        // row latch at 0x4000
	input             tms_we,
	input       [7:0] tms_wdata,
	output            tms_done,       // pulse
	output      [7:0] tms_rdata,
	output            irq,            // vertical interrupt -> main CPU FIRQ

	// Display
	output reg        ce_pix,         // one clock after the colour changes
	output reg  [7:0] r,
	output reg  [7:0] g,
	output reg  [7:0] b,
	output reg        hs,             // active high
	output reg        vs,             // active high
	output reg        hblank,
	output reg        vblank,
	output            vblank_start    // pulse
);

// ---------------------------------------------------------------------------
// TMS34061

wire [15:0] dispstart;
wire  [9:0] hcnt, vcnt, h_end_blank;
wire        t_hs, t_vs, t_hb, t_vb, line_start, display_on, next_visible;
wire  [7:0] next_y;

wire        vr_start, vr_we;
wire [17:0] vr_addr;
wire  [7:0] vr_vdata;
reg         vr_done;
reg   [7:0] vr_rdata;

it8_tms34061 #(.CB(1)) tms
(
	.clk          (clk),
	.reset        (reset),
	.chr_ce       (chr_ce),
	.raster09     (1'b0),
	.op_start     (tms_start),
	.op_offs      ({1'b0, tms_offs}),
	.op_row       (tms_row),
	.op_we        (tms_we),
	.op_wdata     (tms_wdata),
	.op_done      (tms_done),
	.op_rdata     (tms_rdata),
	.latch_we     (1'b0),
	.latch_wdata  (8'h00),
	.latch        (),
	.xyaddress    (),
	.xyoffset     (),
	.vr_start     (vr_start),
	.vr_addr      (vr_addr),
	.vr_we        (vr_we),
	.vr_vdata     (vr_vdata),
	.vr_ldata     (),
	.vr_done      (vr_done),
	.vr_rdata     (vr_rdata),
	.cp_start     (),
	.cp_src       (),
	.cp_dst       (),
	.cp_fill      (),
	.cp_done      (1'b0),
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
	.h_end_sync   (),
	.h_end_blank  (h_end_blank),
	.dispstart    (dispstart),
	.display_on   (display_on),
	.irq          (irq)
);

// ---------------------------------------------------------------------------
// VRAM: one read port shared by the CPU and the line fetch (the CPU goes
// first), one write port for the CPU.

wire [15:0] rd_addr;
wire  [7:0] rd_data;
reg         wr_en;
reg  [15:0] wr_addr;
reg   [7:0] wr_data;

it8_sdpram #(.AW(16), .DW(8)) vram
(
	.clk     (clk),
	.rd_addr (rd_addr),
	.rd_data (rd_data),
	.wr_addr (wr_addr),
	.wr_data (wr_data),
	.wr_en   (wr_en)
);

reg         cpu_rd;               // CPU read waiting for the read port
reg  [15:0] cpu_addr;
reg         cpu_rd_d;             // read data for the CPU arrives this clock
reg         fetch_on;
reg   [7:0] fetch_row;
reg   [8:0] fetch_idx;            // next byte to read
reg         fetch_d;              // read data for the fetch arrives this clock
reg   [7:0] fetch_idx_d;

reg         lb_we;
reg   [7:0] lb_waddr;
reg   [7:0] lb_wdata;

// The read address goes to the RAM directly, so its data is there on the
// next clock (cpu_rd_d / fetch_d).
wire        fetch_new = line_start && next_visible;
wire        use_cpu   = cpu_rd;
wire        use_fetch = !cpu_rd && fetch_on && !fetch_new;
assign      rd_addr   = use_cpu ? cpu_addr : {fetch_row, fetch_idx[7:0]};

reg   [3:0] pal_r[0:15];
reg   [3:0] pal_g[0:15];
reg   [3:0] pal_b[0:15];

always @(posedge clk) begin
	vr_done  <= 1'b0;
	wr_en    <= 1'b0;
	lb_we    <= 1'b0;
	cpu_rd_d <= 1'b0;
	fetch_d  <= 1'b0;

	// Read data from the previous clock.
	if (cpu_rd_d) begin
		vr_rdata <= rd_data;
		vr_done  <= 1'b1;
	end
	if (fetch_d) begin
		lb_we    <= 1'b1;
		lb_waddr <= fetch_idx_d;
		lb_wdata <= rd_data;
		if (fetch_idx_d < 8'd32) begin
			if (!fetch_idx_d[0]) pal_r[fetch_idx_d[4:1]] <= rd_data[3:0];
			else begin
				pal_g[fetch_idx_d[4:1]] <= rd_data[7:4];
				pal_b[fetch_idx_d[4:1]] <= rd_data[3:0];
			end
		end
	end

	if (reset) begin
		cpu_rd   <= 1'b0;
		fetch_on <= 1'b0;
	end
	else begin
		// CPU requests: writes go straight to the write port.
		if (vr_start) begin
			if (vr_we) begin
				wr_en   <= 1'b1;
				wr_addr <= vr_addr[15:0];
				wr_data <= vr_vdata;
				vr_done <= 1'b1;
			end
			else begin
				cpu_rd   <= 1'b1;
				cpu_addr <= vr_addr[15:0];
			end
		end

		// Line fetch starts as the line before the next visible one ends.
		if (fetch_new) begin
			fetch_on  <= 1'b1;
			fetch_row <= dispstart[9:2] + next_y;
			fetch_idx <= 9'd0;
		end

		// Read port: the CPU first, then the fetch.
		if (use_cpu) begin
			cpu_rd   <= 1'b0;
			cpu_rd_d <= 1'b1;
		end
		else if (use_fetch) begin
			fetch_idx_d <= fetch_idx[7:0];
			fetch_d     <= 1'b1;
			fetch_idx   <= fetch_idx + 9'd1;
			if (fetch_idx == 9'd255) fetch_on <= 1'b0;
		end
	end
end

// ---------------------------------------------------------------------------
// Line buffer and display pipeline

wire  [9:0] vis_idx  = hcnt - h_end_blank;             // visible byte count
wire  [7:0] disp_col = vis_idx[7:0] + 8'd32;
wire        in_win   = (vis_idx < (wide ? 10'd212 : 10'd180));
wire  [7:0] lb_rdata;

it8_sdpram #(.AW(8), .DW(8)) line_buf
(
	.clk     (clk),
	.rd_addr (disp_col),
	.rd_data (lb_rdata),
	.wr_addr (lb_waddr),
	.wr_data (lb_wdata),
	.wr_en   (lb_we)
);

// Stage 1 (on pix_ce): pixel value and raster flags for this dot.
reg   [3:0] s1_pix;
reg         s1_hs, s1_vs, s1_hb, s1_vb, s1_on;

always @(posedge clk) begin
	if (pix_ce) begin
		s1_pix <= pix_left ? lb_rdata[7:4] : lb_rdata[3:0];
		s1_hs  <= t_hs;
		s1_vs  <= t_vs;
		s1_hb  <= t_hb | ~in_win;
		s1_vb  <= t_vb;
		s1_on  <= display_on;
	end
end

// Stage 2 (next pix_ce): the line's palette.
always @(posedge clk) begin
	ce_pix <= pix_ce;
	if (pix_ce) begin
		hs     <= s1_hs;
		vs     <= s1_vs;
		hblank <= s1_hb;
		vblank <= s1_vb;
		if (s1_hb || s1_vb || !s1_on) {r, g, b} <= 24'd0;
		else begin
			r <= {2{pal_r[s1_pix]}};
			g <= {2{pal_g[s1_pix]}};
			b <= {2{pal_b[s1_pix]}};
		end
	end
end

endmodule
