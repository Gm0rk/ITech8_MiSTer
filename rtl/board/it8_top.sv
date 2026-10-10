//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_top.sv - Ninja Clowns main board (P/N 1029 REV3A) and sound board
//
//  68000 at 12 MHz. Memory map (MAME itech8.cpp ninclown_map):
//
//    000000-003FFF  RW  16 KB battery-backed RAM (reads of 0-7: ROM vectors)
//    004000-03FFFF  R   program ROM (SDRAM bank 0)
//    040000-07FFFF  R   empty PROM2/3 sockets, read by the ROM check: D840
//    100080         W   sound command (upper byte)
//    100100         RW  R: coins / service, W: GROM bank
//    100180         RW  R: player 1, W: display page (bit 7)
//    100240         W   TMS34061 colour latch
//    100280         R   player 2
//    100300-10031F  RW  blitter (register = offset / 2)
//    100380-1003FF  RW  RAMDAC (register = offset / 32, upper byte)
//    110000-110FFF  RW  TMS34061
//
//  Interrupts are autovectored: level 3 at the start of vertical blank
//  (held until acknowledged), level 2 from the blitter (until its status
//  register is read).
//
//  cpu09 turns the board into a 6809 board of Strata Bowling style (MAME
//  itech8.cpp stratab_hi): the 68000 is held in reset and it8_main09 drives
//  the same video section (in its two_layer mode, 6 MHz dots), the NVRAM
//  (8 KB of it) and the sound board (in its YM2203 mode). Input ports as
//  MAME's stratab: port 40 service, cabinet and the sound board's feedback
//  bit; port 60 hooks, starts and coins; trackball on blitter registers
//  12-15. Golden Tee Golf uses the same board: its trackball sets the same
//  ports (MAME gtgt, tb_horiz for its axes), its joystick sets (joy09, MAME
//  gtg) the stick and the swing button on port 60 bits 0-4, both players'
//  together. gtg2 is Golden Par Golf's 1992 board (MAME gtg2): it8_main09's
//  other I/O layout, the sound board in its YM3812 mode (as Ninja Clowns'),
//  the sound command's bits rewired, and its own ports (MAME gpgolf; with
//  a trackball, tb09, MAME gtg2: Golden Tee Golf II v2.2). map_lo is MAME's
//  common_lo_map (Golden Tee Golf II joystick, v1.0).
//
//  From build 020 the 6809 board also takes a display mode (disp_mode: 0
//  two layers, 1 Ninja Clowns' 2 page large at 8 MHz with the page bit
//  inverted, MAME hstennis; 2 one 8-bit page, MAME pokrdice), a sound board
//  (snd_mode: 0 as above, 1 the YM3812 board with a PIA, MAME
//  sound3812_map; 2 the YM3812 board with a VIA, as Ninja Clowns', without
//  Golden Par Golf's I/O) and an input layout (in_layout, it8_ports09.sv: 0
//  the ports above, others a game's own from the raw joysticks j0r-j3r).
//  rr (build 026) is Rim Rockin' Basketball's board: it8_main09 at 3 MHz
//  with its bank register, 128 KB program and ports 161-165.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_top
(
	input             clk,            // 48 MHz
	input             reset,
	input             hold,           // freeze the 68000 (NVRAM being saved)

	// Clock enables (it8_ce)
	input             cpu_phi1,
	input             cpu_phi2,
	input             pix_ce,
	input             chr_ce,
	input             pix_left,
	input             snd_fall_e,
	input             snd_fall_q,
	input             ym_cen,
	input             oki_cen,
	input             vid6_ce,        // 6 MHz, 6809 board dots

	// Board variant
	input             cpu09,          // 6809 board (see above)
	input             bank_xor,       // 6809: program bank bit inverted
	input             prog64,         // 6809: 64 KB program, fixed area is its upper half
	input             joy09,          // 6809: joystick and swing button (Golden Tee Golf)
	input             gtg2,           // 6809: Golden Par Golf's board (above)
	input             tb09,           // 6809: the game has a trackball
	input             map_lo,         // 6809: MAME common_lo_map (it8_main09)
	input             rr,             // 6809: Rim Rockin' Basketball's board (it8_main09)
	input             tb_horiz,       // 6809: trackball axes of a horizontal game
	input       [1:0] disp_mode,      // 6809: display layout (above)
	input       [1:0] snd_mode,       // 6809: sound board (above)
	input       [3:0] in_layout,      // 6809: input ports (it8_ports09)
	input      [23:0] grom_size,      // graphics ROM region in bytes

	// Controls, active high
	input       [7:0] p1,             // {punch, kick, right, left, down, up, start, throw}
	input       [7:0] p2,
	input             coin1,
	input             coin2,
	input             service,
	input             test,
	input       [7:0] track_x,        // trackball counters (cb_trackball)
	input       [7:0] track_y,
	input      [15:0] j0r,            // 6809, in_layout != 0: MiSTer joysticks
	input      [15:0] j1r,            //   as they come (it8_ports09)
	input      [15:0] j2r,
	input      [15:0] j3r,

	// SDRAM: 68000 program ROM
	output            rom_req,
	output     [21:0] rom_addr,
	input             rom_accept,
	input             rom_ack,
	input      [15:0] rom_data,
	output            rom_quiet,

	// SDRAM: graphics ROM (blitter) and OKI samples, toggle handshake
	output     [23:0] grom_addr,
	output            grom_req,
	input             grom_ack,
	input      [15:0] grom_data,
	output     [23:0] pcm_addr,
	output            pcm_req,
	input             pcm_ack,
	input      [15:0] pcm_data,

	// Loader
	input             vec_we,         // first 8 bytes of the program ROM
	input       [2:0] vec_addr,
	input       [7:0] vec_din,
	input             snd_rom_we,
	input      [14:0] snd_rom_addr,
	input       [7:0] snd_rom_din,

	// NVRAM, MiSTer side
	input      [13:0] nv_addr,
	input       [7:0] nv_din,
	input             nv_we,
	output      [7:0] nv_dout,
	output            nv_written,     // pulse: the 68000 wrote its RAM

	// Video
	output            ce_pix,
	output      [7:0] r,
	output      [7:0] g,
	output      [7:0] b,
	output            hs,
	output            vs,
	output            hblank,
	output            vblank,

	// Audio
	input       [1:0] mix_sel,
	output     [15:0] audio,

	// Debug (6809 board: bus address, NMIs for level 3, FIRQs for level 2,
	// stretched E cycles for wait states)
	output     [23:0] dbg_pc,         // last program fetch
	output     [15:0] dbg_frames,
	output     [15:0] dbg_irq3,
	output     [15:0] dbg_irq2,
	output     [15:0] dbg_waits,      // 68000 ROM reads that needed a wait state
	output     [15:0] dbg_blits,
	output     [15:0] dbg_blit_late,
	output     [15:0] dbg_vram_drop,
	output     [15:0] dbg_snd_cmds,
	output      [7:0] dbg_snd_last,
	output     [15:0] dbg_snd_pc,
	output      [7:0] dbg_page,       // 6809 board: the graphics ROM bank
	output reg [31:0] dbg_nv104       // last value seen at RAM 0x104 (long)
);

