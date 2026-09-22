# Master of Defense — Defold port of the first location

A playable port of the first location (the village, raids 1–15) to **Defold 1.13**: the
game simulation in Lua, the original scene, towers, monsters, bullets, effects, the wooden
HUD panel with the original buttons and bitmap font, the skills window, sounds and music.
No main menu, map, saves, high scores, tutorial pages, balloon or survival mode.

Everything in `assets/`, `data/` and `generated/` is produced from the Godot pipeline's
output (`godot/assets`, `godot/data`, which themselves need the unpacked original game)
and is gitignored:

```bash
make pipeline                          # once: B3D/MD2/textures/sounds -> godot/assets, tables -> godot/data
make defold                            # = python3 defold/tools/export_defold.py --location 1
make defold-run                        # bob build + dmengine (ARGS="--config=main.demo=1")
defold/tools/bob.sh web                # browser bundle -> build/defold-web (serve it over http)
```

Or open `defold/` in the Defold editor (Project ▸ Build). `tools/bob.sh` downloads
`bob.jar` / `dmengine` matching the installed editor's engine SHA into `build/defold-tools`.

## Controls

Arrow keys / WASD or the mouse at the window edge scroll; the buttons on the panel (or
keys 1–5) start placing a tower, LMB places it on the grass (Flame: on the road), RMB
cancels; LMB selects a tower or a monster, RMB deselects; U/R upgrades, Delete sells, Tab
cycles the towers, Space toggles the health bars, N/M normal/fast speed (or the slider),
E/F2 opens the skills window, Esc cancels / closes / quits, Enter restarts after the end.

Debug flags: `--config=main.demo=1` builds a scripted defense (including a level-10 tower)
and keeps upgrading it, `main.demo_ticks=N` simulates N ticks before the first frame,
`main.demo_skills=1` opens the skills window; on the web they are query parameters
(`?demo=1&ticks=2700&skills=1`).

## Layout

- `sim/` — the simulation, pure Lua with no engine calls (tested headless with plain Lua:
  `make test-sim`): `game.lua` (`_fgamelogic`: raids, spawning, towers, bullets, effects,
  economy, auto-balance, an event queue instead of signals), `path_follower.lua` (the
  marker-chasing path movement), `skills.lua`, `balance.lua`, `data.lua` (the JSON tables),
  `blitz.lua` (`Round`, integer division, float32 rounding, the Park–Miller `Rnd`/`Rand`).
  The rules follow docs/ and the Godot port (`godot/src/sim`), not line by line.
- `main/level.script` — the controller: fixed 16 ms ticks (`ticker.lua`), event → view
  bookkeeping, picking (`picking.lua`: ray against the exported zone triangles, tower boxes,
  monster spheres), tower placement, hotkeys, the skills window, end screens.
- `main/views.lua` — game objects spawned from the generated factories and seeked to the
  simulation's frames each frame: monsters (MD2 morph targets, shadow, health bar, status
  effect), towers (skinned animation cursor, `dno` base retextured with the location's
  ground, ANIMMAP texture scroll, range ring, selection), bullets, one-shot effects
  (explosions, the death ghost with its alpha fade), the placement marker.
- `main/hud_model.lua` + `main/hud.gui_script` — the HUD as data: widget layout in the
  800×600 box (docs/13), texts, tooltips (`_ftowerinfo`, `_fcreatetip`), messages and gold
  popups; the gui script only draws the snapshot (buttons in three states, the 16×16 glyph
  font as one box node per glyph with `<colR=…>` tags, slider, progress bar, 9-slice frames).
  The wooden panel `Env.glb` and the portrait `faces.glb` are models at a fixed world
  position drawn by a fixed HUD camera (see the render script), so they never move with the
  scrolling world camera -- parenting them to it made the coplanar panel decals jitter and
  sort-flicker while the camera eased.
- `main/camera.script` — the location camera (pivot at height 30, 45° pitch, 60° horizontal
  fov, 1 unit per tick scrolling with easing 1/20, `move_to` for Tab).
- `render/blitz.render_script` — Blitz's draw order: EntityOrder ground layers without the
  z-buffer, opaque, then the tower base decals (`dno`) in their own `base` pass, then the
  alpha/additive/multiplied brushes sorted back to front; the HUD models over a cleared
  depth buffer with a fixed camera at the origin (so the fixed-position panel is stable);
  the gui. The `base` pass (between the opaque world and the translucent
  bodies) keeps a translucent trunk from sort-flipping with its own base; the base's
  alpha-scissor `dno_solid` copy writes depth there so the tower's underground root is
  occluded, while the soft `dno` decal blends on top (as in the Godot port).
- `tools/export_defold.py` + `tools/modexport/` — the exporter (see below).

## The exporter

