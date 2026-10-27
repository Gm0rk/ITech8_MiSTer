# Capcom Bowling and Coors Light Bowling

[Back to the main README](../README.md)

<img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Capcom_Bowling.png" width="400" alt="Capcom Bowling and Coors Light Bowling title screen"> <img src="https://github.com/Gm0rk/ITech8_MiSTer/blob/main/media/Capcom_Bowling_2.png" width="400" alt="Capcom Bowling and Coors Light Bowling gameplay">

| | |
|---|---|
| Sets | `capbowl` (set 1; main MRA); `capbowl2` (set 2); `capbowl3` (set 3); `capbowl4` (set 4); `clbowl` (Coors Light Bowling) |
| ROM zip | `capbowl.zip` (the parent set). Each other set also needs its own zip (`capbowl2.zip`, `capbowl3.zip`, `capbowl4.zip`, `clbowl.zip`), or use MAME's merged set in `capbowl.zip` |
| Players | 2 (the one Start button adds players, up to 4) |
| Sound | 6809 @ 2 MHz, YM2203, DAC |
| Display | 360 x 245, vertical, about 60 Hz |

## Extra content

What the core adds for this game:

- **[Calibrate trackball](#calibrate-trackball)** (Trackball Options): fills a preset with gains measured from three throws and three sideways rolls, then lets you tune the sideways gain by eye.
- **[Trackball presets](#trackball-feel)** (Trackball Options → Preset: Off, 1, 2, 3): each preset has its own forward and sideways gain, 12 % to 800 % of Normal.
- **[Trackball Speed and Trackball Sideways](#trackball-feel)** (Trackball Options, with Preset Off): the mouse counts per trackball count, and a multiplier for the sideways counts only.
- **Orientation** (Horizontal, Vertical, Vertical Flip, Horizontal Flip): Horizontal turns the picture for a normal screen (Horizontal Flip the other way round); Vertical is for a monitor turned as in the original cabinets, with its left edge at the bottom, Vertical Flip for one turned the other way.
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

The second controller's Coin is the cabinet's second coin slot; this game can price it separately. Service (L) is also in the OSD as Service Mode. The board is IT's earlier bowling board (MAME's `capbowl` driver), with a 2 KB NVRAM.

## Setup menu

Hold Service for half a second in attract mode (not during a game). Roll the trackball to an item and press Start; in Adjustments, Hook Left and Hook Right lower and raise the value. Video Tests ends on an 8 x 8 grid, which fills the picture.

## Trackball feel

The game's own **TRACKBALL TYPE** setting, 0 to 4 (factory 3), changes how fast a roll sends the ball: each step lower doubles the ball speed. With a Taito Egret II Mini trackball, a tester found both games best at Normal with TRACKBALL TYPE 2.

Sideways rolls count at half the rate of forward ones, by design (the original board and MAME do the same), and the ball starts at the edge of the lane.

A roll faster than the most the game can read between two of its reads (7 counts) is held at that, and the rest follows, so a fast roll or a high gain never reads as a move the other way.

With Preset Off, **Trackball Speed** sets how many mouse counts make one trackball count (Fast 1, Normal 2, Slow 4) and **Trackball Sideways** (1x to 4x) multiplies the sideways counts only, for a small trackball that needs several spins to bring the ball to the middle. Preset 1 to 3 each hold their own forward and sideways gain (12 % to 800 % of Normal); only the chosen preset's lines show, and with a preset chosen its gains alone decide the feel. Save settings in the OSD keeps the presets, for that game only.

## Calibrate trackball

Open **OSD → Trackball Options**, choose a **Preset** (with Preset Off, Preset 1 is filled) and select **Calibrate trackball**. A page over the game shows each step.

1. **Three throws**, as hard as you do in play. The core measures them the way the game reads the trackball, so that a hard throw just reaches the game's top speed.
2. **Three sideways rolls**, single rolls of the kind you make to aim, so that one roll moves the ball about half the lane. Only the most a roll covers in half a second counts, so rolling on does not change the result, and the sideways gain is never set below the forward one.
3. **Tune by eye.** The gains found are already in use: roll the bowler and watch where it stops. **Hook Right** makes one roll carry it further and **Hook Left** less, about 9 % a press, until one ordinary roll moves it about half the lane. **Start** keeps both gains. The hook buttons and Start do not reach the game during this step.

**Cancel calibration** stops it at any point before the gains are kept, and it stops by itself after 30 seconds without a throw; either way the preset is unchanged (30 seconds idle in the tuning step keeps the gains as tuned). The calibration assumes the game's own trackball setting is at factory.
