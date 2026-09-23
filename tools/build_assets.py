#!/usr/bin/env python3
"""Build the game's resources for one port or both from the unpacked original.

    python3 tools/build_assets.py --target {godot,defold,all} [--data-dir Data] [--import-dir build/import]
                                  [--force] [--no-skin] [--embed]

1. The import stage (tools/source_import.py): Data/ -> the port-neutral tree in
   `--import-dir` (glb models + sidecars, textures, game tables, launcher icons); skipped
   when its inputs have not changed since the last run (`--force` rebuilds it).
2. The targets, each from that tree and the original's sounds:
   - godot  (tools/targets/godot.py): godot/assets, godot/data, godot/icons and the
     `.import` options; `godot --import` (make import) imports them;
   - defold (tools/targets/defold/): defold/assets, defold/generated, defold/data (emptied first);
     bob (defold/tools/bob.sh) builds the project.
"""
from __future__ import annotations

import argparse
import logging
from pathlib import Path

from source_import import run_import
from targets import godot
from targets.defold.export import Exporter

ROOT = Path(__file__).resolve().parent.parent
TARGETS = ("godot", "defold")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target", choices=(*TARGETS, "all"), default="all", help="port(s) to build (default: all)")
    ap.add_argument("--data-dir", type=Path, default=ROOT / "MasterOfDefense_unpacked" / "Data", help="the unpacked original")
    ap.add_argument("--import-dir", type=Path, default=ROOT / "build" / "import", help="the import stage's tree")
    ap.add_argument("--godot", type=Path, default=ROOT / "godot", help="Godot project")
    ap.add_argument("--defold", type=Path, default=ROOT / "defold", help="Defold project")
    ap.add_argument("--force", action="store_true", help="rebuild the import stage even if it is up to date")
    ap.add_argument("--no-skin", dest="skin", action="store_false", help="keep B3D bones rigid")
    ap.add_argument("--embed", action="store_true", help="embed the textures into the glbs")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    data_dir, import_dir = args.data_dir.resolve(), args.import_dir.resolve()
    if not data_dir.is_dir():
        ap.error(f"no unpacked original at {data_dir}")
    targets = TARGETS if args.target == "all" else (args.target,)
    run_import(data_dir, import_dir, skin=args.skin, embed=args.embed, force=args.force)
    if "godot" in targets:
        godot.export(import_dir, data_dir, args.godot.resolve())
    if "defold" in targets:
        Exporter(import_dir, data_dir, args.defold.resolve()).run()


if __name__ == "__main__":
    main()
