//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_main09.sv - 6809 main CPU of the itech8 6809 boards
//
//  68B09 at 2 MHz (rr: Rim Rockin' Basketball's HD6309 at 3 MHz, below).
//  Memory map (MAME itech8.cpp common_hi_map, the Strata Bowling layout):
//
//    0100         W   (unused)
//    0120         W   sound command
//    0140        RW   R: input port 40, W: graphics ROM bank
//    0160        RW   R: input port 60, W: display page (C0 at reset, as
//                     MAME)
//    0180        RW   R: input port 80, W: TMS34061 colour latch
//    01A0         W   NMI acknowledge (no effect, as MAME)
//    01C0-01DF   RW   blitter (register = offset / 2); register 7 bit 5 is
//                     the program ROM bank; registers 12-13 read player
//                     1's trackball counters, and a write to 12 clears
//                     them (player 2's, 14-15, cocktail only, read 0)
//    01E0-01FF    W   RAMDAC (register = offset / 2)
//    1000-1FFF   RW   TMS34061
//    2000-3FFF   RW   8 KB battery-backed RAM
//    4000-7FFF    R   program ROM, banked (16 KB bank 0 or 1)
//    8000-FFFF    R   program ROM, fixed (its last 32 KB: prog64 for a
//                     64 KB program)
//
//  map_gtg2 selects the 1992 board of Golden Par Golf (MAME gtg2_map), the
//  same devices at other addresses:
//
//    0100        RW   R: input port 40, W: NMI acknowledge
//    0120        RW   R: input port 60, W: display page
//    0140-015F   RW   R (0140): input port 80, W: RAMDAC
//    0160         W   graphics ROM bank
//    0180-019F   RW   blitter (as 01C0 above)
//    01C0         W   sound command (it8_top rewires its bits)
//    01E0         W   TMS34061 colour latch
//
//  map_lo selects MAME's common_lo_map (Golden Tee Golf II joystick, v1.0):
//  the TMS34061 at 0000-0FFF and the I/O registers of the table above at
//  1100-11FF, everything else in place. Bit 12 of the address is turned
//  over for the TMS34061 and I/O decodes only.
//
//  rr selects Rim Rockin' Basketball's board (MAME rimrockn_map, D-047):
//  the layout above with
//
//    0161-0165    R   input ports 161-165 (players 1-4, service and
//                     switches; it8_ports09 inx)
//    01A0         W   program ROM bank (bits 1-0) instead of the NMI
//                     acknowledge; blitter register 7 does not bank
//    4000-7FFF    R   program ROM, banked: 16 KB bank 0-3 of its first 64 KB
//    8000-FFFF    R   program ROM, fixed: the last 32 KB of 128 KB
//
//  and the CPU at 3 MHz: an HD6309 at 12 MHz in MAME. The game runs the
//  6309 as a 6809 (no 6309-only instruction or register in about 100
//  million traced in MAME, D-047), where the 6309 takes the 6809's cycles,
//  so mc6809is runs it on a 16-clock E cycle.
//
//  tb_horiz gives the trackball the horizontal games' axes (MAME gtgt:
//  register 12 is X, right positive; 13 is Y, up positive); without it the
//  vertical games' (stratab: 12 is Y and 13 X, counting down for up and
//  right).
//
//  dial_mode puts a spinner on register 13 (MAME analog D) instead, the
//  trackball's X counter, counting up to the right; the other registers
//  read 0. 1: the counter itself (Wheel Of Fortune, which works out the
//  movement itself; MAME: no PORT_RESET), 2: the count since the last write
//  to register 12, as the trackball (Peggle's trackball set reads 13 and
//  then clears it there, once a frame; MAME: PORT_RESET).
//
//  Interrupts: NMI at the start of vertical blank (held for two E cycles,
//  about MAME's 1 us), IRQ from the TMS34061's vertical interrupt, FIRQ
//  from the blitter.
//
//  The program ROM is in SDRAM bank 0. The CPU runs on its own E cycle of
//  24 clocks (rr: 16): every access starts in the first clock, and E falls
//  only once it has finished, so a late SDRAM read stretches the cycle (as
//  on the Capcom Bowling board, cb_top.sv).
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_main09
(
	input             clk,            // 48 MHz
	input             reset,
	input             hold,           // freeze the CPU (NVRAM being saved)
	input             bank_xor,       // MAME init_invbank: bank bit inverted
	input             prog64,         // 64 KB program: fixed area at 0x8000
	input             map_gtg2,       // Golden Par Golf's I/O layout (above)
	input             map_lo,         // TMS34061 at 0000, I/O at 1100 (above)
	input             rr,             // Rim Rockin' Basketball's board (above)
	input             tb_horiz,       // trackball axes of a horizontal game
	input       [1:0] dial_mode,      // spinner on register 13 (above)

	// Input ports, as the board presents them
	input       [7:0] in40,
	input       [7:0] in60,
	input       [7:0] in80,
	input      [39:0] inx,            // rr: ports 161-165, {165, 164, 163, 162, 161}
	input       [7:0] track_x,        // player 1 trackball counters, right = up
	input       [7:0] track_y,        // ... up = up

	// SDRAM: program ROM (it8_sdram CPU port)
	output reg        rom_req,
	output reg [21:0] rom_addr,
	input             rom_accept,
	input             rom_ack,
	input      [15:0] rom_data,
	output            rom_quiet,

	// Board devices
	output reg        tms_start,      // pulse
	output     [11:0] tms_offs,
	output            tms_we,
	input             tms_done,
	input       [7:0] tms_rdata,
	output reg        latch_we,       // pulse
	output reg        blt_we,         // pulse
	output reg        blt_re,         // pulse
	output reg  [3:0] blt_idx,
	input       [7:0] blt_rdata,
	output reg        dac_we,         // pulse
	output reg  [1:0] dac_idx,
	output reg        snd_we,         // pulse
	output      [7:0] wdata,          // CPU data for every write above
	output reg  [7:0] grom_bank,
	output reg  [7:0] page,
	output     [31:0] an,             // blitter registers 12-15 {15, 14, 13, 12}

	// Battery-backed RAM (it8_nvram: 16-bit, byte lanes, even byte upper)
	output     [12:0] nv_addr,
	output     [15:0] nv_din,
	output      [1:0] nv_we,
	input      [15:0] nv_q,
	output            nv_written,

	// Interrupt sources
	input             vblank_start,   // pulse
	input             tms_irq,
	input             blt_irq,

	// Debug
	output     [15:0] dbg_pc,         // bus address
	output reg [15:0] dbg_frames,
	output reg [15:0] dbg_nmi,
	output reg [15:0] dbg_firq,
	output reg [15:0] dbg_waits       // E cycles stretched by a late access
);

