//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_sdram.sv - SDRAM controller, 48 MHz, CAS latency 2, burst length 1
//
//  Memory map (16-bit words, bank = addr[23:22], row = [21:9], col = [8:0]):
//    bank 0  68000 program ROM   bank 1  blitter GROMs   bank 2  OKI samples
//
//  Command slots are tied to the 68000 clock phase (cpu_ph from it8_ce):
//
//    ph1 clock  decide: 68000 ROM read?     ph2 pins  ACT  (bank 0)
//    ph2 clock  -                           ph3 pins  READ (bank 0)
//    ph3 clock  decide: other client/REF    ph0 pins  ACT / REF
//    ph0 clock  -                           ph1 pins  READ / WRITE
//
//  The 68000 drops AS at the start of a ph1 clock and samples DTACK at the
//  end of the following ph2 clock two CPU clocks later. A ROM read issued in
//  its own slot returns data exactly then, so ROM reads never add wait
//  states, and because the two slots use different banks and command
//  cycles, the blitter and OKI can never delay the 68000.
//
//  Read data is captured on the falling edge of clk in the second clock
//  after READ. SDRAM_CLK is clk inverted, so that edge sits in the middle of
//  the CL2 data window (the SDRAM drives data tAC after its edge T1 and holds
//  it tOH past T2), about 8 ns from either end at 48 MHz. The capture
//  register is the only one fed by the DQ pins, so it goes into the I/O
//  cell and the capture timing is the same in every build.
//
//  Auto refresh is issued only while the 68000 cannot start a ROM read in
//  the next few clocks (cpu_quiet), or unconditionally once 8 are overdue.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_sdram
(
	input             clk,          // 48 MHz; SDRAM_CLK is this clock inverted
	input             init,         // hold high until the PLL has locked
	input       [1:0] cpu_ph,       // 68000 clock phase, 0 = enPhi1 clock
	output reg        ready,        // power-up sequence complete

	// 68000 ROM port. cpu_req is a level: AS low on an unserved ROM read.
	input             cpu_req,
	input      [21:0] cpu_addr,     // word address in bank 0
	output reg        cpu_accept,   // pulse: request taken, deassert cpu_req
	output reg        cpu_ack,      // pulse: cpu_dout valid
	output reg [15:0] cpu_dout,
	input             cpu_quiet,    // no ROM read can start in the next 6 clocks

	// Toggle-handshake read ports: a request is pending while req != ack.
	input      [23:0] blt_addr,     // blitter (GROM)
	input             blt_req,
	output reg        blt_ack,
	output reg [15:0] blt_dout,

	input      [23:0] oki_addr,     // OKI M6295 samples
	input             oki_req,
	output reg        oki_ack,
	output reg [15:0] oki_dout,

	input      [23:0] ver_addr,     // loader read-back check
	input             ver_req,
	output reg        ver_ack,
	output reg [15:0] ver_dout,

	// Toggle-handshake write port (ROM loader).
	input      [23:0] wr_addr,
	input      [15:0] wr_data,
	input       [1:0] wr_be,        // {upper, lower} byte enables
	input             wr_req,
	output reg        wr_ack,

	// Debug counters
	output reg [15:0] dbg_refresh,  // refresh commands issued (wraps)
	output reg [15:0] dbg_forced,   // refreshes that had to be forced

	// SDRAM pins
	output reg [12:0] SDRAM_A,
	output reg  [1:0] SDRAM_BA,
	inout      [15:0] SDRAM_DQ,
	output reg        SDRAM_DQML,
	output reg        SDRAM_DQMH,
	output            SDRAM_nCS,
	output reg        SDRAM_nRAS,
	output reg        SDRAM_nCAS,
	output reg        SDRAM_nWE,
	output            SDRAM_CKE,
	output            SDRAM_CLK
);

assign SDRAM_nCS = 1'b0;
assign SDRAM_CKE = 1'b1;

