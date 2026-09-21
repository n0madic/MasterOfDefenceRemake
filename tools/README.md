# tools — recovering Master of Defense's logic

The scripts used to produce `docs/` and `reference/`. Requirements: Python 3.10+, `pefile`,
`capstone` (for manual disassembly), Ghidra 12 (`analyzeHeadless`).

| Script | Purpose |
|---|---|
| `extract_blitz_module.py EXE OUT_DIR [--base 0x20000000] [--runtime-syms F]` | extracts the Blitz module from resource `RCDATA/1111`, applies relocations, writes `module.bin`, `symbols.txt`, `relocs.txt` |
| `find_runtime_syms.py EXE OUT` | finds the addresses of Blitz3D runtime functions (`rtSym("decl", func)`) → `runtime_syms.txt` |
| `ghidra/LoadBlitzModule.java` | a Ghidra post-script: adds a memory block for the module, labels symbols, creates functions, and decompiles everything into a directory |
| `postprocess_decomp.py MODULE_DIR DECOMP_DIR OUT_DIR` | substitutes runtime function names, string constants, and hex-float comments |
| `b3d_dump.py FILES [--names-only] [--keys]` | dumps chunks/nodes/keys of `.b3d` files |
| `md2_dump.py FILES [--frames]` | MD2 headers |
| `export_paths.py DATA_DIR OUT.json` | enemy path points from `Location*/Path1.b3d` |
| `export_csv.py DATA_DIR OUT_DIR` | CSV → `units.json`, `towers.json`, `raids.json` with the original's semantics |
| `dump_types.py MODULE_DIR [types…]` | field types of every Blitz `Type` from the `BBObjType` descriptors in the module → `docs/data/blitz_types.txt` |
| `hud_layout.py Data/env.b3d [--json OUT]` | projects the HUD panel's quads into 800×600 coordinates → `docs/data/hud_layout.json` |
| `simulate_path.py enemy_paths.json [--raids-json raids.json] [--speed S…] [--json OUT]` | simulates an enemy moving along a path (ticks/seconds) → `docs/data/path_times.json` |

## Remake pipeline (Godot)

| Script | Purpose |
|---|---|
| `b3dlib.py` | module: parses B3D into a tree (`B3DFile{textures, brushes, root}`), `clean_name` for the `B3D_ORDR_n_`/`B3D_BB_1_` prefixes; `b3d_dump.py` is a printer built on top of it |
| `blitzconv.py` | convention C1: mirroring coordinates/quaternions, triangle index order (`WINDING_SWAP`), MD2 axes |
| `gltfwriter.py` | a minimal `.glb` writer (and `read_glb` for tests) |
| `b3d2gltf.py IN.b3d OUT.glb --data-dir Data --textures-dir godot/assets/textures [--embed] [--no-skin]` | B3D → glb + sidecar `OUT.b3d.json` (order, tags, blend, lightmaps); BONE bones → a glTF skin; texture UV transforms are baked (the second layer → `TEXCOORD_1`); brush/vertex colors are converted from gamma to linear, vertex alpha is only kept for brushes with `EntityFX 2` (the ones Blitz draws with alpha blending, `Brush.uses_vertex_alpha`), the alpha of additive brushes is raised to the power 1.5 (to compensate for linear blending); for mirrored nodes (negative scale determinant: `Line04` on Location6, the `selection.b3d` circles) triangle winding is flipped, because Godot itself flips culling for such instances while D3D doesn't; alpha/mask PNGs are generated per Blitz's rules |
| `md2togltf.py IN.md2 [SKIN] OUT.glb --data-dir Data --textures-dir …` | MD2 → glb with morph targets (frame k at t = k) + `OUT.md2.json` (bbox) |
| `copy_assets.py Data godot/assets` | images → `assets/textures/<path>`, sounds → `assets/audio/` (non-PCM wav is re-encoded with ffmpeg/afconvert; ogg is remuxed with ffmpeg to drop the malformed "Sonic Foundry…" comment header that Godot complains about) |
| `convert_all.py Data godot [--no-skin] [--embed]` | orchestrator: all b3d/md2 files + assets, writes `godot/assets/manifest.json` |
| `export_godot_data.py Data godot/data` | `units/towers/raids/paths/locations/texts.json` for the game (in Godot coordinates) + copies of `hud_layout.json`, `path_times.json` |
| `tests/` | `python3 -m unittest discover -s tools/tests -v` — checks for the parser, conversion, and export (needs `Pillow`, the unpacked data, and a completed `convert_all` run) |

## Full decompilation pipeline

```bash
EXE=MasterOfDefense_unpacked/Main.exe
python3 tools/find_runtime_syms.py $EXE work/module/runtime_syms.txt
python3 tools/extract_blitz_module.py $EXE work/module --runtime-syms work/module/runtime_syms.txt
# import the PE into a Ghidra project (once), then:
analyzeHeadless work/ghidra MOD -import $EXE            # initial runtime analysis
analyzeHeadless work/ghidra MOD -process Main.exe -noanalysis \
    -scriptPath tools/ghidra -postScript LoadBlitzModule.java work/module work/decomp 0x20000000
python3 tools/postprocess_decomp.py work/module work/decomp reference/decomp
```

The pipeline's output already sits in `reference/decomp/` (483 functions) and `reference/module/`.
