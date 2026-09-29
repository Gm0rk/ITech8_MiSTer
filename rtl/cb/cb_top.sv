//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  cb_top.sv - Capcom Bowling board (also Coors Light Bowling, and
//  Bowl-O-Rama with its turbo board)
//
//  Main CPU 6809 at 2 MHz (8 MHz / 4). Map (MAME capbowl.cpp):
//
//    0000-3FFF   R    Capcom/Coors: graphics ROM bank (select at 4800)
//    0000-001F   RW   Bowl-O-Rama: turbo board in the GR0 socket
//                       00 R  mask (F in each nibble where the ROM byte is 0)
//                       04 R  ROM byte, then address + 1
//                       08 W  address bits 23:16 (17:16 used)
//                       17 W  address bits 15:8
//                       18 W  address bits 7:0
//    4000        W    row latch (TMS34061 direct access row)
//    4800        W    Capcom/Coors: graphics ROM bank
//    5000-57FF   RW   battery-backed RAM
//    5800-5FFF   RW   TMS34061 (A9:8 function, A7:0 column)
//    6000        W    sound command
//    6800        W    trackball counter reset (and watchdog)
//    7000        R    trackball V nibble, P2 hooks, cabinet, coin 2
//    7800        R    trackball H nibble, P1 hooks, start, coin 1
//    8000-FFFF   R    program ROM
//
//  FIRQ comes from the TMS34061 vertical interrupt. NMI starts the setup
//  menu: MAME pulses it every VBLANK while the service key is held.
//
//  Watchdog: a 555 timer, 16 periods, about 0.32 s (MAME), restarted by
//  every write to 6800. When it runs out the board resets (both CPUs, video,
//  sound; NVRAM kept). Bowl-O-Rama depends on it: at power-up its reset code
//  counts a byte in NVRAM down, parking in a loop for the watchdog between
//  steps, and only starts once the count reaches zero.
//
//  SDRAM bank 0 holds the stream bytes 0x00000-0x1FFFF: the program ROM
//  (CPU 8000-FFFF) at 0x00000, then the graphics ROMs (bank n of the
//  0000-3FFF window at 0x08000 + n * 0x4000). The turbo board ROM is in
//  bank 1, the sound program in bank 2 (cb_sound.sv).
//
//  The CPU runs on its own E cycle of 24 clocks; an access starts in the
//  first clock and E falls only when it has finished (see cb_sound.sv).
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module cb_top
(
	input             clk,            // 48 MHz
	input             reset,
	input             hold,           // freeze both CPUs (NVRAM being saved)
	input             bowlrama,       // turbo board instead of ROM banking
	input             pix_ce,
	input             chr_ce,
	input             pix_left,
	input             ym_cen,         // 4 MHz
	input             wide,           // show the full visible line

	// Controls (active high). track_x/track_y are free-running counters.
	input       [7:0] track_x,
	input       [7:0] track_y,
	input             p1_hook_l,
	input             p1_hook_r,
	input             p2_hook_l,
	input             p2_hook_r,
	input             start,
	input             coin1,
	input             coin2,
	input             service,        // held: NMI every VBLANK (setup menu)
	input             cocktail,

	// Main CPU ROM, SDRAM bank 0 (it8_sdram CPU port)
	output reg        rom_req,
	output reg [21:0] rom_addr,
	input             rom_accept,
	input             rom_ack,
	input      [15:0] rom_data,
	output            rom_quiet,

	// Turbo board ROM, SDRAM bank 1 (toggle handshake)
	output reg [23:0] blt_addr,
	output reg        blt_req,
	input             blt_ack,
	input      [15:0] blt_data,

	// Sound program, SDRAM bank 2 (toggle handshake)
	output     [23:0] snd_addr,
	output            snd_req,
	input             snd_ack,
	input      [15:0] snd_data,

	// NVRAM, MiSTer side
	input      [10:0] nv_addr,
	input       [7:0] nv_din,
	input             nv_we,
	output      [7:0] nv_dout,
	output            nv_written,     // pulse: the CPU wrote its RAM

	// Video and audio
	output            ce_pix,
	output      [7:0] r,
	output      [7:0] g,
	output      [7:0] b,
	output            hs,
	output            vs,
	output            hblank,
	output            vblank,
	output     [15:0] audio,

	// Debug
	output     [15:0] dbg_pc,
	output reg [15:0] dbg_frames,
	output reg [15:0] dbg_firq,
	output reg [15:0] dbg_nmi,
	output reg [15:0] dbg_waits,      // E cycles stretched by a late access
	output reg [15:0] dbg_turbo,      // turbo board ROM bytes read
	output     [15:0] dbg_snd_cmds,
	output      [7:0] dbg_snd_last,
	output     [15:0] dbg_snd_pc,
	output reg  [7:0] dbg_bank
);

