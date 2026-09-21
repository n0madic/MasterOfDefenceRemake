# Master of Defense — Godot 4.7 remake (GDScript)

The project lives in this directory; data and models are generated from the unpacked
original (`../MasterOfDefense_unpacked/Data`) by the tools in `../tools`.

## Building the data

```bash
python3 tools/export_godot_data.py MasterOfDefense_unpacked/Data godot/data   # tables, paths, texts
python3 tools/convert_all.py MasterOfDefense_unpacked/Data godot               # B3D/MD2 → glb, textures, sounds
godot --headless --path godot --import                                         # import resources
```

## Builds (mobile and web)

Presets live in `export_presets.cfg` (`Web`, `Android`, `iOS`); commands are in `../Makefile`
(`make help`; run from the repo root, export templates for the current Godot version are required):

```bash
make web            # build/web (no-threads variant: can be hosted without COOP/COEP headers)
make serve-web      # http://localhost:8060
make android        # build/android/MasterOfDefense-debug.apk (arm64, debug keystore from the editor settings)
make android-release  # release APK; key via GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD, falls back to the debug key with a warning if unset
make android-template GODOT_SRC=~/godot   # trimmed release template built from Godot 4.7.2 sources → build/templates (see below)
make android-emulator # debug APK for the emulator (gl_compatibility)
make ios IOS_TEAM_ID=XXXXXXXXXX   # build/ios/*.xcodeproj, signing and archiving happen in Xcode
make icon           # renders icons/icon_1024.png from the Military tower model (needs a window)
make icons          # icon_1024.png → the rest of icons/*.png for Android and the App Store (the favicon and the remaining iOS icons are derived from icons/icon_256.png automatically)
```

Release APK: if the trimmed template `build/templates/android_release.apk` has been built
(`make android-template GODOT_SRC=…`, `tools/build_android_template.sh`), `make android-release`
exports using the `Android Custom` preset, otherwise the stock `Android` one. The template compiles Godot without
2D physics, navigation, XR, and ~45 unused modules; both renderers are present (Vulkan for Mobile
on phones, OpenGL for Compatibility); `libgodot_android.so` goes from 71 → 45.5 MB, the APK from 45 → 36 MB.
Requires scons, JDK 17, and the Android SDK (the NDK and the Swappy script are installed automatically).

On phones the renderer is Mobile (Vulkan). The Vulkan emulator doesn't display anything ("Couldn't present to
Vulkan queue"), so the `Android Emulator` preset (`make android-emulator`,
`build/android/MasterOfDefense-emulator.apk`) passes `--rendering-method gl_compatibility`.
Mobile has no depth pre-pass, which the alpha-textured brushes (menu posts and planks, HUD sheets,
road patches) relied on: `b3d_post_import.gd` gives them `DEPTH_DRAW_ALWAYS`, otherwise
the posts get sorted over the planks. Compatibility renders lit faces noticeably brighter (Location1's
roofs) — Mobile matches Forward+, so this is a discrepancy in Compatibility itself.

The icon — `icons/icon_1024.png`: a render of a level-10 Military tower (`tools/render_icon.gd`), just like
the original `Data/td.ico`.

## Tests

```bash
godot --headless --path godot -s res://tests/run_tests.gd [-- --filter=test_towers]
python3 -m unittest discover -s tools/tests -v
```

Visual check of the conversion (needs a window):
`godot --path godot --resolution 800x600 -s res://tools/render_check.gd -- <L> out.png [key] [height] [Monster]`;
a single model in front of the camera: `-s res://tools/render_model.gd -- MODEL.glb out.png [frame] [distance] [tint] [rot_x] [rot_y]`;
an effect over time (`OneShotView`, one frame per tick into a directory):
`-s res://tools/render_effect.gd -- res://assets/models/Towers/MilitaryEff.glb OUT_DIR [scale] [speed] [distance]`.
A series of gameplay screenshots: `--shot=PATH:FIRST-LAST/STEP` (a frame number is appended to the name).

## Running

