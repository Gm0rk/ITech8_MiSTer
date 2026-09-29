//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_tms34061.sv - TI TMS34061 video system controller
//
//  Register file, raster counters, XY address unit and the CPU-side VRAM
//  functions, as wired on the IT boards (MAME itech8_v.cpp / tms34061.cpp):
//
//    offset[11:9]  function                offset[7:0]
//    0, 2          register access         column; bit 1 inverted, so
//                                          byte 0 of each register is the
//                                          high half
//    1             XY-addressed pixel      bits 4:1 = XY adjustment
//    3             direct VRAM access      column (row is fixed at 0xFF)
//    4             shift register -> VRAM  destination row
//    5             VRAM -> shift register  source row
//
//  Raster counters run on the 4 MHz character clock (two pixels; on the
//  6809 boards 6 MHz, one pixel). Counts go from 0 to the TOTAL registers
//  inclusive; sync runs from 0 to END SYNC, and the display is visible from
//  END BLANK up to START BLANK. At reset the raster registers take the
//  values the game programs at boot (raster09: Strata Bowling's).
//
//  CB = 1 selects the wiring of the earlier Capcom Bowling board (MAME
//  capbowl.cpp): offset[9:8] is the function (0/2 register, 1 XY, 3 direct),
//  the direct-access row comes from the board's row latch (op_row), VRAM is
//  64 KB (address bits above 15 are dropped), and the raster registers reset
//  to Capcom Bowling's values.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_tms34061 #(parameter CB = 0)
(
	input             clk,
	input             reset,
	input             chr_ce,          // 4 MHz character clock (6809 boards: 6 MHz)
	input             raster09,        // reset to Strata Bowling's raster, not Ninja Clowns'

	// CPU access, one byte at a time.
	input             op_start,        // pulse
	input      [11:0] op_offs,         // byte offset inside the TMS window
	input       [7:0] op_row,          // CB: direct-access row (board latch)
	input             op_we,
	input       [7:0] op_wdata,
	output reg        op_done,         // pulse
	output reg  [7:0] op_rdata,

	input             latch_we,        // board latch at 0x100240 (upper colour nibbles)
	input       [7:0] latch_wdata,
	output reg  [7:0] latch,

	// Values the blitter latches when a blit starts.
	output     [15:0] xyaddress,
	output     [15:0] xyoffset,

	// VRAM jobs (it8_vram).
	output reg        vr_start,
	output reg [17:0] vr_addr,
	output reg        vr_we,
	output reg  [7:0] vr_vdata,
	output reg  [7:0] vr_ldata,
	input             vr_done,
	input       [7:0] vr_rdata,
	output reg        cp_start,
	output reg  [9:0] cp_src,
	output reg  [9:0] cp_dst,
	output reg  [7:0] cp_fill,
	input             cp_done,

	// Raster
	output reg  [9:0] hcnt,
	output reg  [9:0] vcnt,
	output            hsync,
	output            vsync,
	output            hblank,
	output            vblank,
	output            line_start,      // pulse: hcnt is about to become 0
	output            next_visible,    // the line starting next is displayed
	output      [7:0] next_y,          // its display line number
	output            vblank_start,    // pulse: vcnt is about to enter vertical blank
	output      [9:0] h_end_sync,      // for the display column offset
	output      [9:0] h_end_blank,     // first visible count
	output     [15:0] dispstart,
	output            display_on,      // CONTROL2 bit 13 (0 = blanked)
	output            irq              // vertical interrupt (unused on 68000 boards)
);

localparam R_HESYNC  = 5'd0;
localparam R_HEBLNK  = 5'd1;
localparam R_HSBLNK  = 5'd2;
localparam R_HTOTAL  = 5'd3;
localparam R_VESYNC  = 5'd4;
localparam R_VEBLNK  = 5'd5;
localparam R_VSBLNK  = 5'd6;
localparam R_VTOTAL  = 5'd7;
localparam R_DUPDATE = 5'd8;
localparam R_DSTART  = 5'd9;
localparam R_VINT    = 5'd10;
localparam R_CTRL1   = 5'd11;
localparam R_CTRL2   = 5'd12;
localparam R_STATUS  = 5'd13;
localparam R_XYOFFS  = 5'd14;
localparam R_XYADDR  = 5'd15;
localparam R_DADDR   = 5'd16;
localparam R_VCOUNT  = 5'd17;

reg [15:0] regs[0:17];
reg  [3:0] yshift;
reg  [9:0] sr_src;               // shift register source row: {page, bit16, row}

assign xyaddress  = regs[R_XYADDR];
assign xyoffset   = regs[R_XYOFFS];
assign dispstart  = regs[R_DSTART];
assign display_on = regs[R_CTRL2][13];
assign h_end_sync = regs[R_HESYNC][9:0];
assign h_end_blank = regs[R_HEBLNK][9:0];
assign irq        = regs[R_STATUS][0] & regs[R_CTRL1][10];

