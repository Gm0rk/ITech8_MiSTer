# Strata Bowling

[Back to the main README](../README.md)

| | |
|---|---|
| Sets | `stratab` (V3; main MRA); `stratab1` (V1) |
| ROM zip | `stratab.zip` (the parent set). Each other set also needs its own zip (`stratab1.zip`), or use MAME's merged set in `stratab.zip` |
| Players | 2 (the one Start button adds players, up to 4) |
| Sound | 6809 @ 2 MHz, YM2203, OKI M6295 |
| Display | 256 x 240, vertical, 59.7 Hz |

## Extra content

What the core adds for this game:

- **[Calibrate trackball](#calibrate-trackball)** (Trackball Options): fills a preset with gains measured from three throws and three sideways rolls, then lets you tune the sideways gain by eye.
- **[Trackball presets](#trackball-feel)** (Trackball Options → Preset: Off, 1, 2, 3): each preset has its own forward and sideways gain, 12 % to 800 % of Normal.
- **[Trackball Speed and Trackball Sideways](#trackball-feel)** (Trackball Options, with Preset Off): the mouse counts per trackball count, and a multiplier for the sideways counts only.
- **Orientation** (Horizontal, Vertical, Vertical Flip, Horizontal Flip): Horizontal turns the picture for a normal screen (Horizontal Flip the other way round); Vertical is for a monitor turned as in the original cabinets, with its left edge at the bottom, Vertical Flip for one turned the other way.
- **Audio** (FM + PCM, FM only, PCM only): mixes the two sound chips.
- **Button layout**: Hook Left, Hook Right, Start, Coin, Service.

The [core-wide features](../README.md#features) (CRT Adjust, NVRAM saving, Service Mode and the rest) apply to every game.

## Controls

| Input | Use |
|---|---|
| Trackball | The mouse, or the stick |
| A | Hook Left |
| B | Hook Right |
| Start | Adds a player each time it is pressed, up to 4 |
| R / L | Coin / Service |

Roll the trackball to pick a game (Strata Bowling, Flash, Strike or Die), then press Start. The second controller's Coin is the cabinet's second coin slot; this game can price it separately. Service (L) is also in the OSD as Service Mode. The first game on the 6809 blitter board, which shows two layers (an 8-bit background and a 16-colour foreground), with an 8 KB NVRAM.

## Setup menu

Press Service at any time. Move the trackball up or down to an item and press Start; move it left or right to change a value.

## Trackball feel

The game's own **TRACKBALL SENSITIVITY** setting runs from level 1 (least force) to level 5 (most force).

With Preset Off, **Trackball Speed** sets how many mouse counts make one trackball count (Fast 1, Normal 2, Slow 4) and **Trackball Sideways** (1x to 4x) multiplies the sideways counts only, for a small trackball that needs several spins to bring the ball to the middle. Preset 1 to 3 each hold their own forward and sideways gain (12 % to 800 % of Normal); only the chosen preset's lines show, and with a preset chosen its gains alone decide the feel. Save settings in the OSD keeps the presets, for that game only.

## Calibrate trackball

Open **OSD → Trackball Options**, choose a **Preset** (with Preset Off, Preset 1 is filled) and select **Calibrate trackball**. A page over the game shows each step.

1. **Three throws**, as hard as you do in play. The core measures them the way the game reads the trackball, so that a hard throw just reaches the game's top speed.
2. **Three sideways rolls**, single rolls of the kind you make to aim, so that one roll moves the ball about half the lane. Only the most a roll covers in half a second counts, so rolling on does not change the result, and the sideways gain is never set below the forward one.
3. **Tune by eye.** The gains found are already in use: roll the bowler and watch where it stops. **Hook Right** makes one roll carry it further and **Hook Left** less, about 9 % a press, until one ordinary roll moves it about half the lane. **Start** keeps both gains. The hook buttons and Start do not reach the game during this step.

**Cancel calibration** stops it at any point before the gains are kept, and it stops by itself after 30 seconds without a throw; either way the preset is unchanged (30 seconds idle in the tuning step keeps the gains as tuned). The calibration assumes the game's own trackball setting is at factory.