it8_sdram_clk sdram_clk_out
(
	.clk     (clk),
	.clk_out (SDRAM_CLK)
);

localparam [2:0] CMD_NOP   = 3'b111;
localparam [2:0] CMD_ACT   = 3'b011;
localparam [2:0] CMD_READ  = 3'b101;
localparam [2:0] CMD_WRITE = 3'b100;
localparam [2:0] CMD_PRE   = 3'b010;
localparam [2:0] CMD_REF   = 3'b001;
localparam [2:0] CMD_MRS   = 3'b000;

// Mode register: burst length 1, sequential, CAS latency 2.
localparam [12:0] MODE = 13'b000_0_00_010_0_000;

// Read tags, carried alongside a READ through the capture pipeline.
localparam [2:0] TAG_NONE = 3'd0;
localparam [2:0] TAG_CPU  = 3'd1;
localparam [2:0] TAG_BLT  = 3'd2;
localparam [2:0] TAG_OKI  = 3'd3;
localparam [2:0] TAG_VER  = 3'd4;

// DQ bus: driven only in the WRITE clock, captured on the falling edge.
reg  [15:0] dq_out;
reg         dq_oe;
assign SDRAM_DQ = dq_oe ? dq_out : 16'hZZZZ;

reg  [15:0] dq_neg;
always @(negedge clk) dq_neg <= SDRAM_DQ;

// ---------------------------------------------------------------------------
// Power-up: 250 us of NOP, PRECHARGE ALL, 8 x AUTO REFRESH, MODE REGISTER SET

reg [13:0] init_cnt;
reg  [3:0] init_step;
reg  [3:0] init_wait;

// ---------------------------------------------------------------------------
// Scheduler state

reg  [2:0] tag0, tag1, tag2;        // READ tag on the pins now, 1 and 2 clocks ago
reg        cpu_act;                 // the ACT on the pins now is a 68000 read
reg  [8:0] cpu_col;
reg        oth_act;                 // the ACT on the pins now is an other-slot access
reg        oth_wr;                  //   ... and it is a write
reg  [2:0] oth_tag;
reg  [8:0] oth_col;
reg [15:0] oth_wdata;
reg  [1:0] oth_be;

reg  [2:0] bank_busy;               // clocks until every bank is precharged
reg  [2:0] ref_block;               // clocks until an ACT may follow a REFRESH
reg  [3:0] wr_gap;                  // clocks until the next write may start

reg  [8:0] ref_timer;               // one refresh is due every 374 clocks (7.8 us)
reg  [3:0] ref_pending;

wire blt_pend = blt_req ^ blt_ack;
wire oki_pend = oki_req ^ oki_ack;
wire ver_pend = ver_req ^ ver_ack;
wire wr_pend  = wr_req  ^ wr_ack;

// Reads still in flight: a write must not drive DQ over their data.
wire reads_in_flight = (tag0 != TAG_NONE) | (tag1 != TAG_NONE) | (tag2 != TAG_NONE);

// Toggle acknowledges for requests accepted in the other slot. They flip
// only when data is delivered, so a request stays pending until then;
// these flags stop the scheduler starting the same request twice.
reg blt_busy, oki_busy, ver_busy;

