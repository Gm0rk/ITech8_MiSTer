//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_sound.sv - external YM3812 sound board (P/N 1038 REV2)
//
//  6809 at 2 MHz (8 MHz crystal / 4) with 2 KB RAM and a 32 KB program ROM,
//  a YM3812 for music, an OKI M6295 for speech and a 6522 VIA whose timer 1
//  paces the sound driver. Map (MAME sound3812_external_map):
//
//    1000        R    command latch from the main CPU (read clears IRQ)
//    2000-2001   RW   YM3812
//    3000-37FF   RW   RAM
//    4000        RW   OKI M6295
//    5000-500F   RW   6522 VIA
//    8000-FFFF   R    program ROM
//
//  IRQ comes from the command latch, FIRQ from the VIA or the YM3812.
//  The OKI's 256 KB sample ROM lives in SDRAM bank 2.
//
//  ym2203 selects the sound section of the 6809 boards of Strata Bowling
//  style (MAME sound2203_map): the same CPU, RAM, ROM and OKI, a YM2203 at
//  2000-2003 (A1 ignored) instead of the YM3812, no VIA, FIRQ from the
//  YM2203. Its port B bit 0 is read back by the main CPU (special). Mix as
//  MAME: FM 0.75, each SSG channel 0.07, OKI 0.75.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_sound
(
	input                    clk,
	input                    reset,
	input                    fall_e,        // 6809 E falling edge (2 MHz)
	input                    fall_q,        // 6809 Q falling edge
	input                    ym_cen,        // 4 MHz
	input                    oki_cen,       // 1 MHz
	input                    ym2203,        // 6809 board sound map (see above)

	input                    cmd_we,        // main CPU write to the command latch
	input              [7:0] cmd,

	input                    rom_we,        // loader: 6809 program ROM
	input             [14:0] rom_addr,
	input              [7:0] rom_din,

	output reg        [23:0] pcm_addr,      // SDRAM word address, toggle handshake
	output reg               pcm_req,
	input                    pcm_ack,
	input             [15:0] pcm_data,

	input              [1:0] mix_sel,       // 0 = MAME balance, 1 = FM only, 2 = PCM only
	output reg signed [15:0] audio,
	output             [7:0] via_pb,        // coin counter, ticket motor, LED
	output                   special,       // to the main CPU's input port 40 bit 0

	output reg        [15:0] dbg_cmds,
	output reg         [7:0] dbg_last_cmd,
	output            [15:0] dbg_pc
);

localparam [23:0] PCM_BASE = 24'h800000;    // SDRAM word address of bank 2

// ---------------------------------------------------------------------------
// 6809

wire [15:0] addr;
wire  [7:0] cpu_dout;
wire        rnw;
reg   [7:0] cpu_din;

reg         cmd_pend;
reg   [7:0] cmd_latch;
wire        via_irq;
wire        ym_irq_n;
wire        ym3_irq_n;                  // YM2203 (6809 boards)

