# 13. HUD geometry, `gui.png` atlas, 3D text, tooltips

A supplement to [09](09-ui-menus-tutorial.md): exact coordinates and drawing rules for the
entire in-game interface. Everything is **[code]** unless noted otherwise. A machine-readable
dump of the panel is `data/hud_layout.json` (produced by `tools/hud_layout.py`).

## Coordinate system

- Virtual screen **800×600**; physical coordinates = virtual ×
  `_vresaspect = W/800`, `_vresaspecty = H/600` [code: `_finitgui`, `_fewidget`, `_fetext3d`].
- The "Eniretu" GUI library (`_fe*`, type `teniretu`) draws everything as quads of a single mesh
  attached to **the same game camera** (`_vcamera`, created in `_feinit`), on the plane
  `z = 8` in front of the camera [code: `_feinit`, `_fepick2d`]. The camera has a 60° horizontal FOV
  (`CameraZoom = 1/tan 30°`), so at distance `d` the visible half-width is `d·tan 30°`, and
  the half-height is `·600/800` (Blitz3D scales the vertical by `H/W`).
- All sizes below are virtual pixels; `(x, y)` is the top-left corner.

## `gui.png` atlas (512×512)

`_fequad(x, y, w, h, u0, v0, u1, v1, …)` **halves U** before sampling (V is left alone):
atlas pixel = `(512·u/2, 512·v)`. Hence the layout [code: `_fequad`, `_fedrawwidget`]:

