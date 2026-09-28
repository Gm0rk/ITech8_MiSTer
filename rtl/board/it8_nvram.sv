//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_nvram.sv - 16 KB battery-backed work RAM (two MS6264 8K x 8)
//
//  Port A is the 68000 (16-bit, byte lanes). Port B is the MiSTer side, one
//  byte at a time in 68000 order (even address = upper byte), for loading
//  and saving the NVRAM file. Contents are FF from configuration (MAME:
//  nvram DEFAULT_ALL_1), before the loader's fill runs.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_nvram
(
	input             clk,

	input      [12:0] cpu_addr,     // word address
	input      [15:0] cpu_din,
	input       [1:0] cpu_we,       // {upper, lower}
	output     [15:0] cpu_dout,

	input      [13:0] hps_addr,     // byte address
	input       [7:0] hps_din,
	input             hps_we,
	output      [7:0] hps_dout
);

wire [7:0] hps_hi, hps_lo;
reg        hps_lane;

always @(posedge clk) hps_lane <= hps_addr[0];
assign hps_dout = hps_lane ? hps_lo : hps_hi;

it8_dpram #(.AW(13), .DW(8), .INIT(8'hFF)) ram_hi
(
	.clk    (clk),
	.a_addr (cpu_addr),
	.a_din  (cpu_din[15:8]),
	.a_we   (cpu_we[1]),
	.a_dout (cpu_dout[15:8]),
	.b_addr (hps_addr[13:1]),
	.b_din  (hps_din),
	.b_we   (hps_we & ~hps_addr[0]),
	.b_dout (hps_hi)
);

it8_dpram #(.AW(13), .DW(8), .INIT(8'hFF)) ram_lo
(
	.clk    (clk),
	.a_addr (cpu_addr),
	.a_din  (cpu_din[7:0]),
	.a_we   (cpu_we[0]),
	.a_dout (cpu_dout[7:0]),
	.b_addr (hps_addr[13:1]),
	.b_din  (hps_din),
	.b_we   (hps_we & hps_addr[0]),
	.b_dout (hps_lo)
);

endmodule