`godot --path godot` — the main menu. Debug arguments (after `--`): `--location=L`
(jump straight to a location), `--seed=N` (random seed), `--survival`, `--demo` (a tower + start a raid), `--debug` (F1 — start a
raid, F3 — overlay, F4 — gold/experience/magic, F6 — finish the location, F7 — defeat),
`--cheats` (inhabitants never die, gold and experience are never spent, the run isn't scored),
`--demo-tower=T` (tower type for `--demo`; Flame unlocks Fire Magic),
`--shot=PATH:FRAMES` (screenshot and exit), `--act=FRAME:click:X,Y` / `--act=FRAME:key:NAME` / `--act=FRAME:close` (the window's close button), `--hide=node,…`
(scripted input), `--act=FRAME:pivot:X,Z` (pan the location camera to a point, clamped to its bounds),
`--hover=X,Y`, `--open-skills`, `--tutorial-page=N`, `--safe-area=L,T,R,B` (simulates a
phone's notch/gesture-bar cutout, in window pixels).

Saves — `user://saves/<Role>.json` (`Automatic`, `Save`, `Location<L>`, `Survival`),
settings — `user://settings.json`, high scores — `user://highscores.json`.

## Structure

- `src/sim/` — the simulation (RefCounted, no scene): `Game.gd` — global state and the tick
  order of `_fgamelogic`; `Enemy/Tower/Bullet/Balloon/Bomb.gd` — objects; `PathFollower.gd` —
  path movement (a port of `tools/simulate_path.py`); `Skills.gd` — skills; `Balance.gd` —
  auto-balance; `Survival.gd` — survival raid generation.
- `src/autoload/` — `GameData` (tables from `data/*.json`), `Ticker` (tick accumulator,
  convention C3), `Blitz` (not an autoload, a static class: `round_int`, `f32`, coordinates).
- `addons/b3d_import/b3d_post_import.gd` — glb post-import: applies from the sidecar
  `*.b3d.json` whatever isn't in the glTF (ADD/MUL blending, vertex colors, lightmaps on UV2,
  `TextureBlend 5` → albedo ×2, EntityOrder → render_priority, see "Deviations" — billboards).
  Brushes with spherical env-mapping (texture flag 64: tower glows, bullets,
  effects, the death "ghost"), every multi-layer brush (a second alpha layer masks the
  first: Location5's `noparking`, the `transp*` patches, lightmaps), and layers with a positive
  EntityOrder get a generated `ShaderMaterial` — the project's only shader:
  sphere UV = the normal in camera space `(0.5+0.5·nx, 0.5−0.5·ny)`, as in `sphere_mat`
  in `gxscene.cpp`; layers are combined per `TextureBlend` (1 alpha, 2 multiply, 3 add,
  5 modulate2x), the second layer reads `UV2` (the converter writes its coordinates there);
  no fullbright — `diffuse_lambert` without specular; brushes that Blitz draws
  opaquely (blend 1, alpha 1, no alpha/masked layers and no forced alpha) don't write to
  `ALPHA` and stay in the opaque pass; masked layers use alpha scissor; `EntityFX 2` —
  vertex color replaces the brush's color (`D3DMCS_COLOR1`), the brush's alpha is preserved;
  the `albedo`/`uv1_offset` uniforms mirror StandardMaterial3D (so `BlitzAnimator.material_color`
  and others work with both material types).
- `src/scenes/location/` — `LocationScreen` (the gameplay screen: 3D view + HUD + tutorial +
  hotkeys), `LocationView` (the location scene, entity views), `CameraRig`, `Picker`.
- `src/scenes/hud/` — `Hud` (the `Env.glb` panel on the camera + 2D buttons/texts), `BlitzText`
  (a 16×16 font from `gui.png`, `<colR=…>` tags, per-letter alpha), `GuiAtlas`, `Eniretu`
  (slider/checkbox/radio button/text field built from the atlas), `Tutorial`.
- `src/scenes/menu/` — `MenuScene3D` (the original's 3D menus, with picking of "items" and the
  `sel.b3d` cursor), `MainMenu` (with the `cameraEnv` camera fly-through into settings), `OptionsPanel`
  (Eniretu widgets at the coordinates from `_fguicreateoptionsbuttons`), `MapScreen`, `SimpleScreen`
  (congratulations/defeat/credits/high scores), `InGameMenu` (the `ingame.b3d` sheet, tilting toward the
  cursor, 3D sliders `music.b3d`/`sound.b3d`); `Main.gd` — the screen state machine.
- `src/sim/SaveGame.gd` — state serialization (the `tthegamet` fields + towers).
- `tests/` — headless tests (`run_tests.gd` looks for `test_*.gd`), including `test_campaign`
  (a run through 180 raids and 50 survival raids with a scripted defense).

## Conventions

- **C1** coordinates: Blitz `(x, y, z)` → Godot `(x, y, −z)`, quaternion `(w,x,y,z)` →
  `(w,x,y,−z)` (Blitz builds its matrix from the quaternion transposed, i.e. it applies
  the inverse rotation — `blitz3d/geom.h`); triangle index order **is flipped**
  (`tools/blitzconv.py`, `Blitz.gd`). Verified: location floors face up, monsters walk
  facing along the road, the HUD panel's `Env.b3d` quads face the camera.
- **C2** animation: 1 Blitz frame = 1.0 s in glTF; the game never calls `play()`, it does
  `seek(t, true)` once per tick. MD2 monsters: blend-shape weights are set directly
  (`a = floor(t)`, `b = a + 1`, `b = 0` when `b == last`), because Blitz in loop mode
  blends frame 9 → 0.
- **C3** tick: `period_ms = 1000 \ (40 + slider)` (16 ms = 62.5 ticks/s by default),
  accumulated in `Ticker.gd`.
- **C4** numbers: `Blitz.round_int` — round-to-even (x87 `fistp`); float32 accumulators
  (`ingametime`, tower `AnimTime`, skill multipliers) are emulated via `Blitz.f32`.

## Reproduced original quirks

- A raid counts as repulsed once the number of living non-inhabitants hits 0 (`_fdeleteenemy` →
  `_fnextlevel`), even if not every monster has been created yet: killing the first monster before the
  second one spawns ends the raid, and spawning then continues from the next raid's list.
- Game speed: `1000 \ (40 + slider)` ms per tick; key M sets the slider to 100 (7 ms).

## Deviations from the original

- `reproduce_original_bugs` (a `SimGame` field, `false` by default): when `true`, after
  loading a save the attack speed of built towers is recomputed as in the original
  (`level` times the final multiplier instead of the cumulative product, see docs/06).
- `Ticker.MAX_TICKS_PER_FRAME = 250`: after a long pause the window doesn't replay thousands
  of ticks at once (the original would try to catch up on all the missed time).
- Demo mode, the CRC check, submitting high scores to the browser — not carried over; the
  high score is written to a local table (`user://highscores.json`) automatically; the
  "Would you like to submit…" prompt and the Send/Don't send planks on the high-score screen aren't shown
  (`Restart`/`To menu` on the `Send.b3d` sheet are shifted toward the center to take the hidden plank's place —
  `MenuScene3D.offset_item` also fixes up their animation keys). Instead of the online table, the sheet has
  two local ones (campaign / survival, top 10); the "Your score is" line is moved up toward the top of the
  frame; the screen after survival hangs on the location's camera, like game over.
- `Raid`/`Economy` from the plan weren't split into separate files: income, inhabitant losses, and spawning
  are implemented in `Game.gd` (`handle_levels`, `next_level`).
- B3D bones (`Health.b3d`, `Balloon.b3d`) are exported as a glTF skin (Godot builds a
  `Skeleton3D`); `tools/b3d2gltf.py --no-skin` leaves the bones as empty nodes.
- Textures that Blitz loaded with the alpha flag but no alpha channel (alpha = brightness), or with
  the masked flag (black = transparent), are generated by the converter as `*__alpha.png`,
  `*__alphaw.png`, `*__mask.png`.
- The "Choose resolution" and "Color depth" settings are removed (rendering is always 800×600, scaled
  to fit the window; their planks in `buttons.b3d` are hidden); on desktop, window size,
  position, and the "maximized" state are remembered on exit (`XRes`/`YRes`/`WindowX`/
  `WindowY`/`WindowMaximized`) and restored on start (the window is pulled back into the usable
  screen area; centered if no position was saved); "Gamma" is a full-screen
  pass of `pow(rgb, 1/2^(g/100))` over the frame (`DisplayManager`), applied immediately as the
  slider moves. "Windowed" / "VSync" only exist on desktop; in the browser there's a single
  "Fullscreen" checkbox instead (applied on "ok" — a user gesture), and nothing on mobile.
- A "Screen" toggle sits on the former "Color depth" plank: "4:3" (default, like the
  original — an 800×600 canvas with letterboxing) or "Wide" — the canvas grows along whichever axis has
  room (`content_scale_size` based on the window's aspect), the 3D view fills the window, and the "box" with
  the 800×600 interface (`CanvasLayer.offset`) is centered; cameras switch to `KEEP_HEIGHT` with
  the 4:3 frame's vertical fov (≈ 46.83°) in a wide window and to `KEEP_WIDTH` 60° in a tall one, so
  the standard frame is always fully visible (`DisplayManager`). Applied immediately on click.
  Floating HUD groups in Wide stay anchored to their own corners/edges of the window (`HudLayout`): gold/experience —
  top left, inhabitants — top right, Raid and the menu buttons — top center, tower buttons and
  messages — bottom left, Upgrade/Sell and the progress bar — bottom right, the info panel with its slider —
  bottom center. The panel's 3D meshes shift vertices by anchor: posts (`Plane10`)
  spread apart toward the edges, plain planks (`wood.png`) stretch between a post and the
  info panel, tutorial-pointer (`Lines.png`) drops near buttons stay rigid while the
  line to the sheet stretches (the mesh is cut along u/v thresholds from `HudLayout.TUTORIAL_RULES`).
  Pointers that the animation "parks" just past the 4:3 frame are hidden in wider/taller canvases
  (`HudLayout.cull_parked`). Debug flags: `--tutorial-page=N` opens the
  location on the given tutorial page, `--act=F:pivot:X,Z` drives the camera to a point (clamped to its bounds).
  In a location, the scroll bounds (computed for the 4:3 frame) are narrowed by however much the
  frame's footprint on the ground grew (`CameraRig.fit_bounds`, based on the far edge of the view trapezoid), so
  that at the edge the camera shows the same thing as in 4:3; where the scroll rectangle would collapse
  (narrow L1 — already at ~1.64), the canvas is clamped and letterboxing kicks in beyond that
  (`CameraRig.aspect_limits_for` → `DisplayManager.set_aspect_limits`). Menu screens with their
  own camera keep a strict 4:3 (the map/high-scores/credits sheets and backgrounds are built for that frame,
  with a black/white field and parked elements beyond it); the main menu allows 1.25…1.8
  (`MainMenu.ASPECT_LIMITS`: bounded by the width of the `SkyNew` backdrop; below 1.25 you'd see the
  end of the sky and the "OK"/"Credits" planks parked under the frame). The menu's `grass` ground polygon is cut to the 4:3 frame
  (in 4:3 the gap to the horizon is hidden by the castle and the tree), so a plane with a
  grass texture is placed under the scene (`MainMenu._ground_filler`, with the camera's far plane pushed out to the
  horizon) — the original frame is unchanged, this only covers its own black gaps near the horizon.
  On phones, anchored HUD groups pull back from the edges by the safe area (notch, rounded
  corners, gesture bar — `DisplayServer.get_display_safe_area`, converted to canvas pixels by
  `DisplayManager.safe_insets_for`); on desktop it's simulated with the `--safe-area=L,T,R,B` flag.
- Messages in the bottom left stack by line count (in the original the step was a fixed 16 px per message and
  two-line ones would overlap).
- The balloon's decorative rotation (`_fflux_rotate`) uses the view's own RNG so it doesn't
  shift the simulation's `Rnd` sequence.
- The sound `eagle.wav` is missing from the distribution (the eagle's screech is skipped).
- Colors: Blitz/D3D7 computes in gamma space, Godot in linear space. The converter
  converts brush and vertex colors to linear (`blitzconv.blitz_color_to_gltf`), while
  light/ambient colors are given as sRGB `Color`s — the products match the original, the sums
  (ambient + diffuse) differ by fractions. Vertex alpha is only kept for brushes
  with `EntityFX 2`, the ones Blitz draws with alpha blending (`Brush::getBlend`: blend
  add/multiply, a layer with alpha, forced alpha 32, or brush alpha < 1 — `b3dlib.Brush.
  uses_vertex_alpha`): the menu fire and the Flame tower's fire, and Location5's grass (fx 35) fading
  into the ground; for everything else it's forced to 1. Additive blending done in gamma space
  doesn't reproduce exactly on a linear pipeline: the alpha of additive brushes (and their vertices)
  is raised to the power 1.5 (`blitzconv.ADDITIVE_ALPHA_EXPONENT`), which matches the
  original at the center of a glow on a dark background (otherwise the menu's green orb would blow out the trunk).
- Tower texture scrolling (`B3DEXT_ANIMMAP` on Magic/Freeze/Fire): `_fupdateextanims` only updates
  the map on the first tower of each type, while `PositionTexture` acts on the shared texture of
  every copy; for Icerock/Flame the "first" one is the hidden level-0 preview tower (frame cycle 0–10).
  `LocationView` tracks this counter (`preview_anim_time`) and hands each `TowerView` a
  driving frame; `BlitzAnimator.update_animmaps(maps, frame)` samples the UVPOS track.
  Otherwise Flame (10 frames in the model) would stand still at levels ≥ 1.
- Texture clamping is a per-layer flag, not a per-brush one: the sidecar writes `clamp_u`/`clamp_v` for each
  entry in `layers`. Single-axis clamp (flags 16/32 individually: `flame.jpg` for the menu fire and
  the Flame tower, `G1.jpg`/`frost.png` for Freeze, `rockalpha.jpg` for the second UV set on Location2's
  rocks) gives the brush a generated shader that repeats one axis while clamping the other
  to the centers of the outermost texels (a sampler with plain repeat on 0/1 blends opposite
  edges together — for Location2's rocks this showed up as a black transparent stripe along the top of the wall).
- `B3DEXT_AMBIENT` / `B3DEXT_DIRLIGHT` store RGB in the node's position; the converter mirrors z,
  so the color must be read via `Blitz.to_godot(position)` (otherwise the blue channel is
  negative and every location turns yellow).
- Directional light `B3DEXT_DIRLIGHT`: `_fext_initlight` does `CreateLight(parent)` +
  `TurnEntity 90,0,0`, i.e. the light points along the parent's local −Y (like B3D
  Extensions' camera) — `LocationView` sets up `DirectionalLight3D` with `MainMenu.CAMERA_FIX`.
- The tower base `dno`: in the original `dno<L>.png` is loaded with the alpha flag, so
  `TowerView` always enables alpha blending (`Freeze.b3d` has its own untextured, opaque base brush).
- `EntityOrder`: in Blitz, ordered entities are drawn without a z-buffer (positive orders
  first, in decreasing order; negative orders last). Godot doesn't draw anything before the
  opaque pass, so positive orders (location ground layers) get a shader that writes the
  depth of the far plane (`DEPTH = 0.0`, reverse-Z) without keeping it: the layer only passes the
  test where nothing has been drawn yet — the same effect as "drawn first with no z" — and
  `render_priority = -order` orders the layers among themselves. Negative orders are a transparent
  pass with no depth test (location zones, e.g. Location6's `noparking` with order −1, do keep the test).
- The import animation optimizer is disabled (`[importer_defaults]` in `project.godot`), otherwise
  Godot would thin out positional path keys. The same section enables mipmaps for textures
  (Blitz loads almost everything with flag 8; without them the ground and tower bases shimmer and look
  "sharper" than the original) and disables `detect_3d` (otherwise the editor would
  recompress the texture into a VRAM format the first time it's shown).
- Pck size. Animations are baked with `animation/fps=1`: 1 Blitz frame = 1 s, so the converters
  write a key for every frame, which is exactly the source keys (30 fps would have produced 30 keys
  per frame — `birdpath1` went from 56K to 900K). JPEG textures are imported as lossy WebP
  (`compress/mode=1`, q=0.85; WebP stores alpha losslessly), PNG atlases and masks are
  imported lossless. Settings live in `.import` sidecars written by
  `tools/godot_import.py` (called from `convert_all.py`): Godot reads the `[params]` of an
  existing sidecar, and only falls back to `[importer_defaults]` for files that don't have one.
  VRAM compression (mode 2/4) doesn't work here: `UvAtlasAnimator` slices the atlas via
  `get_image().get_region()`, and the Web preset would pack every texture twice
  (S3TC + ETC2). Images from the original that are identical in content (skins under `Additional/`,
  `castle2.jpg` across three locations, …) are copied only once (`copy_assets.canonical_images`,
  preferring the directories the code references — `RUNTIME_TEXTURE_DIRS`); the sidecars
  `*.b3d.json`/`*.md2.json`, `manifest.json`, and `addons/` are excluded from the export.