// ---------------------------------------------------------------------------
// Raster counters

wire h_wrap = (hcnt >= regs[R_HTOTAL][9:0]);
wire v_wrap = (vcnt >= regs[R_VTOTAL][9:0]);

assign hsync  = (hcnt < regs[R_HESYNC][9:0]);
assign vsync  = (vcnt < regs[R_VESYNC][9:0]);
assign hblank = !((hcnt >= regs[R_HEBLNK][9:0]) && (hcnt < regs[R_HSBLNK][9:0]));
assign vblank = !((vcnt >= regs[R_VEBLNK][9:0]) && (vcnt < regs[R_VSBLNK][9:0]));

wire [9:0] v_next = v_wrap ? 10'd0 : vcnt + 10'd1;

assign line_start   = chr_ce && h_wrap;
assign next_visible = (v_next >= regs[R_VEBLNK][9:0]) && (v_next < regs[R_VSBLNK][9:0]);
assign next_y       = v_next[7:0] - regs[R_VEBLNK][7:0];
assign vblank_start = chr_ce && h_wrap && !v_wrap && (vcnt + 10'd1 == regs[R_VSBLNK][9:0]);

// The counters are not reset, so sync keeps running through a reset.
always @(posedge clk) begin
	if (chr_ce) begin
		if (h_wrap) begin
			hcnt <= 10'd0;
			vcnt <= v_wrap ? 10'd0 : vcnt + 10'd1;
		end
		else hcnt <= hcnt + 10'd1;
	end
end

// ---------------------------------------------------------------------------
// XY address adjustment (MAME tms34061_device::adjust_xyaddress)

wire [15:0] xmask = (16'd1 << yshift) - 16'd1;
wire [15:0] ystep = (16'd1 << yshift);

function [15:0] xy_adjust(input [15:0] a, input [4:0] mode, input [15:0] xm, input [15:0] ys);
	begin
		case (mode[4:1])
			4'h0: xy_adjust = a;
			4'h1: xy_adjust = a + 16'd1;
			4'h2: xy_adjust = a - 16'd1;
			4'h3: xy_adjust = a & ~xm;
			4'h4: xy_adjust = a + ys;
			4'h5: xy_adjust = ((a & ~xm) | ((a + 16'd1) & xm)) + ys;
			4'h6: xy_adjust = ((a & ~xm) | ((a - 16'd1) & xm)) + ys;
			4'h7: xy_adjust = (a & ~xm) + ys;
			4'h8: xy_adjust = a - ys;
			4'h9: xy_adjust = ((a & ~xm) | ((a + 16'd1) & xm)) - ys;
			4'hA: xy_adjust = ((a & ~xm) | ((a - 16'd1) & xm)) - ys;
			4'hB: xy_adjust = (a & ~xm) - ys;
			4'hC: xy_adjust = a & xm;
			4'hD: xy_adjust = (a + 16'd1) & xm;
			4'hE: xy_adjust = (a - 16'd1) & xm;
			default: xy_adjust = 16'd0;
		endcase
	end
endfunction

// ---------------------------------------------------------------------------
// CPU operations

localparam [1:0] S_IDLE = 2'd0;
localparam [1:0] S_VRAM = 2'd1;   // waiting for a VRAM byte access
localparam [1:0] S_COPY = 2'd2;   // waiting for a row copy

reg  [1:0] state;

