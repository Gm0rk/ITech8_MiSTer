# Grudge Match

[Back to the main README](../README.md)

<img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Grudge_Match.png" width="400" alt="Grudge Match title screen"> <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Grudge_Match_2.png" width="400" alt="Grudge Match gameplay">

| | |
|---|---|
| Sets | `grmatch` (Yankee Game Technology; main MRA) |
| ROM zip | `grmatch.zip` and `ym2608.zip` (MAME's YM2608 drum sounds, which the game needs too) |
| Players | 2 |
| Sound | 6809 @ 2 MHz, YM2608 sound board (FM music, drum sounds and ADPCM samples) |
| Display | 416 x 240, horizontal, 59.64 Hz |

## Extra content

What the core adds for this game:

- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips (here PCM is the YM2608's drums and samples).
- **Button layout**: Button 1, Button 2, Start, Coin, Service, for each of two players.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Stick | Move (8-way) |
| A | Button 1 |
| B | Button 2 |
| Start | Start |
| R / L | Coin / Service (the first controller's Coin is coin slot 1, the second's slot 2) |

Each of two players uses their own controller. The picture is two 4-bit layers with 16 colours each from 4096; the board loads their palettes from the picture's own memory.
