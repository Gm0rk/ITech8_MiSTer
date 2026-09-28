//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_vram.sv - video RAM and its access scheduler
//
//  Eight MT42C4064 (64K x 4) VRAMs form two display pages. Each address
//  holds two 4-bit pixels (the "VRAM" byte, written with CPU or blitter
//  data) plus two 4-bit upper colour nibbles captured from the TMS34061
//  latch on every write (the "latch" byte). MAME addresses this as an
//  18-bit space: bit 17 selects the page, bits 15:8 the row, bits 7:0 the
//  column. Bit 16 has no RAM behind it on this board; writes with it set
//  are dropped and counted.
//
//  Storage is 16 simple dual-port RAMs, one VRAM byte and one latch byte for
//  each of eight lanes (column bits 2:0). A read returns a whole 8-column
//  chunk, so a 256-byte row moves in 32 accesses: this is what lets the
//  shift-register row copy and the per-line display fetch run in a few
//  hundred nanoseconds, close to the single-cycle transfers of real VRAM.
//
//  Requests are events (single-cycle start pulses held in pending flags),
//  one job runs at a time, and the display line fetch has priority on the
//  read port.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_vram
(
	input              clk,
	input              reset,

	// Display line fetch: copy one 256-byte row into the line buffer.
	input              fetch_start,     // pulse
	input        [8:0] fetch_row,       // {page, row}
	output reg         lb_we,
	output reg   [4:0] lb_addr,         // chunk index
	output reg [127:0] lb_data,         // lane l = {vram, latch} at [16*l +: 16]

	// TMS34061 byte access (CPU XY and direct modes).
	input              tms_start,       // pulse
	input       [17:0] tms_addr,
	input              tms_we,
	input        [7:0] tms_vdata,
	input        [7:0] tms_ldata,
	output reg         tms_done,        // pulse
	output reg   [7:0] tms_rdata,       // VRAM byte before the access

	// TMS34061 shift-register transfer: copy a row, fill latch bytes.
	input              copy_start,      // pulse
	input       [9:0]  copy_src,        // {page, bit16, row}
	input       [9:0]  copy_dst,        // {page, bit16, row}
	input        [7:0] copy_fill,
	output reg         copy_done,       // pulse

	// Blitter nibble write (read-modify-write).
	input              blt_start,       // pulse
	input       [17:0] blt_addr,
	input        [7:0] blt_vdata,
	input        [7:0] blt_vmask,
	input        [7:0] blt_ldata,
	input        [7:0] blt_lmask,
	output reg         blt_done,        // pulse

	output reg  [15:0] dbg_dropped      // writes with address bit 16 set
);

// ---------------------------------------------------------------------------
// Storage

reg  [13:0] rd_addr;
wire [13:0] wr_addr_w;
wire [15:0] ram_we;          // [2*l+1] = VRAM lane l, [2*l] = latch lane l
wire [127:0] rd_data;        // lane l: {vram, latch}
wire [127:0] wr_data;

genvar l;
generate
	for (l = 0; l < 8; l = l + 1) begin : lane
		it8_sdpram #(.AW(14), .DW(8)) vram_ram
		(
			.clk     (clk),
			.rd_addr (rd_addr),
			.rd_data (rd_data[16*l+8 +: 8]),
			.wr_addr (wr_addr_w),
			.wr_data (wr_data[16*l+8 +: 8]),
			.wr_en   (ram_we[2*l+1])
		);

		it8_sdpram #(.AW(14), .DW(8)) latch_ram
		(
			.clk     (clk),
			.rd_addr (rd_addr),
			.rd_data (rd_data[16*l +: 8]),
			.wr_addr (wr_addr_w),
			.wr_data (wr_data[16*l +: 8]),
			.wr_en   (ram_we[2*l])
		);
	end
endgenerate

// Chunk address of an 18-bit VRAM address: {page, row, column bits 7:3}.
function [13:0] chunk_of(input [17:0] a);
	chunk_of = {a[17], a[15:8], a[7:3]};
endfunction

// ---------------------------------------------------------------------------
// Line fetch: 32 reads, then 32 line buffer writes one clock behind.

