# Hot Shots Tennis

[Back to the main README](../README.md)

| | |
|---|---|
| Sets | `hstennis` (v1.1; main MRA); `hstennis10` (v1.0) |
| ROM zip | `hstennis.zip` (the parent set). Each other set also needs its own zip (`hstennis10.zip`), or use MAME's merged set in `hstennis.zip` |
| Players | 2 |
| Sound | 6809 @ 2 MHz, YM3812, OKI M6295, 6821 PIA |
| Display | 416 x 240, vertical, 59.65 Hz |

## Extra content

What the core adds for this game:

- **Orientation** (Horizontal, Vertical, Vertical Flip, Horizontal Flip): Horizontal turns the picture for a normal screen (Horizontal Flip the other way round); Vertical is for a monitor turned with its left edge at the top, Vertical Flip for one turned the other way.
- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips.
- **Button layout**: Hard, Soft, Coin, Service, for each of two players.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Stick | Move (8-way) |
| A | Hard |
| B | Soft |
| R / L | Coin / Service (the first controller's Coin is coin slot 1, the second's slot 2) |

Each of two players uses their own controller.
