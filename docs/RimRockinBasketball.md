# Rim Rockin' Basketball

[Back to the main README](../README.md)

<img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Rim_Rockin_Basketball.png" width="400" alt="Rim Rockin' Basketball title screen"> <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Rim_Rockin_Basketball_2.png" width="400" alt="Rim Rockin' Basketball gameplay">

| | |
|---|---|
| Sets | `rimrockn` (v2.2; main MRA); `rimrockn12` (v1.2); `rimrockn12b` (v1.2, bootleg); `rimrockn15` (v1.5); `rimrockn16` (v1.6); `rimrockn20` (v2.0) |
| ROM zip | `rimrockn.zip` (the parent set). Each other set also needs its own zip (`rimrockn12.zip`, `rimrockn12b.zip`, `rimrockn15.zip`, `rimrockn16.zip`, `rimrockn20.zip`), or use MAME's merged set in `rimrockn.zip` |
| Players | 1 to 4, each on their own controller |
| Sound | Ninja Clowns' sound board: 6809 @ 2 MHz, YM3812, OKI M6295, 6522 VIA |
| Display | 392 x 240, horizontal, 59.65 Hz |

## Extra content

What the core adds for this game:

- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips.
- **Button layout**: Shoot, Pass, Start, Coin, Service, for each of four players.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Stick | Move (8-way) |
| A | Shoot |
| B | Pass |
| Start | Start |
| R / L | Coin / Service: player n's Coin is coin slot n; any player's Service opens the service menu |

The HD6309 (3 MHz) runs here as a 6809, which is all the game uses.

## Setup menu

Press Service (or OSD Service Mode). Player 1's stick up or down selects, Shoot chooses.