wire act_ok     = (ref_block <= 3'd1);
wire refresh_ok = (bank_busy <= 3'd1) && act_ok && (ref_pending != 4'd0);
wire ref_force  = refresh_ok && (ref_pending >= 4'd8);
wire ref_due    = (ref_timer == 9'd373);
wire ref_issue  = ready && !init && (cpu_ph == 2'd3) && (ref_force || (refresh_ok && cpu_quiet));

always @(posedge clk) begin
	// Defaults: NOP on the pins, no strobes.
	{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
	SDRAM_DQML <= 1'b0;
	SDRAM_DQMH <= 1'b0;
	dq_oe      <= 1'b0;
	cpu_accept <= 1'b0;
	cpu_ack    <= 1'b0;
	cpu_act    <= 1'b0;
	oth_act    <= 1'b0;
	tag0       <= TAG_NONE;
	tag1       <= tag0;
	tag2       <= tag1;

	if (bank_busy != 3'd0) bank_busy <= bank_busy - 3'd1;
	if (ref_block != 3'd0) ref_block <= ref_block - 3'd1;
	if (wr_gap    != 4'd0) wr_gap    <= wr_gap    - 4'd1;

	// One refresh falls due every 374 clocks; ref_issue (below) takes one off.
	ref_timer <= (ref_timer == 9'd373) ? 9'd0 : ref_timer + 9'd1;
	ref_pending <= ref_pending + {3'd0, ref_due & (ref_pending != 4'd15)} - {3'd0, ref_issue};

	if (init) begin
		ready       <= 1'b0;
		init_cnt    <= 14'd0;
		init_step   <= 4'd0;
		init_wait   <= 4'd0;
		ref_pending <= 4'd0;
		ref_timer   <= 9'd0;
		bank_busy   <= 3'd0;
		ref_block   <= 3'd0;
		wr_gap      <= 4'd0;
		blt_ack     <= blt_req;
		oki_ack     <= oki_req;
		ver_ack     <= ver_req;
		wr_ack      <= wr_req;
		blt_busy    <= 1'b0;
		oki_busy    <= 1'b0;
		ver_busy    <= 1'b0;
		dbg_refresh <= 16'd0;
		dbg_forced  <= 16'd0;
	end
	else if (!ready) begin
		// Power-up sequence, independent of the slot structure.
		if (init_cnt != 14'd12000) init_cnt <= init_cnt + 14'd1;
		else if (init_wait != 4'd0) init_wait <= init_wait - 4'd1;
		else begin
			init_step <= init_step + 4'd1;
			init_wait <= 4'd7;
			case (init_step)
				4'd0: begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRE;
					SDRAM_A[10] <= 1'b1;
				end
				4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8:
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_REF;
				4'd9: begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_MRS;
					SDRAM_A  <= MODE;
					SDRAM_BA <= 2'b00;
				end
				default: ready <= 1'b1;
			endcase
		end
	end
	else begin
		case (cpu_ph)
			// ph1 clock: a 68000 ROM read starts here. ACT goes out in ph2.
			2'd1: begin
				if (cpu_req && act_ok) begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
					SDRAM_BA   <= 2'd0;
					SDRAM_A    <= cpu_addr[21:9];
					cpu_col    <= cpu_addr[8:0];
					cpu_act    <= 1'b1;
					cpu_accept <= 1'b1;
					bank_busy  <= 3'd4;
				end
			end

			// ph2 clock: READ with auto precharge for the 68000 goes out in ph3.
			2'd2: begin
				if (cpu_act) begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
					SDRAM_BA <= 2'd0;
					SDRAM_A  <= {2'b00, 1'b1, 1'b0, cpu_col};
					tag0     <= TAG_CPU;
				end
			end

			// ph3 clock: pick the other-slot access (or a refresh) for ph0.
			2'd3: begin
				if (ref_issue) begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_REF;
					ref_block   <= 3'd4;
					bank_busy   <= 3'd4;
					dbg_refresh <= dbg_refresh + 16'd1;
					if (!cpu_quiet) dbg_forced <= dbg_forced + 16'd1;
				end
				else if (act_ok && wr_pend && !reads_in_flight && wr_gap == 4'd0 && bank_busy <= 3'd1) begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
					SDRAM_BA  <= wr_addr[23:22];
					SDRAM_A   <= wr_addr[21:9];
					oth_col   <= wr_addr[8:0];
					oth_wdata <= wr_data;
					oth_be    <= wr_be;
					oth_act   <= 1'b1;
					oth_wr    <= 1'b1;
					oth_tag   <= TAG_NONE;
					bank_busy <= 3'd6;
					wr_gap    <= 4'd8;
				end
				else if (act_ok && !wr_pend && blt_pend && !blt_busy) begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
					SDRAM_BA  <= blt_addr[23:22];
					SDRAM_A   <= blt_addr[21:9];
					oth_col   <= blt_addr[8:0];
					oth_act   <= 1'b1;
					oth_wr    <= 1'b0;
					oth_tag   <= TAG_BLT;
					blt_busy  <= 1'b1;
					bank_busy <= 3'd4;
				end
				else if (act_ok && !wr_pend && oki_pend && !oki_busy) begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
					SDRAM_BA  <= oki_addr[23:22];
					SDRAM_A   <= oki_addr[21:9];
					oth_col   <= oki_addr[8:0];
					oth_act   <= 1'b1;
					oth_wr    <= 1'b0;
					oth_tag   <= TAG_OKI;
					oki_busy  <= 1'b1;
					bank_busy <= 3'd4;
				end
				else if (act_ok && !wr_pend && ver_pend && !ver_busy) begin
					{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACT;
					SDRAM_BA  <= ver_addr[23:22];
					SDRAM_A   <= ver_addr[21:9];
					oth_col   <= ver_addr[8:0];
					oth_act   <= 1'b1;
					oth_wr    <= 1'b0;
					oth_tag   <= TAG_VER;
					ver_busy  <= 1'b1;
					bank_busy <= 3'd4;
				end
			end

			// ph0 clock: READ or WRITE (auto precharge) for the other slot in ph1.
			2'd0: begin
				if (oth_act) begin
					SDRAM_A <= {2'b00, 1'b1, 1'b0, oth_col};
					if (oth_wr) begin
						{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_WRITE;
						dq_out     <= oth_wdata;
						dq_oe      <= 1'b1;
						SDRAM_DQMH <= ~oth_be[1];
						SDRAM_DQML <= ~oth_be[0];
						wr_ack     <= wr_req;
					end
					else begin
						{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
						tag0 <= oth_tag;
					end
				end
			end
		endcase

		// Deliver read data: the READ was on the pins two clocks ago, and
		// its data was captured on the falling edge in the middle of this
		// clock.
		case (tag2)
			TAG_CPU: begin
				cpu_dout <= dq_neg;
				cpu_ack  <= 1'b1;
			end
			TAG_BLT: begin
				blt_dout <= dq_neg;
				blt_ack  <= blt_req;
				blt_busy <= 1'b0;
			end
			TAG_OKI: begin
				oki_dout <= dq_neg;
				oki_ack  <= oki_req;
				oki_busy <= 1'b0;
			end
			TAG_VER: begin
				ver_dout <= dq_neg;
				ver_ack  <= ver_req;
				ver_busy <= 1'b0;
			end
			default: ;
		endcase
	end
end

endmodule


// SDRAM_CLK: clk inverted, through a DDIO output register so its phase
// relative to the command and data outputs is fixed by the I/O cell.
module it8_sdram_clk
(
	input  clk,
	output clk_out
);

`ifdef VERILATOR
assign clk_out = ~clk;
`else
altddio_out
#(
	.extend_oe_disable       ("OFF"),
	.intended_device_family  ("Cyclone V"),
	.invert_output           ("OFF"),
	.lpm_hint                ("UNUSED"),
	.lpm_type                ("altddio_out"),
	.oe_reg                  ("UNREGISTERED"),
	.power_up_high           ("OFF"),
	.width                   (1)
)
sdramclk_ddr
(
	.datain_h   (1'b0),
	.datain_l   (1'b1),
	.outclock   (clk),
	.dataout    (clk_out),
	.aclr       (1'b0),
	.aset       (1'b0),
	.oe         (1'b1),
	.outclocken (1'b1),
	.sclr       (1'b0),
	.sset       (1'b0)
);
`endif

endmodule