mc6809is #(.ILLEGAL_INSTRUCTIONS("GHOST")) cpu
(
	.CLK      (clk),
	.fallE_en (fall_e),
	.fallQ_en (fall_q),
	.D        (cpu_din),
	.DOut     (cpu_dout),
	.ADDR     (addr),
	.RnW      (rnw),
	.BS       (),
	.BA       (),
	.nIRQ     (~cmd_pend),
	.nFIRQ    (ym2203 ? ym3_irq_n : ~(via_irq | ~ym_irq_n)),
	.nNMI     (1'b1),
	.AVMA     (),
	.BUSY     (),
	.LIC      (),
	.nHALT    (1'b1),
	.nRESET   (~reset),
	.nDMABREQ (1'b1),
	.RegData  ()
);

assign dbg_pc = addr;

wire sel_latch = (addr == 16'h1000);
wire sel_ym    = !ym2203 && (addr[15:1] == 15'h1000);   // 2000-2001
wire sel_ym3   =  ym2203 && (addr[15:2] == 14'h0800);   // 2000-2003
wire sel_ram   = (addr[15:11] == 5'b00110);             // 3000-37FF
wire sel_oki   = (addr == 16'h4000);
wire sel_via   = !ym2203 && (addr[15:4] == 12'h500);
wire sel_rom   = addr[15];

// Accesses complete at the falling edge of E.
wire wr = fall_e & ~rnw;
wire rd = fall_e &  rnw;

// ---------------------------------------------------------------------------
// Memory

wire [7:0] rom_q, ram_q;

it8_sdpram #(.AW(15), .DW(8)) prog_rom
(
	.clk     (clk),
	.rd_addr (addr[14:0]),
	.rd_data (rom_q),
	.wr_addr (rom_addr),
	.wr_data (rom_din),
	.wr_en   (rom_we)
);

it8_sdpram #(.AW(11), .DW(8)) work_ram
(
	.clk     (clk),
	.rd_addr (addr[10:0]),
	.rd_data (ram_q),
	.wr_addr (addr[10:0]),
	.wr_data (cpu_dout),
	.wr_en   (wr & sel_ram)
);

// ---------------------------------------------------------------------------
// Command latch

always @(posedge clk) begin
	if (reset) begin
		cmd_pend     <= 1'b0;
		dbg_cmds     <= 16'd0;
		dbg_last_cmd <= 8'd0;
	end
	else begin
		if (rd & sel_latch) cmd_pend <= 1'b0;
		if (cmd_we) begin
			cmd_latch    <= cmd;
			cmd_pend     <= 1'b1;
			dbg_cmds     <= dbg_cmds + 16'd1;
			dbg_last_cmd <= cmd;
		end
	end
end

// ---------------------------------------------------------------------------
// VIA

wire [7:0] via_dout;

it8_via6522 via
(
	.clk    (clk),
	.reset  (reset),
	.phi2   (fall_e),
	.cs     (sel_via),
	.rw     (rnw),
	.rs     (addr[3:0]),
	.din    (cpu_dout),
	.dout   (via_dout),
	.pa_in  (8'hFF),
	.pb_in  (8'hFF),
	.pa_out (),
	.pb_out (via_pb),
	.irq    (via_irq)
);

// ---------------------------------------------------------------------------
// YM3812

wire  [7:0] ym_dout;
wire signed [15:0] fm;

jtopl2 ym3812
(
	.rst    (reset),
	.clk    (clk),
	.cen    (ym_cen),
	.din    (cpu_dout),
	.addr   (addr[0]),
	.cs_n   (~(wr & sel_ym)),
	.wr_n   (1'b0),
	.dout   (ym_dout),
	.irq_n  (ym_irq_n),
	.snd    (fm),
	.sample ()
);

// ---------------------------------------------------------------------------
// YM2203 (6809 boards)

wire  [7:0] ym3_dout, ym3_iob;
wire        ym3_iob_oe;
reg         special_q;
wire  [7:0] psg_a, psg_b, psg_c;
wire signed [15:0] fm3;

jt03 ym2203_chip
(
	.rst        (reset),
	.clk        (clk),
	.cen        (ym_cen),
	.din        (cpu_dout),
	.addr       (addr[0]),
	.cs_n       (~(wr & sel_ym3)),
	.wr_n       (1'b0),
	.dout       (ym3_dout),
	.irq_n      (ym3_irq_n),
	.IOA_in     (8'hFF),
	.IOB_in     (8'hFF),
	.IOA_out    (),
	.IOB_out    (ym3_iob),
	.IOA_oe     (),
	.IOB_oe     (ym3_iob_oe),
	.psg_A      (psg_a),
	.psg_B      (psg_b),
	.psg_C      (psg_c),
	.fm_snd     (fm3),
	.psg_snd    (),
	.snd        (),
	.snd_sample (),
	.debug_view ()
);

// MAME sees port B only while it is an output (ym2203_portb_out), and keeps
// the last value otherwise.
always @(posedge clk) begin
	if (reset)           special_q <= 1'b0;
	else if (ym3_iob_oe) special_q <= ym3_iob[0];
end

assign special = ym2203 ? special_q : via_pb[0];

// ---------------------------------------------------------------------------
// OKI M6295 and its sample ROM in SDRAM (one-word cache).

wire  [7:0] oki_dout;
wire [17:0] oki_addr;
wire signed [13:0] pcm;
reg  [16:0] pcm_tag;
reg  [15:0] pcm_word;
reg         pcm_valid, pcm_wait;
wire        pcm_hit = pcm_valid && (pcm_tag == oki_addr[17:1]);

jt6295 #(.INTERPOL(0)) oki
(
	.rst      (reset),
	.clk      (clk),
	.cen      (oki_cen),
	.ss       (1'b1),                // pin 7 high: 1 MHz / 132
	.wrn      (~(wr & sel_oki)),
	.din      (cpu_dout),
	.dout     (oki_dout),
	.rom_addr (oki_addr),
	.rom_data (oki_addr[0] ? pcm_word[7:0] : pcm_word[15:8]),
	.rom_ok   (pcm_hit),
	.sound    (pcm),
	.sample   ()
);

always @(posedge clk) begin
	if (reset) begin
		pcm_valid <= 1'b0;
		pcm_wait  <= 1'b0;
	end
	else if (pcm_wait) begin
		if (pcm_req == pcm_ack) begin
			pcm_word  <= pcm_data;
			pcm_valid <= 1'b1;
			pcm_wait  <= 1'b0;
		end
	end
	else if (!pcm_hit) begin
		pcm_addr  <= PCM_BASE + {7'd0, oki_addr[17:1]};
		pcm_tag   <= oki_addr[17:1];
		pcm_valid <= 1'b0;
		pcm_wait  <= 1'b1;
		pcm_req   <= ~pcm_req;
	end
end

// ---------------------------------------------------------------------------
// CPU read data

always @(*) begin
	if      (sel_rom)   cpu_din = rom_q;
	else if (sel_ram)   cpu_din = ram_q;
	else if (sel_latch) cpu_din = cmd_latch;
	else if (sel_ym)    cpu_din = ym_dout;
	else if (sel_ym3)   cpu_din = ym3_dout;
	else if (sel_oki)   cpu_din = oki_dout;
	else if (sel_via)   cpu_din = via_dout;
	else                cpu_din = 8'h00;
end

// ---------------------------------------------------------------------------
// Mixer: MAME routes both chips to mono at 0.75. One OKI voice at full
// scale (12 bits) matches the YM3812's full scale. The YM2203's SSG
// channels (0-255 each) are 0.07 of full scale (x 9), as on the Capcom
// Bowling board.

wire        [9:0] psg_sum  = {2'b00, psg_a} + {2'b00, psg_b} + {2'b00, psg_c};
wire signed [19:0] fm_in    = ym2203 ? fm3 : fm;
wire signed [19:0] psg_in   = ym2203 ? $signed({10'd0, psg_sum}) * 20'sd9 : 20'sd0;
wire signed [19:0] fm_part  = (mix_sel == 2'd2) ? 20'sd0 : ((fm_in * 20'sd3) >>> 2) + psg_in;
wire signed [19:0] pcm_part = (mix_sel == 2'd1) ? 20'sd0 : pcm * 12;
wire signed [19:0] mix      = fm_part + pcm_part;

always @(posedge clk) begin
	if      (mix >  20'sd32767) audio <= 16'sh7FFF;
	else if (mix < -20'sd32768) audio <= 16'sh8000;
	else                        audio <= mix[15:0];
end

endmodule
