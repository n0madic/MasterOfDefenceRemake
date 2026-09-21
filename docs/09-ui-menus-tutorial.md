# 09. Interface, menus, tutorial, messages, sound

The interface is Blitz3D 3D scenes (menus — `Data/Menu/*.b3d` with "item" meshes that
`CameraPick` is run against) plus the 2D GUI libraries `_fe*` (buttons from the atlas `gui.png`,
slider, progress bar, checkbox) at a virtual resolution of **800×600** (scale
`_vresaspect = width/800`, `_vresaspecty = height/600`) [code: `_2_begin`, `_feinit`].

## Main menu [code: `_floadmenu`, `_fshowmenu`]

Scenes `Menu/env.b3d` (environment with trees/castle), `buttons.b3d`, `playgame.b3d`
(submenu), `sel.b3d` (selection cursor), `loading.b3d`, `credits.b3d`, `cameraenv.b3d`
(camera fly-through). Items (node names): `start` → submenu (`new`, `hard`, `insane`,
`continue`, `hardcore` = survival, `ok`), `settings`, `highscores` (opens a URL),
`credits`, `buynow`/`buynow1` (demo), `exit`. `continue` is active if
`Saves/Automatic.sav` exists. The submenu's "unfold" animation depends on `MenusOpened`
(how many difficulties are unlocked). Textures `Titul1..3.png` — titles. Menu music `menu.ogg`.

## Menu animations [code: `_floadmenu`, `_fshowmenu`, `_fhandlepunkts`, `_fcreatepunkt`]

