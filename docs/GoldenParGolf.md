# Golden Par Golf

[Back to the main README](../README.md)

<img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Par_Golf.png" width="400" alt="Golden Par Golf title screen"> <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Par_Golf_2.png" width="400" alt="Golden Par Golf gameplay">

| | |
|---|---|
| Sets | `gpgolf` (Joystick, v1.1; main MRA); `gpgolfa` (Joystick, v1.0) |
| ROM zip | `gpgolf.zip` (the parent set). Each other set also needs its own zip (`gpgolfa.zip`), or use MAME's merged set in `gpgolf.zip` |
| Players | 1 to 4 |
| Sound | 6809 @ 2 MHz, YM3812, OKI M6295 (Ninja Clowns' sound board) |
| Display | 256 x 240, horizontal, 59.7 Hz |

## Extra content

What the core adds for this game:

- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips.
- **Button layout**: Swing, Start, Coin, Service.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Stick | Move |
| A | Swing: hold for the backswing, let go for the forward swing |
| Start | Start (Select) |
| R / L | Coin / Service (the first controller's Coin is coin slot 1, the second's slot 2) |

Start (the game calls it Select) confirms the number of golfers, one to four, and the course. The core supports the upright cabinet only. The board is IT's 1992 board (P/N 1047) with the YM3812 sound board (P/N 1038).
