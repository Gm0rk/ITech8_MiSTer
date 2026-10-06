//============================================================================
//  Incredible Technologies 8-bit hardware for MiSTer
//  it8_ports09.sv - input ports 40, 60 and 80 of the itech8 6809 boards
//
//  Active low except the sound board's feedback bit (special, port 40 bit 0
//  in every layout but Golden Par Golf's). Unused and unknown bits read 1,
//  DIP switches their MAME defaults.
//
//  layout 0, the games added before build 020, from p1/p2 (the Ninja
//  Clowns order the top level makes) and the board byte's bits:
//    MAME stratab and gtgt: port 40 service, cabinet (Upright), feedback;
//    port 60 coins, starts, both players' hooks (face buttons). gtg (joy09):
//    port 60's low five bits are the stick and the swing button, player 1's
//    and 2's together. gpgolf (gtg2): port 40 coins, service, cabinet
//    (Upright); port 60 start, stick, swing. gtg2 (gtg2 with tb09): port 40
//    as gpgolf; port 60 player 1's start and face buttons, port 80 player
//    2's.
//
//  Other layouts take each player's MiSTer joystick as it comes (j0-j2):
//  bits 3-0 up, down, left, right, then the buttons in the order the MRA
//  names them, listed here. Player 1's Coin is coin 1, player 2's coin 2;
//  any player's Service is the service switch.
//    1  Wheel Of Fortune   Button, Coin, Service (players 1-3: Red, Yellow,
//                          Blue); the dial on blitter register 13
//    3  Poker Dice         Play, Raise, Upper Left, Upper Right, Middle,
//                          Lower Left, Lower Right, Coin, Service
//    4  Hot Shots Tennis   Hard, Soft, Coin, Service (two players)
//    5  Arlington          Win, Place, Show, Collect, Start Race, Coin,
//                          Service
//    6  Peggle (stick)     Start, Coin, Service
//    7  Peggle (trackball) Start, Coin, Service; the dial on register 13
//    8  Neck-N-Neck        Horse 1-6, Start, Coin, Service
//  (2 is kept for Grudge Match, 9 for Rim Rockin' Basketball.)
//
//  Copyright (C) 2026 Gm0rk. GPL-2.0-or-later, see LICENSE.
//============================================================================

module it8_ports09
(
	input       [3:0] layout,
	input             joy09,          // layout 0: joystick and swing (gtg)
	input             gtg2,           // layout 0: Golden Par Golf's board
	input             tb09,           // layout 0: trackball

	input       [7:0] p1,             // layout 0, active high
	input       [7:0] p2,
	input             coin1,
	input             coin2,
	input             service,

	input      [15:0] j0,             // other layouts, active high
	input      [15:0] j1,
	input      [15:0] j2,

	input             test,           // OSD Service Mode
	input             special,        // sound board feedback

	output reg  [7:0] in40,
	output reg  [7:0] in60,
	output reg  [7:0] in80
);

// Stick bits of a MiSTer joystick.
`define UP(j)    j[3]
`define DOWN(j)  j[2]
`define LEFT(j)  j[1]
`define RIGHT(j) j[0]