// ---------------------------------------------------------------------------
// 68000

wire        ASn, UDSn, LDSn, eRWn;
wire        FC0, FC1, FC2;
wire [23:1] eab;
wire [15:0] oEdb;
reg  [15:0] iEdb;
wire        DTACKn, VPAn;
reg   [2:0] ipl;

fx68k cpu
(
	.clk      (clk),
	.HALTn    (1'b1),
	.extReset (reset | cpu09),
	.pwrUp    (reset | cpu09),
	.enPhi1   (cpu_phi1 & ~hold),
	.enPhi2   (cpu_phi2 & ~hold),
	.eRWn     (eRWn),
	.ASn      (ASn),
	.LDSn     (LDSn),
	.UDSn     (UDSn),
	.E        (),
	.VMAn     (),
	.FC0      (FC0),
	.FC1      (FC1),
	.FC2      (FC2),
	.BGn      (),
	.oRESETn  (),
	.oHALTEDn (),
	.DTACKn   (DTACKn),
	.VPAn     (VPAn),
	.BERRn    (1'b1),
	.BRn      (1'b1),
	.BGACKn   (1'b1),
	.IPL0n    (~ipl[0]),
	.IPL1n    (~ipl[1]),
	.IPL2n    (~ipl[2]),
	.iEdb     (iEdb),
	.oEdb     (oEdb),
	.eab      (eab)
);

wire [23:0] a    = {eab, 1'b0};
wire        as   = ~ASn;
wire        uds  = ~UDSn;
wire        lds  = ~LDSn;
wire        ds   = uds | lds;
wire        rd   = eRWn;
wire        iack = FC2 & FC1 & FC0;

// ---------------------------------------------------------------------------
// Address decode

wire sel_ram   = !iack && (a[23:14] == 10'd0);
wire sel_vec   = sel_ram && (a[13:3] == 11'd0) && rd;
wire sel_rom   = !iack && (a[23:18] == 6'd0) && (a[17:14] != 4'd0);
wire sel_const = !iack && (a[23:18] == 6'b000001);
wire sel_io    = !iack && (a[23:10] == 14'h0400);
wire sel_tms   = !iack && (a[23:12] == 12'h110);

wire io_snd    = sel_io && (a[9:1] == 9'h040);        // 100080
wire io_in40   = sel_io && (a[9:1] == 9'h080);        // 100100
wire io_in60   = sel_io && (a[9:1] == 9'h0C0);        // 100180
wire io_latch  = sel_io && (a[9:1] == 9'h120);        // 100240
wire io_in80   = sel_io && (a[9:1] == 9'h140);        // 100280
wire io_blt    = sel_io && (a[9:5] == 5'b11000);      // 100300-10031F
wire io_dac    = sel_io && (a[9:7] == 3'b111);        // 100380-1003FF

wire rom_read  = sel_rom && rd;

// ---------------------------------------------------------------------------
// Bus cycle control

localparam [2:0] B_IDLE = 3'd0;   // waiting for a data strobe
localparam [2:0] B_IORD = 3'd1;   // I/O read side effects issued, capture next
localparam [2:0] B_TMSH = 3'd2;   // TMS34061 upper byte in progress
localparam [2:0] B_TMSL = 3'd3;   // TMS34061 lower byte in progress
localparam [2:0] B_DONE = 3'd4;   // DTACK asserted until AS rises

reg   [2:0] bst;
reg         dtack;
reg  [15:0] io_rdata;
reg         rom_taken, rom_valid;
reg   [7:0] vec[0:7];

// Board registers
reg   [7:0] grom_bank;
reg         page_sel;
reg   [7:0] m68_page;
reg         vbl_irq;

// Device strobes
reg         blt_we, blt_re, dac_we, dac_re, latch_we, snd_we;
reg   [7:0] dev_wdata;            // upper-lane devices
reg   [7:0] blt_wdata;            // blitter: a word write ends with the lower byte, as MAME
reg   [3:0] blt_idx;
reg         tms_start, tms_we;
reg  [11:0] tms_offs;
reg   [7:0] tms_wdata;
wire        tms_done;
wire  [7:0] tms_rdata, blt_rdata, dac_rdata;
wire        blt_irq;
wire        vblank_start;

wire        m9_rom_req, m9_rom_quiet;
wire [21:0] m9_rom_addr;
wire [12:0] m9_nv_addr;
wire [15:0] m9_nv_din;
wire  [1:0] m9_nv_we;
wire        m9_nv_written;

assign rom_req   = cpu09 ? m9_rom_req   : as && rom_read && !rom_taken;
assign rom_addr  = cpu09 ? m9_rom_addr  : a[22:1];
assign rom_quiet = cpu09 ? m9_rom_quiet : reset || (as && !(rom_read && !rom_taken));
assign DTACKn    = ~(dtack | (as && rom_read && (rom_valid || rom_ack)));
assign VPAn      = ~(as && iack);

wire [15:0] nv_q;
wire  [1:0] nv_we_cpu = (as && sel_ram && !rd && bst == B_IDLE && ds) ? {uds, lds} : 2'b00;
assign      nv_written = cpu09 ? m9_nv_written : |nv_we_cpu;


// Controls, active low on the board.
wire  [7:0] in40 = {2'b11, ~coin1, ~coin2, 2'b11, ~test, ~service};
wire  [7:0] in60 = ~{p1[7], p1[6], p1[5], p1[4], p1[3], p1[2], p1[1], p1[0]};
wire  [7:0] in80 = ~{p2[7], p2[6], p2[5], p2[4], p2[3], p2[2], p2[1], p2[0]};

always @(posedge clk) begin
	blt_we    <= 1'b0;
	blt_re    <= 1'b0;
	dac_we    <= 1'b0;
	dac_re    <= 1'b0;
	latch_we  <= 1'b0;
	snd_we    <= 1'b0;
	tms_start <= 1'b0;

	if (rom_accept) rom_taken <= 1'b1;
	if (rom_ack)    rom_valid <= 1'b1;

	if (reset || cpu09) begin
		bst        <= B_IDLE;
		dtack      <= 1'b0;
		rom_taken  <= 1'b0;
		rom_valid  <= 1'b0;
		grom_bank  <= 8'd0;
		page_sel   <= 1'b0;
		vbl_irq    <= 1'b0;
		m68_page   <= 8'h00;
	end
	else if (!as) begin
		bst       <= B_IDLE;
		dtack     <= 1'b0;
		rom_taken <= 1'b0;
		rom_valid <= 1'b0;
	end
	else if (iack) begin
		// Autovectored: VPA does the work. Level 3 is a held line.
		if (a[3:1] == 3'd3) vbl_irq <= 1'b0;
	end
	else case (bst)
		B_IDLE: if (ds && !rom_read) begin
			dev_wdata <= oEdb[15:8];
			blt_wdata <= lds ? oEdb[7:0] : oEdb[15:8];
			if (sel_tms) begin
				tms_offs  <= {a[11:1], ~uds};
				tms_we    <= !rd;
				tms_wdata <= uds ? oEdb[15:8] : oEdb[7:0];
				tms_start <= 1'b1;
				bst       <= uds ? B_TMSH : B_TMSL;
			end
			else if (rd) begin
				// Reads with side effects are strobed once here, and the
				// data is captured on the next clock.
				blt_idx <= a[4:1];
				if (io_blt) blt_re <= 1'b1;
				if (io_dac && uds) dac_re <= 1'b1;
				bst <= B_IORD;
			end
			else begin
				if (io_snd && uds)   snd_we   <= 1'b1;
				if (io_latch && uds) latch_we <= 1'b1;
				if (io_in40 && uds)  grom_bank <= oEdb[15:8];
				if (io_in60 && uds) begin
					page_sel <= oEdb[15];
					m68_page <= oEdb[15:8];
				end
				if (io_blt) begin
					blt_idx <= a[4:1];
					blt_we  <= 1'b1;
				end
				if (io_dac && uds) dac_we <= 1'b1;
				dtack <= 1'b1;
				bst   <= B_DONE;
			end
		end

		B_IORD: begin
			if      (sel_vec)   io_rdata <= {vec[{a[2:1], 1'b0}], vec[{a[2:1], 1'b1}]};
			else if (sel_ram)   io_rdata <= nv_q;
			else if (sel_const) io_rdata <= 16'hD840;
			else if (io_in40)   io_rdata <= {in40, 8'h00};
			else if (io_in60)   io_rdata <= {in60, 8'h00};
			else if (io_in80)   io_rdata <= {in80, 8'h00};
			else if (io_blt)    io_rdata <= {blt_rdata, blt_rdata};
			else if (io_dac)    io_rdata <= {dac_rdata, 8'h00};
			else                io_rdata <= 16'h0000;
			dtack <= 1'b1;
			bst   <= B_DONE;
		end

		B_TMSH: if (tms_done) begin
			io_rdata[15:8] <= tms_rdata;
			if (lds) begin
				tms_offs  <= {a[11:1], 1'b1};
				tms_wdata <= oEdb[7:0];
				tms_start <= 1'b1;
				bst       <= B_TMSL;
			end
			else begin
				dtack <= 1'b1;
				bst   <= B_DONE;
			end
		end

		B_TMSL: if (tms_done) begin
			io_rdata[7:0] <= tms_rdata;
			dtack <= 1'b1;
			bst   <= B_DONE;
		end

		// The strobes rise together with AS at the end of a cycle, except
		// between the read and write halves of a read-modify-write (TAS),
		// where AS stays low: start over for the write.
		B_DONE: if (!ds) begin
			dtack <= 1'b0;
			bst   <= B_IDLE;
		end

		default: ;
	endcase

	if (vblank_start) vbl_irq <= 1'b1;
end

always @(*) begin
	if (rom_read) iEdb = rom_data;
	else          iEdb = io_rdata;
end

// Interrupt priority encoder.
always @(posedge clk) begin
	if (reset)        ipl <= 3'd0;
	else if (vbl_irq) ipl <= 3'd3;
	else if (blt_irq) ipl <= 3'd2;
	else              ipl <= 3'd0;
end

// Debug: the long at RAM 0x104, a credit setting the game divides by
// (0x17450). Zero here means the NVRAM image the game accepted was bad.
// FFFFFFFF from reset until the 68000 first touches it.
wire nv104 = sel_ram && (a[13:2] == 12'h041);

always @(posedge clk) begin
	if (reset) dbg_nv104 <= 32'hFFFFFFFF;
	else begin
		if (nv104 && nv_we_cpu[1]) begin
			if (a[1]) dbg_nv104[15:8]  <= oEdb[15:8];
			else      dbg_nv104[31:24] <= oEdb[15:8];
		end
		if (nv104 && nv_we_cpu[0]) begin
			if (a[1]) dbg_nv104[7:0]   <= oEdb[7:0];
			else      dbg_nv104[23:16] <= oEdb[7:0];
		end
		if (nv104 && as && bst == B_IORD) begin
			if (a[1]) dbg_nv104[15:0]  <= nv_q;
			else      dbg_nv104[31:16] <= nv_q;
		end
	end
end

// ROM vectors, captured by the loader.
always @(posedge clk) if (vec_we) vec[vec_addr] <= vec_din;

// ---------------------------------------------------------------------------
// Work RAM

it8_nvram nvram
(
	.clk      (clk),
	.cpu_addr (cpu09 ? m9_nv_addr : a[13:1]),
	.cpu_din  (cpu09 ? m9_nv_din  : oEdb),
	.cpu_we   (cpu09 ? m9_nv_we   : nv_we_cpu),
	.cpu_dout (nv_q),
	.hps_addr (nv_addr),
	.hps_din  (nv_din),
	.hps_we   (nv_we),
	.hps_dout (nv_dout)
);

// ---------------------------------------------------------------------------
// 6809 main CPU's device lines (it8_main09, below)

wire        m9_tms_start, m9_tms_we, m9_latch_we, m9_blt_we, m9_blt_re;
wire        m9_dac_we, m9_snd_we;
wire [11:0] m9_tms_offs;
wire  [3:0] m9_blt_idx;
wire  [1:0] m9_dac_idx;
wire  [7:0] m9_wdata, m9_grom_bank, m9_page;
wire [31:0] m9_an;
wire        tms_irq, special;
wire [15:0] m9_pc, m9_frames, m9_nmi, m9_firq, m9_waits;

// ---------------------------------------------------------------------------
// Video

// 6809 display modes: 1 (2 page large) runs at Ninja Clowns' 8 MHz, the
// others one byte per 6 MHz dot. MAME's 6809 2 page large shows the page
// whose bit 7 of the page register is clear (Ninja Clowns writes it
// inverted, so it8_video takes bit 7 set as page 1).
wire m9_dots6 = cpu09 & ~disp_mode[0];

it8_video video
(
	.clk           (clk),
	.reset         (reset),
	.pix_ce        (m9_dots6 ? vid6_ce : pix_ce),
	.chr_ce        (m9_dots6 ? vid6_ce : chr_ce),
	.pix_left      (m9_dots6 | pix_left),
	.two_layer     (cpu09 & (disp_mode == 2'd0)),
	.page8         (cpu09 & (disp_mode == 2'd2)),
	.col_eb        (cpu09),
	.page_sel      (cpu09 ? m9_page[7] ^ (disp_mode == 2'd1) : page_sel),
	.grom_bank     (cpu09 ? m9_grom_bank : grom_bank),
	.grom_size     (grom_size),
	.an            (cpu09 ? m9_an : 32'd0),
	.tms_irq       (tms_irq),
	.tms_start     (cpu09 ? m9_tms_start : tms_start),
	.tms_offs      (cpu09 ? m9_tms_offs  : tms_offs),
	.tms_we        (cpu09 ? m9_tms_we    : tms_we),
	.tms_wdata     (cpu09 ? m9_wdata     : tms_wdata),
	.tms_done      (tms_done),
	.tms_rdata     (tms_rdata),
	.latch_we      (cpu09 ? m9_latch_we  : latch_we),
	.latch_wdata   (cpu09 ? m9_wdata     : dev_wdata),
	.blt_we        (cpu09 ? m9_blt_we    : blt_we),
	.blt_re        (cpu09 ? m9_blt_re    : blt_re),
	.blt_idx       (cpu09 ? m9_blt_idx   : blt_idx),
	.blt_wdata     (cpu09 ? m9_wdata     : blt_wdata),
	.blt_rdata     (blt_rdata),
	.blt_irq       (blt_irq),
	.dac_we        (cpu09 ? m9_dac_we    : dac_we),
	.dac_re        (dac_re & ~cpu09),
	.dac_idx       (cpu09 ? m9_dac_idx   : a[6:5]),
	.dac_wdata     (cpu09 ? m9_wdata     : dev_wdata),
	.dac_rdata     (dac_rdata),
	.rom_addr      (grom_addr),
	.rom_req       (grom_req),
	.rom_ack       (grom_ack),
	.rom_data      (grom_data),
	.ce_pix        (ce_pix),
	.r             (r),
	.g             (g),
	.b             (b),
	.hs            (hs),
	.vs            (vs),
	.hblank        (hblank),
	.vblank        (vblank),
	.vblank_start  (vblank_start),
	.dbg_vcnt      (),
	.dbg_blits     (dbg_blits),
	.dbg_blit_late (dbg_blit_late),
	.dbg_vram_drop (dbg_vram_drop)
);

// ---------------------------------------------------------------------------
// 6809 main CPU (cpu09)


// Input ports (it8_ports09.sv).
wire  [7:0] in40_09, in60_09, in80_09;
wire [39:0] inx_09;

it8_ports09 ports09
(
	.layout  (in_layout),
	.joy09   (joy09),
	.gtg2    (gtg2),
	.tb09    (tb09),
	.p1      (p1),
	.p2      (p2),
	.coin1   (coin1),
	.coin2   (coin2),
	.service (service),
	.j0      (j0r),
	.j1      (j1r),
	.j2      (j2r),
	.j3      (j3r),
	.test    (test),
	.special (special),
	.in40    (in40_09),
	.in60    (in60_09),
	.in80    (in80_09),
	.inx     (inx_09)
);

// A dial on blitter register 13 (it8_main09): Wheel Of Fortune's reads the
// counter, Peggle's (trackball set) the count since register 12 was written.
wire  [1:0] dial_mode = (in_layout == 4'd1) ? 2'd1 : (in_layout == 4'd7) ? 2'd2 : 2'd0;

// Golden Par Golf's board wires the sound command's bits in another order
// (MAME gtg2_sound_data_w).
wire  [7:0] snd09 = gtg2 ? {m9_wdata[6], m9_wdata[1], m9_wdata[4], m9_wdata[3],
                            m9_wdata[2], m9_wdata[5], m9_wdata[0], m9_wdata[7]}
                         : m9_wdata;

it8_main09 main09
(
	.clk          (clk),
	.reset        (reset | ~cpu09),
	.hold         (hold),
	.bank_xor     (bank_xor),
	.prog64       (prog64),
	.map_gtg2     (gtg2),
	.map_lo       (map_lo),
	.rr           (rr),
	.tb_horiz     (tb_horiz),
	.dial_mode    (dial_mode),
	.in40         (in40_09),
	.in60         (in60_09),
	.in80         (in80_09),
	.inx          (inx_09),
	.track_x      (track_x),
	.track_y      (track_y),
	.rom_req      (m9_rom_req),
	.rom_addr     (m9_rom_addr),
	.rom_accept   (rom_accept),
	.rom_ack      (rom_ack),
	.rom_data     (rom_data),
	.rom_quiet    (m9_rom_quiet),
	.tms_start    (m9_tms_start),
	.tms_offs     (m9_tms_offs),
	.tms_we       (m9_tms_we),
	.tms_done     (tms_done),
	.tms_rdata    (tms_rdata),
	.latch_we     (m9_latch_we),
	.blt_we       (m9_blt_we),
	.blt_re       (m9_blt_re),
	.blt_idx      (m9_blt_idx),
	.blt_rdata    (blt_rdata),
	.dac_we       (m9_dac_we),
	.dac_idx      (m9_dac_idx),
	.snd_we       (m9_snd_we),
	.wdata        (m9_wdata),
	.grom_bank    (m9_grom_bank),
	.page         (m9_page),
	.an           (m9_an),
	.nv_addr      (m9_nv_addr),
	.nv_din       (m9_nv_din),
	.nv_we        (m9_nv_we),
	.nv_q         (nv_q),
	.nv_written   (m9_nv_written),
	.vblank_start (vblank_start),
	.tms_irq      (tms_irq),
	.blt_irq      (blt_irq),
	.dbg_pc       (m9_pc),
	.dbg_frames   (m9_frames),
	.dbg_nmi      (m9_nmi),
	.dbg_firq     (m9_firq),
	.dbg_waits    (m9_waits)
);

// ---------------------------------------------------------------------------
// Sound board

it8_sound sound
(
	.clk          (clk),
	.reset        (reset),
	.fall_e       (snd_fall_e),
	.fall_q       (snd_fall_q),
	.ym_cen       (ym_cen),
	.oki_cen      (oki_cen),
	.ym2203       (cpu09 & ~gtg2 & (snd_mode == 2'd0)),
	.pia_brd      (cpu09 & (snd_mode == 2'd1)),
	.cmd_we       (cpu09 ? m9_snd_we : snd_we),
	.cmd          (cpu09 ? snd09     : dev_wdata),
	.rom_we       (snd_rom_we),
	.rom_addr     (snd_rom_addr),
	.rom_din      (snd_rom_din),
	.pcm_addr     (pcm_addr),
	.pcm_req      (pcm_req),
	.pcm_ack      (pcm_ack),
	.pcm_data     (pcm_data),
	.mix_sel      (mix_sel),
	.audio        (audio),
	.via_pb       (),
	.special      (special),
	.dbg_cmds     (dbg_snd_cmds),
	.dbg_last_cmd (dbg_snd_last),
	.dbg_pc       (dbg_snd_pc)
);

// ---------------------------------------------------------------------------
// Debug counters

reg        as_d;
reg [23:0] m68_pc;
reg [15:0] m68_frames, m68_irq3, m68_irq2, m68_waits;

assign dbg_pc     = cpu09 ? {8'd0, m9_pc} : m68_pc;
assign dbg_frames = cpu09 ? m9_frames     : m68_frames;
assign dbg_irq3   = cpu09 ? m9_nmi        : m68_irq3;
assign dbg_irq2   = cpu09 ? m9_firq       : m68_irq2;
assign dbg_waits  = cpu09 ? m9_waits      : m68_waits;
assign dbg_page   = cpu09 ? m9_grom_bank  : m68_page;

always @(posedge clk) begin
	as_d <= as;
	if (reset) begin
		m68_frames <= 16'd0;
		m68_irq3   <= 16'd0;
		m68_irq2   <= 16'd0;
		m68_waits  <= 16'd0;
	end
	else begin
		if (vblank_start) m68_frames <= m68_frames + 16'd1;
		if (as && !as_d && iack && a[3:1] == 3'd3) m68_irq3 <= m68_irq3 + 16'd1;
		if (as && !as_d && iack && a[3:1] == 3'd2) m68_irq2 <= m68_irq2 + 16'd1;
		// The DTACK sample for a zero-wait ROM read is the second ph2 clock
		// after AS; anything later is a wait state.
		if (as && rom_read && cpu_phi2 && !rom_valid && !rom_ack && rom_taken) m68_waits <= m68_waits + 16'd1;
		if (as && !as_d && !FC0 && FC1) m68_pc <= a;
	end
end

endmodule