Every screen is a B3D scene placed 10 units in front of the camera (`PointEntity` toward the camera,
`EntityParent`, `TranslateEntity 0,0,10`); `TurnEntity 45,0,0` merely compensates for the
game camera's 45° downward tilt (`_floadgraphics`), so relative to the camera the sheet sits
frontally (verified against a screenshot of the original's map). `Animate(mesh, mode, speed, seq)` speeds are in frames per tick (60 Hz):

| Scene | Mode | Speed | What |
|---|---|---|---|
| `Menu/env.b3d` (background) | loop | 0.1 | main menu environment |
| `Menu/cameraenv.b3d` | one-shot ±0.25 | | camera fly-through entering/leaving settings; the camera `AlignToVector`/`OrientEntity`s to the scene's camera every tick |
| `Menu/buttons.b3d` | one-shot ±0.25 | | buttons leaving/returning; the settings GUI is shown once `AnimTime ≥ 16` |
| `Menu/playgame.b3d` | one-shot ±0.5, seq `MenusOpened+1` | | difficulty submenu unfolding; seq 1/2/3 = frames 0–6 / 8–14 / 16–22 (by number of unlocked difficulties) |
| `Menu/credits.b3d` | one-shot 0.3 / −0.5 | | credits roll; item `ok` goes back |
| `Menu/loading.b3d` | one-shot 0.2, seq 1 (frames 0–10) | | "loading" splash; once `AnimTime > 9.9` the menu ends and the game starts (`fon` order −5, `loading` −6) |
| `Menu/sel.b3d` (selection cursor) | loop 0.2, seq 2 (frames 3–13; sequences 1/2/3 = 0–3 / 3–13 / 13–23) | | copied for each item (`_fcreatepunkt`) |
| `Menu/map.b3d` | `SetAnimTime(L − 0.001)` | | frame = location number (flag position); the current location's flag is tinted (255,203,0) |
| `Menu/ingame.b3d` | one-shot ±0.4 | | in-game menu; sliders `music.b3d`/`sound.b3d`: `SetAnimTime(99.99 − vol·100)` |
| `Menu/congr.b3d`, `gameover.b3d` | one-shot 0.4 | | congratulations / game over |
| `Menu/Send.b3d` / `SendTD.b3d` | one-shot 0.6 | | high-score submission (survival — `Send`: `hs_send`/`hs_restart`/`hs_tomenu`; campaign — `SendTD`: `hs_send`/`hs_dont`); in the remake the send/dont planks are hidden, the score is recorded locally |
| `Additional/end.b3d` (final credits) | **loop** 0.03 | | exits only on a mouse click or key press (`_fhandlefinaltitres`); then `CurrentTitul += 1` (up to 2), `MasterFlag = 1` after the third playthrough |
| `tutorial.b3d` | — | | `_fsettutorialpage(state−1)` on Next: frame = page − 1 (frame 0 has pointers to gold/inhabitants, frame 2 has the window moved off-screen); pages 8–10 don't change the frame |

Menu items (`tpunktt`): a scene node with `EntityPickMode 2`, node name = the object's handle.
Hovering (`CameraPick` under the cursor) — a copy of `sel.b3d` is aligned to the node, rotated
90° on X; brightness (`EntityColor` ×255) rises by **0.2/tick up to 0.9**, then to 1.0; as the
cursor leaves it fades by **0.05/tick** down to 0.1, then hides; on first hover —
`rebutton.wav`. A click is `_fcamerapick` on `_vmc`. In the demo, `hardcore` shows the tooltip
"Not available in demo version". The game version (`_vgameversionfull`) is drawn at (700,580).

The `titul` header in `buttons.b3d` receives texture `Menu/titul<MenusOpened+MasterFlag>.png`
(hidden while `MenusOpened < 1`).

### Text reveal (storyline, tutorial) [code: `_fclearstorylettersalphadata`, `_fdrawstoryline`, `_fhandletutorial`]

Not a "typewriter" effect, but a per-letter fade-in: for each of 1000 positions
`alpha[i] = 0`, `inc[i] = Rnd(a, b)`; every tick `alpha[i] += inc[i]` up to 1. Ranges:
map (storyline) `Rnd(0.005, 0.015)`, tutorial page `Rnd(0.01, 0.03)`, when leaving the
map `Rnd(0.008, 0.02)`. Storyline text — `Storyline.txt[L]` at (470, 420), scale 0.95,
color (0,255,130), `alpha = −1` (see [13](13-hud-geometry.md#3d-text)).

## Settings [code: `_fguicreateoptionsbuttons`, `_fhandleoptionsgui`, `_fsaveoptions`]

Resolution radio buttons (640×480, 800×600, 1024×768, 1280×960), color 16/32, checkboxes
Windowed and VSync ("Uncheck this option only if the game runs slowly"), sliders Gamma,
Music volume, Sound volume, a player-name field (coordinates in [13](13-hud-geometry.md)).
Entering: item `settings` → `Animate(cameraenv, one-shot, 0.25)` and `Animate(buttons, 0.25)`,
items other than `ok` lose `EntityPickMode`; widgets are shown once `AnimTime(cameraenv) ≥ 16`.
Leaving: `ok` → both animations run at −0.25, `_fsaveoptions`; a graphics change makes `_fmainloop` return 1
and graphics are reinitialized.

The in-game menu (`_fhandleingamemenu`): the `ingame.b3d` sheet rotates toward the
cursor every tick — `RotateEntity(menu, −(my − H/2) \ (H/30), (mx − W/2) \ (W/40), 0)` (as integers,
±15°/±20°) relative to the camera; while shown `_vgamelogicupdate = 0`, enemies are
hidden, fps is forced to 60. The sliders — `music.b3d`/`sound.b3d` as children of nodes
`themusic`/`thesound`; while the button over `musicback`/`soundback` is held, the frame is picked by
`_fcalcposfordragger` (out of 100 frames, the one whose slider projection is closest to the cursor is taken),
`vol = 1 − AnimTime/100`.

## In-game HUD [code: `_fguicreateingamebuttons`, `_fdrawalltexts`]

Full geometry (every button, the `gui.png` atlas, the `Env.b3d` panel, the font, tooltips) is
in [13](13-hud-geometry.md).

Coordinates in 800×600 (64×64 buttons on the `window.png` panel):

| Element | Position | Purpose |
|---|---|---|
| Land / Magic / Plant / Icerock / Flame | (5,530) (70,530) (135,530) (200,530) (265,530) | build a tower (Icerock/Flame appear once the skills are unlocked) |
| Balloon | (300,530) | "Go to Balloon" |
| Time slider | (400,500) 190×20, 0..100 | speed: fps = 40 + value; "reset" label |
| Upgrade / Sell | (664,530) (737,530) | upgrade/sell the selected tower |
| Menu / Save / Load / Show-Hide health | (278,−3) (310,−3) (450,−3) (483,−3), 32×32 | top row |
| Magic&Skills / Stop attack | (600,480) 35×35 / (590,520) 30×30 | skills window; "Stop attack" only for Icerock |
| Gold | text at (50,9), centered | `_vgold`, icon `money.png` |
| Inhabitants | (760,40), "+N" (765,55) | `_vlifes`, pending `_vextralifes`; icon `lives.png` |
| Experience | (15,41) | `_vexperience`, icon `expa.png` |
| Raid | (330,5) "Raid: k/n" | k = `curlevel − first[L] + 1`, n = raids in the location; in survival — the raid number |
| Upgrade progress | progress bar | `AnimTime·10` during the upgrade animation |
| Info panel | text `_vindicatortext` + portrait `faces.b3d` | tower or monster |
| Tooltips | `_fcreatetip` | pop-up button descriptions from Texts.txt |

Skills window — `updates.png`/`Env.b3d` ("updates"), "+"/"−" buttons for each skill, OK
(530,405), Cancel (335,402), level and price texts (`_fdrawupgradestexts`), descriptions from
Helps.txt when `ShowHelp` is set.

## Messages [code: `_fcreatemessage(text, type, ms)`, `_fdrawmessages`]

A list of messages, new ones are inserted at the front; type sets the color: 1 — white, 2 — red +
`warning.wav` sound, 3 — gold (255,203,0), 4 — green. Duration in ms
(e.g. 1500 — "Game saved", 3000 — end of raid, 5000 — hiring inhabitants). Floating
"+N" over a killed monster — `_fcreategoldmsg` (`_fdrawgoldmsgs`).

## Tutorial [code: `_fhandletutorial`, `_fnexttutorialpage`, `_ftutorialstep`, `_fdisabletutorial`]

Mesh `tutorial.b3d` (frames = page images), text — `Tutorial.txt[state]`
(line state+1), Next button (665,345), "Skip this tutorial" checkbox (100,345)
(sets `TutorialDisable=1`; only shown on location 1 and for pages < 10). While the tutorial is active (`tutorialmode = 1`, including hidden states 3 and 5), the spawn timer is reset.

| State | Location | Text (Tutorial.txt line) | Transition |
|---|---|---|---|
| 1 | 1 | L2: gold/inhabitants, scrolling | Next |
| 2 | 1 | L3: towers, "build a tower" | Next (window hides, message "Your task: Build tower", 2 s) or clicking a tower button (`_ftutorialstep(2,1)`, no message) |
| 3 | 1 | (hidden) | tower placed (`_ftutorialstep(3,0)`) |
| 4 | 1 | L5: upgrade | Next (jumps straight to page 5) or Upgrade pressed (`_ftutorialstep(4,0)`, window hides until the animation ends) |
| 5 | 1 | L6: selling | Next or Sell |
| 6 | 1 | L7: time slider | Next |
| 7 | 1 | L8: "monsters are coming", saving, Space/Alt | Next → tutorial turns off, message L55 (3 s), timer −5 |
| 8 | 2 | L9: experience and skills | Next → `_fshowupgradeswindow` (the skills window opens **after** the page) and turns off |
| 9 | 4 | L10: the balloon | Next → turns off |
| 10 | any | L11: hotkeys (Help button) | Next → turns off |

States 1/8/9 are set on entering locations 1/2/4 from the map (`_fhandlemapmenu`),
if `TutorialDisable = 0`.

## Map and transitions [code: `_floadmapmenu`, `_fhandlemapmenu`, `_fdrawstoryline`]

`Menu/map.b3d` + `map.jpg`; item `point` (current location's flag) and `map_continue`.
The storyline text `Storyline.txt[L]` is printed letter by letter (`_astorylettersalpha/inc`).
On pressing "continue": the location loads, `_frestartlocation(0)`, tutorial (1/2/4),
save `Location<L>.sav` and `Automatic.sav`, a message about hiring inhabitants.

The "Congratulations" screen (`congr.b3d`, item `cook`) appears after the location's last raid;
`gameover.b3d` (`gorestart`, `gotomenu`) — both sheets hang on the camera over the
still-loaded location (`_vgamelogicupdate = 0`, enemies remain visible; the location
is only unloaded once a choice is made on the sheet); the high-score screen `Send.b3d`/`SendTD.b3d`
(`hs_send`, `hs_dont`/`hs_restart`/`hs_tomenu`; after survival the sheet also hangs on the
location's camera, `TurnEntity 45` compensates for the camera tilt; "Your score is:N" — string 74,
at (250,260), scale 1.3, in gold, shown once the sheet's animation finishes; in the remake, instead of
the online table, there are two local tables below the line, and the line is moved up to the top of the frame);
credits `Additional/end.b3d`;
demo screen `Loader/demo.b3d` (`ngbuynow`, `ngexit`, `ngrestart`, `ngtomenu`).
In-game menu `Menu/ingame.b3d`: `back`, `restart` (location), `tomenu`, `exit`,
`help` (tutorial page 10), `music`/`sound` sliders.

## Sounds [code: `_floadsounds`]

`gsounds` slots (object `tgamesoundst`, field = offset/4):

| Slot | File | When |
|---|---|---|
| 1–5 | `military_build`, `magic_build`, `plant_build`, `freeze_build`, `fire_build` | building a type 1–5 tower |
| 6 | `click.wav` | clicking a button |
| 7–10 | `death1..4.wav` | monster death (random) |
| 11 | `tlen.wav` (loop) | background campfire crackle in the main menu |
| 12 | `feature.wav` | buying a skill |
| 13–16 | `kill1..4.wav` | a monster killed inhabitants |
| 17 | `warning.wav` | type-2 message |
| 18 | `update.wav` | upgrade finished |
| 19 | `water.wav` (loop, 3D at `door` on location 2) | river |
| 20 | `rebutton.wav` | hovering over a button |
| 21 | `start.wav` | raid start |
| 22 | `oops2.wav` | "not enough gold/experience" |
| 23 | `exp1.wav` | Land shot, bomb explosion |
| 24 | `exp2.wav` | Magic/Icerock shot |
| 25 | `check.wav` | checkbox |
| 26 | `eagle.wav` | eagle screech (**file missing from the distribution**) |
| 27 | `congr.wav` | congratulations |
| 28 | `gameover.wav` | defeat |
| 29 | `nokills.wav` | "monster killed by inhabitants" |

Not used by the code: `oops.wav`, `menu.wav` (`menu.ogg` plays in the menu instead).
Music: `music<L>.ogg` loops as a 3D sound on the camera at volume `MusicVol`
[code: `_fstartbackgroundmusic`].

## Texts.txt Indices

`gametext[k]` = line k+1. Usage (per the code):

| k | Line | Where |
|---|---|---|
| 0–2 | Upgrade, Sell tower, Land tower | tower panel / tooltips |
| 3–6 | Magic tower, Plant, Icerock, Flame | `_ftowerinfo` (name) |
| 7–12 | Land Damage … Fire power | `_ftowerinfo` |
| 13–20 | settings texts | `_fguicreateoptionsbuttons` |
| 21–37 | button tooltips | `_fcreatetip` |
| 38–45 | "Next level – air enemies!", "You have received a new tower…", etc. | unused by the code (legacy) |
| 50 | "You can save your game by clicking Save game…" | `_fnextlevel` after raids 10/34/58 |
| 46–48 | You have received / of your inhabitants were killed / Raid | `_fnextlevel`, HUD |
| 49 | Poison power | `_ftowerinfo` |
| 51–54 | tips after raids 3, 4, 1; "Build towers and UPGRADE" | `_fnextlevel`, `_fdisabletutorial` |
| 56–59 | Your task; Tower upgraded; Game saved; Game loaded | |
| 60–68 | skill and button tooltips | `_fcreatetip` |
| 69–73 | Life, Armor, Speed, Type: ground/air | `_fshowenemyinfoondisplay` |
| 74–75 | Your score is / Would you like to submit… | high-score screen |
| 76–81 | (Select tower first), To move baloon…, No more upgrades, Show/Hide health, Skip tutorial | |
| 82–88 | Your experience points, You have spent … people, Screenshot created, Magic towers will receive fire ability, monster was killed by your people | |
| 89–101 | Go to Balloon, Return, skill "−" button texts, Stop/Start attack | `_fcreatetip` |