// Layout 0
wire  [7:0] in40_hi = {~(service | test), 3'b111, 1'b1, 2'b11, special};
wire  [7:0] in40_g2 = {2'b11, 2'b11, ~coin2, ~coin1, ~(service | test), 1'b1};
wire  [7:0] in60_tb = ~{coin1, coin2, p1[1], p2[1], p1[7], p1[6], p2[7], p2[6]};
wire  [7:0] in60_js = ~{coin1, coin2, p1[1], p1[7] | p2[7], p1[4] | p2[4],
                        p1[5] | p2[5], p1[3] | p2[3], p1[2] | p2[2]};
wire  [7:0] in60_g2 = ~{p1[1], p1[2], p1[3], p1[4], p1[5], p1[7], 2'b00};
wire  [7:0] in60_gt = ~{p1[1], 4'b0000, p1[7], p1[6], 1'b0};
wire  [7:0] in80_gt = ~{p2[1], 4'b0000, p2[7], p2[6], 1'b0};

// Coin and service positions in the raw joysticks, by layout.
reg   [3:0] coin_b, svc_b;
always @(*) begin
	case (layout)
		4'd1, 4'd6, 4'd7: begin coin_b = 4'd5;  svc_b = 4'd6;  end
		4'd3, 4'd8:       begin coin_b = 4'd11; svc_b = 4'd12; end
		4'd4:             begin coin_b = 4'd6;  svc_b = 4'd7;  end
		4'd5:             begin coin_b = 4'd9;  svc_b = 4'd10; end
		default:          begin coin_b = 4'd15; svc_b = 4'd15; end
	endcase
end

wire c1  = j0[coin_b];
wire c2  = j1[coin_b];
wire svc = j0[svc_b] | j1[svc_b] | j2[svc_b] | test;

always @(*) begin
	in80 = 8'hFF;
	case (layout)
		// Wheel Of Fortune (MAME wfortune): port 40 cabinet bit 3 (Upright);
		// port 60 bit 3 Blue, 4 Yellow, 5 Red, 6 coin 1, 7 coin 2.
		4'd1: begin
			in40 = {~svc, 3'b111, 1'b1, 2'b11, special};
			in60 = {~c2, ~c1, ~j0[4], ~j1[4], ~j2[4], 3'b111};
		end

		// Poker Dice (MAME pokrdice): port 40 bit 1 Lower Right, 3 cabinet
		// (Upright), 4 a switch (MAME default on); port 60 bit 0 Upper
		// Right, 1 coin 2, 2 Middle, 3 Lower Left, 4 Raise, 5 Upper Left,
		// 6 Play, 7 coin 1.
		4'd3: begin
			in40 = {~svc, 2'b11, 1'b1, 1'b1, 1'b1, ~j0[10], special};
			in60 = {~c1, ~j0[4], ~j0[6], ~j0[5], ~j0[9], ~j0[8], ~c2, ~j0[7]};
		end

		// Hot Shots Tennis (MAME hstennis): port 40 bit 3 cabinet
		// (Upright), 4 a switch (default on); port 60 player 1, port 80
		// player 2: bit 1 Soft, 2 right, 3 left, 4 down, 5 up, 6 Hard,
		// 7 the coin (bit 0, coins 3 and 4, unused).
		4'd4: begin
			in40 = {~svc, 2'b11, 1'b1, 1'b1, 2'b11, special};
			in60 = {~c1, ~j0[4], ~`UP(j0), ~`DOWN(j0), ~`LEFT(j0), ~`RIGHT(j0), ~j0[5], 1'b1};
			in80 = {~c2, ~j1[4], ~`UP(j1), ~`DOWN(j1), ~`LEFT(j1), ~`RIGHT(j1), ~j1[5], 1'b1};
		end

		// Arlington Horse Racing (MAME arlingtn): port 40 bit 3 a switch
		// (default on); port 60 bit 2 Place, 3 Win, 4 down, 5 up, 7 coin 1;
		// port 80 bit 3 Show, 4 Start Race, 5 Collect, 7 coin 2.
		4'd5: begin
			in40 = {~svc, 3'b111, 1'b1, 2'b11, special};
			in60 = {~c1, 1'b1, ~`UP(j0), ~`DOWN(j0), ~j0[4], ~j0[5], 2'b11};
			in80 = {~c2, 1'b1, ~j0[7], ~j0[8], ~j0[6], 3'b111};
		end

		// Peggle (MAME peggle, pegglet): port 60 bit 2 right, 3 left (stick
		// set only), 6 Start, 7 coin 1; port 80 bit 7 coin 2.
		4'd6, 4'd7: begin
			in40 = {~svc, 6'h3F, special};
			in60 = (layout == 4'd6) ? {~c1, ~j0[4], 2'b11, ~`LEFT(j0), ~`RIGHT(j0), 2'b11}
			                        : {~c1, ~j0[4], 6'h3F};
			in80 = {~c2, 7'h7F};
		end

		// Neck-N-Neck (MAME neckneck): port 40 bit 3 a switch (default
		// off); port 60 bit 2 Horse 3, 3 Horse 2, 4 Start, 5 Horse 1, 7 coin
		// 1; port 80 bit 3 Horse 4, 4 Horse 6, 5 Horse 5, 7 coin 2.
		4'd8: begin
			in40 = {~svc, 3'b111, 1'b0, 2'b11, special};
			in60 = {~c1, 1'b1, ~j0[4], ~j0[10], ~j0[5], ~j0[6], 2'b11};
			in80 = {~c2, 1'b1, ~j0[8], ~j0[9], ~j0[7], 3'b111};
		end

		default: begin
			in40 = gtg2 ? in40_g2 : in40_hi;
			in60 = gtg2 ? (tb09 ? in60_gt : in60_g2) : joy09 ? in60_js : in60_tb;
			in80 = (gtg2 & tb09) ? in80_gt : 8'hFF;
		end
	endcase
end

`undef UP
`undef DOWN
`undef LEFT
`undef RIGHT

endmodule
