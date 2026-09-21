# 03. Locations, scenes, paths, camera

## Location table [code: `_finitlocationsinfo`, `_fsetlocationdata`]

`_fsetlocationdata(L, x1, x2, z1, z2, pathsCount, dnoTexture, firstRaid, r, g, b)`:

| L | Name (story) | Camera bounds x1..x2 / z1..z2 | First raid | Raids | Raid count | Notes |
|---|---|---|---|---|---|---|
| 1 | Village (clock) | 50..70 / 0..40 | 1 | 1–15 | 15 | tutorial; balloon unavailable; animated clock hands follow real time |
| 2 | Castle (castle siege) | 10..110 / 0..100 | 16 | 16–45 | 30 | survival is played here; decorative eagle that screeches once every 5 min; `water.wav` at `door` |
| 3 | Rocks/cave (rock) | 10..70 / 0..85 | 46 | 46–70 | 25 | "green sorcerers" — healers (unit 31); Icerock isn't recolored |
| 4 | Desert | 75..140 / 5..100 | 71 | 71–100 | 30 | the **balloon** appears; tutorial page 9 |
| 5 | Shelter (den) | 50..145 / 0..100 | 101 | 101–135 | 35 | starting gold 350 (instead of 300) |
| 6 | Mountains (Living Stone) | 5..105 / 0..150 | 136 | 136–180 | 45 | no shadows for monsters or the balloon; camera clear color (192,212,223); `EntityOrder` on the range circle |

The `paths = 1` field is the same for all (`Path1.b3d`), `dno<L>.png` is the tower-base
texture, base color (255,255,255). All bounds form a rectangle within which the camera
pivot can move (`_fupdatecamera`). The pivot starts at the center of the rectangle, at height 30.

Experience on entering location L: `+10·L`; gold is reset to `200 + 20·L`
(at L=5: `250 + 100 = 350`); gold above 200 is converted into extra
inhabitants (see [08](08-economy-lives-difficulty.md)). The finale after raid 180 leads to the credits
(`Additional/end.b3d`) → the high-score screen.

## Scene nodes `Location<L>/Location<L>.b3d` [code: `_floadlocation`, `_fplacetower`]

The game looks nodes up by name (`FindChild`; the `B3D_ORDR_n_` prefix is stripped by the loader):

| Node | Role |
|---|---|
| `grass` | **allowed build zone** (`CameraPick` hits grass → can place) |
| `road` | road: building is forbidden, except for towers with `PlaceOnRoad` (Flame); RMB on the road moves the balloon |
| `noparking` | building forbidden |
| `rocks` | building forbidden (no marker positioning) |
| `river` | animated texture `Water.jpg` (`LoadAnimTexture`, 64×64 frame, 64 frames; frames 0..62 are shown, +1 frame/tick) |
| `border` | animated texture `border.jpg` (128×128 frame, 8 frames, +0.5 frame/tick) |
| `door` | water sound emission point (location 2) |
| `little_arrow`, `big_arrow`, `second_arrow` | clock hands (location 1) |
| `Camera01`, `CamPath`, `Direct01` | editor camera (unused by the game), light |

Everything else is decoration. The whole scene is animated via `Animate(scene,1,1,0)` (frames 0..100).

"Can I build here" check [code: `_fplacetower`]:
1. `CameraPick` under the cursor with picking enabled only for parts of the location.
2. Hit on `grass` → OK; `road` → OK only for `PlaceOnRoad`; `noparking`/`rocks`/
   anything else → not allowed.
3. Also disallowed if the distance to any visible tower is **< 5.6**.
4. The `*Place.b3d` marker is tinted green (0,250,0) / red (250,0,0); the range circle
   is only shown when placement is allowed.

## Enemy path `Path1.b3d` [code: `_fcreateenemy`, `_fupdateenemies`]

Node `path` has position and rotation keys on every frame 0..N. Mechanics:

