"""The import stage: the unpacked original (`Data/`) -> the port-neutral tree every port
exporter builds from (tools/build_assets.py runs it, then the targets):

    <import>/assets/models/<dir>/<Name>.glb + <Name>.b3d.json   (tools/b3d2gltf.py)
    <import>/assets/models/<dir>/<Name>.glb + <Name>.md2.json   (tools/md2togltf.py)
    <import>/assets/textures/<path>  (+ derived __alpha/__mask PNGs, tools/textures.py)
    <import>/assets/manifest.json    every converted file, the texture report, the fingerprint
    <import>/data/*.json             the game tables (tools/game_data.py)
    <import>/icons/*                 the launcher icons of every platform (tools/icons.py)

The layout mirrors the Godot project's `assets/` and `data/`, so the manifest paths and the
textures' relative URIs inside the glbs hold in both places. Sounds are not converted here:
each port encodes them from the original (tools/audio.py).

The stage is skipped when its inputs have not changed since the last run: the fingerprint
covers every file of `Data/`, the stage's code (tools/*.py), the golden tables in docs/data,
the icon master and the options.
"""
from __future__ import annotations

import hashlib
import json
import logging
import shutil
from pathlib import Path

import b3d2gltf
import md2togltf
from game_data import DOCS_DATA, DOCS_FILES, export_data
from icons import MASTER, generate_icons
from textures import copy_textures

LOG = logging.getLogger("source_import")

TOOLS_DIR = Path(__file__).resolve().parent
MANIFEST = "assets/manifest.json"
OUTPUT_DIRS = ("assets", "data", "icons")
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


def fingerprint(data_dir: Path, options: dict) -> str:
    """Hash of everything the stage reads: file names, sizes and mtimes of `Data/`, the
    contents of its code, golden tables and icon master, and the options."""
    h = hashlib.sha1(json.dumps(options, sort_keys=True).encode())
    for p in sorted(data_dir.rglob("*")):
        if p.is_file():
            st = p.stat()
            h.update(f"{p.relative_to(data_dir).as_posix()}\0{st.st_size}\0{st.st_mtime_ns}\n".encode())
    for p in [*sorted(TOOLS_DIR.glob("*.py")), *(DOCS_DATA / name for name in DOCS_FILES), MASTER]:
        h.update(p.name.encode() + b"\0" + p.read_bytes())
    return h.hexdigest()


def convert_models(data_dir: Path, import_dir: Path, skin: bool, embed: bool) -> dict:
    models_dir = import_dir / "assets" / "models"
    textures_dir = import_dir / "assets" / "textures"
    manifest: dict = {"b3d": {}, "md2": {}, "missing_textures": {}, "warnings": []}
    for src in sorted(data_dir.rglob("*.b3d"), key=lambda p: p.as_posix().lower()):
        rel_dir = src.parent.relative_to(data_dir)
        dst = models_dir / rel_dir / f"{canonical_stem(src, data_dir)}.glb"
        conv = b3d2gltf.convert(src, dst, data_dir, textures_dir, embed=embed, skin=skin)
        key = src.relative_to(data_dir).as_posix()
        manifest["b3d"][key] = {"glb": dst.relative_to(import_dir).as_posix(), "nodes": len(conv.builder.nodes),
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
        manifest["md2"][src.relative_to(data_dir).as_posix()] = {"glb": dst.relative_to(import_dir).as_posix(),
                                                                  "frames": info["frames"], "bbox_min": info["bbox_min"],
                                                                  "bbox_max": info["bbox_max"]}
    return manifest


def load_manifest(import_dir: Path) -> dict | None:
    path = import_dir / MANIFEST
    return json.loads(path.read_text()) if path.exists() else None


def run_import(data_dir: Path, import_dir: Path, skin: bool = True, embed: bool = False, force: bool = False) -> dict:
    """Build `import_dir` from `data_dir` unless it is up to date; returns the manifest."""
    stamp = fingerprint(data_dir, {"skin": skin, "embed": embed})
    manifest = load_manifest(import_dir)
    if manifest is not None and manifest.get("fingerprint") == stamp and not force:
        LOG.info("import stage up to date (%s), skipped", import_dir)
        return manifest
    # A clean rebuild: nothing stale (a renamed model, a texture that became a duplicate)
    # survives into the ports, whose sync mirrors this tree.
    for name in OUTPUT_DIRS:
        shutil.rmtree(import_dir / name, ignore_errors=True)
    manifest = convert_models(data_dir, import_dir, skin, embed)
    copy_textures(data_dir, import_dir / "assets" / "textures")
    export_data(data_dir, import_dir / "data")
    generate_icons(MASTER, import_dir / "icons")
    manifest["fingerprint"] = stamp
    (import_dir / MANIFEST).parent.mkdir(parents=True, exist_ok=True)
    (import_dir / MANIFEST).write_text(json.dumps(manifest, indent=1) + "\n")
    LOG.info("converted %d b3d, %d md2; missing textures in %d files", len(manifest["b3d"]), len(manifest["md2"]),
             len(manifest["missing_textures"]))
    for k, v in manifest["missing_textures"].items():
        LOG.warning("%s: missing %s", k, v)
    return manifest