| Area | Atlas pixels | Contents |
|---|---|---|
| Font | x 0–255, y 256–511 | 16×16 glyphs, 16 px each, index = cp1251 byte (row `c \ 16`, column `c mod 16`) |
| Large buttons (style 0) | x 256 / 320 / 384, y `64·(i−1)`, 64×64 | i = 1 Land, 2 Magic, 3 Plant, 4 Icerock, 5 Flame, 6 Upgrade, 7 Sell, 8 Balloon; columns: normal / **hover** / **pressed** (column x 448 isn't used by the code) |
| Small buttons, style 1 | x `192 + 32·(i−1)`, y 64 / 96 / 128, 32×32 | skill "+" (i=1), OK/checkmark (2), tutorial Next (9), Show/Hide health (10) |
| Small buttons, style 2 | x `128 + 32·(i−1)`, y 160 / 192 / 224, 32×32 | Load (i=0), Menu (1), Magic&Skills/Cancel-"−" (2/4), Save (3), skill "−" (11), Stop attack (12) |
| Panel/tooltip frame | x 0–32, y 192–224 (black, alpha 128; the first row is transparent) | 9-slice for tooltips, the help window (`_feblock` u 0..0.0625, v 0.375..0.4375) |
| Slider: track | u 0.25–0.375 → x 64–96, y 128–144 | edges of `_vslideredge = 7` px |
| Slider: handle | x 64–96, y 160–192 (32×32) | |
| Progress bar: frame | x 0–64, y 128–160; fill x 0–64, y 160–192 | the fill is tiled in chunks ≤ 64 px |
| Checkbox | x 192 / 208 / 224 (normal / held / pressed), y 32 (off) / 48 (on), 16×16, drawn at 20×20 | |

In all three styles the variant order is: normal / hover / pressed. Widget state
`state`: 0 normal, 1 pressed (mouse button held over it), 2 hover
[code: `_fupdatebutton`, `_fedrawwidget`]. State 3 (`+0x20 = 1`, "locked")
is drawn the same as normal.

9-slice: `_feblock(x, y, w, h, u0, v0, u1, v1, corner, r, g, b, a, mask=0x1FF)` — corner
size `corner` px (`_vbuttoncorner = 6`, `_vprogressbarcorner`, `_vgroupboxcorner`); the mask
bits enable the 9 parts. **Eniretu's U coordinates are given in fractions of 256 px, V in fractions of
512 px** (`_ferollout` divides by `edge/256`; checkbox u 0.75 → x 192): converting to
atlas pixels gives `x = u·256`, `y = v·512`.

Settings widgets (`_fedrawwidget`): radio button (type 0x1001) — x 192/208/224, y 0 (off)
/ 16 (on), 16×16, drawn at 20×20, label at (x+18, y+2); checkbox (0x100c) — same
columns, y 32/48; text field (0x100b) — a block x 128–192, y 32–64 with corner
`_vtextboxcorner`, text at (x+2, y+h/2) vertically centered, the "_" cursor blinks once every
200 ms. Coordinates from `_fguicreateoptionsbuttons`: name (20,340)/(20,360,280×30), music
(20,430)/(20,460,280), sound (50,505)/(50,530,240), resolution (390,365) + radio
(380,380) (380,400) (520,380) (520,400), VSync (360,440)/(470,465), Windowed (380,520),
Gamma (360,542)/(450,544,200), color (700,365) + radio (710,380) (710,400).

<a id="3d-text"></a>

## 3D text [code: `_fetext3d`, `_ftextwidth`, `_ftextheight`]

```
EText3D(x, y, text, halign, valign, scale, spacing, width, height, unused, r, g, b, alpha)
```

- A glyph is a `16·scale` px square; the step between characters is `scale·(16 − spacing)`
  (`spacing` = 5 for regular text → 11 px at scale 1; 7 for tooltips → 9·0.8).
- `TextWidth = Len(text)·(16 − spacing)·scale`, `TextHeight = 16·scale`.
- `halign = 1` — center on X (shift by −TextWidth/2), `valign = 1` — center on Y.
- `height > 0` overrides the glyph height (only used by window titles), `−1` = 16·scale.
- A space only advances the cursor. **The first glyph is drawn offset by one step
  from `x`** (the column counter is incremented before drawing).
- Tags within a string: `<vd>` — line break (y += 0.8·TextHeight, column = 0);
  `<colR=nnn>`, `<colG=nnn>`, `<colB=nnn>` — color change (exactly 3 digits).
- `alpha = −1` — alpha is taken per letter from `_astorylettersalpha[i]` (the storyline
  and tutorial "reveal" effect, see [09](09-ui-menus-tutorial.md#menu-animations)).

In-game text colors: gold (255,203,0); inhabitants (110,200,230); pending "+N" inhabitants
(180,227,242) scale 0.9 spacing 4; experience (247,232,172); "Raid: k/n" and the info panel —
white; tooltips — white 0.8; skill descriptions (247,232,171) 0.8; storyline/tutorial
(0,255,130) scale 0.95/1.0, spacing 5/4.5; the menu's game version at (700,580) (247,232,172).

## HUD panel `Data/Env.b3d`

The scene is attached to the camera with offset `(0,0,10)`; all quads sit at local `z ≈ −3`
(depth 7) [code: `_floadgraphics`]. At the moment it's attached, the camera sits at the origin
with no rotation (`_funloadmenu` does `PositionEntity/RotateEntity(camera, 0,0,0)` before
`_floadgraphics`) [code: `_funloadmenu`, `_2_begin`]. Projected into 800×600
(`tools/hud_layout.py`, rounded to 1 px):

| Node | Texture | x | y | w | h | Role |
|---|---|---|---|---|---|---|
| `leftside` | wood.png | −1 | 509 | 396 | 111 | bottom-left panel (tower buttons, slider) |
| `rightside` | wood.png | 541 | 509 | 396 | 111 | bottom-right panel (Upgrade/Sell) |
| `Plane10` | woodtext.png | −18 | 461 | 829 | 155 | backing of the bottom panel |
| `infopanel` | woodtext.png | 379 | 469 | 281 | 140 | info panel (text `_vindicatortext` at (400,500), portrait `faces.b3d`) |
| `leftUp` / `rightUp` | woodtext.png | −40 / 696 | −105 / −83 | 162 / 137 | 179 / 151 | corner "scrolls" |
| `goldIcon` | money.png | 1 | −4 | 35 | 35 | coin |
| `gold` | Lfon.png | 33 | −11 | 58 | 58 | gold plaque (text centered at (50,9)) |
| `expaIcon` | expa.png | 57 | 37 | 27 | 28 | experience icon |
| `expa` | Lfon.png | −2 | 22 | 58 | 58 | experience plaque (text centered at (15,41)) |
| `inhabsIcon` | lives.png | 772 | −5 | 30 | 30 | inhabitants icon |
| `inhabs` | Lfon.png | 742 | 18 | 58 | 58 | inhabitants plaque (text centered at (760,40), "+N" at (765,55)) |
| `raids` | woodtext.png | 265 | −97 | 263 | 142 | "Raid: k/n" banner (text at (330,5)) |
| `beguny` | timespeed.png | 397 | 481 | 202 | 25 | time-slider track |
| `reset` | timespeed.png | 432 | 477 | 16 | 25 | "reset" mark: clicking within x±10, y −10..+5 px of its projection sets the slider to 20 (60 Hz) [code: `_fhandlegui`] |
| `window` | window.png | 74 | 54 | 653 | 326 | window (hidden, unused) |
| `updates` | updates.png | 193 | 38 | 415 | 415 | "Magic and skills" window (`_vupdatesmesh`) |

The ` `/`B3DEXT_CAMERA` nodes in the file are the editor's camera; the game doesn't use it.

## Eniretu widgets [code: `_fguicreateingamebuttons`, `_fcreateupgbuttonscoords`]

`EButton(window, x, y, w, h, caption, icon, style, r, g, b)`; the tooltip is a
`Texts.txt` line index (`gametext[k]`, line k+1), assembled by `_fcreatetip`.

### Bottom panel (64×64, style 0, y = 530)

| Widget | x | icon | Tooltip |
|---|---|---|---|
| Land | 5 | 1 | `[21]` + `_ftowerinfo(1)` |
| Magic | 70 | 2 | `[22]` + info |
| Plant | 135 | 3 | `[23]` + info |
| Icerock | 200 | 4 | `[24]` + info (button hidden until the Cold skill) |
| Flame | 265 | 5 | `[25]` + info (hidden until the Fire skill) |
| Balloon | 300 | 8 | `[89]` Go to Balloon (hidden until the balloon exists) |
| Time slider | 400, 500, 190×20 | — | `[31]`; value 0..100, `fps = 40 + value` |
| Upgrade | 664 | 6 | `[26]` + next-level info; `[27]` at the maximum; `[26]+[76]` "Select tower first" with nothing selected; empty during the upgrade animation |
| Sell | 737 | 7 | `[29]` + `<vd><colR=255><colG=203><colB=000>` N `[30]`, N = `Round(sellRate·spent)`; `[28]` with nothing selected |
| Upgrade progress bar | 648, 512, 152×32 | — | 0..100 with no label (the widget's text is empty; "Updating..." is overridden in the code); the frame is the atlas block (0,128)–(64,160), corner 8, always visible; the fill is ≤64 px strips from (0,160)–(64,192), edge 8 / trim 3 |
| Stop/Start attack | 590, 520, 30×30 | 12, style 2 | `[100]`/`[101]` by `tower.stopped`; only shown for a selected tower with `freeze·coldMagic > 0` (Icerock) [code: `_ftowerinfo`] |

### Top row (32×32, y = −3, style 2)

| Widget | x | icon | Tooltip |
|---|---|---|---|
| Menu | 278 | 1 | `[67]` Show quick menu (pause) |
| Save | 310 | 3 | `[65]` (visible between raids; hidden on difficulty 2) |
| Load | 450 | 0 | `[66]` |
| Show/Hide health | 483 | 10, style 1 | `[79]`/`[80]` by `_vshowunitslifemode` |
| Magic and skills | 600, 480, 35×35 | 2, style 2 | `[68]` |

### Skills window (`updates`)

"+" buttons (style 1, icon 1) at x = 520 and "−" buttons (style 2, icon 11) at x = 550, 30×30, per row:

| y | Skill | Level text (x=470) | "+" tooltip | "−" tooltip |
|---|---|---|---|---|
| 105 | Cold magic | y 113 | `[61]` | `[96]` |
| 135 | Fire magic | 141 | `[62]`; at level 5 — `[87]` in gold (255,207,115) | `[97]` |
| 165 | Poison magic | 172 | `[63]` | `[98]` |
| 202 | Attack speed | 212 | `[36]` | `[94]` |
| 233 | Attack range | 240 | `[37]` | `[95]` |
| 263 | Damage | 266 | `[35]` | `[93]` |
| 293 | Sell rate | 295 | `[34]` | `[92]` |
| 328 | People resistance | 335 | `[64]` | `[99]` |
| 360 | Gold income | 365 | `[32]` | `[91]` |

"+" tooltip format: `[k]<vd><colR=247><colG=232><colB=172>[33]: <price> [60]`
("Cost: N exp points"); `[78]` once the maximum is reached. For "−": `[k]<vd>…[90]: <price/2> [60]`
("Return: N exp points"). At the same time, `_vhelpstoshow` is set to the `Helps.txt`
line for the skill (indices 0..8: cold, fire, poison, speed, range, damage, sell, resistance, gold),
which `_fdrawhelps` draws inside a 185 px-wide frame at point (15, 120) physical px, if
`ShowHelp` is enabled. The header "Your experience points: N" is at (240, 62), color (0,200,120).
OK — (530, 405) 35×35 style 1 icon 2; Cancel — (335, 402) 35×35 style 2 icon 4.
The damage "−" button (`_vdowngrdamagebtn`) is hidden at creation — damage can't be lowered.

### Tutorial

Next — (665, 345) 32×32 style 1 icon 9; "Skip this tutorial" checkbox (`[81]`) — (100, 345);
page text — (100, 105), scale 1, spacing 4.5, color (0,255,130), per-letter alpha.

`_fcreateupgbuttonscoords` creates three `tupgbuttonst` at (200/265/330, 530) — coordinates
of the Icerock/Flame/Balloon buttons for `_fupdateupgradebuttons` (buttons shift left when
earlier ones are hidden).

## Tooltips [code: `_fupdatebutton`, `_fcreatetip`, `_fdrawtips`]

- The tooltip is built on **hover** without a click (state 2) every tick and
  reset after drawing (no appearance delay).
- The frame is 175 px wide; the number of lines `n = CountInstr(tip, "<vd>") + 1`, text height
  `th = n·12.8` (scale 0.8).
- Position: `x = mouseX − 16 − max(0, 170·aspect − (W − mouseX))` (pinned to the right
  edge), `y = mouseY − th`; the frame is drawn from `y − 6.4` with height `th + 12.8`, text at `(x, y)`
  in white, spacing 7.
- Sound `rebutton.wav` on the first hover over a 3D-menu item; Eniretu buttons have no
  hover sound, a click plays `click.wav` from the event handler.

## Widget events [code: `_fupdatebutton`, `_feupdategui`]

A button generates a `tevent` ("1") on the tick the mouse is **released** over it, if the
press also started over it (`+0x68+8 = 1`); pressing sets `_vsomebuttonpressed = 1`, which blocks
clicks on the scene during that tick.