localparam [23:0] TURBO_BASE = 24'h400000;    // SDRAM word address of bank 1

// 555 astable, R1 = R2 = 100k, C = 0.1u: T = 0.693 * 300k * 0.1u = 20.79 ms;
// MAME: 16 T - T/2 = 322.2 ms = 15,467,000 clocks at 48 MHz.
localparam [23:0] WD_TIME = 24'd15467000;

// ---------------------------------------------------------------------------
// Watchdog. rst is the board reset: the core's reset or a watchdog reset.

reg  [23:0] wd_cnt;
reg  [10:0] wd_hold;
wire        wd_kick;
reg         rst = 1'b1;              // registered: it also drives jt03's asynchronous reset

always @(posedge clk) begin
	rst <= reset | (wd_hold != 11'd0);
	if (reset) begin
		wd_cnt  <= 24'd0;
		wd_hold <= 11'd0;
	end
	else begin
		if (wd_hold != 11'd0) wd_hold <= wd_hold - 11'd1;
		if (wd_kick || wd_hold != 11'd0) wd_cnt <= 24'd0;
		else if (!hold) begin
			if (wd_cnt == WD_TIME) begin
				wd_cnt  <= 24'd0;
				wd_hold <= 11'd2047;     // about 40 us, well over one E cycle
			end
			else wd_cnt <= wd_cnt + 24'd1;
		end
	end
end

// ---------------------------------------------------------------------------
// E cycle

reg   [4:0] ph;
reg         busy;
wire        fall_e = (ph == 5'd23) && !busy && !hold;
wire        fall_q = (ph == 5'd17) && !hold;
wire        acc    = (ph == 5'd0)  && !hold && !rst;

// The cycle keeps running through reset: mc6809is applies its reset (and
// arms its NMI mask) only on E and Q enables.
always @(posedge clk) begin
	if (!hold) begin
		if (ph != 5'd23) ph <= ph + 5'd1;
		else if (!busy)  ph <= 5'd0;
	end
end

// ROM reads only start in clock 0 of a cycle, so refresh is safe while the
// cycle is well under way and nothing is outstanding.
assign rom_quiet = rst || (!rom_req && !busy && ph >= 5'd1 && ph <= 5'd16);

// ---------------------------------------------------------------------------
// 6809

wire [15:0] addr;
wire  [7:0] cpu_dout;
wire        rnw;
reg   [7:0] cpu_din;
wire        tms_irq;
reg   [5:0] nmi_cnt;

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
	.nIRQ     (1'b1),
	.nFIRQ    (~tms_irq),
	.nNMI     (nmi_cnt == 6'd0),
	.AVMA     (),
	.BUSY     (),
	.LIC      (),
	.nHALT    (1'b1),
	.nRESET   (~rst),
	.nDMABREQ (1'b1),
	.RegData  ()
);

assign dbg_pc = addr;

wire sel_turbo = bowlrama && (addr[15:5] == 11'd0);
wire sel_grom  = !bowlrama && (addr[15:14] == 2'b00);
wire sel_row   = (addr == 16'h4000);
wire sel_bank  = !bowlrama && (addr == 16'h4800);
wire sel_nv    = (addr[15:11] == 5'b01010);          // 5000-57FF
wire sel_tms   = (addr[15:11] == 5'b01011);          // 5800-5FFF
wire sel_snd   = (addr == 16'h6000);
wire sel_track = (addr == 16'h6800);
wire sel_in0   = (addr == 16'h7000);
wire sel_in1   = (addr == 16'h7800);
wire sel_rom   = addr[15];

assign wd_kick = acc && !rnw && sel_track;

// ---------------------------------------------------------------------------
// Battery-backed RAM (2 KB)

wire [7:0] nv_q;
wire       nv_cpu_we = acc && !rnw && sel_nv;

assign nv_written = nv_cpu_we;

it8_dpram #(.AW(11), .DW(8), .INIT(8'hFF)) nvram
(
	.clk    (clk),
	.a_addr (addr[10:0]),
	.a_din  (cpu_dout),
	.a_we   (nv_cpu_we),
	.a_dout (nv_q),
	.b_addr (nv_addr),
	.b_din  (nv_din),
	.b_we   (nv_we),
	.b_dout (nv_dout)
);

// ---------------------------------------------------------------------------
// Video

reg   [7:0] row;
wire        tms_done, vblank_start;
wire  [7:0] tms_rdata;

cb_video video
(
	.clk          (clk),
	.reset        (rst),
	.pix_ce       (pix_ce),
	.chr_ce       (chr_ce),
	.pix_left     (pix_left),
	.wide         (wide),
	.tms_start    (acc && sel_tms),
	.tms_offs     (addr[10:0]),
	.tms_row      (row),
	.tms_we       (!rnw),
	.tms_wdata    (cpu_dout),
	.tms_done     (tms_done),
	.tms_rdata    (tms_rdata),
	.irq          (tms_irq),
	.ce_pix       (ce_pix),
	.r            (r),
	.g            (g),
	.b            (b),
	.hs           (hs),
	.vs           (vs),
	.hblank       (hblank),
	.vblank       (vblank),
	.vblank_start (vblank_start)
);

// ---------------------------------------------------------------------------
// NMI: while the service key is held, a pulse at every VBLANK (two E
// cycles low, so the edge is sampled). Debug counters.

reg irq_d;

always @(posedge clk) begin
	irq_d <= tms_irq;
	if (rst) begin
		nmi_cnt    <= 6'd0;
		dbg_frames <= 16'd0;
		dbg_firq   <= 16'd0;
		dbg_nmi    <= 16'd0;
	end
	else begin
		if (nmi_cnt != 6'd0 && !hold) nmi_cnt <= nmi_cnt - 6'd1;
		if (vblank_start) begin
			dbg_frames <= dbg_frames + 16'd1;
			if (service) begin
				nmi_cnt <= 6'd48;
				dbg_nmi <= dbg_nmi + 16'd1;
			end
		end
		if (tms_irq && !irq_d) dbg_firq <= dbg_firq + 16'd1;
	end
end

// ---------------------------------------------------------------------------
// Sound board

cb_sound sound
(
	.clk          (clk),
	.reset        (rst),
	.hold         (hold),
	.ym_cen       (ym_cen),
	.cmd_we       (acc && !rnw && sel_snd),
	.cmd          (cpu_dout),
	.rom_addr     (snd_addr),
	.rom_req      (snd_req),
	.rom_ack      (snd_ack),
	.rom_data     (snd_data),
	.audio        (audio),
	.dbg_cmds     (dbg_snd_cmds),
	.dbg_last_cmd (dbg_snd_last),
	.dbg_pc       (dbg_snd_pc)
);

// ---------------------------------------------------------------------------
// Controls: the trackball nibbles count from the last reset at 6800.

reg  [7:0] last_x, last_y;
wire [3:0] dx = track_x[3:0] - last_x[3:0];
wire [3:0] dy = track_y[3:0] - last_y[3:0];
wire [7:0] in0 = {~coin2, ~cocktail, ~p2_hook_r, ~p2_hook_l, dy};
wire [7:0] in1 = {~coin1, ~start,    ~p1_hook_r, ~p1_hook_l, dx};

// ---------------------------------------------------------------------------
// Turbo board: the ROM byte at the current address is kept fetched.

reg  [23:0] tb_addr;
reg   [7:0] tb_data;
reg         tb_valid, tb_wait, tb_again, tb_lo;
wire  [7:0] tb_mask = {(tb_data[7:4] == 4'h0) ? 4'hF : 4'h0,
                       (tb_data[3:0] == 4'h0) ? 4'hF : 4'h0};

// ---------------------------------------------------------------------------
// Bus

reg  [2:0] bank;
reg        rom_wait, rom_lo;
reg        tms_wait, tb_rd_wait, nv_rd;

wire [17:0] rom_byte = sel_rom ? {3'b000, addr[14:0]}
                               : 18'h08000 + {1'b0, bank, addr[13:0]};

always @(posedge clk) begin
	if (rom_accept) rom_req <= 1'b0;

	if (rst) begin
		busy       <= 1'b0;
		rom_req    <= 1'b0;
		rom_wait   <= 1'b0;
		tms_wait   <= 1'b0;
		tb_rd_wait <= 1'b0;
		nv_rd      <= 1'b0;
		row        <= 8'h00;
		bank       <= 3'd0;
		last_x     <= 8'd0;
		last_y     <= 8'd0;
		cpu_din    <= 8'h00;
		dbg_waits  <= 16'd0;
		dbg_turbo  <= 16'd0;
		dbg_bank   <= 8'h00;
	end
	else begin
		nv_rd <= 1'b0;

		if (acc) begin
			if (rnw) begin
				if (sel_rom || sel_grom) begin
					rom_addr <= {5'd0, rom_byte[17:1]};
					rom_lo   <= rom_byte[0];
					rom_req  <= 1'b1;
					rom_wait <= 1'b1;
					busy     <= 1'b1;
				end
				else if (sel_tms) begin
					tms_wait <= 1'b1;
					busy     <= 1'b1;
				end
				else if (sel_turbo && (addr[4:0] == 5'h00 || addr[4:0] == 5'h04)) begin
					tb_rd_wait <= 1'b1;
					busy       <= 1'b1;
				end
				else if (sel_nv) nv_rd <= 1'b1;
				else if (sel_in0) cpu_din <= in0;
				else if (sel_in1) cpu_din <= in1;
				else              cpu_din <= 8'h00;
			end
			else begin
				if (sel_row)   row  <= cpu_dout;
				if (sel_bank) begin
					// MAME: ((d & 0x0c) >> 1) + (d & 1), i.e. {d[3:2], d[0]}
					bank     <= {cpu_dout[3:2], cpu_dout[0]};
					dbg_bank <= cpu_dout;
				end
				if (sel_track) begin
					last_x <= track_x;
					last_y <= track_y;
				end
				if (sel_tms) begin
					tms_wait <= 1'b1;
					busy     <= 1'b1;
				end
			end
		end

		if (nv_rd) cpu_din <= nv_q;

		if (rom_wait && rom_ack) begin
			cpu_din  <= rom_lo ? rom_data[7:0] : rom_data[15:8];
			rom_wait <= 1'b0;
			busy     <= 1'b0;
		end

		if (tms_wait && tms_done) begin
			cpu_din  <= tms_rdata;
			tms_wait <= 1'b0;
			busy     <= 1'b0;
		end

		if (tb_rd_wait && tb_valid) begin
			cpu_din    <= addr[2] ? tb_data : tb_mask;
			tb_rd_wait <= 1'b0;
			busy       <= 1'b0;
			if (addr[2]) dbg_turbo <= dbg_turbo + 16'd1;
		end

		if (ph == 5'd23 && busy && !hold) dbg_waits <= dbg_waits + 16'd1;
	end
end

// Turbo board address register and prefetch. A write or a data read changes
// the address; the new byte is fetched at once (about 10 clocks, well inside
// the next 6809 instruction).
wire tb_rd_data = tb_rd_wait && tb_valid && addr[2];
wire tb_wr      = acc && !rnw && sel_turbo &&
                  (addr[4:0] == 5'h08 || addr[4:0] == 5'h17 || addr[4:0] == 5'h18);

always @(posedge clk) begin
	if (rst) begin
		tb_addr  <= 24'd0;
		tb_valid <= 1'b0;
		tb_wait  <= 1'b0;
		tb_again <= 1'b1;             // fetch address 0 after reset
		blt_req  <= blt_ack;
	end
	else begin
		if (tb_wr) begin
			case (addr[4:0])
				5'h08:   tb_addr[23:16] <= cpu_dout;
				5'h17:   tb_addr[15:8]  <= cpu_dout;
				default: tb_addr[7:0]   <= cpu_dout;
			endcase
			tb_valid <= 1'b0;
			tb_again <= 1'b1;
		end
		if (tb_rd_data) begin
			tb_addr  <= {6'd0, tb_addr[17:0] + 18'd1};
			tb_valid <= 1'b0;
			tb_again <= 1'b1;
		end

		if (tb_wait) begin
			if (blt_req == blt_ack) begin
				tb_wait <= 1'b0;
				// Keep the byte only if the address has not moved since.
				if (!tb_again && !tb_wr && !tb_rd_data) begin
					tb_data  <= tb_lo ? blt_data[7:0] : blt_data[15:8];
					tb_valid <= 1'b1;
				end
			end
		end
		else if (tb_again && !tb_wr && !tb_rd_data) begin
			blt_addr <= TURBO_BASE + {7'd0, tb_addr[17:1]};
			tb_lo    <= tb_addr[0];
			blt_req  <= ~blt_req;
			tb_wait  <= 1'b1;
			tb_again <= 1'b0;
		end
	end
end

endmodule