wire [2:0] func    = CB ? {1'b0, op_offs[9:8]} : op_offs[11:9];
wire [7:0] col     = op_offs[7:0];
wire [7:0] regcol  = col ^ 8'h02;
wire [5:0] regnum  = regcol[7:2];
wire       reg_hi  = regcol[1];
wire [1:0] ctl2_pg = regs[R_CTRL2][6] ? regs[R_CTRL2][1:0] : 2'b00;

// Register read value, before any read side effects.
wire [15:0] reg_val = (regnum == {1'b0, R_VCOUNT}) ? {6'd0, vcnt} :
                      (regnum < 6'd18)     ? regs[regnum[4:0]] :
                                             16'hFFFF;

integer k;
always @(posedge clk) begin
	op_done  <= 1'b0;
	vr_start <= 1'b0;
	cp_start <= 1'b0;

	if (latch_we) latch <= latch_wdata;

	// Vertical interrupt: status bit 0 at the programmed line, at the
	// start of horizontal blank.
	if (chr_ce && (vcnt == regs[R_VINT][9:0]) && (hcnt == regs[R_HSBLNK][9:0]))
		regs[R_STATUS][0] <= 1'b1;

	if (reset) begin
		state  <= S_IDLE;
		latch  <= 8'h00;
		yshift <= 4'd0;
		sr_src <= 10'd0;
		for (k = 0; k < 18; k = k + 1) regs[k] <= 16'h0000;
		// Raster registers reset to the values the game programs at boot
		// rather than the datasheet defaults (a 1026 x 257 raster), so the
		// monitor sees one stable mode while the core is loading or held in
		// reset. The display stays blanked until the game enables it in
		// CONTROL2, and every register is rewritten by the game.
		regs[R_HESYNC] <= CB ? 16'h000E : raster09 ? 16'h0029 : 16'h000C;
		regs[R_HEBLNK] <= CB ? 16'h000F : raster09 ? 16'h0053 : 16'h002C;
		regs[R_HSBLNK] <= CB ? 16'h00E3 : raster09 ? 16'h0153 : 16'h00E1;
		regs[R_HTOTAL] <= CB ? 16'h00FC : raster09 ? 16'h017D : 16'h00FE;
		regs[R_VESYNC] <= CB ? 16'h0005 : raster09 ? 16'h0003 : 16'h0008;
		regs[R_VEBLNK] <= CB ? 16'h0010 : raster09 ? 16'h0015 : 16'h0013;
		regs[R_VSBLNK] <= CB ? 16'h0105 : raster09 ? 16'h0105 : 16'h0103;
		regs[R_VTOTAL] <= CB ? 16'h0106 : 16'h0106;
		regs[R_CTRL1]  <= 16'h7000;
		regs[R_CTRL2]  <= 16'h0600;
		regs[R_XYOFFS] <= 16'h0010;
	end
	else case (state)
		S_IDLE: if (op_start) begin
			case (func)
				3'd0, 3'd2: begin
					if (op_we) begin
						if (regnum < 6'd18) begin
							if (reg_hi) regs[regnum[4:0]][15:8] <= op_wdata;
							else        regs[regnum[4:0]][7:0]  <= op_wdata;
						end
						if (regnum == {1'b0, R_XYOFFS}) begin
							case (reg_hi ? regs[R_XYOFFS][7:0] : op_wdata)
								8'h01: yshift <= 4'd2;
								8'h02: yshift <= 4'd3;
								8'h04: yshift <= 4'd4;
								8'h08: yshift <= 4'd5;
								8'h10: yshift <= 4'd6;
								8'h20: yshift <= 4'd7;
								8'h40: yshift <= 4'd8;
								8'h80: yshift <= 4'd9;
								default: ;
							endcase
						end
					end
					else begin
						op_rdata <= reg_hi ? reg_val[15:8] : reg_val[7:0];
						if (regnum == {1'b0, R_STATUS}) regs[R_STATUS] <= 16'h0000;
					end
					op_done <= 1'b1;
				end

				3'd1: begin
					// Pixel address is taken before the adjustment.
					vr_addr  <= CB ? {2'b00, regs[R_XYADDR]} : {regs[R_XYOFFS][9:8], regs[R_XYADDR]};
					vr_we    <= op_we;
					vr_vdata <= op_wdata;
					vr_ldata <= latch;
					vr_start <= 1'b1;
					if (col[4:1] != 4'h0)
						regs[R_XYADDR] <= xy_adjust(regs[R_XYADDR], col[4:0], xmask, ystep);
					state    <= S_VRAM;
				end

				3'd3: begin
					// IT 8-bit boards: row hard-wired to 0xFF, and only writes
					// add the CONTROL2 page bits (as MAME). Capcom Bowling:
					// row from the board latch, 64 KB.
					vr_addr  <= CB ? {2'b00, op_row, col} : {op_we ? ctl2_pg : 2'b00, 8'hFF, col};
					vr_we    <= op_we;
					vr_vdata <= op_wdata;
					vr_ldata <= latch;
					vr_start <= 1'b1;
					state    <= S_VRAM;
				end

				3'd4: begin
					// Shift register -> VRAM: copy the source row, fill the
					// latch nibbles from the latch. Reads do the same.
					cp_src   <= sr_src;
					cp_dst   <= {ctl2_pg[1], ctl2_pg[0], col};
					cp_fill  <= latch;
					cp_start <= 1'b1;
					op_rdata <= 8'h00;
					state    <= S_COPY;
				end

				3'd5: begin
					// VRAM -> shift register: MAME keeps a pointer to the row.
					sr_src   <= {ctl2_pg[1], ctl2_pg[0], col};
					op_rdata <= 8'h00;
					op_done  <= 1'b1;
				end

				default: begin
					op_rdata <= 8'h00;
					op_done  <= 1'b1;
				end
			endcase
		end

		S_VRAM: if (vr_done) begin
			op_rdata <= vr_rdata;
			op_done  <= 1'b1;
			state    <= S_IDLE;
		end

		S_COPY: if (cp_done) begin
			op_done <= 1'b1;
			state   <= S_IDLE;
		end

		default: state <= S_IDLE;
	endcase
end

endmodule
