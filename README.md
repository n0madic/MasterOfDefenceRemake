# Master of Defense — Godot remake

A fan-made, from-scratch remake of **Master of Defense** (Voodoo Dimention, 2006) — a
Blitz3D tower-defense game — built for **Godot 4.7** (desktop, web, Android, iOS).

The remake is driven entirely by reverse-engineering the original: the game's binary
(`Main.exe`) was decompiled and every rule (damage formulas, tick timing, spawn logic,
skill math, HUD layout, …) was recovered from the actual code, not guessed from
gameplay. See [`docs/`](docs/README.md) for the full research write-up.

This is a personal, non-commercial fan project. It is not affiliated with, endorsed by,
or derived from any source code owned by Voodoo Dimention. **You need your own legally
owned copy of the original game** to build and run it — no original game assets are
included in this repository.

## Repository layout

| Path | What it is |
|---|---|
| [`docs/`](docs/README.md) | Reverse-engineering notes on the original game: data formats, game rules, UI, HUD geometry, notes for the remake |
| [`tools/`](tools/README.md) | Python pipeline: decompilation helpers, and the converters that turn the original's data/models/textures into Godot assets |
| [`godot/`](godot/README.md) | The remake itself (GDScript project) — simulation, scenes, HUD, tests |
| `Makefile` | All the day-to-day commands (data pipeline, tests, running, platform exports) — run `make help` |

## Status

The full campaign (6 locations, 180 raids), Survival mode, the skills/upgrade system,
settings, saves, and local high scores are implemented and covered by an automated
headless test suite (simulation logic + a full scripted campaign run). See
[`godot/README.md`](godot/README.md) for the exact architecture and the list of
intentional deviations from the original.

## Prerequisites

- [Godot 4.7.x](https://godotengine.org/) (the project pins `4.7`, Forward+ renderer)
- Python 3.10+ (only needed to run the asset/data pipeline and its tests)
- Your own copy of **Master of Defense** (`MasterOfDefense.exe`, the original Inno Setup
  installer), unpacked so that `MasterOfDefense_unpacked/Data/` sits at the repo root.
  Unpack the installer without running it, e.g. with
  [`innoextract`](https://constexpr.org/innoextract/) (`innoextract MasterOfDefense.exe`)
  or 7-Zip, and point `Data/` accordingly. This directory is gitignored — the pipeline
  reads it locally but nothing from it is ever committed.

## Quick start

```bash
# 1. Build the Godot data/assets from your copy of the original game
make pipeline          # = data + assets + import (needs MasterOfDefense_unpacked/Data)

# 2. Run the game
make run                       # main menu
make run ARGS="--location=1"   # jump straight into a location (see godot/README.md for all debug flags)
```

Equivalent without `make`:

```bash
python3 tools/export_godot_data.py MasterOfDefense_unpacked/Data godot/data
python3 tools/convert_all.py MasterOfDefense_unpacked/Data godot
godot --headless --path godot --import
godot --path godot
```

## Tests

```bash
make test          # both suites below
make test-godot     # headless GDScript simulation/UI tests
make test-tools     # Python tests for the conversion pipeline
```

## Building for other platforms

```bash
make web            # → build/web (playable in a browser)
make android         # → build/android (debug APK)
make ios IOS_TEAM_ID=XXXXXXXXXX   # → build/ios (Xcode project, sign/archive in Xcode)
make help            # full list of targets and options
```

Export templates for your installed Godot version are required for these
(`make check-templates` verifies they're present). Platform-specific notes (Vulkan vs.
Compatibility rendering, keystores, the trimmed Android template, etc.) are in
[`godot/README.md`](godot/README.md#builds-mobile-and-web).

## Learn more

- [`docs/README.md`](docs/README.md) — how the original game actually works, reconstructed from its code
- [`godot/README.md`](godot/README.md) — the remake's architecture, conventions, and every intentional deviation from the original
- [`tools/README.md`](tools/README.md) — the decompilation and asset-conversion pipeline
