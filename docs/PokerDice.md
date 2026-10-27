# Poker Dice

[Back to the main README](../README.md)

| | |
|---|---|
| Sets | `pokrdice` (v1.7; main MRA) |
| ROM zip | `pokrdice.zip` |
| Players | 1 |
| Sound | 6809 @ 2 MHz, YM2203, OKI M6295 |
| Display | 256 x 240, vertical, 59.7 Hz |

## Extra content

What the core adds for this game:

- **Orientation** (Horizontal, Vertical, Vertical Flip, Horizontal Flip): Horizontal turns the picture for a normal screen (Horizontal Flip the other way round); Vertical is for a monitor turned with its left edge at the top, Vertical Flip for one turned the other way.
- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips.
- **Button layout**: Play, Raise and five dice buttons.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Start | Play |
| B | Raise |
| X | Upper Left die |
| Y | Upper Right die |
| A | Middle die |
| L | Lower Left die |
| R | Lower Right die |
| Select | Coin (coin slot 1) |
| not set | Service: define it in MiSTer, or use OSD Service Mode |

The picture is one 8-bit page.
