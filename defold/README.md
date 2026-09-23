# Master of Defense — Defold port

A complete port of the game to **Defold 1.13** in Lua: the main menu with its 3D sheets
and settings, the world map with the storyline, all six locations of the campaign on
three difficulties, Survival, the tutorial, the balloon and its bombs, the in-game menu,
saves (automatic, per location, quick save), the final titles and local high score
tables. It runs on the desktop, in the browser and on Android / iOS.

The rules follow the decompiled original (`reference/decomp`, [`docs/`](../docs/README.md));
the Godot remake (`godot/`) served as the reference for how the original engine behaves.

Everything in `assets/`, `data/` and `generated/` is produced from the unpacked original
game by the shared pipeline (`tools/build_assets.py`: the port-neutral import stage in
`build/import`, then this port's backend `tools/targets/defold/`) and is gitignored; the export empties these directories before it writes them:

```bash
make defold            # import stage (skipped when up to date) + every location, the menus and the entities into defold/
make defold-run        # bob build + dmengine (ARGS="--config=main.location=3")
make defold-web        # browser bundle -> build/defold-web (serve it over http)
make defold-android    # .apk -> build/defold-android
defold/tools/bob.sh ios   # needs IOS_IDENTITY and IOS_PROVISIONING
make test-sim          # the Lua simulation's headless tests (plain `lua`)
```

Or open `defold/` in the Defold editor after `make defold` (the bootstrap collection
refers to generated files). `tools/bob.sh` downloads `bob.jar` / `dmengine` matching the
installed editor's engine SHA into `build/defold-tools`. Every command builds and runs the
release engine (no log, profiler or debug web server); `VARIANT=debug` (e.g.
`VARIANT=debug make defold-run`) takes the debug one, which prints the log and the
`log_level=debug` output. bob 1.13.1's BasisU encoder now and then deadlocks: `bob.sh`
kills a build whose CPU time stops for `BOB_STALL_SECONDS` (60) and retries it.

Size: `tools/bob.sh` builds with `--texture-compression`, so `render/level.texture_profiles`
applies: textures ship as Basis UASTC (RGB for the jpg ones), transcoded at load to what the
GPU supports; the HUD atlas stays raw RGBA for the crisp glyphs. `make defold` re-encodes the
music and the wavs longer than 2 s with libvorbis (`oggenc`, e.g. `brew install
vorbis-tools`, plus `ffmpeg`); short effects stay PCM.

## Controls

Arrow keys / WASD or the mouse at the window edge scroll; the panel buttons (or keys
1–5) start placing a tower, LMB places it (Flame: on the road), RMB cancels, deselects and
sends the balloon (RMB on the road); U/R upgrade, Delete sells, Tab cycles the towers,
Space toggles the health bars, N/M normal/fast speed (or the slider), E/F2 the skills
window (from location 2 on, as in the original), F5/F9 quick save/load, Esc (Android
Back) closes a window or opens the in-game menu. On a touch screen a tap is the left
click, a long press the right click and a drag scrolls the map.

Debug options: `--config=main.<name>=<value>` on the desktop, `?<name>=<value>` on the
web. `location=N` [`titul=T`] starts a campaign there, `continue=1` loads the automatic
save, `survival=1`, `show_ending=N` (final titles, score N), `wide=1`; on a location
`demo=1` (a scripted defense that keeps upgrading), `demo_ticks=N` (simulate N ticks
first), `demo_skills=1`, `demo_menu=1`, `pivot_x`/`pivot_z` (camera), `auto_advance=1`
(leaves the map and the end sheets by itself); in the main menu `menu_script=start,new`
(activates items) and `menu_hover=item`; `log_level=debug`.

## Architecture

- **Screens are collection proxies** of the bootstrap collection `main/main.collection`:
  `main/controller.script` owns the session and switches between `main/menu/`,
  `main/map/`, the six generated location collections and `main/ending/` (the campaign's
  final titles and scores; the survival score sheet hangs over its location, as in the
  original), one loaded at a time, the "Loading" plank shown while a location loads.
  The audio script and the sounds live in the bootstrap collection too.
- **State**: `main/session.lua` holds the game tables, the settings and the running game
  (`script.shared_state`); screens change screens only by messages to the controller
  (`main/messages.lua`, small payloads). `main/storage.lua` keeps saves, settings and
  high scores with `sys.save` (IndexedDB on the web).
- **Simulation** (`sim/`, pure Lua, tested headless): `game.lua` (`_fgamelogic`: raids,
  spawning, towers, bullets, effects, economy, auto-balance, campaign progression,
  balloon and bombs, events instead of signals), `survival.lua`, `balloon.lua`,
  `tutorial.lua`, `savegame.lua`, `profile.lua` (settings defaults, difficulty unlocks,
  saves, high score tables), `skills.lua`, `balance.lua`, `path_follower.lua`, `data.lua`,
  `blitz.lua` (Blitz numerics and its random generator).
- **Location screen** (`main/location/`): `location.script` ticks the game on the fixed
  step, turns input into intents and runs the end sheets, the in-game menu
  (`ingame_menu.lua`) and the tutorial; `world.lua` maps simulation events to views
  (`main/views/`) keyed by the simulation objects; `decor.lua` runs location 1's clock,
  location 2's eagle and water; `hud.gui_script` owns the HUD's input and draws what
  `hud_model.lua` composes; `camera.script` scrolls.
- **3D menus** (`main/ui/menu_scene.lua`): the original's menu sheets are bone-posed
  models drawn by a fixed overlay camera; items are picked by casting the mouse ray
  into each item's joint space, hidden through their joint's pose, and the `sel` cursor is
  laid onto the hovered item. Texts are the 16×16 glyphs of the original font as gui box
  nodes (`main/ui/glyph_text.lua`), which keeps the per-letter colours and fades;
  `main/ui/widgets.lua` has the settings widgets.
- **Rendering** (`render/blitz.render_script`): Blitz's draw order (positive EntityOrders
  first without the z-buffer, the opaque world, the tower bases, the translucent brushes,
  negative orders last), then the overlay (HUD panel, sheets) in the 4:3 box and the gui.
  The scene light (a directional light in the locations, the menu's two point lights)
  comes from the screen in a constant buffer, so one set of materials serves every
  location. Translucent brushes of one model draw in depth-ranked passes (Blitz sorts by
  entity, Defold by model; the static HUD panel is ranked node by node), and the sheets'
  alpha-textured brushes also write the depth of their solid texels. Only the changed
  render state is set between passes (the engine allows 1024 render commands a frame).
  The menu's loading curtain is drawn across the whole canvas, so in Wide mode it covers
  the sides too; the rest of the overlay stays in the 4:3 box.
  The gui atlas is premultiplied (Defold's gui blends premultiplied alpha).

## The exporter

`../tools/targets/defold/` reads the import stage's glbs and `.b3d.json` sidecars (the
same ones the Godot port imports), so the conventions verified for Godot are reused; the
sounds are encoded from the original (`../tools/audio.py`).

- **Models**: Defold plays only skeletal and morph target animations, so B3D node
  animation becomes skinning — one joint per node. Hierarchies Defold's SRT bones cannot
  represent (shear, degenerate scale, animated billboards) and every menu sheet are
  **bone-posed**: joint-local vertices and baked world matrices per frame
  (`generated/bones/`), uploaded by the runtime. Primitives that need their own state
  (tower base, animated textures, river / border, swapped textures) become separate
  model components; location 1's clock hands separate game objects.
- **Materials**: one per brush, EntityOrder and group: the two-layer `TextureBlend`
  combine, sphere maps (V flipped relative to Godot: Defold flips imported texcoords only),
  EntityFX, per-vertex Blitz lighting, billboards (`PointEntity` toward the camera
  position), animated texture frames (`frame_atlas`); a menu sheet's translucent brushes
  draw in depth layers (Defold sorts meshes of one model by the model's origin).
- **Generated data**: `generated/locations/l<N>.lua` (bounds, background, light, zones,
  decorations), `generated/collections/location<N>.collection`, `generated/menus.lua`
  (pickable menu items, the menu camera's flight), `generated/models.lua`,
  `generated/render_passes.lua`, `generated/entities.go`, `generated/sounds.go` (groups
  `music` / `sfx` for the volume settings).
- **Icons**: the import stage's icon set (`../tools/icons.py`, from `../art/icon_1024.png`) gives `generated/icons/` (Android / iOS PNGs,
  macOS `.icns`, Windows `.ico`) and the bundle resources `generated/bundle/` (Android's
  adaptive icon, the web `favicon.ico`, linked into `index.html` by `tools/bob.sh web`).

## Deviations and known gaps

- High scores are two local top-10 tables (campaign, survival); the online submission and
  its "send" planks are gone, the survival sheet's remaining planks are centred.
- Wide mode (a setting): the world fills the window, wider or taller than 4:3, the HUD
  panel, the sheets and the gui stay in the centred 4:3 box; the cameras keep the 4:3 frame
  in view (the vertical fov when wider, the horizontal one when taller). The menu backdrop
  allows 1.25:1 to 1.8:1. A location's camera range narrows by the extra ground the bigger
  view uncovers, and a location is drawn only as wide / tall as that range allows (location
  1 about 1.07:1 to 1.64:1, the others up to 2.3:1 to 2.9:1), so the wide view never shows
  ground the 4:3 view could not (`main/location/camera_view.lua`, as godot's CameraRig).
- The settings drop the original's resolution, colour depth and VSync; fullscreen can be
  toggled in the browser only (the desktop window mode is the platform's). The gamma
  (`SetGamma` offsets of -100..100 levels) is a full-screen pass over a render target,
  drawn only while it is not 0.
- Location 2's water loop is not positional (Defold has no 3D sound): its gain follows the
  camera's distance to the door with the original listener's roll-off.
- The eagle's scream every five minutes is skipped: `eagle.wav` is missing from the
  original distribution.
- Leaving the window (focus lost) writes the automatic save like the menu's "to menu",
  for phones that close background apps.
- Loading a survival save draws its raids anew, as the original's load re-runs
  `_floaddata`; past raid 200 the last raid repeats (the original read beyond its table).
- `collectionproxy` `async_load` crashes the macOS engine (MoltenVK), so screens load
  synchronously behind the Loading plank.
- Not ported: the demo / "buy now" screens, the `B3DEXT_ANIMBRUSH` colour/alpha keys
  (only `death2.b3d`) and single-axis texture clamps; phone safe areas are not handled
  (the 4:3 box keeps clear of a side notch).
- A raid whose first monster dies before the second spawns ends at once and its remaining
  monsters spill into the next raid — the original's `_fdeleteenemy` → `_fnextlevel`
  behaviour, reproduced by the Godot port too.
