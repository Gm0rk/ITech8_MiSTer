//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  Arcade-ITech8.sv - MiSTer emu top level
//
//  Three boards, chosen by the MRA (ioctl index 1, one byte, bits 1:0):
//    0  Ninja Clowns (Strata / Incredible Technologies, 1991), the 68000
//       variant of the IT 8-bit blitter hardware (it8_top)
//    1  Capcom Bowling / Coors Light Bowling (1988-89), the earlier 6809
//       board (cb_top)
//    2  Bowl-O-Rama (1991): the same board with its turbo board
//    3  the 6809 variant of the IT 8-bit blitter hardware, Strata Bowling
//       (1990) style: it8_top with its 6809 main CPU (it8_main09)
//  The board not selected is held in reset; SDRAM ports, NVRAM, video and
//  audio are switched between them. The bowling games are vertical (MAME
//  ROT270); screen_rotate turns them for a horizontal screen.
//
//  Clocks: clk_sys 48 MHz runs the whole board (every board clock divides
//  it, see it8_ce.sv) and the SDRAM. clk_vid 96 MHz, from the same PLL, runs
//  the video output stage so CRT Adjust can step H-Size in 1/48 of a pixel.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1         = 0;
assign VGA_SCALER     = 0;
assign VGA_DISABLE    = 0;
assign HDMI_FREEZE    = 0;
assign HDMI_BLACKOUT  = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////
// OSD

`include "build_id.v"
`include "rtl/it8_build.vh"

// CRT Adjust amounts. H-Size and V-Shift are 5-bit two's complement; the
// H-Position list is 0..+48 then -48..-1 (index 49 = -48).
localparam CRT_S5 = "0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1";
localparam CRT_HP = "0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1";

