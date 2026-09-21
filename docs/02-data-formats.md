# 02. Data formats

All tables are CSV with a `;` delimiter, cp1251 encoding, CRLF line endings.
The game's parser (`_fsplitcsvline`) is **primitive**: the file is read whole, split into
tokens by `;` and by `CR`; `LF` stays inside the token (it's stripped separately for texts).
Tokens are packed into a global array `split_params[0..17000]`; looking up a label row
is done with `_ffindbyval(label)` — a case-insensitive comparison with `Trim`, values are
read as `split_params[label_index + k]`, where `k` is the column number (1-based). Consequence:
**row order doesn't matter, only the labels in the first column do**; extra rows are ignored.

## Units.csv — monsters [code: `_floaddata`]

34 units (id 1..34), columns = id. Rows read:

| Label | Type | Meaning |
|---|---|---|
| `Air:` | int | 1 — flying (id 7, 14, 21, 28: Ratter, Head, TwoEyed, Sepp) |
| `Name:` | str | Name = file names `Data/Monsters/<Name>.md2` + `<Name>.jpg` |
| `AnimSpeed:` | float | Walk animation speed multiplier |
| `Healer:` | int | Healing radius/strength (only id 31 "Health" = 40). The healer loads as `<Name>.b3d` (`Health.b3d`), not md2 |
| `Worker:` | int | 1 — "inhabitant" (id 32 Male, 33 Female, 34 Gnome): walks the road and **adds** a life, towers don't attack it |

Row `Monsters:` is a header only. Full list: 1 Crawl, 2 Hairy, 3 Natt, 4 Ugr,
5 Gor, 6 Fats, 7 Ratter✈, 8 Ded, 9 Dino, 10 Nite, 11 Mini, 12 Bobby, 13 Spi, 14 Head✈,
15 Zaur, 16 Spikey, 17 Mol, 18 Cat, 19 Skeleton, 20 Gend, 21 TwoEyed✈, 22 Dotle,
23 Thorn, 24 Sve, 25 Spryth, 26 Elle, 27 Rokk, 28 Sepp✈, 29 Tall, 30 Plant, 31 Health (healer),
32 Male, 33 Female, 34 Gnome (inhabitants). Dump: `data/units.json`.

## Tower1..5.csv — tower prototypes [code: `_floadtowerprototipesdata`]

`Tower<t>.csv`, t = 1 Land (military), 2 Magic, 3 Plant (nature), 4 Icerock (freeze),
5 Flame (fire). **`Tower6.csv` isn't loaded** (a copy of Tower1). Columns 1..11 =
upgrade levels 0..10 (column `k` → level `k-1`). Rows read:

| Label | Type | Prototype field | Usage |
|---|---|---|---|
| `LandDamage` | float | `+0x00` | damage to ground units |
| `AirDamage` | float | `+0x04` | damage to flying units |
| `AttackRange` | float | `+0x08` | radius (world units) |
| `RateOfFire` | int (ms) | `+0x28` | shot period; the tower fires when the timer (`+16` per tick) > RateOfFire |
| `Freeze` | int | `+0x0C` | base freeze strength |
| `Fire` | int | `+0x10` | base fire strength (Flame only) |
| `PoisonCoof` | int | `+0x14` | poison duration (ticks) × Poison Magic level |
| `PoisonDamage` | float | `+0x18` | poison damage per tick |
| `Splash` | float | `+0x1C` | read into the struct, **never used anywhere** |
| `TargetMethod` | int | `+0x20` | 1 — nearest in range, 2 — "sticky" target (see [05](05-towers.md)) |
| `PlaceOnRoad` | int | `+0x24` | 1 — can only be placed on the road (Flame) |
| `MaxUpgradesAmount` | int (column 1 only) | `+0x34` | maximum level |
| `BulletNames` | str | `+0x38` | `Data/Towers/<name>.b3d` — bullet model (identical adjacent names aren't reloaded) |
| `Price` | int | `+0x3C` | build price (column 1) / price to upgrade to level k-1 |

Rows `BaseModel`, `BangEffName`, `*Coof` (AirDamageCoof, LandDamageCoof, FreezeCoof,
FireCoof, SplashCoof, TargetCoof, PlaceOnRoadCoof, AttackRangeCoof) **are not read** —
they're notes left by the table generator (e.g. AttackRangeCoof=1.1 explains the geometric
progression of radius 10·1.1^k). Dump: `data/towers.json`.

## Raids.csv — raid composition [code: `_floaddata`]

Rows `Raid1`..`Raid205`, up to 25 monster ids; the first `0` terminates the list
(`raid\count = k-1`). Raid array `raids[1..200]`; the campaign ends at raid
**180**, so rows 181..205 are unreachable. A raid with **< 4 monsters is a boss raid**
(monsters get the boss flag). Dump: `data/raids.json`.

## RaidsData1..6.csv — per-location raid parameters [code: `_floaddata`]

Columns = the raid's ordinal number within the location. Rows read: `Life:`, `Speed:`, `Armor:`,
`Gold:`. Mapping to the global raid number: location `L` covers raids
`first[L] .. first[L+1]-1` (for L=6: `first[6] .. first[6]+45`), where
`first = {1, 16, 46, 71, 101, 136}`. The Russian rows at the bottom ("Total coefficient",
"flying-unit reduction coefficient", "speed-growth coefficient", "gold coefficient") **are not read** —
they're the parameters the author used to generate the series (Life = coefficient·n, Speed = 1+0.03n…).

| Field | Type | Meaning in-game |
|---|---|---|
| Life | int | base health × `_vunitslifemultyplier` (auto-balance, see [08](08-economy-lives-difficulty.md)) |
| Speed | float | movement speed = Speed/10 units per tick |
| Armor | int | subtracted from each bullet's damage |
| Gold | int | gold for a kill |

## RaidsData7.csv — Survival [code: `_floaddata`]

255 columns, 1..200 used. In survival the composition of raid n is generated randomly:
`count = n \ 18 + 10` monsters, each `Rand(1,30)` (i.e. including flying 7/14/21/28;
the code counts how many are multiples of 7, but the result is unused).

## Settings.vdd [code: `_freaddata`, `_freadvalue`, `_fwritevalue`]

INI format: section `[OPTIONS]` (case-insensitive lookup), `Key=Value`.

| Key | Default | Meaning |
|---|---|---|
| XRes, YRes, ColorDepth | 800, 600, 16 | screen mode (menu options: 640x480, 800x600, 1024x768, 1280x960; 16/32 bit) |
| Windowed | 1 | `Graphics3D` mode: 1 — fullscreen, 2 — windowed (windowed mode sets the `td.ico` icons) [code: `_feinit` → `_fgraphics3d(w,h,depth,mode)`] |
| VSync | 0 | `Flip` parameter |
| GammaIntensity | 0 | gamma |
| TimeForWin | 0 | if 1 (or Windowed=2) — a `Delay(1)` is added each tick to yield time to the system |
| DebugShow | 1 | debug output of FPS/stage timing (disabled in the distribution's file) |
| ShowHelp | 1 | show skill tooltips (disabled in the distribution's file) |
| SoundVol, MusicVol | 0.5, 0.5 | volumes |
| PlayerName | | name for the high-score table |
| TutorialDisable | 0 | 1 — tutorial disabled ("Skip this tutorial" checkbox) |
| GamedevMode | 0 | 1 — developer mode (inhabitant is always Gnome, etc.) |
| DeathMode | 0 | 0 — death animation `Death.b3d`, 1 — blood puddle `Death2.b3d` |
| CurrentTitul | 0 | 0 normal, 1 "Defenser-Hero", 2 "Defenser-Legend" (difficulty) |
| MenusOpened | 0 | how many difficulties are unlocked (grows as you finish the campaign) |
| MasterFlag | 0 | 1 — the maximum difficulty has been completed ("Master of Defense") |
| Scores | 0 | not read by the code |
| AffiliateID, HiScoreURL | | affiliate/high-score-table URL |

## Texts: Texts.txt, Helps.txt, Storyline.txt, Tutorial.txt [code: `_floadgametexts`]

These files are split by the same CSV parser on CR; `LF` is stripped. Indexing is **zero-based by line**:
`gametext[k]` = line `k+1` of the file. The tag `<vd>` = line break; tags
`<colR=255><colG=203><colB=000>` change the text color (used in tower descriptions).
Helps.txt (lines longer than 20 characters) and Tutorial.txt (longer than 45) are automatically
wrapped by `_faddvdtags` at 25 and 50 characters [code: `_floadgametexts`]. A quirk of
`_faddvdtags`: the inserted `<vd>` replaces a space, and scanning continues from the `vd>`
characters, which count toward the next line's width — so every line after the first
ends up 3 characters shorter (22 and 47).
Storyline.txt: line L is the intro for location L (the 7th is the finale). Tutorial.txt: page
`k` = line `k+1` (pages 0..10, see [09](09-ui-menus-tutorial.md)).

The mapping between Texts.txt indices and where they're used is collected in the table in
[09-ui-menus-tutorial.md](09-ui-menus-tutorial.md#textstxt-indices).

## B3D (models, scenes, paths)

Standard Blitz3D chunk format (`BB3D` → `TEXS`, `BRUS`, `NODE{MESH{VRTS,TRIS}, BONE,
KEYS, ANIM, NODE…}`). Parser: `tools/b3d_dump.py`. Quirks of this game:

- Location scenes load through B3D Extensions (`_fext_loadentity`): tag nodes
  `B3DEXT_BGCOLOR`, `B3DEXT_AMBIENT` (node position = RGB 0..1), `B3DEXT_DIRLIGHT`
  (directional light — a child of node `Direct01`); the prefix `B3D_ORDR_<n>_` in a node
  name sets `EntityOrder n` and **is stripped**, so `FindChild(scene,"grass")` finds
  `B3D_ORDR_30_grass`; `B3D_BB_1_` is a billboard.
- **Enemy path** — `Location<L>/Path1.b3d`: node `path` with positional keys
  (frames 0..N, N = 20/100/30/80/70/100 for locations 1..6). The enemy "chases" this
  node (see [04](04-enemies-raids.md)). Coordinates are dumped to `data/enemy_paths.json`.
- Tower models: animation 0..210 frames (Land, Plant) / 0..110 (Magic, Icerock) / 0..10
  (Flame). Sequences of 10 frames: `seq = 2·level` — build/upgrade animation,
  `seq = 2·level+1` — "idle" at that level. Child nodes `fire1` (muzzle point) and
  `dno` (base, recolored per location with texture `dno<L>.png`).
- Monster health — `Data/health.b3d`, animation 1..99 = percent of health lost.
- Menus — 3D scenes with "items" (nodes that `CameraPick` is run against):
  `Data/Menu/*.b3d`.

## MD2 (monsters)

Quake II MD2 v8, all monsters have **11 frames** (0..10) of a single walk animation,
frame names aren't set ("FRAME 000"). Texture 256×256 JPG with the same name.
`eagle.md2` (location 2 decoration) has 51 frames. Parser: `tools/md2_dump.py`.

## Textures and sound

JPG/PNG/BMP, loaded with `LoadTexture` using Blitz3D flags (1 colour, 2 alpha, 4 masked,
8 mipmap, 16/32 clamp U/V, 256 vram, 512 high-colour): `9` = colour+mipmap (monsters),
`0xB` = colour+alpha+mipmap (`border.jpg`), `0x20B` = colour+alpha+mipmap+high-colour
(`dno*.png`, `titul*.png` — 0x203). Values confirmed against Blitz3D sources
(`gxruntime/gxcanvas.h`: RGB 0x1, ALPHA 0x2, MASK 0x4, MIPMAP 0x8, CLAMPU 0x10,
CLAMPV 0x20, SPHERE 0x40, CUBE 0x80, VIDMEM 0x100, HICOLOR 0x200). Bit 0x200 forces the
texture to be stored in 32-bit format even in 16-bit video mode — so the alpha gradient of
translucent bases and titles doesn't quantize. This is irrelevant for Godot: all
textures are 32-bit anyway. Animated atlases `Water.jpg` (64×64 frame, 64 frames) and `border.jpg`
(128×128, 8 frames). Sounds are WAV, music is OGG (`music<L>.ogg` for location L,
`menu.ogg` in the menu). The list of sounds and slots is in [09](09-ui-menus-tutorial.md#sounds).

## Saves `Saves/*.sav` [code: `_fsavegame`, `_floadgame`]

Blitz's plain binary `WriteString` format (int32 length + bytes, no terminator):

```
str  Str(game)        ; "[gold,lifes,curlevel,location,rangeUpg,speedUpg,damageUpg,goldRate,sellRate,
                      ;  enemiesCreated,ingameTime,showLife,createMode,levelFinished,
                      ;  rangeLvl,speedLvl,damageLvl,goldLvl,sellLvl,cold,fire,poison,pplRes,
                      ;  experience,maxLocation,oldLifes,balloonX,balloonY,balloonZ,extraLifes]"
str  "Towers"
str  towersAmount     ; includes 2 hidden preview towers → on load, amount-2 is read
repeat (amount-2) times:
  str type, str level, str x, str y, str z
```

Files: `Save.sav` (F5/button), `Automatic.sav` (autosave after every raid and on the map),
`Location<L>.sav` (snapshot at the start of a location; used by "Restart location"/game over),
`Survival.sav`. Loading rebuilds towers via `_fcreatetower` + `_fpositiontower`
and recomputes skills from levels (`_fupgradetowerbuildingskills(k,1)`).
The string `"Towers"` is the only integrity check ("Corrupted save file!").

## Blitz module format in the exe [source: blitz3d/linker/linker.cpp, `bbruntime_dll.cpp`]

Resource `RCDATA/1111`:

```
int32 code_size; uint8 code[code_size]
int32 num_syms;  { cstring name; int32 offset }*   ; _f<function>, _v<global>, _t<type>, _a<array>, _l_<label>, _NNN (strings/labels)
int32 num_rels;  { cstring symbol; int32 offset }*  ; relative relocations (call)
int32 num_abss;  { cstring symbol; int32 offset }*  ; absolute relocations
```

Runtime symbols (`_bb*`, `_f<command>`) aren't exported; they're registered at
startup via `rtSym("<decl>", func)` — their addresses are recovered by scanning for pairs
`push func; push "decl"` (`tools/find_runtime_syms.py`). The output of decompilation is
`reference/decomp/*.c`, where function names, globals, and string constants have been restored.
