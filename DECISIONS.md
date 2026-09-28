# Decisions

Every architectural choice, measurement and reversal, with its reasoning.
Newest last. A decision is only overturned by a later entry that says so.

---

## D-001 — First target: Ninja Clowns, the 68000 board set

The IT 8-bit family in MAME's `itech8` driver has sixteen games. Fifteen run a
6809 main CPU. Ninja Clowns runs a 68000 at 12 MHz (lower board P/N 1029
REV3A) with the external YM3812 sound board (P/N 1038 REV2). It was asked for
first, so the core is built around that board set. The 6809 boards share the
video and sound sections (TMS34061, ITV4400, RAMDAC, 6809 sound board), so
those modules are written to be reusable when the 6809 main board is added.

## D-002 — One system clock, 48 MHz

Every Ninja Clowns clock divides 48 MHz exactly: 68000 12 MHz (/4), dot clock
8 MHz (/6), TMS34061 character clock 4 MHz (/12), 6809 E 2 MHz (/24), YM3812
4 MHz (/12), OKI 1 MHz (/48), and MAME's blitter timing base 3 MHz (/16). So
the whole board runs on `clk_sys` = 48 MHz with clock enables from one
modulo-48 counter (`it8_ce.sv`). No clock-domain crossings inside the board.

## D-003 — SDRAM at 48 MHz, falling-edge capture, command slots tied to the 68000 phase

The 256 KB program ROM cannot share block RAM with the 2 Mbit of VRAM
(256 + 256 of 553 M10K), so it lives in SDRAM with the graphics ROMs and OKI
samples. A 68000 ROM read must then finish inside the bus cycle to avoid wait
states the real board never had.