`ifdef IT8_DEBUG
localparam CONF_DBG = {
	"P2,Debug;",
	"P2-;",
	"P2O[65:64],Diagnostic overlay,Off,Board,Trackball,Analog;",
	"P2T[66],Clear control counters;",
	"-;"
};
`else
localparam CONF_DBG = "-;";
`endif

localparam CONF_STR = {
	"ITech8;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O[12:10],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"P1,CRT Adjust;",
	"P1-;",
	"P1O[101],CRT Adjust,Off,On;",
	"H1P1O[102],CRT Auto-Width,Off,On;",
	"H1P1O[100:96],CRT H-Size,", CRT_S5, ";",
	"H1P1O[85:79],CRT H-Position,", CRT_HP, ";",
	"H1P1O[78:74],CRT V-Shift,", CRT_S5, ";",
	"-;",
	"H2O[8:7],Audio,FM + PCM,FM only,PCM only;",
	"H3O[18:17],Orientation,Horizontal,Vertical,Vertical Flip;",
	"H4O[16:15],Trackball Speed,Normal,Fast,Slow;",
	"H5O[20:19],Trackball Sideways,1x,2x,3x,4x;",
	// The board's service switch: on opens the game's service menu.
	"O[9],Service Mode,Off,On;",
	CONF_DBG,
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"J1,Punch,Kick,Throw,Start,Coin,Service;",
	"jn,A,B,X,Start,R,L;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [21:0] gamma_bus;

wire         ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire  [15:0] ioctl_index;
wire         ioctl_wait;
wire   [7:0] ioctl_din;

wire  [31:0] joystick_0, joystick_1, joystick_2;
wire  [24:0] ps2_mouse;
// For the debug build's Controls page only (it8_dbg_ctrl.sv); no game uses
// them.
wire  [15:0] ana_l0, ana_r0, ana_l1, ana_r1;
wire   [8:0] spinner_0;
wire   [7:0] paddle_0;
wire         video_rotated;

// Board, from the MRA (ioctl index 1). Bits 1:0: 0 Ninja Clowns, 1 Capcom
// / Coors Light Bowling, 2 Bowl-O-Rama, 3 an itech8 6809 board (Strata
// Bowling style). Bits 7:2 describe a 6809 game: 7 vertical (ROT270),
// 6 trackball, 5 Golden Par Golf's 1992 board (its I/O layout, YM3812 sound
// board, joystick and swing button), 4 program bank bit inverted, 3 64 KB
// program, 2 joystick and swing button (Golden Tee Golf). Stays 0 when the
// MRA sends no index 1. An optional second byte carries more 6809 layout
// bits: bit 0 MAME's common_lo_map (TMS34061 at 0000, I/O at 1100; Golden
// Tee Golf II joystick); bits 2-1 the display (0 two layers, 1 2 page large
// at 8 MHz, 2 one 8-bit page); bits 4-3 the sound board (0 as bit 5 of the
// first byte says, 1 the YM3812 board with a PIA); bit 6 the NVRAM starts
// as 00, not FF; bit 7 the game is vertical the other way (MAME ROT90). A third byte is the input layout
// (it8_ports09.sv; 0 the ports of the games before build 020). Both are
// cleared with every first byte, so an MRA that sends one byte gets 0.
reg    [7:0] board_byte = 8'd0;
reg    [7:0] board_byte2 = 8'd0;
reg    [7:0] board_byte3 = 8'd0;
wire   [1:0] board_sel = board_byte[1:0];
wire         is_cb  = (board_sel == 2'd1) || (board_sel == 2'd2);
wire         is_br  = (board_sel == 2'd2);
wire         is_m09 = (board_sel == 2'd3);
wire         rot90   = is_m09 & board_byte2[7];
wire         is_vert = is_cb | (is_m09 & board_byte[7]) | rot90;
wire         has_tb  = is_cb | (is_m09 & board_byte[6]);
wire         is_gtg2 = is_m09 & board_byte[5];
wire         one_btn = is_m09 & ~board_byte[6] & (board_byte[2] | board_byte[5]);   // swing only
wire         map_lo  = is_m09 & board_byte2[0];
wire   [1:0] disp_mode = is_m09 ? board_byte2[2:1] : 2'd0;
wire   [1:0] snd_mode  = is_m09 ? board_byte2[4:3] : 2'd0;
wire   [3:0] in_layout = is_m09 ? board_byte3[3:0] : 4'd0;
wire         has_dial  = (in_layout == 4'd1) || (in_layout == 4'd7);   // it8_main09
wire         nv_fill00 = is_br | (is_m09 & board_byte2[6]);           // NVRAM starts 00
// 6 MHz dots: the 6809 games but those in 2 page large (8 MHz, as Ninja
// Clowns and the bowling board).
wire         dot6      = is_m09 & ~disp_mode[0];
wire         flip180 = is_vert & (status[18:17] == 2'd2);   // OSD Orientation "Vertical Flip"

// Declared here because hps_io and the loader use them before the board.
wire         nv_written;
reg          nv_dirty = 1'b0;
wire         nv_io = (ioctl_index[5:0] == 6'd4);
wire         nv_saving = ioctl_upload & nv_io;

// NVRAM save request (D-032). MiSTer checks it each time the OSD's main page
// is drawn, which is on opening and again after every option change, and
// hps_io latches it on a rising edge. These games' battery RAM is their work
// RAM, written all the time, so the request is held low while the OSD is
// open: one save as it opens, none while settings are changed, and a new
// request once it closes.
reg    [1:0] osd_s = 2'b00;
always @(posedge clk_sys) osd_s <= {osd_s[0], OSD_STATUS};
wire         nv_save_req = nv_dirty & ~osd_s[1];
wire         user_reset = status[0] | buttons[1];
reg          user_reset_d;
reg          reset = 1'b1;

hps_io #(.CONF_STR(CONF_STR), .CONF_STR_BRAM(1)) hps_io
(
	.clk_sys            (clk_sys),
	.HPS_BUS            (HPS_BUS),
	.EXT_BUS            (),
	.gamma_bus          (gamma_bus),

	.forced_scandoubler (forced_scandoubler),
	.video_rotated      (video_rotated),
	.new_vmode          (1'b0),

	.buttons            (buttons),
	.status             (status),
	.status_menumask    ({10'd0, ~has_tb, ~(has_tb | has_dial), ~is_vert, is_cb, ~status[101], 1'b0}),

	.ioctl_download     (ioctl_download),
	.ioctl_upload       (ioctl_upload),
	.ioctl_upload_req   (nv_save_req),
	.ioctl_upload_index (8'd4),
	.ioctl_wr           (ioctl_wr),
	.ioctl_rd           (ioctl_rd),
	.ioctl_addr         (ioctl_addr),
	.ioctl_dout         (ioctl_dout),
	.ioctl_din          (ioctl_din),
	.ioctl_index        (ioctl_index),
	.ioctl_wait         (ioctl_wait),

	.joystick_0         (joystick_0),
	.joystick_1         (joystick_1),
	.joystick_2         (joystick_2),
	.joystick_l_analog_0 (ana_l0),
	.joystick_r_analog_0 (ana_r0),
	.joystick_l_analog_1 (ana_l1),
	.joystick_r_analog_1 (ana_r1),
	.paddle_0           (paddle_0),
	.spinner_0          (spinner_0),
	.ps2_mouse          (ps2_mouse)
);

always @(posedge clk_sys)
	if (ioctl_download && ioctl_wr && ioctl_index[5:0] == 6'd1) begin
		if (ioctl_addr == 27'd0) begin
			board_byte  <= ioctl_dout;
			board_byte2 <= 8'd0;
			board_byte3 <= 8'd0;
		end
		else if (ioctl_addr == 27'd1)
			board_byte2 <= ioctl_dout;
		else if (ioctl_addr == 27'd2)
			board_byte3 <= ioctl_dout;
	end

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys, clk_vid, pll_locked;

pll pll
(
	.refclk   (CLK_50M),
	.rst      (0),
	.outclk_0 (clk_sys),
	.outclk_1 (clk_vid),
	.locked   (pll_locked)
);

wire cpu_phi1, cpu_phi2, pix_ce, chr_ce, pix_left;
wire snd_fall_e, snd_fall_q, ym_cen, oki_cen, vid6_ce;
wire [1:0] cpu_ph;

it8_ce ce
(
	.clk        (clk_sys),
	.reset      (~pll_locked),
	.cpu_phi1   (cpu_phi1),
	.cpu_phi2   (cpu_phi2),
	.cpu_ph     (cpu_ph),
	.pix_ce     (pix_ce),
	.chr_ce     (chr_ce),
	.pix_left   (pix_left),
	.snd_fall_e (snd_fall_e),
	.snd_fall_q (snd_fall_q),
	.ym_cen     (ym_cen),
	.oki_cen    (oki_cen),
	.blt_tick   (),
	.vid6_ce    (vid6_ce)
);

///////////////////////   SDRAM AND ROM LOADING   ///////////////

wire        sd_ready;
wire        rom_accept, rom_ack;
wire [15:0] rom_data;
wire [23:0] ver_addr, wr_addr;
wire        grom_ack, pcm_ack, ver_req, ver_ack, wr_req, wr_ack;
wire [15:0] grom_data, pcm_data, ver_data, wr_data;
wire [15:0] sd_refresh, sd_forced;

// Each board's SDRAM requests; the board in reset holds its lines still.
wire        it8_rom_req, it8_rom_quiet, it8_grom_req, it8_pcm_req;
wire [21:0] it8_rom_addr;
wire [23:0] it8_grom_addr, it8_pcm_addr;
wire        cb_rom_req, cb_rom_quiet, cb_blt_req, cb_snd_req;
wire [21:0] cb_rom_addr;
wire [23:0] cb_blt_addr, cb_snd_addr;

wire        rom_req   = is_cb ? cb_rom_req   : it8_rom_req;
wire [21:0] rom_addr  = is_cb ? cb_rom_addr  : it8_rom_addr;
wire        rom_quiet = is_cb ? cb_rom_quiet : it8_rom_quiet;
wire        grom_req  = is_cb ? cb_blt_req   : it8_grom_req;
wire [23:0] grom_addr = is_cb ? cb_blt_addr  : it8_grom_addr;
wire        pcm_req   = is_cb ? cb_snd_req   : it8_pcm_req;
wire [23:0] pcm_addr  = is_cb ? cb_snd_addr  : it8_pcm_addr;

it8_sdram sdram
(
	.clk         (clk_sys),
	.init        (~pll_locked),
	.cpu_ph      (cpu_ph),
	.ready       (sd_ready),
	.cpu_req     (rom_req),
	.cpu_addr    (rom_addr),
	.cpu_accept  (rom_accept),
	.cpu_ack     (rom_ack),
	.cpu_dout    (rom_data),
	.cpu_quiet   (rom_quiet),
	.blt_addr    (grom_addr),
	.blt_req     (grom_req),
	.blt_ack     (grom_ack),
	.blt_dout    (grom_data),
	.oki_addr    (pcm_addr),
	.oki_req     (pcm_req),
	.oki_ack     (pcm_ack),
	.oki_dout    (pcm_data),
	.ver_addr    (ver_addr),
	.ver_req     (ver_req),
	.ver_ack     (ver_ack),
	.ver_dout    (ver_data),
	.wr_addr     (wr_addr),
	.wr_data     (wr_data),
	.wr_be       (2'b11),
	.wr_req      (wr_req),
	.wr_ack      (wr_ack),
	.dbg_refresh (sd_refresh),
	.dbg_forced  (sd_forced),
	.SDRAM_A     (SDRAM_A),
	.SDRAM_BA    (SDRAM_BA),
	.SDRAM_DQ    (SDRAM_DQ),
	.SDRAM_DQML  (SDRAM_DQML),
	.SDRAM_DQMH  (SDRAM_DQMH),
	.SDRAM_nCS   (SDRAM_nCS),
	.SDRAM_nRAS  (SDRAM_nRAS),
	.SDRAM_nCAS  (SDRAM_nCAS),
	.SDRAM_nWE   (SDRAM_nWE),
	.SDRAM_CKE   (SDRAM_CKE),
	.SDRAM_CLK   (SDRAM_CLK)
);

// ioctl_index[5:0] is the MRA index; the upper bits can carry the file
// extension index, so only the low six bits are compared (nv_io above).
wire        rom_dl = ioctl_download && (ioctl_index[5:0] == 6'd0);

wire        vec_we, snd_we, nv_fill, nv_zero, loaded, ld_wait, ld_busy;
wire  [2:0] vec_addr;
wire  [7:0] vec_din, snd_din;
wire [14:0] snd_addr;
wire [13:0] nv_fill_addr;
wire [31:0] sum_w, sum_r;
wire [20:0] words;
wire [23:0] grom_bytes;

it8_loader loader
(
	.clk          (clk_sys),
	.reset        (~sd_ready),
	.recheck      (user_reset & ~user_reset_d),
	.cb           (is_cb),
	.m09          (is_m09),
	.nv_guard     (~is_cb & ~is_m09),
	.dl           (rom_dl),
	.nv_dl        (ioctl_download & nv_io),
	.dl_wr        (ioctl_wr),
	.dl_addr      (ioctl_addr),
	.dl_data      (ioctl_dout),
	.dl_wait      (ld_wait),
	.wr_addr      (wr_addr),
	.wr_data      (wr_data),
	.wr_req       (wr_req),
	.wr_ack       (wr_ack),
	.ver_addr     (ver_addr),
	.ver_req      (ver_req),
	.ver_ack      (ver_ack),
	.ver_data     (ver_data),
	.vec_we       (vec_we),
	.vec_addr     (vec_addr),
	.vec_din      (vec_din),
	.snd_we       (snd_we),
	.snd_addr     (snd_addr),
	.snd_din      (snd_din),
	.nv_fill      (nv_fill),
	.nv_fill_addr (nv_fill_addr),
	.nv_zero      (nv_zero),
	.busy         (ld_busy),
	.loaded       (loaded),
	.sum_w        (sum_w),
	.sum_r        (sum_r),
	.words        (words),
	.grom_bytes   (grom_bytes)
);

// Downloads wait while the SDRAM is still initialising.
assign ioctl_wait = ld_wait | ~sd_ready;

// NVRAM, MiSTer side: filled at ROM load (FF; Bowl-O-Rama 00, as MAME; Hot
// Shots Tennis 00, board byte 2 bit 6: from all FF it hangs at the first
// game start, in MAME too, D-041), then the saved file (index 4); for
// Ninja Clowns a file of all zeros is
// replaced by the FF fill again (it8_loader). Any CPU write marks it for
// saving; MiSTer saves it when the OSD opens, and the CPUs are held
// meanwhile so the image is consistent.
wire  [7:0] it8_nv_dout, cb_nv_dout;
wire        it8_nv_written, cb_nv_written;
wire  [7:0] nv_dout = is_cb ? cb_nv_dout : it8_nv_dout;
assign      nv_written = is_cb ? cb_nv_written : it8_nv_written;

always @(posedge clk_sys) begin
	if (nv_written) nv_dirty <= 1'b1;
	if (nv_saving)  nv_dirty <= 1'b0;
end

wire [13:0] nv_addr = nv_fill ? nv_fill_addr : ioctl_addr[13:0];
wire  [7:0] nv_din  = nv_fill ? (nv_fill00 ? 8'h00 : 8'hFF) : ioctl_dout;
wire        nv_we   = nv_fill | (ioctl_download & ioctl_wr & nv_io & ~|ioctl_addr[26:14]);
assign ioctl_din    = nv_dout;

///////////////////////   BOARD   ////////////////////////////////

// A user reset also re-reads the ROM image (SUMR on the overlay). The
// board also stays in reset while the loader fills NVRAM.
always @(posedge clk_sys) begin
	user_reset_d <= user_reset;
	reset        <= RESET | user_reset | ioctl_download | ~loaded | ~sd_ready | ld_busy;
end

// MiSTer joystick: [3:0] = up, down, left, right (bit 3 = up); then the
// buttons in the order the MRA names them. Ninja Clowns: punch, kick, throw,
// start, coin, service (bits 4-9). The trackball games have no third button,
// so their MRAs name five: hook left, hook right, start, coin, service (bits
// 4-8), and MiSTer asks for nothing it does not use (D-033). The golf
// games with a stick have one button: swing, start, coin, service (bits
// 4-7). j0 and j1 put them all in the Ninja Clowns layout, the missing
// buttons reading 0. The games from build 020 on have their own layouts
// (board byte 3, it8_ports09.sv), which take the joysticks as they come.
function [15:0] jlayout(input [31:0] j, input two, input one);
	jlayout = two ? {j[15:10], j[8:6], 1'b0, j[5:0]} :
	          one ? {j[15:10], j[7:5], 2'b00, j[4:0]} : j[15:0];
endfunction
wire [15:0] j0 = jlayout(joystick_0, has_tb, one_btn);
wire [15:0] j1 = jlayout(joystick_1, has_tb, one_btn);

wire [7:0] p1 = {j0[4], j0[5], j0[0], j0[1], j0[2], j0[3], j0[7], j0[6]};
wire [7:0] p2 = {j1[4], j1[5], j1[0], j1[1], j1[2], j1[3], j1[7], j1[6]};

// Trackball (bowling and golf games) or dial: the mouse, or the stick.
wire [7:0] track_x, track_y;
wire [15:0] track_drop_x, track_drop_y;      // the Controls page's DROP

cb_trackball trackball
(
	.clk       (clk_sys),
	.reset     (reset),
	.ps2_mouse (ps2_mouse),
	.up        (j0[3]),
	.down      (j0[2]),
	.left      (j0[1]),
	.right     (j0[0]),
	.speed     (status[16:15]),
	.side      (status[20:19]),
	.per_frame (is_m09),
	.x         (track_x),
	.y         (track_y),
	.drop_x    (track_drop_x),
	.drop_y    (track_drop_y)
);

wire        it8_ce_pix, it8_hs, it8_vs, it8_hb, it8_vb;
wire  [7:0] it8_r, it8_g, it8_b;
wire [15:0] it8_audio;

wire [23:0] dbg_pc;
wire [15:0] dbg_frames, dbg_irq3, dbg_irq2, dbg_waits, dbg_blits, dbg_blit_late;
wire [15:0] dbg_vram_drop, dbg_snd_cmds, dbg_snd_pc;
wire  [7:0] dbg_snd_last, dbg_page;
wire [31:0] dbg_nv104;

it8_top board
(
	.clk           (clk_sys),
	.reset         (reset | is_cb),
	.hold          (nv_saving),
	.vid6_ce       (vid6_ce),
	.cpu09         (is_m09),
	.bank_xor      (board_byte[4]),
	.prog64        (board_byte[3]),
	.joy09         (board_byte[2]),
	.gtg2          (is_gtg2),
	.tb09          (has_tb),
	.map_lo        (map_lo),
	.tb_horiz      (~board_byte[7]),
	.disp_mode     (disp_mode),
	.snd_mode      (snd_mode),
	.in_layout     (in_layout),
	.grom_size     (is_m09 ? grom_bytes : 24'h180000),
	// A game without a trackball reads 0 there, as MAME (read_safe(0)):
	// the stick, which also drives cb_trackball, must not show up in it.
	.track_x       ((has_tb | has_dial) ? track_x : 8'd0),
	.track_y       (has_tb ? track_y : 8'd0),
	.j0r           (joystick_0[15:0]),
	.j1r           (joystick_1[15:0]),
	.j2r           (joystick_2[15:0]),
	.cpu_phi1      (cpu_phi1),
	.cpu_phi2      (cpu_phi2),
	.pix_ce        (pix_ce),
	.chr_ce        (chr_ce),
	.pix_left      (pix_left),
	.snd_fall_e    (snd_fall_e),
	.snd_fall_q    (snd_fall_q),
	.ym_cen        (ym_cen),
	.oki_cen       (oki_cen),
	.p1            (p1),
	.p2            (p2),
	.coin1         (j0[8]),
	.coin2         (j1[8]),
	.service       (j0[9] | j1[9]),
	.test          (status[9]),
	.rom_req       (it8_rom_req),
	.rom_addr      (it8_rom_addr),
	.rom_accept    (rom_accept),
	.rom_ack       (rom_ack),
	.rom_data      (rom_data),
	.rom_quiet     (it8_rom_quiet),
	.grom_addr     (it8_grom_addr),
	.grom_req      (it8_grom_req),
	.grom_ack      (grom_ack),
	.grom_data     (grom_data),
	.pcm_addr      (it8_pcm_addr),
	.pcm_req       (it8_pcm_req),
	.pcm_ack       (pcm_ack),
	.pcm_data      (pcm_data),
	.vec_we        (vec_we),
	.vec_addr      (vec_addr),
	.vec_din       (vec_din),
	.snd_rom_we    (snd_we),
	.snd_rom_addr  (snd_addr),
	.snd_rom_din   (snd_din),
	.nv_addr       (nv_addr),
	.nv_din        (nv_din),
	.nv_we         (nv_we),
	.nv_dout       (it8_nv_dout),
	.nv_written    (it8_nv_written),
	.ce_pix        (it8_ce_pix),
	.r             (it8_r),
	.g             (it8_g),
	.b             (it8_b),
	.hs            (it8_hs),
	.vs            (it8_vs),
	.hblank        (it8_hb),
	.vblank        (it8_vb),
	.mix_sel       (status[8:7]),
	.audio         (it8_audio),
	.dbg_pc        (dbg_pc),
	.dbg_frames    (dbg_frames),
	.dbg_irq3      (dbg_irq3),
	.dbg_irq2      (dbg_irq2),
	.dbg_waits     (dbg_waits),
	.dbg_blits     (dbg_blits),
	.dbg_blit_late (dbg_blit_late),
	.dbg_vram_drop (dbg_vram_drop),
	.dbg_snd_cmds  (dbg_snd_cmds),
	.dbg_snd_last  (dbg_snd_last),
	.dbg_snd_pc    (dbg_snd_pc),
	.dbg_page      (dbg_page),
	.dbg_nv104     (dbg_nv104)
);

// ---------------------------------------------------------------------------
// Capcom Bowling board. Controls on the MRA's buttons: Hook Left (1), Hook
// Right (2), Start (3), Coin (4), Service (5); the trackball from the mouse
// or the stick.


wire        cb_ce_pix, cb_hs, cb_vs, cb_hb, cb_vb;
wire  [7:0] cb_r, cb_g, cb_b;
wire [15:0] cb_audio;
wire [15:0] cb_pc, cb_frames, cb_firq, cb_nmi, cb_waits, cb_turbo, cb_snd_cmds, cb_snd_pc;
wire  [7:0] cb_snd_last, cb_bank;

cb_top cb_board
(
	.clk          (clk_sys),
	.reset        (reset | ~is_cb),
	.hold         (nv_saving),
	.bowlrama     (is_br),
	.pix_ce       (pix_ce),
	.chr_ce       (chr_ce),
	.pix_left     (pix_left),
	.ym_cen       (ym_cen),
	.wide         (1'b0),
	.track_x      (track_x),
	.track_y      (track_y),
	.p1_hook_l    (j0[4]),
	.p1_hook_r    (j0[5]),
	.p2_hook_l    (j1[4]),
	.p2_hook_r    (j1[5]),
	.start        (j0[7] | j1[7]),
	.coin1        (j0[8]),
	.coin2        (j1[8]),
	.service      (j0[9] | j1[9] | status[9]),
	.cocktail     (1'b0),
	.rom_req      (cb_rom_req),
	.rom_addr     (cb_rom_addr),
	.rom_accept   (rom_accept),
	.rom_ack      (rom_ack),
	.rom_data     (rom_data),
	.rom_quiet    (cb_rom_quiet),
	.blt_addr     (cb_blt_addr),
	.blt_req      (cb_blt_req),
	.blt_ack      (grom_ack),
	.blt_data     (grom_data),
	.snd_addr     (cb_snd_addr),
	.snd_req      (cb_snd_req),
	.snd_ack      (pcm_ack),
	.snd_data     (pcm_data),
	.nv_addr      (nv_addr[10:0]),
	.nv_din       (nv_din),
	.nv_we        (nv_we),
	.nv_dout      (cb_nv_dout),
	.nv_written   (cb_nv_written),
	.ce_pix       (cb_ce_pix),
	.r            (cb_r),
	.g            (cb_g),
	.b            (cb_b),
	.hs           (cb_hs),
	.vs           (cb_vs),
	.hblank       (cb_hb),
	.vblank       (cb_vb),
	.audio        (cb_audio),
	.dbg_pc       (cb_pc),
	.dbg_frames   (cb_frames),
	.dbg_firq     (cb_firq),
	.dbg_nmi      (cb_nmi),
	.dbg_waits    (cb_waits),
	.dbg_turbo    (cb_turbo),
	.dbg_snd_cmds (cb_snd_cmds),
	.dbg_snd_last (cb_snd_last),
	.dbg_snd_pc   (cb_snd_pc),
	.dbg_bank     (cb_bank)
);

// Selected board's picture and sound. Both boards' pixel enables are pix_ce
// one clock late, so the stream timing is the same either way.
wire        ce_pix  = is_cb ? cb_ce_pix : it8_ce_pix;
wire  [7:0] core_r  = is_cb ? cb_r  : it8_r;
wire  [7:0] core_g  = is_cb ? cb_g  : it8_g;
wire  [7:0] core_b  = is_cb ? cb_b  : it8_b;
wire        core_hs = is_cb ? cb_hs : it8_hs;
wire        core_vs = is_cb ? cb_vs : it8_vs;
wire        core_hb = is_cb ? cb_hb : it8_hb;
wire        core_vb = is_cb ? cb_vb : it8_vb;
wire [15:0] audio   = is_cb ? cb_audio : it8_audio;

assign AUDIO_L = audio;
assign AUDIO_R = audio;

///////////////////////   DIAGNOSTIC OVERLAY   ///////////////////

// The panel is drawn after Vertical Flip turns the picture (video output
// section), so it stays upright: ov_hit is a text pixel, ov_blk the box.
wire ov_hit, ov_blk;

`ifdef IT8_DEBUG
reg  [8:0] vis_x;
reg  [7:0] vis_y;
reg        hb_d;

