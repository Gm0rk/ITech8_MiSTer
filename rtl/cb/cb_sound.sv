//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  cb_sound.sv - sound board of Capcom Bowling / Bowl-O-Rama
//
//  6809 at 2 MHz (8 MHz / 4), 2 KB RAM, 32 KB program ROM, YM2203 at 4 MHz
//  and a DAC0832. Map (MAME capbowl.cpp sound_map):
//
//    0000-07FF   RW   RAM
//    1000-1001   RW   YM2203
//    2000        W    watchdog (not modelled)
//    6000        W    DAC
//    7000        R    command latch from the main CPU (read clears IRQ)
//    8000-FFFF   R    program ROM, SDRAM bank 2
//
//  IRQ comes from the command latch, FIRQ from the YM2203. YM2203 port A bit
//  7 reads the ticket dispenser's sensor (inverted), port B bit 7 drives its
//  motor; with the motor on the sensor toggles every 100 ms (MAME ticket.cpp).
//  Mix as MAME: each SSG channel 0.07, FM 0.75, DAC 0.5.
//
//  The CPU runs on its own E cycle of 24 clocks. Every bus access starts in
//  the first clock of the cycle; E falls only when it has finished, so a
//  late SDRAM read stretches the cycle instead of returning stale data.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module cb_sound
(
	input                    clk,
	input                    reset,
	input                    hold,          // freeze the CPU
	input                    ym_cen,        // 4 MHz

	input                    cmd_we,        // main CPU write to 0x6000
	input              [7:0] cmd,

	output reg        [23:0] rom_addr,      // SDRAM word address, toggle handshake
	output reg               rom_req,
	input                    rom_ack,
	input             [15:0] rom_data,

	output reg signed [15:0] audio,

	output reg        [15:0] dbg_cmds,
	output             [7:0] dbg_last_cmd,
	output            [15:0] dbg_pc
);

localparam [23:0] ROM_BASE = 24'h800000;    // SDRAM word address of bank 2

// ---------------------------------------------------------------------------
// E cycle

