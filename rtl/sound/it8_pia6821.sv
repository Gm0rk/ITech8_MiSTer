//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_pia6821.sv - Motorola 6821 PIA, the parts the IT sound boards use
//
//  The YM3812 sound board of Hot Shots Tennis style (MAME sound3812_map)
//  has a 6821 at 5000-5003. Its port B drives the feedback bit the main CPU
//  reads (bit 0), the ticket dispenser (4), the coin counter (5) and the
//  diagnostic LED (6); port A goes to nothing MAME models. Neither port's
//  control lines nor its interrupt outputs are connected (MAME connects no
//  CA/CB lines or IRQ), so this model keeps only the data, direction and
//  control registers:
//
//    RS  CRx bit 2 = 1        CRx bit 2 = 0
//    0   port A data          data direction A
//    1   control A
//    2   port B data          data direction B
//    3   control B
//
//  A read of a port gives its output register on output lines and the pins
//  on input lines. The outputs are the output register on output lines and
//  0 on input lines (MAME pia6821_device::get_out_b_value, nothing on its
//  tri-state input). The interrupt flags (control bits 7-6) never set, as
//  nothing drives CA1/CA2/CB1/CB2.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_pia6821
(
	input             clk,
	input             reset,
	input             we,             // one-clock write strobe (selected)
	input       [1:0] rs,
	input       [7:0] din,
	output reg  [7:0] dout,           // read data (combinational)
	input       [7:0] pa_in,
	input       [7:0] pb_in,
	output      [7:0] pa_out,
	output      [7:0] pb_out
);

reg [7:0] ora, orb, ddra, ddrb;
reg [5:0] cra, crb;

assign pa_out = ora & ddra;
assign pb_out = orb & ddrb;

always @(posedge clk) begin
	if (reset) begin
		ora  <= 8'h00;
		orb  <= 8'h00;
		ddra <= 8'h00;
		ddrb <= 8'h00;
		cra  <= 6'd0;
		crb  <= 6'd0;
	end
	else if (we) begin
		case (rs)
			2'd0: if (cra[2]) ora <= din; else ddra <= din;
			2'd1: cra <= din[5:0];
			2'd2: if (crb[2]) orb <= din; else ddrb <= din;
			2'd3: crb <= din[5:0];
		endcase
	end
end

always @(*) begin
	case (rs)
		2'd0:    dout = cra[2] ? ((ora & ddra) | (pa_in & ~ddra)) : ddra;
		2'd1:    dout = {2'b00, cra};
		2'd2:    dout = crb[2] ? ((orb & ddrb) | (pb_in & ~ddrb)) : ddrb;
		default: dout = {2'b00, crb};
	endcase
end

endmodule
