# Incredible Technologies 8-bit hardware for MiSTer FPGA

A work-in-progress FPGA implementation of Incredible Technologies' (Strata)
**8-bit blitter** arcade hardware for the
[MiSTer](https://github.com/MiSTer-devel) platform. The first game is
**Ninja Clowns** (1991), which runs on the 68000 variant of the board.

## Contents

- [The hardware](#the-hardware)
- [Status](#status)
  - [Measured in simulation](#measured-in-simulation)
  - [Where the core deliberately differs from MAME](#where-the-core-deliberately-differs-from-mame)
- [Using the core](#using-the-core)
  - [Controls](#controls)
  - [OSD menu](#osd-menu)
  - [CRT Adjust](#crt-adjust)
- [Building](#building)
  - [The debug overlay](#the-debug-overlay)
- [Repository layout](#repository-layout)
- [How it is verified](#how-it-is-verified)
- [Credits and references](#credits-and-references)
- [License](#license)

**Ninja Clowns runs in simulation.** On the real ROMs, the RTL goes from
power-on through the game's own self-test ("SYSTEM INITIALIZED"), the title
screen and its palette fade, and the attract-mode demo. With coins and
inputs it goes into gameplay. All of this runs through the SDRAM controller
and a cycle model of the SDRAM chip, with music and speech on the audio
output.

**On a DE10-Nano (build 001)** the core compiled, loaded, ran the game's
self-test and showed "SYSTEM STATUS OK", then went black. In simulation
exactly that sequence comes from the game accepting an NVRAM image with
zeroed settings and trapping on a divide by zero (D-017); the hardware has
not confirmed it yet. Build 003 makes NVRAM start as FF in every case,
refuses an all-zero file, and adds two overlay rows that show which NVRAM
path was taken. **If you ran build 001, delete
`config/nvram/Ninja Clowns (27 oct 91).nvm` from the SD card first.**
See [Status](#status).

> **This core was made with AI.** The RTL, testbenches and documentation
> were written in collaboration with an AI assistant (Claude, by Anthropic).
> It worked from MAME's source and from a disassembly of the game's own
> program ROMs. Every block was checked in simulation on the real ROMs.
> Hardware testing has only just started (one run of build 001, see
> above). This is disclosed here so you can make your decision to use this
> core accordingly.

---

## The hardware

The IT 8-bit boards pair a TMS34061 video controller with IT's own ITV4400
blitter, which draws raw or run-length-encoded graphics into VRAM frame
buffers. MAME's `itech8` driver covers sixteen games on eight board
variants: Arlington Horse Racing, Dyno Bop, Golden Par Golf, Golden Tee Golf
I and II, Grudge Match, Hot Shots Tennis, Neck-N-Neck, Ninja Clowns, Peggle,
Poker Dice, Rim Rockin' Basketball, Slick Shot, Strata Bowling, Super Strike
Bowling and Wheel of Fortune. All but Ninja Clowns use a 6809 main CPU.

Board photographs and the family listing are at
[System 16 — Incredible Technologies 8-bit Hardware](https://www.system16.com/hardware.php?id=805&gid=2280#2280).

This core implements the **Ninja Clowns** board set: lower board P/N 1029
REV3A and the external YM3812 sound board P/N 1038 REV2.

| | |
|---|---|
| Main CPU | Motorola 68000 (MC68000P12) @ 12 MHz |
| Sound | 68B09 @ 2 MHz (8 MHz crystal / 4), YM3812 @ 4 MHz, OKI M6295 @ 1 MHz (pin 7 high: 7.576 kHz), 6522 VIA |
| Video controller | TI TMS34061 |
| Blitter | ITV4400: raw or RLE source, X/Y flip, nibble shift, 4 bpp transparency, clipping |
| Frame buffer | 8 × MT42C4064 VRAM: two 512 × 256 pages; each pixel is a 4-bit VRAM nibble plus a 4-bit colour latched on write |
| Palette | MS176 RAMDAC, 256 colours, 6 bits per gun |
| Display | 362 × 240 visible in a 510 × 263 raster, 8 MHz dot clock: 15.686 kHz, 59.64 Hz |
| RAM | 16 KB battery-backed (68000), 2 KB (6809) |
| ROM | 256 KB program, 1.5 MB graphics, 256 KB samples, 32 KB sound program |

The raster comes from the values the game itself writes to the TMS34061.
The 8 MHz dot clock is inferred from the board's crystals and MAME's screen,
not measured on a board.

---

## Status

| Area | State |
|---|---|
| **Ninja Clowns** | **Runs in simulation**: self-test, title, attract demo and gameplay. **Hardware, build 001:** self-test and status screen, then black (NVRAM, D-017). Build 003 not yet run on hardware. |
| 68000 and memory map | **Working in simulation.** All of MAME's `ninclown_map`, including the ROM check over the empty PROM sockets and the ROM vectors over RAM. |
| SDRAM | **Working in simulation.** Zero wait states on every 68000 ROM read, zero SDRAM protocol errors, zero forced refreshes. The loader's read-back sum matches what was written (`0E087110`). |
| TMS34061 | **Working in simulation.** Registers, raster, XY addressing, direct access, and the shift-register row copy the game uses to clear the screen. |
| Blitter | **Working in simulation.** 18,282 blits over the two runs, none slower than MAME's busy timing. |
| Palette | **Working in simulation**, including the read-back the fades use. |
| Sound board | **Working in simulation.** The 6809 runs the sound program on its VIA timer tick, takes the 68000's commands, and drives the YM3812 and OKI. Audio levels were checked; no one has listened to it yet. |
| Controls and coins | **Working in simulation**: coin, credit, start, stick and all three buttons. The service switch opens the game's service menu. |
| NVRAM | FF from configuration and at every ROM load, as MAME's all-1s default; loaded with the MRA (`<nvram index="4">`), an all-zero file refused; saved when the OSD opens. Simulated through MiSTer's load, save and reset paths (build 002). On hardware, build 001 booted with a zero-settings image (D-017). |
| CRT Adjust | Integrated core-side (rmonic79). Checked in simulation through the whole MiSTer video chain. Not yet on a CRT. |
| MRA | `Ninja Clowns (27 oct 91).mra`, byte-exact at 2,129,920 bytes. The md5 is computed the way MiSTer's loader computes it (over the raw parts, before interleaving). |
| Pause, cheats, hiscores | Not implemented. |
| Other IT 8-bit games | Not started (they need the 6809 main board). |

### Measured in simulation

From two Verilator runs on the real ROMs (`sim/`), build 001: 1,800 frames
of attract mode, and 1,200 frames of coin, start and gameplay.

* **ROM reads:** 0 wait states, over 126 million SDRAM reads.
* **Refresh:** every refresh issued in a quiet slot, none forced; 0 SDRAM
  protocol errors or bus contentions in the chip model.
* **Blitter:** 18,282 blits, none slower than MAME's timing (`dbg_late`);
  0 VRAM writes dropped to the missing address bit 16.
* **Loader:** write-side and read-back byte sums both `0E087110` over
  1,048,576 words, at load and again after an OSD reset.
* **Audio:** no clipped samples in 50 seconds of attract and gameplay.
* **NVRAM (build 002, whole `emu` top level):** a fresh load, a saved file,
  an OSD save followed by an OSD reset, and an all-zero file all reach the
  title; a ROM download that starts during SDRAM initialisation still fills
  NVRAM and loads the ROMs intact; a file with zeroed settings reproduces
  the hardware crash and shows `N104` `00000000` on the overlay. Table in
  `PROGRESS.md`.

### Where the core deliberately differs from MAME

* **The RAMDAC pixel mask is ANDed with the pixel**, as on the MS176.
  MAME's model shows black instead when the mask would change the pixel.
  Ninja Clowns uses mask FF, so the picture is the same.
* **The TMS34061 raster registers reset to the values Ninja Clowns
  programs**, not the datasheet's, and the counters never stop, so the
  monitor sees one stable mode while the core loads. The game rewrites
  every register at boot.
* **VRAM address bit 16 has no memory**, as with the board's 64K × 4 VRAMs;
  MAME's array has it. Writes there are dropped and counted (0 so far).
* **The VIA's free-running timer interrupts every N + 2 cycles**, as on a
  real 6522; MAME uses N + 3.
* **The blitter draws over time** instead of instantly, but its busy bit and
  interrupt follow MAME's timing exactly.

---

## Using the core

ROMs are not distributed with this core. Put
`Ninja Clowns (27 oct 91).mra` from `mra/` in `_Arcade`, the core in
`_Arcade/cores` (`Arcade-ITech8.rbf` as Quartus names it), and the MAME ROM
set `ninclown.zip` in `/games/mame/`.

The MRA asks for `ITech8`. MiSTer accepts any `.rbf` in `_Arcade/cores`
named `ITech8` or `Arcade-ITech8`, optionally followed by `_` and more, and
loads the one that sorts last by name. So keep only one of them there: with
`Arcade-ITech8.rbf` and `Arcade-ITech8_debug.rbf` side by side the debug one
loads, and an older `ITech8.rbf` would win over both.

### Controls

| Control | Default | Game |
|---|---|---|
| Stick | D-pad / stick | move |
| Punch | A | button 1 |
| Kick | B | button 2 |
| Throw | X | button 3 |
| Start | Start | |
| Coin | R | |
| Service | L | the service coin |

Both players use the same layout on their own pads.

### OSD menu

| Item | |
|---|---|
| Aspect ratio | Original (4:3), Full Screen, or the two custom ratios |
| Scandoubler Fx | None, HQ2x, CRT 25/50/75% scanlines |
| Scale | Normal, V-Integer, Narrower / Wider HV-Integer |
| CRT Adjust | see below |
| Audio | FM + PCM (MAME balance), FM only, PCM only |
| Service Mode | the board's service switch: on opens the game's service menu (adjustables, audits, diagnostics) |
| Reset | |

NVRAM (settings, statistics and high scores in the game's battery-backed RAM)
is saved by MiSTer when the OSD is opened, and loaded with the MRA. The game
pauses for the moment the save takes. It lives in
`config/nvram/Ninja Clowns (27 oct 91).nvm`; delete that file to return the
game to its factory settings (it then shows "SYSTEM INITIALIZED" once).

### CRT Adjust

rmonic79's [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust),
built into the core (no `sys/` changes). **OSD → CRT Adjust → On** shows three
controls for the analog output:

* **H-Size** (−16 … +15): each step is 1/48 of a pixel, about 2%.
* **H-Position** (−48 … +48 pixels).
* **V-Shift** (−16 … +15 lines).

The picture stays locked while you adjust. CRT Adjust only works at the
native 15 kHz rate, so it switches itself off while a scandoubler effect is
selected. HDMI follows the adjusted picture while it is on, so leave it off
for an untouched HDMI image.

---

## Building

Use Quartus Prime 17.0.x, the MiSTer standard. Everything the build needs is
in this repository, including the MiSTer framework (`sys/`, unmodified) and
the third-party cores. There are two Quartus projects in the root folder,
one per build:

| Project | Settings | Output | |
|---|---|---|---|
| `Arcade-ITech8.qpf` | `Arcade-ITech8.qsf` | `output_files/Arcade-ITech8.rbf` | production |
| `Arcade-ITech8_debug.qpf` | `Arcade-ITech8_debug.qsf` | `output_files/Arcade-ITech8_debug.rbf` | adds OSD → Debug → Diagnostic overlay |

The two settings files are identical except for the `IT8_DEBUG` macro, and
Quartus keeps each project's database under its own name, so both can be
compiled from the same folder.

The PLL makes two clocks from the 50 MHz reference, both integer-exact
(VCO 960 MHz):

| Output | Frequency | Use |
|---|---|---|
| outclk0 | 48 MHz | `clk_sys`: the whole board, the SDRAM controller; `SDRAM_CLK` is this clock inverted through a DDIO output |
| outclk1 | 96 MHz | `clk_vid`: `arcade_video`, CRT Adjust, `video_freak` |

The memory map uses 2 MB of SDRAM, so any MiSTer SDRAM module is enough. The
two VRAM pages use 256 of the FPGA's 553 M10K blocks.

### The debug overlay

OSD → Debug → Diagnostic overlay shows sixteen labelled 32-bit values in a
white-on-black panel, in the style of the Atari G1 and GT cores' overlays.
The game keeps running behind it at full brightness. The values are sampled
once per frame, so a photo of the screen reads cleanly.

| Row | Meaning |
|---|---|
| `BLD` | compile date (`YYMMDD`) and three-digit build number |
| `PC` | last 68000 program fetch address |
| `FRM` | frames (vertical blanks) since reset |
| `IRQS` | level 3 (VBLANK) and level 2 (blitter) interrupts acknowledged |
| `BLIT` | blits started; blits whose drawing outlasted MAME's timing (should stay 0) |
| `WAIT` | 68000 ROM reads that needed a wait state (should stay 0); VRAM writes dropped at address bit 16 |
| `SND` | commands sent to the sound board, and the last one |
| `SPC` | sound CPU bus address |
| `SDRF` | SDRAM refreshes issued; refreshes that had to be forced (should stay 0) |
| `SUMW`, `SUMR` | byte sum of the ROM image written to SDRAM, and read back after loading and after every reset (must match) |
| `LOAD` | bit 28: ROM loaded and checked; bits 20:0: words written |
| `PAGE` | last value written to the display page register |
| `JOY` | player 2 and player 1 joystick words |
| `NVST` | NVRAM: FF fills, saved files loaded, all-zero files refused (one hex digit each), then the number of saves. A fresh load with no saved file reads `10000000`; with a saved file `11000000` |
| `N104` | the long at RAM 0x104 (a credit setting) as the 68000 last read or wrote it; `FFFFFFFF` until it first does. `00000000` means the game accepted a bad NVRAM image and will crash |

The build number goes up with every set of changed files and appears in the
name of the zip they ship in.

---

## Repository layout

```
Arcade-ITech8.qpf         Quartus project, production build
Arcade-ITech8.qsf         production settings
Arcade-ITech8_debug.qpf   Quartus project, debug build
Arcade-ITech8_debug.qsf   debug settings (IT8_DEBUG)
Arcade-ITech8.sdc         timing constraints for this core
Arcade-ITech8.sv          core top level: OSD, loader, inputs, video output, CRT Adjust, overlay
files.qip                 the core's source list
clean.bat                 deletes Quartus build output
LICENSE, README.md
HANDOFF.md                start here to resume the project
PROGRESS.md               build log
DECISIONS.md              design decisions and their reasoning
BUILD.md                  faults found, and the rules that came out of them
mra/                      Ninja Clowns (27 oct 91).mra
releases/                 built cores go here
rtl/
  it8_build.vh            build number
  board/                  main board: top level, clock enables, battery-backed RAM
  video/                  TMS34061, VRAM, ITV4400 blitter, RAMDAC, display path
  sound/                  sound board: 6809 glue, 6522 VIA, mixer
  mem/                    block RAM templates, SDRAM controller, ROM loader
  debug/                  diagnostic overlay
  crt/                    CRT Adjust (rmonic79)
  fx68k/                  68000 (Jorge Cwik)
  mc6809/                 6809 (Greg Miller; synchronous version by Sorgelig)
  jtopl/                  YM3812 (jotego)
  jt6295/                 OKI M6295 (jotego)
  pll/, pll.v, pll.qip    PLL (Quartus IP)
sim/                      Verilator models, see sim/README.md
sys/                      MiSTer framework, unmodified
```

---

## How it is verified

Each block is checked against MAME's behaviour and against the game's own
code, in simulation on the real ROMs:

* **The whole board.** `sim/tb_it8.sv` runs `it8_top` with the real SDRAM
  controller and a cycle model of the SDRAM chip, from power-on into
  gameplay, with scripted coins and inputs. It saves frames and audio and
  counts faults: SDRAM protocol errors and bus contention, ROM wait states,
  late blits, dropped VRAM writes.
* **The whole core.** `sim/emu/tb_emu.sv` runs the complete `emu` top level:
  the ROM stream goes in through the loader exactly as MiSTer sends an MRA,
  is read back and checked, and the picture comes out through
  `arcade_video`, CRT Adjust and `video_freak` on the 96 MHz video clock.
* **The game's code.** The program and sound ROMs were disassembled to
  settle what MAME leaves implicit. That covered the TMS34061 byte order and
  raster values, the shift-register screen clear, the palette fade, the
  VIA timer use, and the boot's NVRAM checksum. An exception-stop trace
  (`-s`) and a PC histogram (`-p`) find where the game is and why.
* **Lint.** `sim/lint.sh` runs Verilator's lint over the complete `emu` top
  level with the real `sys/` modules, in both builds.

---

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

**[System 16](https://www.system16.com/hardware.php?id=805&gid=2280#2280)**
for the hardware family listing.

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