reg   [4:0] ph;
reg         busy;
wire        fall_e = (ph == 5'd23) && !busy && !hold;
wire        fall_q = (ph == 5'd17) && !hold;
wire        acc    = (ph == 5'd0)  && !hold && !reset;    // bus access starts

// The cycle keeps running through reset: mc6809is applies its reset (and
// arms its NMI mask) only on E and Q enables.
always @(posedge clk) begin
	if (!hold) begin
		if (ph != 5'd23) ph <= ph + 5'd1;
		else if (!busy)  ph <= 5'd0;
	end
end

// ---------------------------------------------------------------------------
// 6809

wire [15:0] addr;
wire  [7:0] cpu_dout;
wire        rnw;
reg   [7:0] cpu_din;

reg         cmd_pend;
reg   [7:0] cmd_latch;
wire        ym_irq_n;

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
	.nFIRQ    (ym_irq_n),
	.nNMI     (1'b1),
	.AVMA     (),
	.BUSY     (),
	.LIC      (),
	.nHALT    (1'b1),
	.nRESET   (~reset),
	.nDMABREQ (1'b1),
	.RegData  ()
);

assign dbg_pc       = addr;
assign dbg_last_cmd = cmd_latch;

wire sel_ram   = (addr[15:11] == 5'b00000);       // 0000-07FF
wire sel_ym    = (addr[15:1]  == 15'h0800);       // 1000-1001
wire sel_dac   = (addr == 16'h6000);
wire sel_latch = (addr == 16'h7000);
wire sel_rom   = addr[15];

// ---------------------------------------------------------------------------
// RAM

wire [7:0] ram_q;

it8_sdpram #(.AW(11), .DW(8)) work_ram
(
	.clk     (clk),
	.rd_addr (addr[10:0]),
	.rd_data (ram_q),
	.wr_addr (addr[10:0]),
	.wr_data (cpu_dout),
	.wr_en   (acc & ~rnw & sel_ram)
);

// ---------------------------------------------------------------------------
// YM2203

wire  [7:0] ym_dout, ioa_in, iob_out;
wire  [7:0] psg_a, psg_b, psg_c;
wire signed [15:0] fm;

reg         ticket;
reg  [22:0] ticket_cnt;
localparam [22:0] TICKET_PERIOD = 23'd4799999;    // 100 ms at 48 MHz

assign ioa_in = {~ticket, 7'h7F};

jt03 ym2203
(
	.rst        (reset),
	.clk        (clk),
	.cen        (ym_cen),
	.din        (cpu_dout),
	.addr       (addr[0]),
	.cs_n       (~(acc & sel_ym)),
	.wr_n       (rnw),
	.dout       (ym_dout),
	.irq_n      (ym_irq_n),
	.IOA_in     (ioa_in),
	.IOB_in     (8'hFF),
	.IOA_out    (),
	.IOB_out    (iob_out),
	.IOA_oe     (),
	.IOB_oe     (),
	.psg_A      (psg_a),
	.psg_B      (psg_b),
	.psg_C      (psg_c),
	.fm_snd     (fm),
	.psg_snd    (),
	.snd        (),
	.snd_sample (),
	.debug_view ()
);

// Ticket dispenser: with the motor on, the sensor toggles every 100 ms.
always @(posedge clk) begin
	if (reset) begin
		ticket     <= 1'b0;
		ticket_cnt <= 23'd0;
	end
	else if (iob_out[7]) begin
		if (ticket_cnt == TICKET_PERIOD) begin
			ticket_cnt <= 23'd0;
			ticket     <= ~ticket;
		end
		else ticket_cnt <= ticket_cnt + 23'd1;
	end
	else ticket_cnt <= 23'd0;
end

// ---------------------------------------------------------------------------
// Command latch, DAC

reg [7:0] dac;

always @(posedge clk) begin
	if (reset) begin
		cmd_pend <= 1'b0;
		dac      <= 8'h80;
		dbg_cmds <= 16'd0;
	end
	else begin
		if (acc & rnw & sel_latch) cmd_pend <= 1'b0;
		if (acc & ~rnw & sel_dac)  dac <= cpu_dout;
		if (cmd_we) begin
			cmd_latch <= cmd;
			cmd_pend  <= 1'b1;
			dbg_cmds  <= dbg_cmds + 16'd1;
		end
	end
end

// ---------------------------------------------------------------------------
// Bus: ROM reads come from SDRAM; everything else answers in one clock.

reg         rom_wait, rom_lo, rd_d;
reg   [7:0] rd_sel;               // one-hot source of the read in flight

always @(posedge clk) begin
	rd_d <= 1'b0;
	if (reset) begin
		busy     <= 1'b0;
		rom_wait <= 1'b0;
		rom_req  <= rom_ack;
		cpu_din  <= 8'h00;
	end
	else begin
		if (acc && rnw) begin
			if (sel_rom) begin
				rom_addr <= ROM_BASE + {9'd0, addr[14:1]};
				rom_lo   <= addr[0];
				rom_req  <= ~rom_req;
				rom_wait <= 1'b1;
				busy     <= 1'b1;
			end
			else begin
				rd_d   <= 1'b1;
				rd_sel <= {4'd0, sel_ram, sel_ym, sel_latch, 1'b0};
			end
		end

		if (rd_d) begin
			if      (rd_sel[3]) cpu_din <= ram_q;
			else if (rd_sel[2]) cpu_din <= ym_dout;
			else if (rd_sel[1]) cpu_din <= cmd_latch;
			else                cpu_din <= 8'h00;
		end

		if (rom_wait && rom_req == rom_ack) begin
			cpu_din  <= rom_lo ? rom_data[7:0] : rom_data[15:8];
			rom_wait <= 1'b0;
			busy     <= 1'b0;
		end
	end
end

// ---------------------------------------------------------------------------
// Mixer

// FM x 0.75; each SSG channel (0-255) x 0.07 of full scale (x 9); the DAC
// (offset binary) x 0.5 of full scale (x 128).
wire        [9:0] psg_sum  = {2'b00, psg_a} + {2'b00, psg_b} + {2'b00, psg_c};
wire signed [20:0] fm_s     = fm;
wire signed [20:0] dac_s    = $signed({{13{~dac[7]}}, ~dac[7], dac[6:0]});
wire signed [20:0] fm_part  = (fm_s * 21'sd3) >>> 2;
wire signed [20:0] psg_part = $signed({11'd0, psg_sum}) * 21'sd9;
wire signed [20:0] dac_part = dac_s <<< 7;
wire signed [20:0] mix      = fm_part + psg_part + dac_part;

always @(posedge clk) begin
	if      (mix >  21'sd32767) audio <= 16'sh7FFF;
	else if (mix < -21'sd32768) audio <= 16'sh8000;
	else                        audio <= mix[15:0];
end

endmodule
