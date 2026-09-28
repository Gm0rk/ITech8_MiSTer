//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_ce.sv - clock enables derived from the 48 MHz system clock
//
//  Every clock on the Ninja Clowns board set divides 48 MHz exactly, so a
//  single modulo-48 counter produces all of them in a fixed phase relation.
//  The SDRAM controller relies on that: it lines its command slots up with
//  cpu_ph so that 68000 ROM reads never wait (see it8_sdram.sv).
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_ce
(
	input            clk,         // 48 MHz system clock
	input            reset,       // holds every divider at phase 0

	output reg       cpu_phi1,    // 12 MHz 68000, fx68k enPhi1
	output reg       cpu_phi2,    // 12 MHz 68000, fx68k enPhi2
	output reg [1:0] cpu_ph,      // CPU clock phase, 0 = the enPhi1 clock
	output reg       pix_ce,      // 8 MHz dot clock
	output reg       chr_ce,      // 4 MHz TMS34061 character clock (2 dots)
	output reg       pix_left,    // with pix_ce: the left dot of a character
	output reg       snd_fall_e,  // 2 MHz 6809 E falling edge (8 MHz / 4)
	output reg       snd_fall_q,  // 6809 Q falling edge, 1/4 cycle before E
	output reg       ym_cen,      // 4 MHz YM3812 master clock (8 MHz / 2)
	output reg       oki_cen,     // 1 MHz OKI M6295 clock (8 MHz / 8)
	output reg       blt_tick     // 3 MHz blitter timing tick (12 MHz / 4)
);

reg  [5:0] cnt;
wire [5:0] nxt = (cnt == 6'd47) ? 6'd0 : cnt + 6'd1;

// All outputs are registered from the next count, so each one is a
// single-cycle pulse that is high while cnt holds the matching value.
always @(posedge clk) begin
	if (reset) begin
		cnt        <= 6'd0;
		cpu_phi1   <= 1'b0;
		cpu_phi2   <= 1'b0;
		cpu_ph     <= 2'd0;
		pix_ce     <= 1'b0;
		chr_ce     <= 1'b0;
		pix_left   <= 1'b0;
		snd_fall_e <= 1'b0;
		snd_fall_q <= 1'b0;
		ym_cen     <= 1'b0;
		oki_cen    <= 1'b0;
		blt_tick   <= 1'b0;
	end
	else begin
		cnt        <= nxt;
		cpu_ph     <= nxt[1:0];
		cpu_phi1   <= (nxt[1:0] == 2'd0);
		cpu_phi2   <= (nxt[1:0] == 2'd2);
		pix_ce     <= (nxt % 6)  == 0;
		chr_ce     <= (nxt % 12) == 0;
		pix_left   <= (nxt % 12) == 6;
		ym_cen     <= (nxt % 12) == 0;
		snd_fall_e <= (nxt % 24) == 0;
		snd_fall_q <= (nxt % 24) == 18;
		oki_cen    <= (nxt == 6'd0);
		blt_tick   <= (nxt % 16) == 0;
	end
end

endmodule
