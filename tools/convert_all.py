#!/usr/bin/env python3
"""Convert the whole Data/ directory for the Godot project.

    python3 tools/convert_all.py MasterOfDefense_unpacked/Data godot

- *.b3d -> godot/assets/models/<dir>/<Name>.glb + <Name>.b3d.json (tools/b3d2gltf.py)
- *.md2 -> godot/assets/models/<dir>/<Name>.glb + <Name>.md2.json (tools/md2togltf.py)
- images/sounds -> godot/assets/{textures,audio} (tools/copy_assets.py)
- pins the import options in the .import sidecars (tools/godot_import.py)
- writes godot/assets/manifest.json with every converted file and the texture report.
"""
from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path

import b3d2gltf
import md2togltf
from copy_assets import copy_assets
from godot_import import apply_import_params

LOG = logging.getLogger("convert_all")

# Files whose on-disk case differs from the names the game code uses (keys are paths
# relative to Data/, lower case).
CANONICAL_STEMS = {"location1/location1.b3d": "Location1", "location2/location2.b3d": "Location2",
                   "location3/location3.b3d": "Location3", "location4/location4.b3d": "Location4",
                   "location5/location5.b3d": "Location5", "location6/location6.b3d": "Location6",
                   "env.b3d": "Env"}
for _L in range(1, 7):
    CANONICAL_STEMS[f"location{_L}/path1.b3d"] = "Path1"


def canonical_stem(p: Path, data_dir: Path) -> str:
    return CANONICAL_STEMS.get(p.relative_to(data_dir).as_posix().lower(), p.stem)


def convert_all(data_dir: Path, godot_dir: Path, skin: bool = True, embed: bool = False) -> dict:
    models_dir = godot_dir / "assets" / "models"
    textures_dir = godot_dir / "assets" / "textures"
    manifest: dict = {"b3d": {}, "md2": {}, "missing_textures": {}, "warnings": []}
    for src in sorted(data_dir.rglob("*.b3d"), key=lambda p: p.as_posix().lower()):
        rel_dir = src.parent.relative_to(data_dir)
        dst = models_dir / rel_dir / f"{canonical_stem(src, data_dir)}.glb"
        conv = b3d2gltf.convert(src, dst, data_dir, textures_dir, embed=embed, skin=skin)
        key = src.relative_to(data_dir).as_posix()
        manifest["b3d"][key] = {"glb": dst.relative_to(godot_dir).as_posix(), "nodes": len(conv.builder.nodes),
                                "anim_frames": conv.b3d.anim_frames}
        if conv.sidecar["missing_textures"]:
            manifest["missing_textures"][key] = conv.sidecar["missing_textures"]
    for src in sorted(data_dir.rglob("*.md2"), key=lambda p: p.as_posix().lower()):
        rel_dir = src.parent.relative_to(data_dir)
        skin_file = next((p for p in src.parent.iterdir() if p.stem.lower() == src.stem.lower() and p.suffix.lower() in (".jpg", ".png")), None)
        if skin_file is None:
            manifest["warnings"].append(f"no skin for {src.name}")
        dst = models_dir / rel_dir / f"{src.stem}.glb"
        info = md2togltf.convert(src, skin_file, dst, data_dir, textures_dir, embed=embed)
        manifest["md2"][src.relative_to(data_dir).as_posix()] = {"glb": dst.relative_to(godot_dir).as_posix(),
                                                                  "frames": info["frames"], "bbox_min": info["bbox_min"],
                                                                  "bbox_max": info["bbox_max"]}
    copied = copy_assets(data_dir, godot_dir / "assets")
    manifest["copied"] = {k: len(v) for k, v in copied.items()}
    apply_import_params(godot_dir)
    (godot_dir / "assets" / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    LOG.info("converted %d b3d, %d md2; missing textures in %d files", len(manifest["b3d"]), len(manifest["md2"]),
             len(manifest["missing_textures"]))
    for k, v in manifest["missing_textures"].items():
        LOG.warning("%s: missing %s", k, v)
    return manifest


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("data_dir", type=Path)
    ap.add_argument("godot_dir", type=Path)
    ap.add_argument("--no-skin", dest="skin", action="store_false", help="keep B3D bones rigid")
    ap.add_argument("--embed", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    convert_all(args.data_dir.resolve(), args.godot_dir.resolve(), args.skin, args.embed)


if __name__ == "__main__":
    main()
