//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_ram.sv - block RAM templates used throughout the core
//
//  Written in the form Quartus maps to M10K. Both modules use one clock and
//  a registered read, so read data appears the cycle after the address.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

// Simple dual-port: one read port, one write port. A read of the address
// being written in the same cycle returns the old contents.
module it8_sdpram #(parameter AW = 8, parameter DW = 8)
(
	input               clk,
	input      [AW-1:0] rd_addr,
	output reg [DW-1:0] rd_data,
	input      [AW-1:0] wr_addr,
	input      [DW-1:0] wr_data,
	input               wr_en
);

reg [DW-1:0] mem[0:(1<<AW)-1];

always @(posedge clk) begin
	rd_data <= mem[rd_addr];
	if (wr_en) mem[wr_addr] <= wr_data;
end

endmodule


// True dual-port: two independent read/write ports on one clock. Every
// word starts as INIT when the FPGA is configured.
module it8_dpram #(parameter AW = 8, parameter DW = 8, parameter [DW-1:0] INIT = {DW{1'b0}})
(
	input               clk,

	input      [AW-1:0] a_addr,
	input      [DW-1:0] a_din,
	input               a_we,
	output reg [DW-1:0] a_dout,

	input      [AW-1:0] b_addr,
	input      [DW-1:0] b_din,
	input               b_we,
	output reg [DW-1:0] b_dout
);

reg [DW-1:0] mem[0:(1<<AW)-1];

// Two nested loops: Quartus stops a single constant loop at 5000 iterations.
localparam LO = AW / 2;
integer i, j;
initial
	for (i = 0; i < (1 << (AW - LO)); i = i + 1)
		for (j = 0; j < (1 << LO); j = j + 1)
			mem[i * (1 << LO) + j] = INIT;

always @(posedge clk) begin
	if (a_we) begin
		mem[a_addr] <= a_din;
		a_dout      <= a_din;
	end
	else a_dout <= mem[a_addr];
end

always @(posedge clk) begin
	if (b_we) begin
		mem[b_addr] <= b_din;
		b_dout      <= b_din;
	end
	else b_dout <= mem[b_addr];
end

endmodule
