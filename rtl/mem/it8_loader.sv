//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_loader.sv - ROM download routing and SDRAM read-back check
//
//  The MRA sends one stream (ioctl index 0):
//
//    000000-03FFFF  68000 program, bytes in 68000 order   -> SDRAM bank 0
//    040000-1BFFFF  graphics ROMs 0-5                     -> SDRAM bank 1
//    1C0000-1FFFFF  OKI M6295 samples                     -> SDRAM bank 2
//    200000-207FFF  6809 sound program                    -> block RAM
//
//  Byte pairs become 16-bit words (even byte in the upper half). The first
//  eight program bytes are also copied to the 68000 vector registers. When
//  the download ends, and again at every reset, every word is read back and
//  summed, so the debug overlay can compare SUMW (bytes written) with SUMR
//  (bytes read back).
//  NVRAM is filled with FF when a ROM download starts (MAME: all 1s); a
//  saved NVRAM file, if any, is loaded after the ROMs and overwrites it.
//  A file of all zeros is not a state the game ever saves, and the game
//  accepts it (its checksum of zeros is zero) and then divides by a zero
//  setting, so the fill runs again after such a file.
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_loader
(
	input             clk,
	input             reset,          // SDRAM not ready yet

	input             recheck,        // pulse: read the loaded image back again
	input             dl,             // ioctl_download && index 0
	input             nv_dl,          // ioctl_download && index 4 (NVRAM file)
	input             dl_wr,
	input      [26:0] dl_addr,
	input       [7:0] dl_data,
	output            dl_wait,

	// SDRAM write port (toggle)
	output reg [23:0] wr_addr,
	output reg [15:0] wr_data,
	output reg        wr_req,
	input             wr_ack,

	// SDRAM read-back port (toggle)
	output reg [23:0] ver_addr,
	output reg        ver_req,
	input             ver_ack,
	input      [15:0] ver_data,

	// Board loader ports
	output reg        vec_we,
	output reg  [2:0] vec_addr,
	output reg  [7:0] vec_din,
	output reg        snd_we,
	output reg [14:0] snd_addr,
	output reg  [7:0] snd_din,

	// NVRAM fill
	output reg        nv_fill = 1'b0, // owns the NVRAM port while high
	output reg [13:0] nv_fill_addr,
	output reg        nv_zero,        // pulse: an all-zero NVRAM file was replaced
	output            busy,           // hold the board in reset

	output reg        loaded,         // download and check finished
	output reg [31:0] sum_w,          // byte sum written to SDRAM
	output reg [31:0] sum_r,          // byte sum read back
	output reg [20:0] words           // words written
);

reg  [7:0] even_byte;
reg        dl_d = 1'b0;
reg        nv_dl_d = 1'b0;
reg        nv_any;
reg        ver_run;
reg [20:0] ver_idx;                   // word index across the three regions
reg        ver_wait;

assign dl_wait = (wr_req != wr_ack);
assign busy    = nv_fill | nv_dl_d;

// Word index 0-0FFFFF of the SDRAM part of the stream -> SDRAM word address.
function [23:0] sdram_word(input [20:0] w);
	if (w < 21'h20000)      sdram_word = {3'h0, w};
	else if (w < 21'hE0000) sdram_word = 24'h400000 + {3'h0, w - 21'h20000};
	else                    sdram_word = 24'h800000 + {3'h0, w - 21'hE0000};
endfunction

always @(posedge clk) begin
	vec_we  <= 1'b0;
	snd_we  <= 1'b0;
	nv_zero <= 1'b0;

	if (reset) begin
		loaded   <= 1'b0;
		ver_run  <= 1'b0;
		ver_wait <= 1'b0;
		nv_fill  <= 1'b0;
		wr_req   <= wr_ack;
		ver_req  <= ver_ack;
	end
	else begin
		// Edges are taken here, not during reset, so a download that starts
		// before the SDRAM is ready is still seen.
		dl_d    <= dl;
		nv_dl_d <= nv_dl;

		// NVRAM file: note whether any byte is non-zero.
		if (nv_dl && !nv_dl_d) nv_any <= 1'b0;
		if (nv_dl && dl_wr && dl_data != 8'h00) nv_any <= 1'b1;

		// NVRAM fill with FF, 16K bytes: while the ROM download runs, and
		// after an NVRAM file of all zeros.
		if ((dl && !dl_d) || (!nv_dl && nv_dl_d && !nv_any)) begin
			nv_fill      <= 1'b1;
			nv_fill_addr <= 14'd0;
			nv_zero      <= !dl;
		end
		else if (nv_fill) begin
			nv_fill_addr <= nv_fill_addr + 14'd1;
			if (nv_fill_addr == 14'h3FFF) nv_fill <= 1'b0;
		end

		if (dl && !dl_d) begin
			loaded <= 1'b0;
			sum_w  <= 32'd0;
			words  <= 21'd0;
		end

		if (dl && dl_wr) begin
			if (dl_addr < 27'h200000) begin
				if (!dl_addr[0]) even_byte <= dl_data;
				else begin
					wr_addr <= sdram_word({1'b0, dl_addr[20:1]});
					wr_data <= {even_byte, dl_data};
					wr_req  <= ~wr_req;
					words   <= words + 21'd1;
				end
				sum_w <= sum_w + {24'd0, dl_data};
				if (dl_addr < 27'd8) begin
					vec_we   <= 1'b1;
					vec_addr <= dl_addr[2:0];
					vec_din  <= dl_data;
				end
			end
			else if (dl_addr < 27'h208000) begin
				snd_we   <= 1'b1;
				snd_addr <= dl_addr[14:0];
				snd_din  <= dl_data;
			end
		end

		// Download finished, or a re-check was asked for (every reset):
		// read every word back. loaded drops meanwhile, which holds the
		// board in reset, so the check has the SDRAM to itself.
		if ((!dl && dl_d) || (recheck && !dl && !ver_run && words != 21'd0)) begin
			ver_run <= 1'b1;
			ver_idx <= 21'd0;
			sum_r   <= 32'd0;
			loaded  <= 1'b0;
		end

		if (ver_run && !dl && !dl_wait) begin
			if (!ver_wait) begin
				if (ver_idx == words) begin
					ver_run <= 1'b0;
					loaded  <= 1'b1;
				end
				else begin
					ver_addr <= sdram_word(ver_idx);
					ver_req  <= ~ver_req;
					ver_wait <= 1'b1;
				end
			end
			else if (ver_req == ver_ack) begin
				sum_r    <= sum_r + {24'd0, ver_data[15:8]} + {24'd0, ver_data[7:0]};
				ver_idx  <= ver_idx + 21'd1;
				ver_wait <= 1'b0;
			end
		end
	end
end

endmodule
