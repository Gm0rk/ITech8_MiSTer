# Peggle

[Back to the main README](../README.md)

| | |
|---|---|
| Sets | `peggle` (Joystick, v1.0; main MRA); `pegglet` (Trackball, v1.0) |
| ROM zip | `peggle.zip` (the parent set). Each other set also needs its own zip (`pegglet.zip`), or use MAME's merged set in `peggle.zip` |
| Players | 1 |
| Sound | 6809 @ 2 MHz, YM3812, OKI M6295, 6821 PIA |
| Display | 416 x 240, vertical, 59.65 Hz |

## Extra content

What the core adds for this game:

- **[Dial speed](#dial)** (Trackball Options → Trackball Speed): sets how many mouse counts make one dial count. Trackball set only.
- **Orientation** (Horizontal, Vertical, Vertical Flip, Horizontal Flip): Horizontal turns the picture for a normal screen (Horizontal Flip the other way round); Vertical is for a monitor turned with its left edge at the top, Vertical Flip for one turned the other way.
- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips.
- **Button layout**: Start, Coin, Service.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Stick | Joystick set: left and right |
| Dial | Trackball set: the mouse's left-right movement, or the stick |
| Start | Start |
| R / L | Coin / Service |

## Dial

The trackball set (`pegglet`) reads a dial; there is no calibration. **OSD → Trackball Options → Trackball Speed** sets how many mouse counts make one dial count (Fast 1, Normal 2, Slow 4).
