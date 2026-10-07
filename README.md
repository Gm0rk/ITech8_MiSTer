# Incredible Technologies 8-bit hardware for MiSTer FPGA

A work-in-progress FPGA core for Incredible Technologies' (Strata) **8-bit
blitter** arcade hardware, for the [MiSTer](https://github.com/MiSTer-devel)
platform. It is built on `Template_MiSTer` with rmonic79's CRT Adjust built
in. **Ninja Clowns** (1991) boots and is fully playable. Capcom Bowling,
Coors Light Bowling and Bowl-O-Rama, on IT's earlier bowling board, are
playable with sound too, and so is **Strata Bowling** (1990), the first
game on the 6809 blitter board. **Golden Tee Golf**, **Golden Tee Golf II**
and **Golden Par Golf**, on the same board, are not yet tested on hardware,
and neither are the newest: **Wheel Of Fortune**, **Poker Dice**, **Hot
Shots Tennis**, **Arlington Horse Racing**, **Peggle** and
**Neck-N-Neck**.

> **This core was made with AI.** The RTL and documentation were written in
> collaboration with an AI assistant (Claude, by Anthropic).
> It worked from MAME's source and from a disassembly of the game's own
> program ROMs.  This is disclosed here
> so you can make your decision to use this core accordingly.

## Games

<img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/itech8_Gameplay.png" width="800">

The table lists every game MAME runs on Incredible Technologies' 8-bit
hardware: the bowling games in its `capbowl` driver, the rest in its
`itech8` driver. This core implements three of the boards: the 68000
board, which only Ninja Clowns uses, the earlier bowling board ¹, and the
6809 blitter board ², so far for every planned game on it but two: Rim
Rockin' Basketball and Grudge Match, which come next. Three games are not
planned ³.

| Game | Year | Main CPU | Status |
|---|---|---|---|
| **Arlington Horse Racing** (v1.40-D, v1.21-D, v1.21-I) | 1991 | 6809 ² | **Added**, not yet tested on hardware |
| **Bowl-O-Rama** | 1991 | 6809 ¹ | **Playable, with sound** |
| **Capcom Bowling** (sets 1-4), **Coors Light Bowling** | 1988-89 | 6809 ¹ | **Playable, with sound** |
| Dyno Bop (v1.1) | 1990 | 6809, Z80 sensor board | Not planned ³ |
| **Golden Par Golf** (joystick v1.1, v1.0) | 1991-92 | 6809 ² | **Added**, not yet tested on hardware |
| **Golden Tee Golf** (joystick v3.3, v3.1; trackball v2.1, v2.0, v1.0) | 1989-90 | 6809 ² | **Added**, not yet tested on hardware |
| **Golden Tee Golf II** (trackball v2.2, v1.1; joystick v1.0) | 1989-92 | 6809 ² | **Added**, not yet tested on hardware |
| Grudge Match (Yankee Game Technology) | 1989 | 6809 | Planned (YM2608 sound board) |
| **Hot Shots Tennis** (v1.1, v1.0) | 1990 | 6809 ² | **Added**, not yet tested on hardware |
| **Neck-N-Neck** (v1.2) | 1992 | 6809 ² | **Added**, not yet tested on hardware |
| **Ninja Clowns** | 1991 | 68000 | **Playable, with sound** |
| **Peggle** (joystick, trackball) | 1991 | 6809 ² | **Added**, not yet tested on hardware |
| **Poker Dice** (v1.7) | 1991 | 6809 ² | **Added**, not yet tested on hardware |
| Rim Rockin' Basketball (v2.2, v2.0, v1.6, v1.5, v1.2) | 1991 | HD6309 | Planned (next) |
| Slick Shot (v2.2, v1.7, v1.6) | 1990 | 6809, Z80 sensor board | Not planned ³ |
| **Strata Bowling** (V3, V1) | 1990 | 6809 ² | **Playable, with sound** |
| Super Strike Bowling (v1) | 1990 | 6809, Z80 sensor board | Not planned ³ |
| **Wheel Of Fortune** (sets 1, 2) | 1989 | 6809 ² | **Added**, not yet tested on hardware |

¹ The earlier IT bowling board (MAME's `capbowl` driver): TMS34061 video
with a 16-colour palette on every line but no ITV4400 blitter, a trackball,
a vertical monitor, and a 6809 sound CPU with a YM2203 and a DAC.
Bowl-O-Rama adds a turbo board that reads its graphics from a ROM. The other
games are in MAME's `itech8` driver.

² The 6809 blitter board (MAME's `itech8` driver): the same TMS34061,
ITV4400 blitter and RAMDAC as Ninja Clowns with a 6809 main CPU, and a 6809
sound CPU with a YM2203 and an OKI M6295. Strata Bowling shows two layers,
an 8-bit background and a 16-colour foreground, on a vertical monitor, and
plays with a trackball. Golden Tee Golf and Golden Tee Golf II are the
same board on a horizontal monitor, with a stick and a Swing button or a
trackball; Golden Par Golf and Golden Tee Golf II v2.2 are IT's 1992 board,
with its I/O at other addresses and Ninja Clowns' YM3812 sound board.
Wheel Of Fortune is Strata Bowling's board with a dial. Hot Shots Tennis,
Arlington Horse Racing, Peggle and Neck-N-Neck show Ninja Clowns' screen
layout (two 512 × 256 pages of 4-bit pixels, 8 MHz dots, wider pictures)
and have a YM3812 sound board with a PIA; Poker Dice shows one 8-bit page.

³ Not planned for now: Dyno Bop, Slick Shot and Super Strike Bowling, and
the Strata Bowling v1 set built on Super Strike Bowling's board (MAME's
`stratabs`). Their cabinets use their own physical controls, which a
MiSTer setup is unlikely to reproduce well. MAME lists all three as
mechanical games.

## Progress

```
Ninja Clowns board    [##########]  10/10 sections working on hardware
Bowling board         [########--]   8/10 sections confirmed on hardware
6809 blitter board    [########--]   8/10 sections confirmed on hardware
Games                 [#########-]  13/15 added, 4 playable on hardware (3 not planned)
```

The Ninja Clowns board's ten sections are the 68000 and memory map, SDRAM
and ROM loader, TMS34061, VRAM, blitter, RAMDAC, sound board, controls,
NVRAM, and the MiSTer video path. The bowling board's are the main 6809 and
memory map, SDRAM and ROM loader, TMS34061, VRAM and line palettes, turbo
board, sound board, trackball and controls, NVRAM, watchdog, and the
rotated video path. The 6809 blitter board's are the main 6809 and memory
map, SDRAM and ROM loader, TMS34061, the display layouts, blitter, RAMDAC,
sound boards, trackball and controls, NVRAM, and the rotated video path; its
video section, RAMDAC, NVRAM and sound CPU are the Ninja Clowns board's.
On the bowling board and the 6809 blitter board, NVRAM save and reload and
the rotated picture are the two sections not yet confirmed. Design choices
and their reasons are in `DECISIONS.md`.

## At a glance

| | Ninja Clowns board | Bowling board | 6809 blitter board (Strata Bowling, golf and the rest) |
|---|---|---|---|
| Board | IT 8-bit, 68000 variant: lower board P/N 1029 REV3A and YM3812 sound board P/N 1038 REV2 | IT bowling board (1988); Bowl-O-Rama adds a turbo board | IT 8-bit, 6809 variant, Strata Bowling style (single board); Golden Par Golf and Golden Tee Golf II v2.2: the 1992 board P/N 1047 with the YM3812 sound board P/N 1038 |
| Main CPU | 68000 @ 12 MHz | 6809 @ 2 MHz | 6809 @ 2 MHz |
| Sound | 6809 @ 2 MHz, YM3812, OKI M6295, 6522 VIA | 6809 @ 2 MHz, YM2203, DAC | 6809 @ 2 MHz, YM2203, OKI M6295 (Golden Par Golf, Golden Tee Golf II v2.2: Ninja Clowns' sound board; Hot Shots Tennis, Arlington, Peggle, Neck-N-Neck: YM3812, OKI M6295, 6821 PIA) |
| Video | TMS34061 and ITV4400 blitter, two 512 × 256 VRAM pages, MS176 RAMDAC (256 colours) | TMS34061, 64 KB VRAM, 16 colours per line from 4096 | TMS34061 and ITV4400 blitter, 6-bit RAMDAC (256 colours); a 256 × 256 8-bit background and a 4-bit foreground, or Ninja Clowns' two pages (Hot Shots Tennis, Arlington, Peggle, Neck-N-Neck), or one 8-bit page (Poker Dice) |
| Display | 362 × 240, 15.686 kHz, 59.64 Hz | 360 × 245 (Bowl-O-Rama 240), vertical, 15.81 kHz, about 60 Hz | 256 × 240, 15.71 kHz, 59.7 Hz; 416 × 240 (Hot Shots Tennis, Peggle) or 392 × 240 (Arlington, Neck-N-Neck), 15.69 kHz, 59.65 Hz; vertical (Strata Bowling; Hot Shots Tennis, Peggle and Poker Dice turned the other way) or horizontal |
| Controls | 8-way stick, 3 buttons | trackball (mouse or stick), 2 hook buttons | trackball (mouse or stick) and 2 buttons; or 8-way stick and Swing (golf joystick sets); each other game its own (below) |
| NVRAM | 16 KB | 2 KB | 8 KB |

All use 2 MB of SDRAM or less (any MiSTer SDRAM module) and save NVRAM to
the SD card. The analog picture is centred on a standard 15 kHz screen in
every game, the vertical ones on a rotated monitor included: the sync
pulses are placed where such a screen expects them around the picture, so
it sits in the middle with equal margins. CRT Adjust (Auto-Width, H-Size,
H-Position, V-Shift) works from there, so H-Position and V-Shift at 0 are
the centre. **CRT Auto-Width** widens each game's picture to 48.75 µs, so
that on a screen with ordinary overscan it reaches close to the edges
without stretching the picture much wider than its height allows; H-Size
then trims it about the middle of the screen (each step about 2 %, about
1.6 % on the 6809 blitter board), for a screen with more or less overscan.
The height is the monitor's own (its vertical size): the games send 240 or
245 lines, so a screen set up for 224-line consoles cuts some at the top
and bottom, and V-Shift chooses which end loses more. The vertical games are turned for
a horizontal screen through MiSTer's frame buffer, or left vertical for a
rotated monitor.

## Using the core

ROMs are not included. Copy:

* the MRAs from `mra/` to `_Arcade/`, keeping the `_alternatives` folder:
  the root holds one MRA per game (MAME's parent set), and
  `_alternatives/_<game>/` holds the other versions and clones (Capcom
  Bowling sets 2-4 and Coors Light Bowling, Strata Bowling V1, the other
  Golden Tee Golf, Golden Tee Golf II and Golden Par Golf versions, Wheel
  Of Fortune set 2, Hot Shots Tennis v1.0, Arlington Horse Racing v1.21-D
  and v1.21-I, and the trackball Peggle)
* the newest `Arcade-ITech8_YYYYMMDD.rbf` from `releases/` to `_Arcade/cores/`
* the MAME ROM sets to `games/mame/`: `ninclown.zip`; `capbowl.zip` (with
  `capbowl2.zip`-`capbowl4.zip` and `clbowl.zip`, or one merged
  `capbowl.zip`); `bowlrama.zip`; `stratab.zip` (with `stratab1.zip` for
  V1, or one merged `stratab.zip`); `gtg.zip` (with `gtgj31.zip`,
  `gtgt21.zip`, `gtgt20.zip` and `gtgt10.zip`, or one merged `gtg.zip`);
  `gtg2.zip` (with `gtg2t.zip` and `gtg2j.zip`, or one merged `gtg2.zip`);
  `gpgolf.zip` (with `gpgolfa.zip` for v1.0, or one merged `gpgolf.zip`);
  `wfortune.zip` (with `wfortunea.zip`); `pokrdice.zip`; `hstennis.zip`
  (with `hstennis10.zip`); `arlingtn.zip` (with `arlingtna.zip` and
  `arlingtni.zip`); `peggle.zip` (with `pegglet.zip`); `neckneck.zip`.
  Merged sets work as well, each clone inside its parent's zip

Keep only one ITech8 core in `_Arcade/cores/`: MiSTer loads the matching file
whose name sorts last.

**Ninja Clowns controls:** stick, Punch (A), Kick (B), Throw (X), Start,
Coin (R), Service (L), the same for both players.

**Bowling controls** (all the bowling games): the trackball is the mouse,
or the stick; Hook Left (A), Hook Right (B), Start, Coin (R), Service (L,
or OSD Service Mode). The one Start button adds a player each time it is
pressed, up to four (Bowl-O-Rama five). The second controller's Coin is
the cabinet's second coin slot; Capcom Bowling, Coors Light Bowling and
Strata Bowling can price it separately. Strata Bowling: roll the
trackball to pick a game (Strata Bowling, Flash, Strike or Die), then
Start.

**Golf controls:** the joystick sets (Golden Tee Golf v3.3 and v3.1, Golden
Tee Golf II v1.0, Golden Par Golf) use the stick and Swing (A), Start, Coin
(R), Service (L): hold Swing for the backswing and let go for the forward
swing. The trackball sets (Golden Tee Golf v2.1, v2.0, v1.0, Golden Tee
Golf II v2.2 and v1.1) use the trackball (the mouse, or the stick), Face Left (A), Face Right (B), Start, Coin (R), Service (L), and OSD
Trackball Speed: pull the trackball back, then push it forward to swing.
In both, Start (the games call it Select) confirms the number of golfers,
one to four, and the course. Upright cabinet only.

**Other 6809 games' controls** (each MRA names the game's own buttons,
Coin and Service last; by default Coin is on R and Service on L, except in
Poker Dice and Neck-N-Neck, which use every other button: Coin on Select,
Service left for you to define or OSD Service Mode; the first controller's
Coin is coin slot 1, the second's slot 2):

* Wheel Of Fortune: the dial is the mouse's left-right movement or the
  stick (OSD Trackball Speed); Button on each of three controllers is
  the Red, Yellow and Blue player's button.
* Poker Dice: Play, Raise, and the five dice buttons Upper Left, Upper
  Right, Middle, Lower Left and Lower Right.
* Hot Shots Tennis: stick, Hard and Soft, for each of two players.
* Arlington Horse Racing: stick up and down, Win, Place, Show, Collect and
  Start Race.
* Peggle: the stick's left and right (joystick set) or the dial (trackball
  set: mouse left-right or the stick), and Start.
* Neck-N-Neck: Horse 1 to Horse 6 and Start.

**Setup menus**, as the operator manuals describe them:

* Capcom Bowling and Coors Light Bowling: hold Service for half a second
  in attract mode (not during a game). Roll the trackball to an item and
  press Start; in Adjustments, Hook Left and Hook Right lower and raise the
  value. Video Tests ends on an 8 × 8 grid, which fills the picture.
* Bowl-O-Rama: hold Service on the test screen after power-on, or in
  attract mode with no credits. Audits are at the top, adjustments below:
  roll the trackball to an item and press any button to change it.
* Strata Bowling: press Service at any time. Move the trackball up or down
  to an item and press Start; move it left or right to change a value.

**Trackball feel:** OSD Trackball Speed sets how many mouse counts make one
trackball count (Fast 1, Normal 2, Slow 4). Each game also has its own
setting in its setup menu, which changes how fast a roll sends the ball:
Capcom Bowling and Coors Light Bowling TRACKBALL TYPE, 0 to 4 (factory 3;
each step lower doubles the ball speed a roll gives); Bowl-O-Rama 2.0, 2.5
or 4.5 INCH TRACKBALL (a larger size is more sensitive); Strata Bowling
TRACKBALL SENSITIVITY, level 1 (least force) to level 5 (most force). With
a Taito Egret II Mini trackball, a tester found Capcom Bowling and Coors Light
Bowling best at Normal with TRACKBALL TYPE 2. Those two games take a
sideways roll at half the rate of a forward one, by design (the original
board and MAME do the same), and start the ball at the edge of the lane.
OSD Trackball Sideways (1x to 4x) multiplies the sideways counts only, for
a small trackball that needs several spins to bring the ball to the
middle; the forward roll is unchanged. It cannot go past the most the board
can read, about 28 counts a frame on each axis.

**Setting up a trackball, spinner or analog controller:** the debug core
(`Arcade-ITech8_debug`, started by the MRAs in `mra/debug/`) has OSD Debug
→ Diagnostic overlay → Trackball and → Analog, small pages over the
running game (upright on the vertical games too). Trackball shows what
MiSTer receives from the mouse (where most USB trackballs and spinners
arrive) and its spinner input, and what reaches the game's trackball:
counts in the last frame, the most in one frame, the counts in one roll of
the ball, reports a second, and the counts dropped above what the game
can read. Analog shows the paddle and the analog sticks of controllers 1
and 2 with each one's range. Debug → Clear control counters starts them
again.

**OSD:** aspect ratio, scandoubler effects, scaling, CRT Adjust, Service
Mode and Reset; the games on the IT blitter boards add the audio mix (FM
+ PCM, FM only, PCM only); the vertical games add Orientation
(Horizontal: turned for a normal screen; Vertical: for a monitor turned as
in the original cabinets, with its left edge at the bottom, or for Hot
Shots Tennis, Peggle and Poker Dice at the top; Vertical Flip: for a
monitor turned the other way, on every output, shown one frame later); the
trackball games add Trackball Speed and Trackball Sideways, the dial games
Trackball Speed.

**NVRAM** (settings, audits and high scores) is saved once each time the OSD
opens, to `config/nvram/<game name>.nvm`; changing OSD options does not save
it again. Delete that file to return the game to its factory settings.

## Credits and references

This core is a reimplementation. It would not have been possible without:

**[MAME](https://www.mamedev.org/)**, the reference for essentially all
hardware behaviour:

| File | Author | Used for |
|---|---|---|
| `itech8.cpp`, `itech8.h` | Aaron Giles | memory map, machine configuration, interrupts, input ports, sound board map |
| `itech8_v.cpp` | Aaron Giles | blitter, page select, TMS34061 wiring, the 2-page-large, 2-page and two-layer displays |
| `tms34061.cpp` | Zsolt Vasvari, Aaron Giles | TMS34061 registers, XY addressing, shift-register transfers |
| `tlc34076.cpp` | Philip Bennett | RAMDAC register protocol |
| `6522via.cpp` | Peter Trauner, Mathis Rosenhauer | 6522 timers and interrupts |
| `6821pia.cpp` | Aaron Giles, Nathan Woods | 6821 registers (sound board of Hot Shots Tennis style) |
| `gen_latch.cpp` | Miodrag Milanovic | sound command latch |
| `capbowl.cpp` | Zsolt Vasvari | bowling board: memory maps, row palettes, turbo board, trackball, watchdog |
| `ticket.cpp` | Aaron Giles | ticket dispenser sensor |

MAME is a reference for *behaviour*; no MAME code is compiled into this core.

**[System 16](https://www.system16.com/hardware.php?id=805)** for the
hardware family listing.

**[fx68k](https://github.com/ijor/fx68k)** by Jorge Cwik: the 68000, cycle
accurate.

**[mc6809](https://github.com/cavnex/mc6809)** by Greg Miller: the 6809, in
the synchronous version by Alexey Melnikov (**Sorgelig**) with the
reset-interrupt fix by **RndMnkIII**.

**[JTOPL, JT6295 and JT12](https://github.com/jotego)** by Jose Tejada
(**jotego**): the YM3812, the OKI M6295, and the YM2203 (JT03, with JT49 for
its SSG).

**[MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust)** by
Umberto Parisi (**rmonic79**): CRT geometry adjustment.

**[MiSTer](https://github.com/MiSTer-devel/Main_MiSTer)** and
[`Template_MiSTer`](https://github.com/MiSTer-devel/Template_MiSTer) by
Alexey Melnikov (**Sorgelig**), whose `sys/` provides the HPS interface,
video scaler, `arcade_video` and pin handling this core builds on.

## License

The core's own RTL is released under the GNU General Public License v2.0 or
later, as the MiSTer framework is. See `LICENSE`. fx68k, JTOPL, JT6295,
JT12/JT49 and CRT Adjust are GPL v3, so a built core, which contains them,
is distributed under GPL v3. The mc6809 core is under its BSD licence (`rtl/mc6809/`).
`sys/` and every third-party core keep their original licences and
authorship.

No ROM data is included or distributed.
