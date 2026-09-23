"""The original's images, shared by every port:

- every image (jpg/png/bmp) -> `<textures_dir>/<path relative to Data>` (HUD atlases,
  dno1-6, Water.jpg, border.jpg, Gradient.bmp, Menu/*, Additional/*);
- byte-identical images (the original repeats skins, doors and walls per location) are
  shipped once, see `canonical_images()`.
"""
from __future__ import annotations

import functools
import hashlib
import logging
import shutil
from pathlib import Path

LOG = logging.getLogger("textures")

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp"}
# Demo-mode marker files: preved.png is a deliberately corrupt PNG, Demo.bmp a marker.
SKIP_FILES = {"menu/preved.png", "menu/demo.bmp"}
# Directories whose textures the game loads by path at run time (src/ and data/ name them
# as res://assets/textures/<dir>/<file>): a duplicated image is kept in the first of these
# it appears in, so those paths always exist. Other directories rank alphabetically.
RUNTIME_TEXTURE_DIRS = ("", "Monsters", "Towers", "Menu")


def _canonical_rank(rel: Path) -> tuple[int, str]:
    parent = rel.parent.as_posix()
    if parent == ".":
        parent = ""
    if parent in RUNTIME_TEXTURE_DIRS:
        return (RUNTIME_TEXTURE_DIRS.index(parent), rel.as_posix().lower())
    return (len(RUNTIME_TEXTURE_DIRS), rel.as_posix().lower())


@functools.lru_cache(maxsize=None)
def canonical_images(data_dir: Path) -> dict[Path, Path]:
    """Map every image under `data_dir` to the copy that is shipped: byte-identical files
    collapse into the one ranked first by `_canonical_rank`, unique files map to themselves."""
    by_hash: dict[str, list[Path]] = {}
    for p in sorted(data_dir.rglob("*")):
        if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES:
            by_hash.setdefault(hashlib.md5(p.read_bytes()).hexdigest(), []).append(p)
    canonical: dict[Path, Path] = {}
    for paths in by_hash.values():
        keep = min(paths, key=lambda p: _canonical_rank(p.relative_to(data_dir)))
        for p in paths:
            canonical[p] = keep
    return canonical


def copy_if_changed(src: Path, dst: Path) -> bool:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_size == src.stat().st_size and dst.stat().st_mtime >= src.stat().st_mtime:
        return False
    shutil.copy2(src, dst)
    return True


def copy_textures(data_dir: Path, textures_dir: Path) -> list[str]:
    """Copy every canonical image of `data_dir` into `textures_dir`; returns the copied
    paths (relative to Data)."""
    copied = []
    canonical = canonical_images(data_dir)
    for p in sorted(data_dir.rglob("*")):
        if not p.is_file() or p.suffix.lower() not in IMAGE_SUFFIXES:
            continue
        rel = p.relative_to(data_dir)
        if rel.as_posix().lower() in SKIP_FILES or canonical[p] != p:
            continue
        if copy_if_changed(p, textures_dir / rel):
            copied.append(rel.as_posix())
    LOG.info("copied %d textures", len(copied))
    return copied
