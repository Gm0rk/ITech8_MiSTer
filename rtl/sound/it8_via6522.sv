//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_via6522.sv - 6522 VIA, the subset used by the IT sound board
//
//  Ports A and B with direction registers, timer 1 (one-shot and free-run),
//  timer 2 (one-shot), and the interrupt flag / enable registers. The shift
//  register, handshake lines and PB7 / PB6 timer modes are not connected on
//  this board and are not implemented; their registers read back as written.
//
//  Timers count once per phi2 (6809 E) cycle. In free-run mode timer 1
//  interrupts every N + 2 cycles, as on the real part.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_via6522
(
	input            clk,
	input            reset,
	input            phi2,        // one pulse per E cycle, at its falling edge

	input            cs,          // register access, a pulse together with phi2
	input            rw,          // 1 = read
	input      [3:0] rs,
	input      [7:0] din,
	output reg [7:0] dout,        // read value for rs, valid during the cycle

	input      [7:0] pa_in,
	input      [7:0] pb_in,
	output     [7:0] pa_out,
	output     [7:0] pb_out,
	output           irq
);

reg  [7:0] ora, orb, ddra, ddrb, acr, pcr, sr;
reg  [7:0] t1_ll, t1_lh, t2_ll;
reg [15:0] t1_cnt, t2_cnt;
reg        t1_armed, t1_reload, t2_armed;
reg  [6:0] ifr, ier;

wire [7:0] ifr_rd = {|(ifr & ier), ifr};

assign pa_out = ora | ~ddra;
assign pb_out = orb | ~ddrb;
assign irq    = |(ifr & ier);

always @(*) begin
	case (rs)
		4'h0: dout = (orb & ddrb) | (pb_in & ~ddrb);
		4'h1: dout = (ora & ddra) | (pa_in & ~ddra);
		4'h2: dout = ddrb;
		4'h3: dout = ddra;
		4'h4: dout = t1_cnt[7:0];
		4'h5: dout = t1_cnt[15:8];
		4'h6: dout = t1_ll;
		4'h7: dout = t1_lh;
		4'h8: dout = t2_cnt[7:0];
		4'h9: dout = t2_cnt[15:8];
		4'hA: dout = sr;
		4'hB: dout = acr;
		4'hC: dout = pcr;
		4'hD: dout = ifr_rd;
		4'hE: dout = {1'b1, ier};
		default: dout = (ora & ddra) | (pa_in & ~ddra);
	endcase
end

always @(posedge clk) begin
	if (reset) begin
		ora       <= 8'h00;
		orb       <= 8'h00;
		ddra      <= 8'h00;
		ddrb      <= 8'h00;
		acr       <= 8'h00;
		pcr       <= 8'h00;
		sr        <= 8'h00;
		t1_ll     <= 8'hFF;
		t1_lh     <= 8'hFF;
		t2_ll     <= 8'hFF;
		t1_cnt    <= 16'hFFFF;
		t2_cnt    <= 16'hFFFF;
		t1_armed  <= 1'b0;
		t1_reload <= 1'b0;
		t2_armed  <= 1'b0;
		ifr       <= 7'd0;
		ier       <= 7'd0;
	end
	else if (phi2) begin
		// Timer 1: after reaching zero the next cycle reloads the latch in
		// free-run mode, or keeps counting down in one-shot mode.
		if (t1_reload) begin
			t1_cnt    <= {t1_lh, t1_ll};
			t1_reload <= 1'b0;
		end
		else begin
			t1_cnt <= t1_cnt - 16'd1;
			if (t1_cnt == 16'd0) begin
				if (acr[6] || t1_armed) ifr[6] <= 1'b1;
				t1_armed  <= acr[6];
				t1_reload <= acr[6];
			end
		end

		// Timer 2, one-shot interval mode.
		t2_cnt <= t2_cnt - 16'd1;
		if (t2_cnt == 16'd0 && t2_armed) begin
			ifr[5]   <= 1'b1;
			t2_armed <= 1'b0;
		end

		if (cs) begin
			if (!rw) begin
				case (rs)
					4'h0: orb   <= din;
					4'h1: ora   <= din;
					4'h2: ddrb  <= din;
					4'h3: ddra  <= din;
					4'h4, 4'h6: t1_ll <= din;
					4'h5: begin
						t1_lh     <= din;
						t1_cnt    <= {din, t1_ll};
						t1_reload <= 1'b0;
						t1_armed  <= 1'b1;
						ifr[6]    <= 1'b0;
					end
					4'h7: begin
						t1_lh  <= din;
						ifr[6] <= 1'b0;
					end
					4'h8: t2_ll <= din;
					4'h9: begin
						t2_cnt   <= {din, t2_ll};
						t2_armed <= 1'b1;
						ifr[5]   <= 1'b0;
					end
					4'hA: sr  <= din;
					4'hB: acr <= din;
					4'hC: pcr <= din;
					4'hD: ifr <= ifr & ~din[6:0];
					4'hE: ier <= din[7] ? (ier | din[6:0]) : (ier & ~din[6:0]);
					4'hF: ora <= din;
				endcase
			end
			else begin
				case (rs)
					4'h4: ifr[6] <= 1'b0;
					4'h8: ifr[5] <= 1'b0;
					default: ;
				endcase
			end
		end
	end
end

endmodule
