# 12. Notes for the Godot remake and open questions

## What to carry over as-is (the rule-core)

1. **Fixed tick with an integer period** `1000 \ (40 + slider)` ms (16 ms =
   62.5 ticks/s by default) and all "per tick" constants (see [01](01-overview.md)).
   In Godot: a dedicated millisecond accumulator in `_process` (`Ticker.gd`), not
   `_physics_process` and not `Engine.time_scale`, so the period matches the original.
2. The data in `docs/data/*.json` is exactly what the original reads. It's convenient to turn it
   into Godot `Resource`s (units, towers, raids) — CSV tables with "label in the first
   column" semantics.
3. Damage/poison/fire/freeze/inhabitant formulas — see [04](04-enemies-raids.md),
   [05](05-towers.md), [06](06-magic-skills.md). Especially non-obvious ones:
   - bullet damage `max(0, damage − armor)`; freeze overwrites the counter;
     poison/fire only applies if the new duration is longer than the current one;
   - skills multiply prototypes **cumulatively** (Π(1+0.005k));
   - upgrade parameters take effect after the animation (100 ticks);
   - inhabitants lost = `Round(life% / (3·res+33))`, boss ×5;
   - health auto-balance based on inhabitants lost (`_fhandlebalance`).
4. Path movement: a marker "guide" that advances by `speed/4` frame while
   the enemy is closer than 1 unit. Since the key spacing on every location is > 4 units,
   the resulting speed is ≈ `speed` units/tick, and the travel time is ≈ `length/speed` (table and simulator —
   [03](03-levels-locations.md#enemy-path-path1b3d), `tools/simulate_path.py`).
   For the remake this can be replaced with movement along a `Path3D`/`Curve3D` at a constant
   speed of `speed`; the end of the path is one frame step before the last key.

## Assets

- B3D → glTF: import into Blender via the `io_scene_b3d` add-on (or a custom converter built on
  `tools/b3d_dump.py`), then export glTF. It's important to keep the node names
  (`grass`, `road`, `noparking`, `rocks`, `river`, `border`, `door`, `fire1`, `dno`)
  and the tower animations (sequences of 10 frames).
- MD2 → glTF: `noesis`/the Blender MD2 add-on; 11 walk frames.
- Enemy paths have already been dumped to `data/enemy_paths.json` (world coordinates, frame →
  point); they can be loaded directly into a `Curve3D`.
- Texts are in cp1251, with `<vd>` and `<colR=…>` tags — replace with BBCode.

## What not to carry over / known original quirks

- CRC check of the CSVs (`_fcheckgamefiles`), demo mode, affiliate links,
  submitting high scores to the browser.
- `Tower6.csv`, comment rows in the CSVs, `Splash`, raids 181–205, survival
  columns 201–255 — dead data.
- The flying-monster counter in survival is unused; `eagle.wav` is missing.
- The help text claiming "income depends on inhabitants" is wrong for the campaign.
- Hotkey M sets the slider to 100 (=140 Hz), but the fps is 120 — a discrepancy.
- After loading a save, the attack speed of existing towers is recomputed incorrectly
  (×upgrader^level instead of the cumulative product) — see [06](06-magic-skills.md).
- This unpacked build is a demo build by its marker byte (`0x3C` instead of `0x3D`), see [01](01-overview.md).

## Closed questions

- HUD geometry, atlas, font, tooltips — [13](13-hud-geometry.md), `data/hud_layout.json`.
- Menu/credits animations, text reveal — [09](09-ui-menus-tutorial.md#menu-animations).
- Path travel time — [03](03-levels-locations.md#enemy-path-path1b3d), `data/path_times.json`.
- Fields `tenemyt+0x34` (a second `tdurationt` slot, unused), `+0x64` (int, unused)
  and `ttowerprototypet+0x2C/0x30` (`BaseModel`/`BangEffName` strings, never
  populated) — types confirmed via type descriptors (`data/blitz_types.txt`); they don't
  affect the game and aren't needed in the remake.
- `LoadTexture` flags (`0x20B` = RGB+alpha+mipmap+**high-colour 32-bit**) — [02](02-data-formats.md#textures-and-sound).

## Open questions (not verified against the code)

| Question | Where to look |
|---|---|
| Behavior of `_fupdateplayer`/`_fnextmusic` (playlist `_fmid_*` — seems inactive; music goes through `_fstartbackgroundmusic`) | `_fupdateplayer` |