// ---------------------------------------------------------------------------
// E cycle

// 24 clocks (2 MHz), or 16 (3 MHz) with rr; Q falls three quarters in.
reg   [4:0] ph;
reg         busy;
wire  [4:0] ph_last = rr ? 5'd15 : 5'd23;
wire        fall_e = (ph == ph_last) && !busy && !hold;
wire        fall_q = (ph == (rr ? 5'd11 : 5'd17)) && !hold;
wire        acc    = (ph == 5'd0)  && !hold && !reset;

// The cycle keeps running through reset: mc6809is applies its reset only on
// its E and Q enables.
always @(posedge clk) begin
	if (!hold) begin
		if (ph < ph_last) ph <= ph + 5'd1;
		else if (!busy)   ph <= 5'd0;
	end
end

// ROM reads only start in clock 0 of a cycle, so refresh is safe while the
// cycle is well under way (at least 7 clocks from its end) and nothing is
// outstanding.
assign rom_quiet = reset || (!rom_req && !busy && ph >= 5'd1 && ph <= (rr ? 5'd9 : 5'd16));

// ---------------------------------------------------------------------------
// 6809

wire [15:0] addr;
wire  [7:0] cpu_dout;
wire        rnw;
reg   [7:0] cpu_din;
reg   [1:0] nmi_cnt;

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
	.nIRQ     (~tms_irq),
	.nFIRQ    (~blt_irq),
	.nNMI     (nmi_cnt == 2'd0),
	.AVMA     (),
	.BUSY     (),
	.LIC      (),
	.nHALT    (1'b1),
	.nRESET   (~reset),
	.nDMABREQ (1'b1),
	.RegData  ()
);

assign dbg_pc   = addr;
assign wdata    = cpu_dout;
assign tms_offs = addr[11:0];
assign tms_we   = !rnw;

// Reads of the input ports and writes of the board registers, by layout.
// a_io is the address as the hi layout sees it (map_lo: bit 12 turned over).
wire [15:0] a_io = {addr[15:13], addr[12] ^ map_lo, addr[11:0]};
wire sel_in40  = (a_io == (map_gtg2 ? 16'h0100 : 16'h0140));
wire sel_in60  = (a_io == (map_gtg2 ? 16'h0120 : 16'h0160));
wire sel_in80  = (a_io == (map_gtg2 ? 16'h0140 : 16'h0180));
wire sel_snd   = (a_io == (map_gtg2 ? 16'h01C0 : 16'h0120));
wire sel_grom  = (a_io == (map_gtg2 ? 16'h0160 : 16'h0140));
wire sel_page  = (a_io == (map_gtg2 ? 16'h0120 : 16'h0160));
wire sel_latch = (a_io == (map_gtg2 ? 16'h01E0 : 16'h0180));
wire sel_blt   = map_gtg2 ? (a_io[15:5] == 11'b0000_0001_100)   // 0180-019F
                          : (a_io[15:5] == 11'b0000_0001_110);  // 01C0-01DF
wire sel_dac   = map_gtg2 ? (a_io[15:5] == 11'b0000_0001_010)   // 0140-015F
                          : (a_io[15:5] == 11'b0000_0001_111);  // 01E0-01FF
wire sel_tms   = (a_io[15:12] == 4'h1);
wire sel_inx   = rr && (a_io >= 16'h0161) && (a_io <= 16'h0165);
wire sel_bnk2  = rr && (a_io == 16'h01A0);
wire sel_nv    = (addr[15:13] == 3'b001);
wire sel_bank  = (addr[15:14] == 2'b01);
wire sel_fixed = addr[15];

// ---------------------------------------------------------------------------
// Battery-backed RAM: byte address a -> word a / 2, lane a[0].

wire nv_cpu_we = acc && !rnw && sel_nv;

assign nv_addr    = {1'b0, addr[12:1]};
assign nv_din     = {cpu_dout, cpu_dout};
assign nv_we      = nv_cpu_we ? {~addr[0], addr[0]} : 2'b00;
assign nv_written = nv_cpu_we;

// ---------------------------------------------------------------------------
// Trackball: the counters read as the count since player 1's were last
// cleared (a write to register 12). MAME stratab: analog C is the
// trackball's Y, analog D its X reversed, both counting down for up /
// right; gtgt (tb_horiz): C is X and D is Y reversed, counting up for
// right / up.

reg  [7:0] ref_x, ref_y;
wire [7:0] dial = dial_mode[1] ? track_x - ref_x : track_x;
assign an = (dial_mode != 2'd0) ? {8'h00, 8'h00, dial, 8'h00} :
            tb_horiz ? {8'h00, 8'h00, track_y - ref_y, track_x - ref_x}
                     : {8'h00, 8'h00, ref_x - track_x, ref_y - track_y};

// ---------------------------------------------------------------------------
// Bus

reg        bank;
reg  [1:0] bank2;                  // rr: the bank register at 01A0
reg        rom_wait, rom_lo, tms_wait, rd_d;
reg  [3:0] rd_src;                 // one-hot: blitter, NVRAM, input port, zero
reg  [7:0] in_val;

// Byte address in the program ROM: 32 or 64 KB (fixed area its last 32 KB,
// banks 0-1 from 0), or with rr 128 KB (fixed area 18000, banks 0-3 from 0).
wire [16:0] rom_byte = sel_fixed ? {rr, rr | prog64, addr[14:0]}
                                 : rr ? {1'b0, bank2, addr[13:0]}
                                      : {2'b00, bank ^ bank_xor, addr[13:0]};

// rr: port 161 + n
wire  [2:0] inx_n  = a_io[2:0] - 3'd1;
wire  [7:0] inx_v  = inx[8 * inx_n +: 8];

always @(posedge clk) begin
	tms_start <= 1'b0;
	latch_we  <= 1'b0;
	blt_we    <= 1'b0;
	blt_re    <= 1'b0;
	dac_we    <= 1'b0;
	snd_we    <= 1'b0;
	rd_d      <= 1'b0;

	if (rom_accept) rom_req <= 1'b0;

	if (reset) begin
		busy      <= 1'b0;
		rom_req   <= 1'b0;
		rom_wait  <= 1'b0;
		tms_wait  <= 1'b0;
		bank      <= 1'b0;
		bank2     <= 2'd0;
		grom_bank <= 8'h00;
		page      <= 8'hC0;           // MAME video_start
		ref_x     <= track_x;
		ref_y     <= track_y;
		cpu_din   <= 8'h00;
		dbg_waits <= 16'd0;
	end
	else begin
		if (acc) begin
			if (rnw) begin
				if (sel_fixed || sel_bank) begin
					rom_addr <= {6'd0, rom_byte[16:1]};
					rom_lo   <= rom_byte[0];
					rom_req  <= 1'b1;
					rom_wait <= 1'b1;
					busy     <= 1'b1;
				end
				else if (sel_tms) begin
					tms_start <= 1'b1;
					tms_wait  <= 1'b1;
					busy      <= 1'b1;
				end
				else begin
					// Answered one clock later, when the blitter register
					// index and the RAM read have settled.
					rd_d    <= 1'b1;
					blt_idx <= addr[4:1];
					if (sel_blt) blt_re <= 1'b1;
					rd_src  <= {sel_blt, sel_nv, sel_in40 | sel_in60 | sel_in80 | sel_inx, 1'b0};
					in_val  <= sel_inx ? inx_v : sel_in40 ? in40 : sel_in60 ? in60 : in80;
				end
			end
			else begin
				if (sel_snd)   snd_we    <= 1'b1;
				if (sel_bnk2)  bank2     <= cpu_dout[1:0];
				if (sel_grom)  grom_bank <= cpu_dout;
				if (sel_page)  page      <= cpu_dout;
				if (sel_latch) latch_we  <= 1'b1;
				if (sel_blt) begin
					blt_idx <= addr[4:1];
					blt_we  <= 1'b1;
					if (addr[4:1] == 4'd7 && !rr) bank <= cpu_dout[5];
					if (addr[4:1] == 4'd12) begin
						ref_x <= track_x;
						ref_y <= track_y;
					end
				end
				if (sel_dac && addr[4:3] == 2'b00) begin
					dac_idx <= addr[2:1];
					dac_we  <= 1'b1;
				end
				if (sel_tms) begin
					tms_start <= 1'b1;
					tms_wait  <= 1'b1;
					busy      <= 1'b1;
				end
			end
		end

		if (rd_d) begin
			if      (rd_src[3]) cpu_din <= blt_rdata;
			else if (rd_src[2]) cpu_din <= addr[0] ? nv_q[7:0] : nv_q[15:8];
			else if (rd_src[1]) cpu_din <= in_val;
			else                cpu_din <= 8'h00;
		end

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

		if (ph == 5'd23 && busy && !hold) dbg_waits <= dbg_waits + 16'd1;
	end
end

// ---------------------------------------------------------------------------
// NMI: low from the start of vertical blank for two Q falling edges (the
// CPU samples it there; MAME holds it for 1 us), however long a late access
// stretches the cycle. Debug counters.

reg firq_d;

always @(posedge clk) begin
	firq_d <= blt_irq;
	if (reset) begin
		nmi_cnt    <= 2'd0;
		dbg_frames <= 16'd0;
		dbg_nmi    <= 16'd0;
		dbg_firq   <= 16'd0;
	end
	else begin
		if (nmi_cnt != 2'd0 && fall_q) nmi_cnt <= nmi_cnt - 2'd1;
		if (vblank_start) begin
			nmi_cnt    <= 2'd2;
			dbg_frames <= dbg_frames + 16'd1;
			dbg_nmi    <= dbg_nmi + 16'd1;
		end
		if (blt_irq && !firq_d) dbg_firq <= dbg_firq + 16'd1;
	end
end

endmodule
