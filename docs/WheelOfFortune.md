# Wheel Of Fortune

[Back to the main README](../README.md)

| | |
|---|---|
| Sets | `wfortune` (set 1; main MRA); `wfortunea` (set 2) |
| ROM zip | `wfortune.zip` (the parent set). Each other set also needs its own zip (`wfortunea.zip`), or use MAME's merged set in `wfortune.zip` |
| Players | 3 (one button each: Red, Yellow, Blue) |
| Sound | 6809 @ 2 MHz, YM2203, OKI M6295 |
| Display | 256 x 240, horizontal, 59.7 Hz |

## Extra content

What the core adds for this game:

- **[Dial speed](#dial)** (Trackball Options → Trackball Speed): sets how many mouse counts make one dial count.
- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips.
- **Button layout**: one Button for each of three players, Coin, Service.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Dial | The mouse's left-right movement, or the stick |
| A | Button: on each of three controllers, the Red, Yellow and Blue player's button |
| R / L | Coin / Service (the first controller's Coin is coin slot 1, the second's slot 2) |

Strata Bowling's board with a dial.

## Dial

Wheel Of Fortune has no calibration. **OSD → Trackball Options → Trackball Speed** sets how many mouse counts make one dial count (Fast 1, Normal 2, Slow 4).