* The controller runs on `clk_sys`, with `SDRAM_CLK` = `clk_sys` inverted
  through a DDIO output. At 48 MHz the CL2 data window (tAC after edge T1 to
  tOH after T2) is centred on the falling edge of `clk_sys` two clocks after
  READ, with about ±8 ns of margin. The capture register is on that falling
  edge. (The Atari G1 core's sweep found the same "t + x.5" point.)
* The 68000 always drops AS at the start of the clock after `enPhi1`, and
  samples DTACK at the end of the second `enPhi2` clock after. So the
  controller gives the 68000 a fixed slot, ACT in phase 2 and READ in phase 3
  on bank 0, and everything else (blitter, OKI, loader) a second slot, ACT in
  phase 0 and READ in phase 1 on banks 1 and 2. The slots never collide on
  the command bus, the banks or the DQ bus, so ROM reads have zero wait
  states whatever the blitter is doing.
* Refresh waits for a moment when the 68000 cannot start a ROM read within
  six clocks (AS low on a cycle that is not an unserved ROM read), and is
  forced only if eight fall overdue.

Measured in simulation: 0 wait states on ROM reads, 0 forced refreshes.

## D-004 — VRAM in block RAM, eight lanes wide

Two pages × 64K addresses × 16 bits (a VRAM byte of two 4-bit pixels, plus a
latch byte holding their upper colour nibbles) = 2 Mbit. It is stored as 16
simple dual-port RAMs (VRAM and latch byte for each of eight column lanes),
so one access reads or writes an 8-column chunk:

* The shift-register row copy (TMS34061 function 4), which the game uses to
  clear 240 rows in vertical blank, takes 32 chunk accesses instead of 256.
* The display copies a whole row into a line buffer at the start of each
  line, as the real VRAM transfers the row to its serial port.

MAME's VRAM array is 256 KB (address bits 17:0). This board has 64K×4 chips,
so address bit 16 has no memory behind it. Writes with bit 16 set are
dropped and counted (`dbg_vram_drop`); the count stays 0 in simulation.

## D-005 — TMS34061 register addressing taken from the game code, not assumed

With register access, column bit 1 is inverted (MAME's `col ^= 2`). The
disassembly of the program ROM confirms the game writes each register's
upper byte first at offset +1 and the lower at +2 (for example
`0x110001 = 0`, `0x110002 = 0x0C` for HESYNC). The raster it programs is
HESYNC 12, HEBLNK 44, HSBLNK 225, HTOTAL 254, VESYNC 8, VEBLNK 19,
VSBLNK 259, VTOTAL 262.

## D-006 — Raster: counts inclusive, two dots per count, 8 MHz dot clock

The counters run 0..TOTAL inclusive: 255 × 263. With two dots per count and
the lower board's 8 MHz crystal as the dot clock, that is 510 × 263 at
15.686 kHz / 59.64 Hz, which matches MAME's 512 × 263 screen and its
360-pixel visible area (here 181 counts = 362 dots). The display column for
count h is (h − HESYNC): the serial port starts shifting when sync ends,
which puts VRAM column 32 at the first visible dot, as MAME's
`visarea(64, ...)` does. The dot clock is inferred, not measured.

## D-007 — Raster registers reset to the game's values, counters free-run

The datasheet reset raster is 1026 × 257. The game reprograms it within a
millisecond of reset, but while the core loads or sits in reset that would
put an odd mode on the monitor. The raster registers therefore reset to the
values the game programs (D-005), and the counters are never reset, so sync
runs continuously. The display stays blanked until the game sets CONTROL2
bit 13, exactly as before.

## D-008 — Blitter: MAME's algorithm, MAME's busy time, a real drawing engine

`it8_blitter.sv` follows `perform_blit` line for line: skip counts, the
serpentine row order, RLE, X/Y flip, nibble shift, 4 bpp transparency, the
source mask, and the `m_grom % length` wrap. MAME draws instantly and holds
the busy bit for (W × H + 12) ticks of 3 MHz; the core keeps that busy time
and never finishes earlier, so the game sees MAME's timing. The engine itself
must never be slower (`dbg_late` counts blits where it was).

## D-009 — 6809 sound board: VIA subset, MAME mixing

The sound program uses VIA timer 1 in free-run mode (latch 0x1E60) for its
tick and port B for board outputs; no other VIA function. `it8_via6522.sv`
implements ports, both timers and IFR/IER. Free-run period is N + 2 cycles as
on the real part (MAME uses N + 3; 0.013% tempo difference). Mixing follows
MAME's routing, 0.75 each for the YM3812 and the OKI, with one full-scale OKI
voice equal to the YM3812's full scale, saturated to 16 bits.

## D-010 — RAMDAC pixel mask as on the chip

MAME's TLC34076 model shows black when (pixel & mask) != pixel. The MS176 /
IMSG176 datasheet ANDs the mask into the palette address. The core does what
the chip does. Ninja Clowns writes 0xFF, so the two agree for this game.

## D-011 — NVRAM starts as all 1s

MAME declares the RAM `nvram_device::DEFAULT_ALL_1`. The game checks an
NVRAM checksum at boot; all-zero RAM happens to pass it, the defaults are
then never written, and the game divides by zero (found in simulation: zero
divide at 0x17450, then the bus/address error handler). The loader fills
the NVRAM with 0xFF when a ROM download starts; a saved NVRAM file (MRA index
4) loads afterwards and replaces it.

## D-012 — CRT Adjust core-side, on a 96 MHz video clock

rmonic79's `crt_adjust.sv` steps H-Size in quarter clock cycles of the video
clock. At 48 MHz with an 8 MHz dot that is 1/24 of a pixel (4.2% per step);
at 96 MHz it is 1/48 (2.1%). The PLL makes 96 MHz in phase with `clk_sys`;
the pixel stream crosses into it once, after the overlay, and `arcade_video`,
CRT Adjust and `video_freak` run there. `HPOS_MODE` is content-shift: the
picture is wide and centred (362 of 510 dots). CRT Adjust switches off when
the scandoubler is on, as the module requires.

## D-013 — Production and debug revisions

`Arcade-ITech8.qsf` is the production build. `Arcade-ITech8_debug.qsf` adds
`IT8_DEBUG`: an OSD Debug page with the diagnostic overlay. Everything else
is identical, so the two builds behave the same with the overlay off. (The
first draft also had an SDRAM capture-point selector; see D-016.)

Build 001 put both as revisions of one `Arcade-ITech8.qpf`; the debug one
was only reachable from Quartus's revision list and went unnoticed. From
build 002 each has its own project file, `Arcade-ITech8.qpf` and
`Arcade-ITech8_debug.qpf`. Their outputs keep Quartus's names; since MiSTer
loads the matching `.rbf` that sorts last, only one of the two should be
in `_Arcade/cores` at a time.

## D-014 — Palette read-back is combinational

Found in simulation (attract mode, the title's fade-out): the game fades by
reading each colour back through the RAMDAC, decrementing it and writing it
back. The read value was registered on the read strobe, one clock after the
bus captured it, so every read returned the previous component and the fade
rotated the colours. The RAMDAC now presents its read value combinationally,
and the read side effects (latching the entry, advancing the address) happen
on the strobe as before.

## D-015 — Blitter engine: prefetch window and posted VRAM writes

Found in simulation: in gameplay about a quarter of the blits outlasted
MAME's busy time (`dbg_late`). The engine spent about twelve clocks per
pixel (one state per step, waiting for each VRAM write), against sixteen
allowed but more on every ROM word fetch. It now reads source bytes from a
two-word window that prefetches the next ROM word, takes one clock per
source byte, and posts each VRAM write so the next pixel is fetched while
it completes.

## D-016 — Fixes from an independent review of build 001

A separate review of the RTL, MRA and project files before the first
Quartus compile (by an agent that had not written them) found:

* **MRA md5.** MiSTer's `mra_loader.cpp` hashes each part's raw bytes in
  MRA order, before interleaving (`MD5Update` in `rom_data`). The first MRA
  carried the md5 of the assembled stream, so MiSTer would have discarded the
  ROM ("md5 mismatch for rom 0") and the core would have sat in reset. Now
  `f449778faa393bf8080bf702f40c72f6`, and `sim/mkroms.py` prints the value
  MiSTer computes.
* **SDRAM capture selector removed.** Switching it while reads were in
  flight could lose or duplicate a delivery and wedge a client. It also put
  a second register on every DQ pin, so the debug build could not keep the
  falling-edge capture register in the I/O cell and would have captured
  differently from production. The capture is now a single falling-edge
  register in both builds (D-003). If a board ever shows `SUMR` ≠ `SUMW`,
  the next step is a phase-shifted capture clock from the PLL, measured with
  the overlay.
* **Re-check at every reset.** An OSD reset now repeats the SDRAM read-back
  (about 90 ms, board held in reset), so `SUMR` can be re-measured without
  reloading the MRA.
* **NVRAM saving.** MiSTer only saves an arcade core's NVRAM on OSD open if
  the core asks (`ioctl_upload_req`). The core now asks whenever the 68000
  has written its RAM, and holds the 68000 (its clock enables) during the
  save so the image and the game's checksum are consistent.
* **Read-modify-write.** The bus logic now performs the write half of a TAS
  (AS stays low while the strobes drop between the halves). Ninja Clowns
  has no TAS in code, so this is for later games.
* Smaller: `reset` is registered in `clk_sys`; `ioctl_wait` is held while
  the SDRAM initialises; `rtl/pll.qip` was listed twice (`sys/pll_q17.qip`
  already adds it); `hps_io` stores the long OSD string in block RAM
  (`CONF_STR_BRAM`).

Noted, not changed: ACT to READ is one 48 MHz clock (20.8 ns). The -7 grade
of the AS4C32M16SB and AS4C16M16SA specifies tRCD 21 ns, and READ with
auto-precharge relies on the chip holding precharge off until tRAS. Other
MiSTer cores run the same chips with the same 20.8 ns (two clocks at
96 MHz).

## D-017 — NVRAM made safe against a zero image (build 002)

First hardware run of build 001: self-test, "SYSTEM STATUS OK", then a black
screen. That is exactly the simulation with zeroed NVRAM (D-011): all-zero
RAM passes the game's checksum, the defaults are never written, the credit
setting at 0x104 stays 0, and the divide at 0x17450 traps into the error
handler loop at 0x18080. With FF the game prints "SYSTEM INITIALIZED"
instead, and with a valid image (warm reset, or a saved file) it prints
"SYSTEM STATUS OK" and reaches the title; both were simulated for build 002.

What MiSTer does, from `Main_MiSTer` (`support/arcade/mra_loader.cpp`,
`menu.cpp`): the saved `.nvm` is sent as ioctl index 4 after the ROMs only
if the file exists; it is saved only when the OSD opens and the core has
raised `ioctl_upload_req`. The save reads back correctly (checked against
`hps_io`'s upload path and Main's strobe/ack handshake). Because the whole
16 KB is the 68000's work RAM, the core raises the request within
microseconds of boot, so every OSD open saves a snapshot, including one of
a crashed game. Once a zero-settings image is saved it comes back on every
boot.

How the RAM held zeros on the first boot is not proven yet (the overlay
rows below are there to show it). Build 002 closes every path found:

* **FF from configuration.** The NVRAM's M10K blocks are initialised to FF
  in the bitstream (`it8_dpram` `INIT`), so the RAM is never zeros, even if
  the loader's fill never runs.
* **The fill cannot be missed.** The loader took its download edge even
  while held in reset (`~sd_ready`), so a download starting during SDRAM
  initialisation skipped the fill. Edges are now taken only outside reset.
  Simulated with the download started at clock 100.
* **An all-zero file is refused.** If every byte of the index 4 download is
  zero, the loader runs the FF fill again. The game never saves such a
  state (its defaults routine at 0x1E6F6 sets 0x104 to 1). The board stays
  in reset while any fill runs.
* **Measured on the overlay (debug build).** `NVST`: FF fills, files
  loaded, zero files replaced (one hex digit each), then saves. `N104`: the
  long at RAM 0x104 as the 68000 last read or wrote it. 0 there means the
  game accepted a bad image.

Not changed: a file that is not all zeros loads as it is, as in MAME. A file
saved while build 001 was crashed has zero settings and a non-zero stack, so
it passes the new check; it has to be deleted by hand
(`config/nvram/Ninja Clowns (27 oct 91).nvm` on the SD card).