always @(posedge clk_sys) begin
	if (ce_pix) begin
		hb_d <= core_hb;
		if (!core_hb) vis_x <= vis_x + 9'd1;
		if (core_hb && !hb_d) begin
			vis_x <= 9'd0;
			if (!core_vb) vis_y <= vis_y + 8'd1;
		end
		if (core_vb) vis_y <= 8'd0;
	end
end

// BLD: compile date (YYMMDD from build_id.v) then the build number.
localparam [47:0] BLD_DATE = `BUILD_DATE;
// The digits are worked out as integers and cut to four bits, so the lint
// width check does not depend on the build number.
localparam integer BN_HI   = (`IT8_BUILD / 100) % 10;
localparam integer BN_TI   = (`IT8_BUILD / 10) % 10;
localparam integer BN_OI   = `IT8_BUILD % 10;
localparam  [3:0] BN_H     = BN_HI[3:0];
localparam  [3:0] BN_T     = BN_TI[3:0];
localparam  [3:0] BN_O     = BN_OI[3:0];
localparam [35:0] BLD_BCD  = {BLD_DATE[43:40], BLD_DATE[35:32], BLD_DATE[27:24], BLD_DATE[19:16],
                              BLD_DATE[11:8], BLD_DATE[3:0], BN_H, BN_T, BN_O};

// NVST: FF fills, NVRAM files loaded, all-zero files replaced (one hex
// digit each, saturating), then the number of saves.
reg  [3:0] nvst_fill = 4'd0, nvst_file = 4'd0, nvst_zero = 4'd0;
reg [15:0] nvst_save = 16'd0;
reg        nvst_fill_d = 1'b0, nvst_dl_d = 1'b0, nvst_save_d = 1'b0;

always @(posedge clk_sys) begin
	nvst_fill_d <= nv_fill;
	nvst_dl_d   <= ioctl_download & nv_io;
	nvst_save_d <= nv_saving;
	if (nv_fill && !nvst_fill_d && nvst_fill != 4'hF) nvst_fill <= nvst_fill + 4'd1;
	if (!(ioctl_download & nv_io) && nvst_dl_d && nvst_file != 4'hF) nvst_file <= nvst_file + 4'd1;
	if (nv_zero && nvst_zero != 4'hF) nvst_zero <= nvst_zero + 4'd1;
	if (!nv_saving && nvst_save_d) nvst_save <= nvst_save + 16'd1;
end

// OSD Diagnostic overlay: Board (this panel), or the Trackball or Analog
// page (below).
wire ov_pix, ov_box, cp_pix, cp_box;
wire ov_on = (status[65:64] == 2'd1);
wire cp_on = status[65];

it8_dbg_text #(
	.N_ROWS (16),
	.BOX_X  (8),
	.BOX_Y  (8),
	.LABELS ("BLD PC  FRM IRQSBLITWAITSND SPC SDRFSUMWSUMRLOADPAGEJOY NVSTN104")
) dbg_text (
	.clk      (clk_sys),
	.vis_x    (vis_x),
	.vis_y    (vis_y),
	.vals     ({BLD_BCD[31:0],
	            is_cb ? {16'd0, cb_pc}                   : {8'd0, dbg_pc},
	            is_cb ? {16'd0, cb_frames}               : {16'd0, dbg_frames},
	            is_cb ? {cb_firq, cb_nmi}                : {dbg_irq3, dbg_irq2},
	            is_cb ? {cb_turbo, 16'd0}                : {dbg_blits, dbg_blit_late},
	            is_cb ? {cb_waits, 16'd0}                : {dbg_waits, dbg_vram_drop},
	            is_cb ? {cb_snd_cmds, cb_snd_last, 8'd0} : {dbg_snd_cmds, dbg_snd_last, 8'd0},
	            is_cb ? {16'd0, cb_snd_pc}               : {16'd0, dbg_snd_pc},
	            {sd_refresh, sd_forced},
	            sum_w,
	            sum_r,
	            {1'b0, board_sel, loaded, 7'd0, words},
	            is_cb ? {24'd0, cb_bank}                 : {24'd0, dbg_page},
	            {joystick_1[15:0], joystick_0[15:0]},
	            {nvst_fill, nvst_file, nvst_zero, 4'd0, nvst_save},
	            has_tb ? {16'd0, track_x, track_y}       : dbg_nv104}),
	.row0_msn (BLD_BCD[35:32]),
	.pix      (ov_pix),
	.in_box   (ov_box)
);

// Trackball and Analog pages (D-042, D-043): what the mouse, spinner,
// paddle and analog sticks send and what reaches the game's trackball
// counters. A page is written once a frame from the start of vertical
// blanking, and turned to read upright with the game: cp_rot is how the
// viewer sees the raster, turned anticlockwise for MAME ROT270 (as
// screen_rotate, or a monitor on its side), clockwise for ROT90, and the
// other way after Vertical Flip, which turns the picture under the overlay.
// OSD Clear control counters, or a reset, starts the counts again.
reg        cp_vb_d = 1'b0, cp_clr_d = 1'b0;
always @(posedge clk_sys) begin
	if (ce_pix) cp_vb_d <= core_vb;
	cp_clr_d <= status[66];
end
wire       cp_frame = ce_pix & core_vb & ~cp_vb_d;
wire [1:0] cp_rot   = ~is_vert ? 2'd0 : (~rot90 ^ flip180) ? 2'd1 : 2'd2;
wire [3:0] tb_div   = (status[16:15] == 2'd1) ? 4'd1 : (status[16:15] == 2'd2) ? 4'd4 : 4'd2;

it8_dbg_ctrl dbg_ctrl
(
	.clk       (clk_sys),
	.clear     (reset | (status[66] & ~cp_clr_d)),
	.frame     (cp_frame),
	.ps2_mouse (ps2_mouse),
	.spinner   (spinner_0),
	.paddle    (paddle_0),
	.ana_l0    (ana_l0),
	.ana_r0    (ana_r0),
	.ana_l1    (ana_l1),
	.ana_r1    (ana_r1),
	.track_x   (track_x),
	.track_y   (track_y),
	.drop_x    (track_drop_x),
	.drop_y    (track_drop_y),
	.div       (tb_div),
	.side      ({1'b0, status[20:19]} + 3'd1),
	.ce        (ce_pix),
	.de        (~core_hb & ~core_vb),
	.vis_x     (vis_x),
	.vis_y     (vis_y),
	.rot       (cp_rot),
	.page      (status[64]),
	.pix       (cp_pix),
	.in_box    (cp_box)
);

assign ov_hit = (ov_on & ov_pix) | (cp_on & cp_pix);
assign ov_blk = (ov_on & ov_box) | (cp_on & cp_box);
`else
assign ov_hit = 1'b0;
assign ov_blk = 1'b0;
`endif

///////////////////////   VIDEO OUTPUT (clk_vid, 96 MHz)   ///////

// Bring the pixel stream across. It changes only on ce_pix, a 48 MHz clock
// after the colour, so sampling on its rising edge sees stable data.
reg        vce_s, vce_d, ce_vid;
reg  [7:0] c_r, c_g, c_b;
reg        v_hs, v_vs, v_hb, v_vb, v_ovh, v_ovb;

always @(posedge clk_vid) begin
	vce_s  <= ce_pix;
	vce_d  <= vce_s;
	ce_vid <= vce_s & ~vce_d;
	if (vce_s & ~vce_d) begin
		c_r   <= core_r;
		c_g   <= core_g;
		c_b   <= core_b;
		v_hs  <= core_hs;
		v_vs  <= core_vs;
		v_hb  <= core_hb;
		v_vb  <= core_vb;
		v_ovh <= ov_hit;
		v_ovb <= ov_blk;
	end
end

// Vertical Flip (D-031). These boards cannot turn their own picture, and the
// games redraw moving objects as the beam passes, so the picture is turned
// through a frame buffer in DDRAM: each frame shows the previous one turned
// 180 degrees, on every output, with the board's own timing. The DDRAM port
// is screen_rotate's otherwise (Horizontal); it changes hands only when
// it8_flip180 has no transfer under way.
reg  flip_own = 1'b0;
reg  flip_rst;
wire flip_idle;
wire [23:0] f_rgb;

always @(posedge clk_vid) begin
	flip_rst <= reset;
	if (flip180)        flip_own <= 1'b1;
	else if (flip_idle) flip_own <= 1'b0;
end

wire        fb_rd, fb_we;
wire  [7:0] fb_burstcnt, fb_be;
wire [28:0] fb_addr;
wire [63:0] fb_din;

it8_flip180 flip_fb
(
	.clk            (clk_vid),
	.reset          (flip_rst),
	.enable         (flip180 & flip_own),
	.flipping       (),
	.idle           (flip_idle),
	.ce             (ce_vid),
	.rgb_in         ({c_r, c_g, c_b}),
	.hb_in          (v_hb),
	.vb_in          (v_vb),
	.vs_in          (v_vs),
	.rgb_out        (f_rgb),
	.ddr_busy       (DDRAM_BUSY),
	.ddr_burstcnt   (fb_burstcnt),
	.ddr_addr       (fb_addr),
	.ddr_dout       (DDRAM_DOUT),
	.ddr_dout_ready (DDRAM_DOUT_READY),
	.ddr_rd         (fb_rd),
	.ddr_din        (fb_din),
	.ddr_be         (fb_be),
	.ddr_we         (fb_we),
	.dbg_late       ()
);

wire [7:0] v_r = v_ovh ? 8'hFF : v_ovb ? 8'h00 : f_rgb[23:16];
wire [7:0] v_g = v_ovh ? 8'hFF : v_ovb ? 8'h00 : f_rgb[15:8];
wire [7:0] v_b = v_ovh ? 8'hFF : v_ovb ? 8'h00 : f_rgb[7:0];

// Centred sync (D-035). The boards place their sync where the game programs
// the TMS34061, which left the picture up to 2 us left of centre and up to
// 4 lines off on a 15 kHz screen. New pulses of standard width are placed
// around the picture the board shows: the middle of the line 35.75 us after
// HSync, the middle of the frame 138 lines after VSync. The picture and the
// blanking (so HDMI and the OSD) are untouched; CRT Adjust works from here.
// it8_sync_center is below, after CRT Adjust's settings.
wire c_hs, c_vs, c_vb;

wire [7:0] av_r, av_g, av_b;
wire       av_hs, av_vs, av_de, av_ce;
wire [1:0] av_sl;

// WIDTH: the widest picture, Hot Shots Tennis's 416 dots (the scandoubler's
// line buffer).
arcade_video #(.WIDTH(416), .DW(24)) arcade_video
(
	.clk_video          (clk_vid),
	.ce_pix             (ce_vid),
	.RGB_in             ({v_r, v_g, v_b}),
	.HBlank             (v_hb),
	.VBlank             (v_vb),
	.HSync              (c_hs),
	.VSync              (c_vs),
	.CLK_VIDEO          (),
	.CE_PIXEL           (av_ce),
	.VGA_R              (av_r),
	.VGA_G              (av_g),
	.VGA_B              (av_b),
	.VGA_HS             (av_hs),
	.VGA_VS             (av_vs),
	.VGA_DE             (av_de),
	.VGA_SL             (av_sl),
	.fx                 (status[5:3]),
	.forced_scandoubler (forced_scandoubler),
	.gamma_bus          (gamma_bus)
);

// ---------------------------------------------------------------------------
// CRT Adjust (rmonic79), core-side. Active only without the scandoubler:
// its read rate assumes the native 15 kHz pixel clock. 12 clk_vid clocks per
// pixel = 48 quarter cycles (8 MHz dots); each H-Size step is 1/48 (about
// 2%). The 6809 board's 6 MHz dots (dot6: every 6809 game but the 2 page
// large ones, which run at 8 MHz) are 16 clocks, 64 quarter cycles.

wire scandoubled = (status[5:3] != 3'd0) | forced_scandoubler;

reg              crt_on, autofill;
reg signed [4:0] hsize_s;
reg signed [5:0] vshift_s;
reg        [6:0] hpos_d;

always @(posedge clk_vid) begin
	if (ce_vid) begin
		crt_on   <= status[101] & ~scandoubled;
		autofill <= status[102];
		hsize_s  <= $signed(status[100:96]);
		vshift_s <= $signed(status[78:74]);
		hpos_d   <= status[85:79];
	end
end

// The centred sync (above). With CRT Adjust on, the picture leaves its line
// buffer a line late, so VSync follows it; the line buffer takes VBlank for
// each line at HSync, which now comes before the board's line starts, so it
// gets the VBlank of the line that HSync begins (c_vb).
it8_sync_center sync_center
(
	.clk     (clk_vid),
	.ce      (ce_vid),
	.dot6    (dot6),
	.hs_in   (v_hs),
	.vs_in   (v_vs),
	.hb_in   (v_hb),
	.vb_in   (v_vb),
	.vlate   (crt_on),
	.hs_out  (c_hs),
	.vs_out  (c_vs),
	.vb_out  (c_vb),
	.centred (),
	.pic_dots(pic_dots)
);

wire signed [8:0] hpos_usr = (hpos_d <= 7'd48) ? $signed({2'b00, hpos_d})
                                               : $signed({2'b00, hpos_d}) - 9'sd97;

// Auto-Width (D-037; OSD "CRT Auto-Fill" until build 018): the H-Size that
// makes the picture 48.75 us wide, about 93 % of a broadcast line
// (52.66 us, SMPTE's safe action area), so on a screen with ordinary
// overscan it reaches the edges without widening the games far beyond the
// shape their height allows. The picture is pic_dots
// wide and each of its dots lasts (base + H-Size) / 384 us (base 48 at
// 8 MHz, 64 at 6 MHz), so the read period that fills is
// 48.75 x 384 / pic_dots = 18720 / pic_dots, rounded: a restoring division,
// one quotient bit a clock, run over and over. The OSD's H-Size then trims
// from there. Capcom Bowling and Ninja Clowns come out at +4, Strata Bowling
// and the golf games at +9 (build 015's 50.5 us gave +6 and +12).
wire [10:0] pic_dots;
wire  [7:0] rd_base = dot6 ? 8'd64 : 8'd48;

reg   [3:0] dv_n = 4'd0;              // 0: load, 1-15: quotient bits 14..0
reg  [14:0] dv_num = 15'd0, dv_q = 15'd0;
reg  [10:0] dv_den = 11'd0, dv_rem = 11'd0;
reg   [7:0] fill_per = 8'd0;          // read period that fills; 0 unknown

wire [11:0] dv_try = {dv_rem, dv_num[14]};
wire        dv_bit = dv_try >= {1'b0, dv_den};
wire [14:0] dv_qn  = {dv_q[13:0], dv_bit};

always @(posedge clk_vid) begin
	if (dv_n == 4'd0) begin
		dv_num <= 15'd18720 + {5'd0, pic_dots[10:1]};
		dv_den <= pic_dots;
		dv_rem <= 11'd0;
		dv_q   <= 15'd0;
		dv_n   <= 4'd1;
	end
	else begin
		dv_num <= {dv_num[13:0], 1'b0};
		dv_rem <= dv_bit ? 11'(dv_try - {1'b0, dv_den}) : dv_try[10:0];
		dv_q   <= dv_qn;
		dv_n   <= (dv_n == 4'd15) ? 4'd0 : dv_n + 4'd1;
		if (dv_n == 4'd15)
			fill_per <= (dv_den >= 11'd128 && dv_qn < 15'd256) ? dv_qn[7:0] : 8'd0;
	end
end

// The H-Size in use: Auto-Width's, if on, plus the OSD's, kept to -16..+31.
wire signed [8:0] h_fill = (autofill && fill_per != 8'd0)
                         ? $signed({1'b0, fill_per}) - $signed({1'b0, rd_base}) : 9'sd0;
wire signed [8:0] h_sum  = h_fill + {{4{hsize_s[4]}}, hsize_s};
reg  signed [6:0] h_eff = 7'sd0;
always @(posedge clk_vid)
	h_eff <= (h_sum < -9'sd16) ? -7'sd16 : (h_sum > 9'sd31) ? 7'sd31 : h_sum[6:0];

// H-Size about the middle of the screen (D-035). CRT Adjust stretches the
// line from HSync, which would carry the picture's middle, 35.75 us after
// the centred HSync (286 dots at 8 MHz, 215 at 6 MHz), right as it grows
// and its right edge past the next HSync. A content shift of
// -middle x H-Size / (base + H-Size) dots, added to H-Position, holds the
// middle in place. Indexed by H-Size + 16. One dot less again makes up for
// the dot CRT Adjust's read pipeline adds to the picture.
localparam [431:0] HMID8 = {   // H-Size +31 .. -16
	-9'sd112, -9'sd110, -9'sd108, -9'sd105, -9'sd103, -9'sd100,  -9'sd98,  -9'sd95,
	 -9'sd93,  -9'sd90,  -9'sd87,  -9'sd84,  -9'sd81,  -9'sd78,  -9'sd75,  -9'sd72,
	 -9'sd68,  -9'sd65,  -9'sd61,  -9'sd57,  -9'sd53,  -9'sd49,  -9'sd45,  -9'sd41,
	 -9'sd36,  -9'sd32,  -9'sd27,  -9'sd22,  -9'sd17,  -9'sd11,   -9'sd6,    9'sd0,
	   9'sd6,   9'sd12,   9'sd19,   9'sd26,   9'sd33,   9'sd41,   9'sd49,   9'sd57,
	  9'sd66,   9'sd75,   9'sd85,   9'sd95,  9'sd106,  9'sd118,  9'sd130,  9'sd143
};
localparam [431:0] HMID6 = {   // H-Size +31 .. -16
	 -9'sd70,  -9'sd69,  -9'sd67,  -9'sd65,  -9'sd64,  -9'sd62,  -9'sd60,  -9'sd59,
	 -9'sd57,  -9'sd55,  -9'sd53,  -9'sd51,  -9'sd49,  -9'sd47,  -9'sd45,  -9'sd43,
	 -9'sd41,  -9'sd39,  -9'sd36,  -9'sd34,  -9'sd32,  -9'sd29,  -9'sd27,  -9'sd24,
	 -9'sd21,  -9'sd18,  -9'sd16,  -9'sd13,  -9'sd10,   -9'sd7,   -9'sd3,    9'sd0,
	   9'sd3,    9'sd7,   9'sd11,   9'sd14,   9'sd18,   9'sd22,   9'sd26,   9'sd31,
	  9'sd35,   9'sd40,   9'sd45,   9'sd50,   9'sd55,   9'sd60,   9'sd66,   9'sd72
};

wire       [5:0] h_idx = 6'(h_eff + 7'sd16);
reg signed [8:0] hmid, hpos_off;
always @(posedge clk_vid) begin
	hmid     <= $signed(dot6 ? HMID6[h_idx * 9 +: 9] : HMID8[h_idx * 9 +: 9]);
	hpos_off <= hpos_usr + hmid - 9'sd1;
end

wire hs_ref;
reg  hs_ref_d;
always @(posedge clk_vid) hs_ref_d <= hs_ref;
wire hs_ref_rise = hs_ref & ~hs_ref_d;

wire [7:0] rd_period = rd_base + {h_eff[6], h_eff};
reg  [7:0] rd_acc;
wire       rd_tick = (rd_acc + 8'd4) >= rd_period;

always @(posedge clk_vid) begin
	if      (hs_ref_rise) rd_acc <= 8'd0;
	else if (rd_tick)     rd_acc <= rd_acc + 8'd4 - rd_period;
	else                  rd_acc <= rd_acc + 8'd4;
end

wire rd_ce = crt_on ? rd_tick : ce_vid;

wire [7:0] str_r, str_g, str_b;
wire       str_hs, str_vs, str_hb, str_vb;

crt_adjust #(
	.VTOTAL    (263),
	.HTOTAL    (510),
	.HPOS_MODE (1)
) crt_adjust (
	.clk        (clk_vid),
	.pxl_cen    (ce_vid),
	.pxl2_cen   (rd_ce),
	.active     (crt_on),
	.hsize      (hsize_s),
	.hoffset    (hpos_off),
	.voffset    (vshift_s),
	.r_in       (v_r),
	.g_in       (v_g),
	.b_in       (v_b),
	.hs_in      (c_hs),
	.vs_in      (c_vs),
	.hb_in      (v_hb | v_vb),
	.vb_in      (c_vb),
	.r_out      (str_r),
	.g_out      (str_g),
	.b_out      (str_b),
	.hs_out     (str_hs),
	.vs_out     (str_vs),
	.hb_out     (str_hb),
	.vb_out     (str_vb),
	.hs_ref_out (hs_ref)
);

// The DE window for the OSD and HDMI while CRT Adjust is on: from whichever
// of the native and the adjusted active areas starts first to whichever ends
// last, so it holds the whole picture when H-Position or H-Size moves it
// either way, and the OSD moves at most half as far. VBlank is taken at the
// end of each line, so the native area runs one line late like the module's
// output.
reg  hs_d1, vb_prev, vblank_1l, de_osd;
wire line_tick     = ce_vid & c_hs & ~hs_d1;
always @(posedge clk_vid) begin
	if (ce_vid) begin
		hs_d1   <= c_hs;
		vb_prev <= v_vb;
	end
	if (line_tick) vblank_1l <= vb_prev;
end
wire native_active = ~(v_hb | vblank_1l);
wire str_active    = ~str_hb;
always @(posedge clk_vid) de_osd <= native_active | str_active;

assign CLK_VIDEO = clk_vid;
assign CE_PIXEL  = crt_on ? rd_ce  : av_ce;
assign VGA_R     = crt_on ? str_r  : av_r;
assign VGA_G     = crt_on ? str_g  : av_g;
assign VGA_B     = crt_on ? str_b  : av_b;
assign VGA_HS    = crt_on ? str_hs : av_hs;
assign VGA_VS    = crt_on ? str_vs : av_vs;
assign VGA_SL    = crt_on ? 2'd0   : av_sl;

wire [1:0] ar = status[122:121];

// Bowling games are vertical (MAME ROT270): screen_rotate turns the picture
// 90 degrees anticlockwise into the DDRAM frame buffer for a horizontal
// screen; the ROT90 games (Hot Shots Tennis, Peggle, Poker Dice) clockwise.
// Orientation "Vertical" leaves it as the board makes it, for a rotated
// monitor; "Vertical Flip" turns it 180 degrees through it8_flip180 (on
// every output), for a monitor rotated the other way. Ninja Clowns is never
// rotated; a 6809 game is when its board bytes say it is vertical.
wire no_rotate = ~is_vert | (status[18:17] != 2'd0);

wire        sr_we, sr_rd;
wire  [7:0] sr_burstcnt, sr_be;
wire [28:0] sr_addr;
wire [63:0] sr_din;

screen_rotate screen_rotate
(
	.CLK_VIDEO      (clk_vid),
	.CE_PIXEL       (av_ce),
	.VGA_R          (av_r),
	.VGA_G          (av_g),
	.VGA_B          (av_b),
	.VGA_HS         (av_hs),
	.VGA_VS         (av_vs),
	.VGA_DE         (av_de),
	.rotate_ccw     (~rot90),
	.no_rotate      (no_rotate),
	.flip           (1'b0),
	.video_rotated  (video_rotated),
	.FB_EN          (FB_EN),
	.FB_FORMAT      (FB_FORMAT),
	.FB_WIDTH       (FB_WIDTH),
	.FB_HEIGHT      (FB_HEIGHT),
	.FB_BASE        (FB_BASE),
	.FB_STRIDE      (FB_STRIDE),
	.FB_VBL         (FB_VBL),
	.FB_LL          (FB_LL),
	.DDRAM_CLK      (),
	.DDRAM_BUSY     (DDRAM_BUSY),
	.DDRAM_BURSTCNT (sr_burstcnt),
	.DDRAM_ADDR     (sr_addr),
	.DDRAM_DIN      (sr_din),
	.DDRAM_BE       (sr_be),
	.DDRAM_WE       (sr_we),
	.DDRAM_RD       (sr_rd)
);

// One DDRAM port, both users on clk_vid.
assign DDRAM_CLK      = clk_vid;
assign DDRAM_BURSTCNT = flip_own ? fb_burstcnt : sr_burstcnt;
assign DDRAM_ADDR     = flip_own ? fb_addr     : sr_addr;
assign DDRAM_DIN      = flip_own ? fb_din      : sr_din;
assign DDRAM_BE       = flip_own ? fb_be       : sr_be;
assign DDRAM_WE       = flip_own ? fb_we       : sr_we;
assign DDRAM_RD       = flip_own ? fb_rd       : sr_rd;

assign FB_FORCE_BLANK = 1'b0;

// Original aspect: 4:3 as the board outputs it, 3:4 once rotated.
wire [11:0] ar_x = (!ar) ? (no_rotate ? 12'd4 : 12'd3) : (ar - 1'd1);
wire [11:0] ar_y = (!ar) ? (no_rotate ? 12'd3 : 12'd4) : 12'd0;

video_freak video_freak
(
	.CLK_VIDEO   (clk_vid),
	.CE_PIXEL    (CE_PIXEL),
	.VGA_VS      (VGA_VS),
	.HDMI_WIDTH  (HDMI_WIDTH),
	.HDMI_HEIGHT (HDMI_HEIGHT),
	.VGA_DE      (VGA_DE),
	.VIDEO_ARX   (VIDEO_ARX),
	.VIDEO_ARY   (VIDEO_ARY),
	.VGA_DE_IN   (crt_on ? de_osd : av_de),
	.ARX         (ar_x),
	.ARY         (ar_y),
	.CROP_SIZE   (12'd0),
	.CROP_OFF    (5'd0),
	.SCALE       (status[12:10])
);

///////////////////////   LED   //////////////////////////////////

assign LED_USER = ioctl_download;

endmodule
