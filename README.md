# Incredible Technologies 8-bit hardware for MiSTer FPGA

A work-in-progress FPGA core for Incredible Technologies' (Strata) **8-bit
blitter** arcade hardware, for the [MiSTer](https://github.com/MiSTer-devel)
platform. It is built on `Template_MiSTer` with rmonic79's CRT Adjust built
in. **Ninja Clowns** (1991) boots and is playable.

> **This core was made with AI.** The RTL and documentation were written in
> collaboration with an AI assistant (Claude, by Anthropic).
> It worked from MAME's source and from a disassembly of the game's own
> program ROMs. Ninja Clowns has been tested and played on a DE10-Nano. This
> is disclosed here so you can make your decision to use this core
> accordingly.

## Games

[System 16](https://www.system16.com/hardware.php?id=805) lists seventeen
games on Incredible Technologies' 8-bit hardware. This core implements the
68000 board, which only Ninja Clowns uses; the other games run on 6809
boards, which are not started.

| Game | Year | Main CPU | Status |
|---|---|---|---|
| Arlington Horse Racing | 1991 | 6809 | Not started |
| Bowl-O-Rama | 1991 | 6809 ¹ | Not started |
| Capcom Bowling | 1988 | 6809 ¹ | Not started |
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
| Strata Bowling | 1990 | 6809 | Not started |
| Super Strike Bowling | 1990 | 6809, Z80 ball sensors | Not started |
| Wheel Of Fortune | 1989 | 6809 | Not started |

¹ The earlier IT board (MAME's `capbowl` driver): TMS34061 video but no
ITV4400 blitter, and a 6809 sound CPU with a YM2203 instead of the YM3812
and OKI M6295. The other games are in MAME's `itech8` driver.

## Progress

```
Ninja Clowns board  [##########]  10/10 sections working on hardware
Games               [#---------]  1/17 playable
```

The ten board sections are the 68000 and memory map, SDRAM and ROM loader,
TMS34061, VRAM, blitter, RAMDAC, sound board, controls, NVRAM, and the MiSTer
video path. Design choices and their reasons are in `DECISIONS.md`.

## At a glance

| | |
|---|---|
| Board | IT 8-bit, 68000 variant: lower board P/N 1029 REV3A and YM3812 sound board P/N 1038 REV2 ([System 16](https://www.system16.com/hardware.php?id=805&gid=2280#2280)) |
| Main CPU | 68000 @ 12 MHz |
| Sound | 6809 @ 2 MHz, YM3812, OKI M6295, 6522 VIA |
| Video | TMS34061 and ITV4400 blitter, two 512 × 256 VRAM pages, MS176 RAMDAC (256 colours) |
| Display | 362 × 240, 15.686 kHz, 59.64 Hz |
| Memory | 2 MB of SDRAM (any MiSTer SDRAM module); 16 KB NVRAM saved to the SD card |
| CRT Adjust | H-Size, H-Position and V-Shift on the analog output at 15 kHz |

## Using the core

ROMs are not included. Copy:

* `mra/Ninja Clowns (27 oct 91).mra` to `_Arcade/`
* `Arcade-ITech8.rbf` to `_Arcade/cores/`
* the MAME ROM set `ninclown.zip` to `games/mame/`

Keep only one ITech8 core in `_Arcade/cores/`: MiSTer loads the matching file
whose name sorts last.

**Controls:** stick, Punch (A), Kick (B), Throw (X), Start, Coin (R),
Service (L), the same for both players. **OSD:** aspect ratio, scandoubler
effects, scaling, CRT Adjust, audio mix (FM + PCM, FM only, PCM only),
Service Mode (opens the game's service menu) and Reset.

**NVRAM** (settings, audits and high scores) is saved when the OSD opens, to
`config/nvram/Ninja Clowns (27 oct 91).nvm`. Delete that file to return the
game to its factory settings.

## Credits and references

This core is a reimplementation. It would not have been possible without:

**[MAME](https://www.mamedev.org/)**, the reference for essentially all
hardware behaviour:

| File | Author | Used for |
|---|---|---|
| `itech8.cpp`, `itech8.h` | Aaron Giles | memory map, machine configuration, interrupts, input ports, sound board map |
| `itech8_v.cpp` | Aaron Giles | blitter, page select, TMS34061 wiring, the 2-page-large display |
| `tms34061.cpp` | Zsolt Vasvari, Aaron Giles | TMS34061 registers, XY addressing, shift-register transfers |
| `tlc34076.cpp` | Philip Bennett | RAMDAC register protocol |
| `6522via.cpp` | Peter Trauner, Mathis Rosenhauer | 6522 timers and interrupts |
| `gen_latch.cpp` | Miodrag Milanovic | sound command latch |

MAME is a reference for *behaviour*; no MAME code is compiled into this core.

**[System 16](https://www.system16.com/hardware.php?id=805)** for the
hardware family listing and the game list.

**[fx68k](https://github.com/ijor/fx68k)** by Jorge Cwik: the 68000, cycle
accurate.

**[mc6809](https://github.com/cavnex/mc6809)** by Greg Miller: the 6809, in
the synchronous version by Alexey Melnikov (**Sorgelig**) with the
reset-interrupt fix by **RndMnkIII**.

**[JTOPL and JT6295](https://github.com/jotego)** by Jose Tejada
(**jotego**): the YM3812 and the OKI M6295.

**[MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust)** by
Umberto Parisi (**rmonic79**): CRT geometry adjustment.

**[MiSTer](https://github.com/MiSTer-devel/Main_MiSTer)** and
[`Template_MiSTer`](https://github.com/MiSTer-devel/Template_MiSTer) by
Alexey Melnikov (**Sorgelig**), whose `sys/` provides the HPS interface,
video scaler, `arcade_video` and pin handling this core builds on.

## License

The core's own RTL is released under the GNU General Public License v2.0 or
later, as the MiSTer framework is. See `LICENSE`. fx68k, JTOPL, JT6295 and
CRT Adjust are GPL v3, so a built core, which contains them, is distributed
under GPL v3. The mc6809 core is under its BSD licence (`rtl/mc6809/`).
`sys/` and every third-party core keep their original licences and
authorship.

No ROM data is included or distributed.
