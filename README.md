# Incredible Technologies 8-bit hardware for MiSTer FPGA

A work-in-progress FPGA core for Incredible Technologies' (Strata) **8-bit
blitter** arcade hardware, for the [MiSTer](https://github.com/MiSTer-devel)
platform. It is built on `Template_MiSTer` with rmonic79's CRT Adjust built
in. **Ninja Clowns** (1991) boots and is fully playable. Capcom Bowling,
Coors Light Bowling and Bowl-O-Rama, on IT's earlier bowling board, are
playable with sound too, and so is **Strata Bowling** (1990), the first
game on the 6809 blitter board.

> **This core was made with AI.** The RTL and documentation were written in
> collaboration with an AI assistant (Claude, by Anthropic).
> It worked from MAME's source and from a disassembly of the game's own
> program ROMs.  This is disclosed here
> so you can make your decision to use this core accordingly.

## Games

[System 16](https://www.system16.com/hardware.php?id=805) lists seventeen
games on Incredible Technologies' 8-bit hardware. This core implements three
of the boards: the 68000 board, which only Ninja Clowns uses, the earlier
bowling board ¹, and the 6809 blitter board ², so far for Strata Bowling.
The other 6809 games need their own controls and, for most, other screen
layouts; Dyno Bop, Slick Shot and Super Strike Bowling also need the Z80
ball-sensor board.

| Game | Year | Main CPU | Status |
|---|---|---|---|
| Arlington Horse Racing | 1991 | 6809 | Not started |
| **Bowl-O-Rama** | 1991 | 6809 ¹ | **Playable, with sound** |
| **Capcom Bowling** (sets 1-4), **Coors Light Bowling** | 1988-89 | 6809 ¹ | **Playable, with sound** |
| Dyno Bop | 1990 | 6809, Z80 ball sensors | Not started |
| Golden Par Golf | 1992 | 6809 | Not started |
| Golden Tee Golf | 1990 | 6809 | Not started |
| Golden Tee Golf II | 1992 | 6809 | Not started |
| Hot Shots Tennis | 1990 | 6809 | Not started |
| Neck'N'Neck | 1992 | 6809 | Not started |
| **Ninja Clowns** | 1991 | 68000 | **Fully playable, with sound** |
| Peggle | 1991 | 6809 | Not started |
| Poker Dice | 1991 | 6809 | Not started |
| Rim Rockin' Basketball | 1991 | 6809 | Not started |
| Slick Shot | 1990 | 6809, Z80 ball sensors | Not started |
| **Strata Bowling** (V3, V1) | 1990 | 6809 ² | **Playable, with sound** |
| Super Strike Bowling | 1990 | 6809, Z80 ball sensors | Not started |
| Wheel Of Fortune | 1989 | 6809 | Not started |

¹ The earlier IT bowling board (MAME's `capbowl` driver): TMS34061 video
with a 16-colour palette on every line but no ITV4400 blitter, a trackball,
a vertical monitor, and a 6809 sound CPU with a YM2203 and a DAC.
Bowl-O-Rama adds a turbo board that reads its graphics from a ROM. The other
games are in MAME's `itech8` driver.

² The 6809 blitter board (MAME's `itech8` driver): the same TMS34061,
ITV4400 blitter and RAMDAC as Ninja Clowns with a 6809 main CPU, and a 6809
sound CPU with a YM2203 and an OKI M6295. Strata Bowling shows two layers,
an 8-bit background and a 16-colour foreground, on a vertical monitor, and
plays with a trackball.

## Progress

```
Ninja Clowns board    [##########]  10/10 sections working on hardware
Bowling board         [########--]   8/10 sections confirmed on hardware
6809 blitter board    [########--]   8/10 sections confirmed on hardware
Games                 [##--------]   4/17 playable
```

The Ninja Clowns board's ten sections are the 68000 and memory map, SDRAM
and ROM loader, TMS34061, VRAM, blitter, RAMDAC, sound board, controls,
NVRAM, and the MiSTer video path. The bowling board's are the main 6809 and
memory map, SDRAM and ROM loader, TMS34061, VRAM and line palettes, turbo
board, sound board, trackball and controls, NVRAM, watchdog, and the
rotated video path. The 6809 blitter board's are the main 6809 and memory
map, SDRAM and ROM loader, TMS34061, the two-layer display, blitter, RAMDAC,
sound board, trackball and controls, NVRAM, and the rotated video path; its
video section, RAMDAC, NVRAM and sound CPU are the Ninja Clowns board's.
On the bowling board and the 6809 blitter board, NVRAM save and reload and
the rotated picture are the two sections not yet confirmed. Design choices
and their reasons are in `DECISIONS.md`.

## At a glance

| | Ninja Clowns board | Bowling board | 6809 blitter board (Strata Bowling) |
|---|---|---|---|
| Board | IT 8-bit, 68000 variant: lower board P/N 1029 REV3A and YM3812 sound board P/N 1038 REV2 | IT bowling board (1988); Bowl-O-Rama adds a turbo board | IT 8-bit, 6809 variant, Strata Bowling style (single board) |
| Main CPU | 68000 @ 12 MHz | 6809 @ 2 MHz | 6809 @ 2 MHz |
| Sound | 6809 @ 2 MHz, YM3812, OKI M6295, 6522 VIA | 6809 @ 2 MHz, YM2203, DAC | 6809 @ 2 MHz, YM2203, OKI M6295 |
| Video | TMS34061 and ITV4400 blitter, two 512 × 256 VRAM pages, MS176 RAMDAC (256 colours) | TMS34061, 64 KB VRAM, 16 colours per line from 4096 | TMS34061 and ITV4400 blitter, a 256 × 256 8-bit background and a 4-bit foreground, 6-bit RAMDAC (256 colours) |
| Display | 362 × 240, 15.686 kHz, 59.64 Hz | 360 × 245 (Bowl-O-Rama 240), vertical, 15.81 kHz, about 60 Hz | 256 × 240, vertical, 15.71 kHz, 59.7 Hz |
| Controls | 8-way stick, 3 buttons | trackball (mouse or stick), 2 hook buttons | trackball (mouse or stick), 2 hook buttons |
| NVRAM | 16 KB | 2 KB | 8 KB |

All use 2 MB of SDRAM or less (any MiSTer SDRAM module) and save NVRAM to
the SD card. CRT Adjust (H-Size, H-Position, V-Shift) works on the analog
output at 15 kHz. The bowling games are turned for a horizontal screen
through MiSTer's frame buffer, or left vertical for a rotated monitor.

## Using the core

ROMs are not included. Copy:

* the MRAs from `mra/` to `_Arcade/`
* `Arcade-ITech8.rbf` to `_Arcade/cores/`
* the MAME ROM sets to `games/mame/`: `ninclown.zip`; `capbowl.zip` (with
  `capbowl2.zip`-`capbowl4.zip` and `clbowl.zip`, or one merged
  `capbowl.zip`); `bowlrama.zip`; `stratab.zip` (with `stratab1.zip` for
  V1, or one merged `stratab.zip`)

Keep only one ITech8 core in `_Arcade/cores/`: MiSTer loads the matching file
whose name sorts last.

**Ninja Clowns controls:** stick, Punch (A), Kick (B), Throw (X), Start,
Coin (R), Service (L), the same for both players.

**Bowling controls** (all the bowling games): the trackball is the mouse,
or the stick; Hook Left (A), Hook Right (B), Start, Coin (R). Capcom
Bowling and Bowl-O-Rama: hold Service (L, or OSD Service Mode) on the high
score screen for the setup menu. Strata Bowling: roll the trackball to
pick a game (Strata Bowling, Flash, Strike or Die), then Start.

**OSD:** aspect ratio, scandoubler effects, scaling, CRT Adjust, Service
Mode and Reset; Ninja Clowns and Strata Bowling add the audio mix (FM + PCM,
FM only, PCM only); the bowling games add Orientation (Horizontal: turned
for a normal screen; Vertical: for a rotated monitor) and Trackball Speed.

**NVRAM** (settings, audits and high scores) is saved when the OSD opens, to
`config/nvram/<game name>.nvm`. Delete that file to return the game to its
factory settings.

## Credits and references

This core is a reimplementation. It would not have been possible without:

**[MAME](https://www.mamedev.org/)**, the reference for essentially all
hardware behaviour:

| File | Author | Used for |
|---|---|---|
| `itech8.cpp`, `itech8.h` | Aaron Giles | memory map, machine configuration, interrupts, input ports, sound board map |
| `itech8_v.cpp` | Aaron Giles | blitter, page select, TMS34061 wiring, the 2-page-large and two-layer displays |
| `tms34061.cpp` | Zsolt Vasvari, Aaron Giles | TMS34061 registers, XY addressing, shift-register transfers |
| `tlc34076.cpp` | Philip Bennett | RAMDAC register protocol |
| `6522via.cpp` | Peter Trauner, Mathis Rosenhauer | 6522 timers and interrupts |
| `gen_latch.cpp` | Miodrag Milanovic | sound command latch |
| `capbowl.cpp` | Zsolt Vasvari | bowling board: memory maps, row palettes, turbo board, trackball, watchdog |
| `ticket.cpp` | Aaron Giles | ticket dispenser sensor |

MAME is a reference for *behaviour*; no MAME code is compiled into this core.

**[System 16](https://www.system16.com/hardware.php?id=805)** for the
hardware family listing and the game list.

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
