# Incredible Technologies 8-bit hardware for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

> **AI disclosure:** this core was developed using AI and MAME as a reference.
> (Claude, by Anthropic - Opus 5.5 & Sonnet 5.5).

An FPGA implementation of Incredible Technologies' (Strata) 8-bit blitter
arcade hardware (1988-1992), the TMS34061 and ITV4400 platform behind Ninja
Clowns, Capcom Bowling, Strata Bowling, Golden Tee Golf and Rim Rockin'
Basketball.

## Table of Contents

- [Hardware](#hardware)
- [Games](#games)
- [Games not planned](#games-not-planned-because-of-unique-physical-controls)
- [Features](#features)
- [ROMs](#roms)
- [Credits and references](#credits-and-references)
- [License](#license)

## Hardware

| | Ninja Clowns board | Bowling board | 6809 blitter board |
|---|---|---|---|
| Games | Ninja Clowns | Capcom Bowling, Coors Light Bowling, Bowl-O-Rama | every other game |
| Main CPU | 68000 @ 12 MHz | 6809 @ 2 MHz | 6809 @ 2 MHz (Rim Rockin' Basketball: HD6309 @ 3 MHz) |
| Sound | 6809 @ 2 MHz, YM3812, OKI M6295, 6522 VIA | 6809 @ 2 MHz, YM2203, DAC | 6809 @ 2 MHz, YM2203, OKI M6295; a YM3812 board on some games, a YM2608 board on Grudge Match |
| Video | TMS34061 and ITV4400 blitter, two 512 x 256 pages, 256 colours | TMS34061, 16 colours per line from 4096, no blitter | TMS34061 and ITV4400 blitter, 256 colours; the layout depends on the game |
| Display | 362 x 240, 59.64 Hz | 360 x 245 (Bowl-O-Rama 240), vertical, about 60 Hz | 256 x 240 to 416 x 240, about 59.7 Hz; horizontal or vertical |
| Controls | 8-way stick, 3 buttons | trackball, 2 hook buttons | trackball, stick, dial or buttons, by game |
| NVRAM | 16 KB | 2 KB | 8 KB |

Every board runs at its original speeds from one 48 MHz clock, and the video
output runs at 96 MHz from the same PLL. All games use 2 MB of SDRAM or less.

## Games

Each game has its own page in [`docs`](docs) with its versions, controls and
game-specific features.

| Game | Main set | Title Screen | Gameplay |
|---|---|---|---|
| [Arlington Horse Racing](docs/ArlingtonHorseRacing.md) | arlingtn (v1.40-D) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Arlington_Horse_Racing.png" width="300" alt="Arlington Horse Racing title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Arlington_Horse_Racing_2.png" width="300" alt="Arlington Horse Racing gameplay"> |
| [Bowl-O-Rama](docs/BowlORama.md) | bowlrama | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Bowl-O-Rama.png" width="300" alt="Bowl-O-Rama title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Bowl-O-Rama_2.png" width="300" alt="Bowl-O-Rama gameplay"> |
| [Capcom Bowling](docs/CapcomBowling.md) (and Coors Light Bowling) | capbowl (set 1) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Capcom_Bowling.png" width="300" alt="Capcom Bowling title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Capcom_Bowling_2.png" width="300" alt="Capcom Bowling gameplay"> |
| [Golden Par Golf](docs/GoldenParGolf.md) | gpgolf (joystick v1.1) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Par_Golf.png" width="300" alt="Golden Par Golf title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Par_Golf_2.png" width="300" alt="Golden Par Golf gameplay"> |
| [Golden Tee Golf](docs/GoldenTeeGolf.md) | gtg (joystick v3.3) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Tee_Golf.png" width="300" alt="Golden Tee Golf title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Tee_Golf_2.png" width="300" alt="Golden Tee Golf gameplay"> |
| [Golden Tee Golf II](docs/GoldenTeeGolfII.md) | gtg2 (trackball v2.2) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Tee_Golf_II.png" width="300" alt="Golden Tee Golf II title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Tee_Golf_II_2.png" width="300" alt="Golden Tee Golf II gameplay"> |
| [Grudge Match](docs/GrudgeMatch.md) | grmatch | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Grudge_Match.png" width="300" alt="Grudge Match title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Grudge_Match_2.png" width="300" alt="Grudge Match gameplay"> |
| [Hot Shots Tennis](docs/HotShotsTennis.md) | hstennis (v1.1) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Hot_Shots_Tennis.png" width="300" alt="Hot Shots Tennis title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Hot_Shots_Tennis_2.png" width="300" alt="Hot Shots Tennis gameplay"> |
| [Neck-N-Neck](docs/NeckNNeck.md) | neckneck (v1.2) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Neck-N-Neck.png" width="300" alt="Neck-N-Neck title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Neck-N-Neck_2.png" width="300" alt="Neck-N-Neck gameplay"> |
| [Ninja Clowns](docs/NinjaClowns.md) | ninclown | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Ninja_Clowns.png" width="300" alt="Ninja Clowns title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Ninja_Clowns_2.png" width="300" alt="Ninja Clowns gameplay"> |
| [Peggle](docs/Peggle.md) | peggle (joystick) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Peggle.png" width="300" alt="Peggle title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Peggle_2.png" width="300" alt="Peggle gameplay"> |
| [Poker Dice](docs/PokerDice.md) | pokrdice (v1.7) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Poker_Dice.png" width="300" alt="Poker Dice title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Poker_Dice_2.png" width="300" alt="Poker Dice gameplay"> |
| [Rim Rockin' Basketball](docs/RimRockinBasketball.md) | rimrockn (v2.2) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Rim_Rockin_Basketball.png" width="300" alt="Rim Rockin' Basketball title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Rim_Rockin_Basketball_2.png" width="300" alt="Rim Rockin' Basketball gameplay"> |
| [Strata Bowling](docs/StrataBowling.md) | stratab (V3) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Strata_Bowling.png" width="300" alt="Strata Bowling title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Strata_Bowling_2.png" width="300" alt="Strata Bowling gameplay"> |
| [Wheel Of Fortune](docs/WheelOfFortune.md) | wfortune (set 1) | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Wheel_Of_Fortune.png" width="300" alt="Wheel Of Fortune title screen"> | <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Wheel_Of_Fortune_2.png" width="300" alt="Wheel Of Fortune gameplay"> |

The other versions and clones are in `mra/_alternatives`.

## Games not planned because of unique physical controls

| Game | Year | Main CPU | Status |
|---|---|---|---|
| Dyno Bop (v1.1) | 1990 | 6809, Z80 sensor board | Not planned |
| Slick Shot (v2.2, v1.7, v1.6) | 1990 | 6809, Z80 sensor board | Not planned |
| Super Strike Bowling (v1) | 1990 | 6809, Z80 sensor board | Not planned |

## Features

- CRT Adjust by rmonic79: H-Size, H-Position and V-Shift.
- Vertical games can be turned for a normal screen (Horizontal) or vertical for a rotated monitor
- Trackball presets and Calibrate trackball: three throws or swings as hard
  as in play set the gain to match the game (the bowling games and the golf
  trackball sets)
- NVRAM saved to the SD card: settings, audits and high scores

## ROMs

ROMs are **not** included in this repository; you need your own dumps of the
games. Merged or split MAME sets both work, and each game's page names its
zips. Put the ROMS in `games/mame` (Grudge Match also needs an additional sound ROM
`ym2608.zip`.), the MRA files from `mra/` go in `_Arcade`(keep the `_alternatives` folder). 
The core goes in `_Arcade/cores`.

## Credits and references

This core is a reimplementation; MAME is a reference for *behaviour*, and no
MAME code is compiled into it.

- MAME `itech8` and `capbowl` drivers, `tms34061`, `tlc34076`, `6522via`,
  `6821pia`, `gen_latch`, `ticket` and `ymfm`: Aaron Giles, Zsolt Vasvari,
  Philip Bennett, Peter Trauner, Mathis Rosenhauer, Nathan Woods and Miodrag
  Milanovic
- [System 16](https://www.system16.com/hardware.php?id=805) for the hardware
  family listing
- [fx68k](https://github.com/ijor/fx68k): Jorge Cwik (the 68000)
- [mc6809](https://github.com/cavnex/mc6809): Greg Miller (synchronous version
  by Sorgelig, reset-interrupt fix by RndMnkIII)
- [JTOPL, JT6295 and JT12](https://github.com/jotego): Jose Tejada (jotego)
  (YM3812, OKI M6295, YM2203 and the YM2608's FM)
- [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust): Umberto
  Parisi (rmonic79)
- ppriest: [MiSTer-CoreSkill](https://github.com/ppriest/MiSTer-CoreSkill),
  whose [`clocks.md`](https://github.com/ppriest/MiSTer-CoreSkill/blob/main/mister-arcade-core/references/clocks.md)
  the core's clocks were checked against
- [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) and
  [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer):
  Alexey Melnikov (Sorgelig), whose `sys/` this core builds on

## License

The core's own RTL is GPL-2.0-or-later, as the MiSTer framework is (see
`LICENSE`). fx68k, JTOPL, JT6295, JT12/JT49 and CRT Adjust are GPL v3, so a
built core is distributed under GPL v3. The mc6809 core is under its BSD
licence (`rtl/mc6809/`). `sys/` and every third-party core keep their
original licences and authorship.

No ROM data is included or distributed.