- For each enemy a **copy** of the path is made (`CopyEntity`), randomly offset
  by `Rnd(-1,1)` on X and `Rnd(0,1)` on Z (spread across the road's width); its
  `path` child is found and hidden.
- The enemy is placed at the marker's position. Every tick (in this order): if the
  distance to the marker is < 1 — `SetAnimTime(pathCopy, AnimTime + speed/4)`; then
  `PointEntity(enemy, marker)`, `MoveEntity(enemy, 0,0, speed)` (unclamped —
  it can "overshoot" the marker). The marker "runs away" by `speed/4` frame per tick, while
  the enemy chases it at `speed` units/tick. Under freeze the step becomes `speed/freeze·2`, and the marker's
  `+ speed/4/freeze·2` (verified by disassembly; the 1:4 ratio is preserved).
- `SetAnimTime` in Blitz3D takes `time mod AnimLength`, so the end of the path is
  detected as `AnimTime > AnimLength − 1` [code: `_fupdateenemies`, disassembly — the decompiler
  loses the "−1"]. `AnimLength` is the frame count from the ANIM chunk (20/100/30/80/70/100), i.e.
  **the last path key is never reached**: the enemy "arrives" roughly one frame
  step early. `mod` wraparound is impossible: it would require `speed/4 ≥ 1`,
  i.e. `raid\speed ≥ 40` (the maximum in the data is 5.2).
- The average step between keys on every location is **> 4 units** (4.4–6.8), so the
  marker always stays ahead of the enemy and the real movement speed is ≈ `speed` units/tick; travel
  time is ≈ `length / speed` ticks.

Path travel time (simulated by `tools/simulate_path.py` from `data/enemy_paths.json`,
result in `data/path_times.json`; `speed = raid\speed/10`, 62.5 ticks/s (16 ms) at slider 20;
speeds are the minimum and maximum across the location's raids):

| Loc. | Frames | Length to `N−1`, units | Step, units | Slowest raid | Fastest raid |
|---|---|---|---|---|---|
| 1 | 20 | 97.7 | 5.14 | 1.03 → 938 ticks (15.6 s) | 1.45 → 668 ticks (11.1 s) |
| 2 | 100 | 431.6 | 4.36 | 1.03 → 4144 ticks (69.1 s) | 1.9 → 2247 ticks (37.5 s) |
| 3 | 30 | 197.9 | 6.82 | 1.03 → 1902 ticks (31.7 s) | 1.8 → 1088 ticks (18.1 s) |
| 4 | 80 | 422.0 | 5.34 | 1.03 → 4080 ticks (68.0 s) | 2.0 → 2103 ticks (35.0 s) |
| 5 | 70 | 339.3 | 4.92 | 1.03 → 3279 ticks (54.6 s) | 2.1 → 1609 ticks (26.8 s) |
| 6 | 100 | 599.2 | 6.05 | 1.03 → 5801 ticks (96.7 s) | 3.0 → 1992 ticks (33.2 s) |

Start point = key 0 (entrance), end = key N (castle/exit). Coordinates of all
keys: `data/enemy_paths.json` (per location: 21, 101, 31, 81, 71, 101 points).

## Camera [code: `_fupdatecamera`, `_fcontrolcamera`, `_fmainloop`]

- Perspective, FOV 60°, `CameraClsColor` black (location 6 — light blue).
- The pivot `_vcampiv` sits at height **30**; the camera `AlignToVector`/`_falignentity`s to the pivot;
  camera movement is smoothing toward the pivot with a coefficient of **1/20 per tick**.
- Scrolling: A/← or the mouse at the left edge (x<1) — `x -= 1` while `x > x1`; D/→ or the right
  edge — `x += 1` while `x < x2`; W/↑ or the top — `z += 1` while `z < z2`; S/↓ or the bottom —
  `z -= 1` while `z > z1`. Units are world units, per tick.
- The "Go to Balloon" button / Tab — `_fmovecameratoentity`.

## Decorations [code: `_fdecoratelocation`, `_fhandledecorates`]

- Location 1: the clock. On load, the system time is read; the hands rotate:
  seconds +1/60 per tick, minutes +1/3600; angles `-h·30°`, `-m·6°`, `-s·6°`.
- Location 2: `Location1/birdpath1.b3d` (animation 0.1) + `Additional/eagle.md2` —
  an eagle flies in a circle, screeching `eagle.wav` every 300,000 ms (the file is
  **missing** from the distribution — Blitz silently returns 0).
