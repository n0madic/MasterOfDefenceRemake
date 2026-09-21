# 01. Overview: engine, files, launch, main loop

## What kind of game this is

Tower defense from Voodoo Dimention (2006), version **1.67e** ("v1.67" + letter "e",
[code: `_2_begin`], `_vgameversion = 1.67`). A campaign of 6 locations / 180 raids, three
difficulty levels ("titles"), Survival mode, an online high-score table
(`http://www.master-of-defense.com/scores.php`).

## Engine and binaries

| File | What it is |
|---|---|
| `MasterOfDefense.exe` (16 MB) | **Inno Setup 5.1.2** installer, contains what's unpacked below |
| `Main.exe` (2 MB) | The game. **Blitz3D** (BlitzBasic 3D, DirectX 7) — the `bbruntime` runtime is linked into the exe, and the compiled program sits in resource `RCDATA/1111` (see [02-data-formats.md](02-data-formats.md#blitz-module-format-in-the-exe)) |
| `RunProgram.dll` | Userlib for Blitz3D: `RunProgram` (launches `GetFullVersion.exe`/the browser), window icons |
| `GetFullVersion.exe` | Opens the purchase page (demo functionality) |
| `Settings.vdd` | INI settings (`[Options]`) |
| `Saves/` | Save files (empty in the distribution) |
| `Data/` | All game assets |

Blitz3D community libraries used (identifiable by function prefixes):
`_fext_*` — B3D Extensions (scene loader with `B3DEXT_*`/`B3D_ORDR_*` tags),
`_fe*`/`_fewidget` — GUI library (buttons, sliders, 3D text),
`_fflux_*` — tweening (moving the balloon), `_fvd_*` — timers, `_fmid_*` — music playlist,
`_fcrc_*`, `_fb64*`, `_fxorstring` — CRC/Base64/XOR for file checks and high-score submission.

Demo mode: `_fcheckgamestate` reads byte `0x7C0` from `Data/Menu/Demo.bmp` and byte `0x8F`
from `Data/Menu/preved.png`; if both equal `0x3D` ("=") — full version, otherwise demo.
**In this unpacked build both bytes = `0x3C`, i.e. `_vdemomode = 1`** [verified with `xxd`]:
after raid 37 (`_vcurlevel > 0x25`) the game saves to `Automatic.sav` and shows the
"Register now" screen (`Loader/demo.b3d`); Survival ("hardcore") is unavailable ("Not available in
demo version"). All six locations' data is nevertheless present on disk; to run the
full version it's enough to change both bytes to `0x3D`.

`_fcheckgamefiles` computes a CRC (`_fgetstringpart`) of `Units.csv`, `Raids.csv`,
`RaidsData1..6.csv`, `Tower1..5.csv` and compares it to a hardcoded string
`CF194C1A…BCA7`. **Editing any of these CSVs breaks the original's launch** ("Some of game files
corrupted") [code: `_fcheckgamefiles`].

## Startup sequence [code: `_2_begin`]

1. Initialize globals (see constants in [08](08-economy-lives-difficulty.md)), `_fcrc_init`,
   `_fcheckgamefiles`, read `Settings.vdd` (`_freaddata`), `_fstartlogfile` log.
2. `_floadsounds` (all wavs, `menu.ogg` as the menu's background music).
3. Graphics: `_feinit(XRes, YRes, ColorDepth, Windowed, title)`, camera FOV 60°
   (`_fsetfov(cam, 60)`), listener, `_finitgui`, `_finitbalancedata`, `_floadgametexts`.
4. Menu loop: `_floadmenu` → `_fshowmenu` (returns 2 = exit) → `_funloadmenu`.
   On first entry into the game: `_fguicreateingamebuttons`, `_finitlocationsinfo`, `_floaddata`
   (CSV), `_floadgraphics` (models), `_fcreateingamemenu`.
5. Depending on the choice: new game (`_vstartnewgame`: location 1, map, tutorial),
   continue (`_floadgame("Automatic.sav")` + `_floadlocation`), survival
   (`_finitsurvival`, location 2).
6. `_fmainloop` — returns 0 (exit), 1 (restart graphics after a settings change),
   2 (to menu).

## Main loop and time model [code: `_fmainloop`]

Fixed logic step with a "catch-up" renderer:

```
period_ms = 1000 \ fps                 ; integer division; fpsl\fps, default 60 → 16 ms (62.5 ticks/s)
elapsed   = Millisecs() - fpsl\last
ticks     = elapsed / period_ms        ; run the logic this many times
for i = 1 .. ticks:
    _fgamelogic()                      ; if _vgamelogicupdate = 1
    handle menu/save keys, _fupdateplayer, _fupdateevents, UpdateWorld(1), _fflux_update(1)
RenderWorld(tween); 2D (texts, GUI); Flip(vsync)
```

- **Game speed** is set by the time slider: `fps = 40 + slider` (slider 0..100,
  default 20 → `fps = 60`) [code: `_fhandlegui`, disassembly: `fld 40.0; fadd`].
  Key **N** → fps 60 (slider 20), **M** → fps 120 (slider 100). All movement/timer
  constants are defined "per tick", so speeding up is linear.
- **The real tick rate is not `fps`, but `1000 \ (1000 \ fps)`**: the period is computed
  as an integer, so `fps = 60` gives 16 ms = **62.5 ticks/s**, and `fps = 120` gives 8 ms =
  125 ticks/s. The leftover milliseconds carry over to the next frame (`fpsl\last += ticks·period`).
  In this documentation "60 Hz" and "60 ticks/s" mean exactly this mode (slider 20, 16 ms).
- When the window is inactive, the logic is paused (`_vmainloooppaused`).
- One logic tick = `_fgamelogic` (see below) + `UpdateWorld(1)` (Blitz animations).

### `_fgamelogic` (update order within a tick) [code: `_fgamelogic`]

If the skills window is not open (`_vupgadeswindowshown = 0`):

1. `_fhandlelevels` — raid spawn timer (if `_vlevelfinished = 1`).
2. Keys: Space/Alt — show/hide monster health; U/R — upgrade the selected
   tower; Tab — next tower; 1..5 — build a tower (4 and 5 only if
   Cold/Fire Magic is unlocked).
3. `_fhandledecorates` (clock on location 1, eagle on 2), `_fupdateenemies`,
   `_fupdatedeathanims`, `_fhandletowers`, `_fhandleballoons`, `_fupdatebullets`,
   `_fhandlebombs`, `_fupdateexplosions`, `_fupdatelocation` (river/border texture animation).

Always: `_feupdategui`, build mode (`_fplacetower`), `_fhandlegui` (buttons),
`_fhandletutorial`, drawing text/messages/tooltips/cursor.

The skills window **stops all monsters and towers** (logic doesn't run), but the GUI
keeps working.

## Hotkeys (DirectInput scan codes) [code: `_fmainloop`, `_fgamelogic`]

| Key | Action |
|---|---|
| Esc (0x01) / P (0x19) / F10 (0x44) | In-game menu (pause) |
| N (0x31) / M (0x32) | Normal / fast speed |
| F5 (0x3F) | Save `Save.sav` (only between raids, not in survival or on "insane") |
| F9 (0x43) | Load `Save.sav` |
| F2 (0x3C) / E (0x12) | Skills window (only from location 2 onward) |
| Space (0x39) / Alt (0x38) | Show/hide monster health |
| U (0x16) / R (0x13) | Upgrade the selected tower |
| Tab (0x0F) | Switch selection to the next tower (if towers > 3) |
| 1–5 (0x02–0x06) | Build Land / Magic / Plant / Icerock / Flame |
| F8 (0x42, hold) | Screenshot `<millisecs>.bmp` |
| W/A/S/D, arrows, screen edge | Scroll the camera |
| LMB | Select tower/monster, place a tower |
| RMB | Cancel building, deselect; on the road — move the balloon |
