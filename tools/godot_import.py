#!/usr/bin/env python3
"""Pin the Godot import options of the generated assets in their `.import` sidecars.

    python3 tools/godot_import.py godot

Godot reads the `[params]` of an existing `.import` file and only falls back to the
project's `[importer_defaults]` when there is none, so options that depend on the file
type (lossy WebP for the JPEG textures, lossless for the PNG atlases and masks) or that
changed after the first import (one animation key per Blitz frame) have to be written
here. A texture without a sidecar gets a minimal one that Godot completes on import;
a model without one is left to `[importer_defaults]` (its options include the
post-import script, which must not be dropped by a partial sidecar). Whenever a sidecar
changes, its import products are deleted so the next `godot --import` regenerates them
even without the editor's filesystem cache.
"""
from __future__ import annotations

import argparse
import json
import logging
import re
from pathlib import Path

LOG = logging.getLogger("godot_import")

# Kept in sync with `[importer_defaults]` texture in project.godot (those only apply to
# files that have no sidecar yet, e.g. the icons).
TEXTURE_PARAMS = {"mipmaps/generate": True, "detect_3d/compress_to": 0}
# JPEG sources are already lossy; storing them losslessly (WebP lossless + mipmaps)
# made every one 5-10x larger than the source. Lossy WebP keeps the alpha channel exact.
JPG_PARAMS = {"compress/mode": 1, "compress/lossy_quality": 0.85}
# 1 Blitz frame = 1.0 s of the imported animation (BlitzAnimator.seek) and the converters
# write one key per frame, so baking at 1 fps reproduces the source keys exactly; the
# default 30 fps stored 30 keys per frame.
SCENE_PARAMS = {"animation/fps": 1}

DEST_RE = re.compile(r'"(res://[^"]+)"')


def format_value(v: object) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    return json.dumps(v)


def _set_params(text: str, params: dict[str, object]) -> str:
    """Replace or add `key=value` lines in the `[params]` section of a .import file."""
    lines = text.splitlines()
    pending = dict(params)
    start = next((i for i, l in enumerate(lines) if l.strip() == "[params]"), None)
    if start is None:
        lines += ["", "[params]", ""]
        start = len(lines) - 2
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    for i in range(start + 1, end):
        key = lines[i].split("=", 1)[0]
        if key in pending:
            lines[i] = f"{key}={format_value(pending.pop(key))}"
    insert_at = end
    while insert_at > start + 1 and lines[insert_at - 1] == "":
        insert_at -= 1
    lines[insert_at:insert_at] = [f"{k}={format_value(v)}" for k, v in pending.items()]
    return "\n".join(lines) + "\n"


def _remove_products(godot_dir: Path, text: str) -> None:
    for m in re.finditer(r"^(?:dest_files|path)=(.*)$", text, re.M):
        for res in DEST_RE.findall(m.group(1)):
            product = godot_dir / res[len("res://"):]
            for f in (product, product.with_suffix(".md5")):
                if f.exists():
                    f.unlink()


def ensure_import_params(godot_dir: Path, source: Path, importer: str | None, params: dict[str, object]) -> bool:
    """Make `<source>.import` carry `params`. Returns True when the sidecar was written.
    With `importer` None a missing sidecar is left to the project's importer defaults."""
    sidecar = source.with_name(source.name + ".import")
    if sidecar.exists():
        old = sidecar.read_text()
        new = _set_params(old, params)
        if new == old:
            return False
        _remove_products(godot_dir, old)
    elif importer is None:
        return False
    else:
        new = _set_params(f"[remap]\n\nimporter={json.dumps(importer)}\n", params)
    sidecar.write_text(new)
    return True


def apply_import_params(godot_dir: Path) -> int:
    """Pin the options of every generated texture and model; returns the number written."""
    assets = godot_dir / "assets"
    written = 0
    for p in sorted((assets / "textures").rglob("*")):
        suffix = p.suffix.lower()
        if suffix in (".jpg", ".jpeg"):
            written += ensure_import_params(godot_dir, p, "texture", {**TEXTURE_PARAMS, **JPG_PARAMS})
        elif suffix in (".png", ".bmp"):
            written += ensure_import_params(godot_dir, p, "texture", TEXTURE_PARAMS)
    for p in sorted((assets / "models").rglob("*.glb")):
        written += ensure_import_params(godot_dir, p, None, SCENE_PARAMS)
    LOG.info("import options written for %d files", written)
    return written


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("godot_dir", type=Path)
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    apply_import_params(args.godot_dir.resolve())


if __name__ == "__main__":
    main()
