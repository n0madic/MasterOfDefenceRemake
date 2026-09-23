# 12. What the remake does, and open questions

The remake exists in two ports that share the rules and the asset pipeline: Godot 4.7
([`godot/`](../godot/README.md), GDScript) and Defold 1.13 ([`defold/`](../defold/README.md),
Lua). This page maps the research onto their code; the full architecture and every
intentional deviation are in the two READMEs.

## The rule-core, carried over as-is

1. **Fixed tick with an integer period** `1000 \ (40 + slider)` ms (16 ms =
   62.5 ticks/s by default) and all "per tick" constants (see [01](01-overview.md)): a
   millisecond accumulator of its own, not `_physics_process` / `Engine.time_scale` —
   `godot/src/autoload/Ticker.gd`, `defold/main/ticker.lua`. The hotkeys set the rate
   directly, as `_fmainloop` does: M = 120 fps with the slider drawn at 100, N = 60.
2. **Data**: `tools/game_data.py` turns the original's CSVs, paths and texts into
   `data/*.json` (units, towers, raids with the survival table, paths, locations, texts,
   plus the golden `hud_layout.json` / `path_times.json` from `docs/data`), in Godot
   coordinates; the CSV semantics (label in the first column, integer truncation) are those
   of `tools/export_csv.py`. Godot loads them in the `GameData` autoload
   (`godot/src/autoload/GameData.gd`), Defold in `defold/sim/data.lua`; `godot/data/` is
   committed and read by the headless tests of both ports.
3. **Simulation**: a scene-free port of `_fgamelogic` — `godot/src/sim/` (`Game.gd` and the
   object classes), `defold/sim/` (`game.lua` …). The damage/poison/fire/freeze/inhabitant
   formulas follow [04](04-enemies-raids.md), [05](05-towers.md), [06](06-magic-skills.md),
   including the non-obvious ones:
   - bullet damage `max(0, damage − armor)`; freeze overwrites the counter;
     poison/fire only applies if the new duration is longer than the current one;
   - skills multiply prototypes **cumulatively** (Π(1+0.005k));
   - upgrade parameters take effect after the animation (100 ticks);
   - inhabitants lost = `Round(life% / (3·res+33))`, boss ×5;
   - health auto-balance based on inhabitants lost (`_fhandlebalance`, `Balance.gd`);
   - numbers: round-to-even (`Blitz.round_int`) and emulated float32 accumulators
     (`Blitz.f32`), seedable `Rand`/`Rnd` with Blitz's range semantics (Godot wraps the
     engine's generator, Defold reimplements Blitz's own, so sequences differ between ports).
4. **Path movement** is the original's, not a curve at constant speed: the enemy chases a
   marker "guide" that advances by `speed/4` frame while the enemy is closer than 1 unit
   (`godot/src/sim/PathFollower.gd`, `defold/sim/path_follower.lua`, both ports of
   `tools/simulate_path.py`). With key spacing > 4 units the speed is ≈ `speed`
   units/tick and the travel time ≈ `length/speed`
   ([03](03-levels-locations.md#enemy-path-path1b3d), `data/path_times.json` as the test oracle).

## Assets

One pipeline builds both ports from the unpacked original: `tools/build_assets.py --target
godot|defold|all` (`make assets`). Its import stage (`tools/source_import.py`) converts
everything once into `build/import/`; the targets `tools/targets/godot.py` and
`tools/targets/defold/` take it from there. Details in [`tools/README.md`](../tools/README.md).

- **B3D → glb**: `tools/b3d2gltf.py`, a custom converter on top of the `tools/b3dlib.py`
  parser. Node names (`grass`, `road`, `noparking`, `rocks`, `river`, `border`, `door`,
  `fire1`, `dno`) and the tower animations (sequences of 10 frames) are kept; BONE bones
  become a glTF skin; what glTF cannot say (blend modes, EntityOrder, lightmaps, tags) goes
  into a `*.b3d.json` sidecar, applied by Godot's `addons/b3d_import/b3d_post_import.gd`
  and by the Defold exporter. The coordinate, winding and colour conventions are in
  [`godot/README.md`](../godot/README.md#conventions) (C1–C4, `tools/blitzconv.py`).
- **MD2 → glb**: `tools/md2togltf.py`, frames as morph targets (frame k at t = k); 11 walk frames.
- **Enemy paths**: `data/paths.json` (keys and rotations per frame), the same points as
  `docs/data/enemy_paths.json`.
- **Texts**: decoded from cp1251, `<vd>` becomes a line break and long lines are wrapped as
  `_faddvdtags` does; the `<colR=nnn><colG=nnn><colB=nnn>` colour tags stay and are drawn by
  the ports' own `EText3D` layout on the 16×16 glyphs of `gui.png` (`BlitzText.gd`,
  `defold/main/blitz_text.lua`, see [13](13-hud-geometry.md#3d-text)).
- **Menus** are the original's 3D sheets (`Menu/*.b3d`) with item picking and the `sel.b3d`
  cursor, not redrawn 2D screens ([09](09-ui-menus-tutorial.md#menu-animations)).

## Original quirks: dropped and kept

- **Not carried over**: the CRC check of the CSVs (`_fcheckgamefiles`), demo mode and the
  "buy now" screens, affiliate links, submitting high scores to the browser (both ports
  keep two local top-10 tables instead).
- **Dead data**, ignored: `Tower6.csv`, comment rows in the CSVs, `Splash`, raids 181–205,
  survival columns 201–255; the flying-monster counter in survival.
- **Missing file**: `eagle.wav` — the eagle's screech is skipped.
- **Kept**: a raid counts as repulsed once no living non-inhabitant is left, even before
  every monster has spawned (`_fdeleteenemy` → `_fnextlevel`); the rest spill into the next raid.
- **Kept, optional**: after loading a save the original recomputes the attack speed of
  existing towers incorrectly (×upgrader^level instead of the cumulative product, see
  [06](06-magic-skills.md)); Godot's `reproduce_original_bugs` flag (off by default) restores it.
- **Hotkey M** sets the fps to 120 but draws the slider at 100 (where dragging would give
  140); both ports reproduce that.
- The help text claiming "income depends on inhabitants" is wrong for the campaign.
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
