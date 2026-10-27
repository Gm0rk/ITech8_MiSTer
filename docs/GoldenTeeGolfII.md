# Golden Tee Golf II

[Back to the main README](../README.md)

<img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Tee_Golf_II.png" width="400" alt="Golden Tee Golf II title screen"> <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Golden_Tee_Golf_II_2.png" width="400" alt="Golden Tee Golf II gameplay">

| | |
|---|---|
| Sets | `gtg2` (Trackball, v2.2; main MRA); `gtg2j` (Joystick, v1.0); `gtg2t` (Trackball, v1.1) |
| ROM zip | `gtg2.zip` (the parent set). Each other set also needs its own zip (`gtg2j.zip`, `gtg2t.zip`), or use MAME's merged set in `gtg2.zip` |
| Players | 1 to 4 |
| Sound | 6809 @ 2 MHz, YM2203, OKI M6295 (v2.2: Ninja Clowns' YM3812 sound board) |
| Display | 256 x 240, horizontal, 59.7 Hz |

## Extra content

What the core adds for this game:

- **[Calibrate trackball](#calibrate-trackball)** (Trackball Options; trackball sets): fills a preset with a gain measured from three swings, so a hard swing just reaches full power.
- **[Trackball presets](#trackball-feel)** (Trackball Options → Preset: Off, 1, 2, 3): each preset has its own gain, 12 % to 800 % of Normal.
- **[Trackball Speed](#trackball-feel)** (Trackball Options, with Preset Off): the mouse counts per trackball count.
- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips.
- **Button layout**: the trackball sets have Face Left and Face Right; the joystick set has Swing.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Stick | Joystick sets: move |
| A | Joystick sets: Swing. Trackball sets: Face Left |
| B | Trackball sets: Face Right |
| Trackball | Trackball sets: the mouse, or the stick. Pull it back, then push it forward to swing |
| Start | Start (Select) |
| R / L | Coin / Service (the first controller's Coin is coin slot 1, the second's slot 2) |

Joystick sets: hold Swing (A) for the backswing and let go for the forward swing. Start (the game calls it Select) confirms the number of golfers, one to four, and the course. The core supports the upright cabinet only. The trackball sets are v2.2 and v1.1; the joystick set is v1.0. Version 2.2 runs on IT's 1992 board (P/N 1047) with Ninja Clowns' YM3812 sound board (P/N 1038).

## Trackball feel

This applies to the trackball sets. With Preset Off, **Trackball Speed** sets how many mouse counts make one trackball count (Fast 1, Normal 2, Slow 4). Preset 1 to 3 each hold their own gain (12 % to 800 % of Normal); only the chosen preset's lines show, and with a preset chosen its gain alone decides the feel. Save settings in the OSD keeps the presets, for that game only.

## Calibrate trackball

Open **OSD → Trackball Options**, choose a **Preset** (with Preset Off, Preset 1 is filled) and select **Calibrate trackball**. A page over the game shows each try.

Swing **three times**, as hard as you do in play: pull the trackball back, then push it forward. The core measures them the way the game does, so that a hard swing just reaches full power, and keeps the gain.

**Cancel calibration** stops it before the gain is kept, and it stops by itself after 30 seconds without a swing; either way the preset is unchanged. The calibration assumes the game's own trackball setting is at factory.
