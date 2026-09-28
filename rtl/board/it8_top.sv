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

	// Controls, active high
	input       [7:0] p1,             // {punch, kick, right, left, down, up, start, throw}
	input       [7:0] p2,
	input             coin1,
	input             coin2,
	input             service,
	input             test,

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

	// Debug
	output reg [23:0] dbg_pc,         // last program fetch
	output reg [15:0] dbg_frames,
	output reg [15:0] dbg_irq3,
	output reg [15:0] dbg_irq2,
	output reg [15:0] dbg_waits,      // 68000 ROM reads that needed a wait state
	output     [15:0] dbg_blits,
	output     [15:0] dbg_blit_late,
	output     [15:0] dbg_vram_drop,
	output     [15:0] dbg_snd_cmds,
	output      [7:0] dbg_snd_last,
	output     [15:0] dbg_snd_pc,
	output reg  [7:0] dbg_page,
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
	.extReset (reset),
	.pwrUp    (reset),
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

assign rom_req   = as && rom_read && !rom_taken;
assign rom_addr  = a[22:1];
assign rom_quiet = reset || (as && !(rom_read && !rom_taken));
assign DTACKn    = ~(dtack | (as && rom_read && (rom_valid || rom_ack)));
assign VPAn      = ~(as && iack);

wire [15:0] nv_q;
wire  [1:0] nv_we_cpu = (as && sel_ram && !rd && bst == B_IDLE && ds) ? {uds, lds} : 2'b00;
assign      nv_written = |nv_we_cpu;


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

	if (reset) begin
		bst        <= B_IDLE;
		dtack      <= 1'b0;
		rom_taken  <= 1'b0;
		rom_valid  <= 1'b0;
		grom_bank  <= 8'd0;
		page_sel   <= 1'b0;
		vbl_irq    <= 1'b0;
		dbg_page   <= 8'h00;
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
					dbg_page <= oEdb[15:8];
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
	.cpu_addr (a[13:1]),
	.cpu_din  (oEdb),
	.cpu_we   (nv_we_cpu),
	.cpu_dout (nv_q),
	.hps_addr (nv_addr),
	.hps_din  (nv_din),
	.hps_we   (nv_we),
	.hps_dout (nv_dout)
);

// ---------------------------------------------------------------------------
// Video

it8_video video
(
	.clk           (clk),
	.reset         (reset),
	.pix_ce        (pix_ce),
	.chr_ce        (chr_ce),
	.pix_left      (pix_left),
	.page_sel      (page_sel),
	.grom_bank     (grom_bank),
	.tms_start     (tms_start),
	.tms_offs      (tms_offs),
	.tms_we        (tms_we),
	.tms_wdata     (tms_wdata),
	.tms_done      (tms_done),
	.tms_rdata     (tms_rdata),
	.latch_we      (latch_we),
	.latch_wdata   (dev_wdata),
	.blt_we        (blt_we),
	.blt_re        (blt_re),
	.blt_idx       (blt_idx),
	.blt_wdata     (blt_wdata),
	.blt_rdata     (blt_rdata),
	.blt_irq       (blt_irq),
	.dac_we        (dac_we),
	.dac_re        (dac_re),
	.dac_idx       (a[6:5]),
	.dac_wdata     (dev_wdata),
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
// Sound board

it8_sound sound
(
	.clk          (clk),
	.reset        (reset),
	.fall_e       (snd_fall_e),
	.fall_q       (snd_fall_q),
	.ym_cen       (ym_cen),
	.oki_cen      (oki_cen),
	.cmd_we       (snd_we),
	.cmd          (dev_wdata),
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
	.dbg_cmds     (dbg_snd_cmds),
	.dbg_last_cmd (dbg_snd_last),
	.dbg_pc       (dbg_snd_pc)
);

// ---------------------------------------------------------------------------
// Debug counters

reg as_d;
always @(posedge clk) begin
	as_d <= as;
	if (reset) begin
		dbg_frames <= 16'd0;
		dbg_irq3   <= 16'd0;
		dbg_irq2   <= 16'd0;
		dbg_waits  <= 16'd0;
	end
	else begin
		if (vblank_start) dbg_frames <= dbg_frames + 16'd1;
		if (as && !as_d && iack && a[3:1] == 3'd3) dbg_irq3 <= dbg_irq3 + 16'd1;
		if (as && !as_d && iack && a[3:1] == 3'd2) dbg_irq2 <= dbg_irq2 + 16'd1;
		// The DTACK sample for a zero-wait ROM read is the second ph2 clock
		// after AS; anything later is a wait state.
		if (as && rom_read && cpu_phi2 && !rom_valid && !rom_ack && rom_taken) dbg_waits <= dbg_waits + 16'd1;
		if (as && !as_d && !FC0 && FC1) dbg_pc <= a;
	end
end

endmodule