reg        f_busy;
reg  [8:0] f_row;
reg  [5:0] f_idx;            // next chunk to read, 32 = all issued
reg        f_rd;             // a fetch read was issued last clock
reg  [4:0] f_rd_idx;
wire       f_use = f_busy && (f_idx != 6'd32);  // fetch owns the read port this clock

always @(posedge clk) begin
	lb_we <= 1'b0;
	f_rd  <= 1'b0;
	if (reset) begin
		f_busy <= 1'b0;
	end
	else begin
		if (fetch_start) begin
			f_busy <= 1'b1;
			f_row  <= fetch_row;
			f_idx  <= 6'd0;
		end
		else if (f_use) begin
			f_rd     <= 1'b1;
			f_rd_idx <= f_idx[4:0];
			f_idx    <= f_idx + 6'd1;
		end
		else if (f_busy && !f_rd) f_busy <= 1'b0;

		if (f_rd) begin
			lb_we   <= 1'b1;
			lb_addr <= f_rd_idx;
			lb_data <= rd_data;
		end
	end
end

// ---------------------------------------------------------------------------
// Job scheduler: TMS byte access, TMS row copy, blitter write.

localparam [2:0] J_IDLE = 3'd0;
localparam [2:0] J_BRD  = 3'd1;   // byte: read issued
localparam [2:0] J_BWR  = 3'd2;   // byte: merge and write
localparam [2:0] J_COPY = 3'd3;   // copy: read/write pipeline

reg  [2:0] job;
reg        pend_tms, pend_copy, pend_blt;
reg        job_is_blt;           // current byte job belongs to the blitter
reg [17:0] j_addr;
reg        j_we;
reg  [7:0] j_vdata, j_vmask, j_ldata, j_lmask;

reg  [9:0] c_src, c_dst;
reg  [7:0] c_fill;
reg  [5:0] c_rd_idx;             // next chunk to read
reg        c_rd;                 // a copy read was issued last clock
reg  [4:0] c_wr_idx;

// Write port drive (combinational from the job state).
reg  [13:0] wr_addr;
reg  [15:0] we;
reg [127:0] wdata;
assign wr_addr_w = wr_addr;
assign ram_we    = we;
assign wr_data   = wdata;

wire [2:0] j_lane = j_addr[2:0];
wire [7:0] old_v  = rd_data[16*j_lane+8 +: 8];
wire [7:0] old_l  = rd_data[16*j_lane +: 8];
wire [7:0] new_v  = (old_v & ~j_vmask) | (j_vdata & j_vmask);
wire [7:0] new_l  = (old_l & ~j_lmask) | (j_ldata & j_lmask);

integer i;
always @(*) begin
	rd_addr = chunk_of(j_addr);
	wr_addr = chunk_of(j_addr);
	we      = 16'd0;
	wdata   = {8{new_v, new_l}};

	if (f_use) rd_addr = {f_row, f_idx[4:0]};
	else if (job == J_COPY) rd_addr = {c_src[9], c_src[7:0], c_rd_idx[4:0]};

	if (job == J_BWR && j_we && !j_addr[16]) begin
		we[2*j_lane+1] = |j_vmask;
		we[2*j_lane]   = |j_lmask;
	end

	if (job == J_COPY && c_rd && !c_dst[8]) begin
		wr_addr = {c_dst[9], c_dst[7:0], c_wr_idx};
		we      = 16'hFFFF;
		for (i = 0; i < 8; i = i + 1)
			wdata[16*i +: 16] = {rd_data[16*i+8 +: 8], c_fill};
	end
end

always @(posedge clk) begin
	tms_done  <= 1'b0;
	copy_done <= 1'b0;
	blt_done  <= 1'b0;
	c_rd      <= 1'b0;

	if (tms_start)  pend_tms  <= 1'b1;
	if (copy_start) pend_copy <= 1'b1;
	if (blt_start)  pend_blt  <= 1'b1;

	if (reset) begin
		job         <= J_IDLE;
		pend_tms    <= 1'b0;
		pend_copy   <= 1'b0;
		pend_blt    <= 1'b0;
		dbg_dropped <= 16'd0;
	end
	else case (job)
		J_IDLE: begin
			if (pend_copy) begin
				pend_copy <= 1'b0;
				c_src     <= copy_src;
				c_dst     <= copy_dst;
				c_fill    <= copy_fill;
				c_rd_idx  <= 6'd0;
				job       <= J_COPY;
				if (copy_dst[8]) dbg_dropped <= dbg_dropped + 16'd1;
			end
			else if (pend_tms) begin
				pend_tms   <= 1'b0;
				job_is_blt <= 1'b0;
				j_addr     <= tms_addr;
				j_we       <= tms_we;
				j_vdata    <= tms_vdata;
				j_ldata    <= tms_ldata;
				j_vmask    <= 8'hFF;
				j_lmask    <= 8'hFF;
				job        <= J_BRD;
			end
			else if (pend_blt) begin
				pend_blt   <= 1'b0;
				job_is_blt <= 1'b1;
				j_addr     <= blt_addr;
				j_we       <= 1'b1;
				j_vdata    <= blt_vdata;
				j_vmask    <= blt_vmask;
				j_ldata    <= blt_ldata;
				j_lmask    <= blt_lmask;
				job        <= J_BRD;
			end
		end

		// The read address is presented while in J_BRD; it is taken when
		// the display fetch leaves the port free, and the data is merged
		// one clock later in J_BWR.
		J_BRD: if (!f_use) job <= J_BWR;

		J_BWR: begin
			if (j_we && j_addr[16]) dbg_dropped <= dbg_dropped + 16'd1;
			if (job_is_blt) blt_done <= 1'b1;
			else begin
				tms_done  <= 1'b1;
				tms_rdata <= old_v;
			end
			job <= J_IDLE;
		end

		J_COPY: begin
			if (!f_use && c_rd_idx != 6'd32) begin
				c_rd     <= 1'b1;
				c_wr_idx <= c_rd_idx[4:0];
				c_rd_idx <= c_rd_idx + 6'd1;
			end
			else if (c_rd_idx == 6'd32 && !c_rd) begin
				copy_done <= 1'b1;
				job       <= J_IDLE;
			end
		end

		default: job <= J_IDLE;
	endcase
end

endmodule