Reads the Godot pipeline's glbs and `.b3d.json` sidecars, so the coordinate / winding / UV
conventions verified for Godot are reused as they are.

- **Models** (`modexport/models.py`): Defold plays only skeletal and morph target
  animations, while B3D scenes animate plain nodes, so every model with node animation is
  rewritten as a skinned mesh — one joint per node, vertices baked into rest-pose world
  space and weighted 1.0 to their joint, the TRS channels driving the joints. Static models
  keep their rigid hierarchy. Primitives that need runtime control of their own (`dno`,
  `updates`, `window`, each ANIMMAP brush) are split into separate glbs and model
  components ("groups"). Brush and vertex colours go back from linear to gamma (Defold, like
  Blitz3D, shades in gamma space). MD2 monsters keep their morph targets.
- **Bone-posed models** (the Nature tower, the death soul, the Magic and Icerock towers, the
  Magic/Freeze/Poison shot effects): some animated hierarchies break Defold's SRT-bone skinning. Nature's non-uniform
  scales and rotations give world matrices with shear the SRT bones cannot represent (worse
  the more it is upgraded); the death soul's frost planes are flattened to scale 0.001 on one
  axis, whose inverse-bind matrix is near-singular and which Defold renders as a flipped,
  blown-up ghost. The exporter detects both (`bone_posed` = shear or an anisotropic degenerate
  joint scale) and bakes the full *world* matrix of every joint at each integer frame into
  `generated/bones/<model>.bin`, keeping the mesh vertices in joint-*local* space. The shader
  skins through a `bone_matrices[]` array constant that `main/views.lua` fills each frame (two
  nearest frames lerped), multiplying local vertex by full world matrix with no inverse-bind —
  exactly how Godot transforms the nodes, so the near-singular inverse is never formed.
  Defold's own rig is left at the bind pose. Blitz billboards (`B3D_BB_1_` nodes: the
  Magic tower's crown ring, the Icerock glow) also take this path: their material variant
  does what `_fext_updatebillboards` does — PointEntity toward the camera *position* (world
  Y up, no roll), keeping the joint's position and scale. Drawn as a static quad the crown
  lay on its side; aligned to the camera *axes* it slid off the tower top, because the ring
  sits 3.44 units along its node's Z. The demo builds a level-5 Magic tower to show it.
- **Materials** (`modexport/materials.py`): one Defold material per (brush, EntityOrder,
  group): the two-layer `TextureBlend` combine, spherical environment maps from the
  camera-space normal (with the V sign inverted relative to Godot's shader: Defold flips
  the V of imported texcoords to its bottom-left origin, which a UV computed in the shader
  never passes through -- without this every sphere-mapped texture, e.g. the death soul's
  `death.png` ghost, rendered upside down), `EntityFX` fullbright / vertex colours / no-cull (duplicated
  triangles), masked textures, per-vertex ambient + Lambert of the scene light, and the
  per-component constants `entity_color` (EntityColor), `entity_alpha` (EntityAlpha),
  `uv_offset` (PositionTexture); skinning and morph target variants.
- **HUD atlas** (`modexport/hud.py`): `gui.png` cut into buttons, slider, progress bar,
  frames and the 223 glyphs of the Blitz font (`assets/hud/hud.atlas`); `Gradient.bmp` →
  health bar colours.
- `generated/level_data.lua` (bounds, background, render passes, build zone triangles,
  gradient), `generated/models.lua` (per model: game object, animation length, groups,
  ANIMMAP keys per frame), `generated/entities.go` (a factory per model),
  `generated/sounds.go` (a sound component per file; `.ogg` re-encoded stereo with ffmpeg
  because the originals fail in the web decoder), `generated/main.collection` (the
  bootstrap collection: the exported location's scene and the level controller with that
  location's tower ground texture, so `--location N` needs no hand edits),
  `data/*.json` (custom resources).

## Deviations and known gaps

- The skills window opens on location 1 (`hud_model.SKILLS_ON_LOCATION_1`); the original
  locks it until location 2, so Icerock / Flame never appear there.
- The tutorial pages, the balloon, saves, the in-game menu are not ported.
- The `B3DEXT_ANIMBRUSH` colour/alpha keys (only `death2.b3d`, unused on location 1) and
  single-axis texture clamps are not implemented.
- A raid whose first monster dies before the second spawns ends at once and its remaining
  monsters spill into the next raid — the original's `_fdeleteenemy` → `_fnextlevel`
  behaviour, reproduced by the Godot port too.
- The 800×600 game view is letterboxed inside the window and keeps its 4:3 aspect at any
  window size (`main/screen.lua`, `render/blitz.render_script`); the mouse is mapped into
  that centred box so the HUD hover and the picking stay aligned when the window is resized.
