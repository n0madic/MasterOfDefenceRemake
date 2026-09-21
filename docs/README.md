# Master of Defense — research on the original

Documentation on the classic game **Master of Defense** (Voodoo Dimention, 2006, version 1.67e)
for building a remake in Godot. Everything written here comes from the unpacked
distribution (`MasterOfDefense_unpacked/`) and decompilation of the game module `Main.exe`.

## How to read this

- The mark **[code: `_fname`]** means the fact is confirmed by the decompiled function
  `reference/decomp/_fname.c`. Function and global-variable names are the original
  ones (the Blitz3D linker's symbols survived in the executable).
- The mark **[assumption]** is a conclusion not directly verified in the code.
- Numeric constants are given exactly (from the code); the unit of game time is the **tick**
  of the logic (at normal speed the tick period is `1000 \ 60 = 16` ms, i.e. 62.5 ticks/s, see [01-overview.md](01-overview.md)).

## Contents

| File | About |
|---|---|
| [01-overview.md](01-overview.md) | Engine, distribution files, launch, main loop, time model, hotkeys |
| [02-data-formats.md](02-data-formats.md) | Formats of all data: CSV, `.vdd`, texts, B3D, MD2, saves, the Blitz module format in the exe |
| [03-levels-locations.md](03-levels-locations.md) | Locations, scene nodes, enemy paths, raid ranges, camera |
| [04-enemies-raids.md](04-enemies-raids.md) | Monsters, raids, spawning, movement, health/armor/speed, healers, bosses, inhabitants |
| [05-towers.md](05-towers.md) | Towers: types, building, upgrading, selling, target selection, bullets, damage, effects |
| [06-magic-skills.md](06-magic-skills.md) | "Magic and skills" window: experience, 9 skills, prices, limits, application formulas |
| [07-balloon.md](07-balloon.md) | The balloon and bombs |
| [08-economy-lives-difficulty.md](08-economy-lives-difficulty.md) | Gold, inhabitants (lives), experience, auto-balance, difficulty modes, survival, score |
| [09-ui-menus-tutorial.md](09-ui-menus-tutorial.md) | Menus, HUD, tutorial, messages, sounds/music |
| [10-type-layouts.md](10-type-layouts.md) | Field layout of Blitz types (a key for reading the decompiled output) |
| [11-assets.md](11-assets.md) | Asset inventory and what's actually used |
| [12-remake-notes.md](12-remake-notes.md) | Notes for the Godot remake and a list of unknowns |
| [13-hud-geometry.md](13-hud-geometry.md) | Exact HUD geometry: the `gui.png` atlas, font, `Env.b3d` panel, every button and tooltip |
| `data/` | Machine-readable dumps: `units.json`, `towers.json`, `raids.json`, `enemy_paths.json`, `path_times.json`, `hud_layout.json`, `blitz_types.txt` |

The tools used to produce all of this live in `../tools/` (see `tools/README.md`);
the decompiled functions are in `../reference/decomp/`.
