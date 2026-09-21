#!/usr/bin/env python3
"""Copy the non-model assets of Data/ into the Godot project:

- every image (jpg/png/bmp) -> godot/assets/textures/<path relative to Data>
  (HUD atlases, dno1-6, Water.jpg, border.jpg, Gradient.bmp, Menu/*, Additional/*);
  byte-identical images (the original repeats skins, doors and walls per location) are
  shipped once, see `canonical_images()`;
- every sound (wav/ogg)     -> godot/assets/audio/<basename> (ogg remuxed without its
  malformed comment header, non-PCM wav transcoded).

    python3 tools/copy_assets.py Data/ godot/assets
"""
from __future__ import annotations

import argparse
import functools
import hashlib
import logging
import shutil
import subprocess
from pathlib import Path

LOG = logging.getLogger("copy_assets")

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp"}
AUDIO_SUFFIXES = {".wav", ".ogg"}
# Demo-mode marker files: preved.png is a deliberately corrupt PNG, Demo.bmp a marker.
SKIP_FILES = {"menu/preved.png", "menu/demo.bmp"}
# Directories whose textures the game loads by path at run time (src/ and data/ name them
# as res://assets/textures/<dir>/<file>): a duplicated image is kept in the first of these
# it appears in, so those paths always exist. Other directories rank alphabetically.
RUNTIME_TEXTURE_DIRS = ("", "Monsters", "Towers", "Menu")
# WAV files that are not PCM (oops2.wav is MP3-in-RIFF); Godot needs PCM, so transcode.
PCM_MAGIC = b"fmt "


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


def remove_stale_copy(dst: Path) -> None:
    """Delete a previously copied texture together with its .import and derived PNGs."""
    for p in [dst, *dst.parent.glob(f"{dst.stem}__*.png")]:
        for f in (p, p.with_name(p.name + ".import")):
            if f.exists():
                f.unlink()
                LOG.info("removed duplicate %s", f)


def is_pcm_wav(path: Path) -> bool:
    d = path.read_bytes()
    i = d.find(PCM_MAGIC)
    if i < 0:
        return False
    fmt_tag = int.from_bytes(d[i + 8 : i + 10], "little")
    return fmt_tag in (1, 3)


def transcode_wav(src: Path, dst: Path) -> None:
    """Re-encode to 16-bit PCM with ffmpeg (or afconvert on macOS)."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-acodec", "pcm_s16le", str(dst)], check=True)
    except FileNotFoundError:
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", str(src), str(dst)], check=True)


def remux_ogg(src: Path, dst: Path) -> None:
    """Stream-copy the Ogg Vorbis file without its comment header: the originals carry a
    "Sonic Foundry OggVorbis Beta 3" comment with no '=' that Godot warns about on load."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-map_metadata", "-1", "-c", "copy", str(dst)],
            check=True,
        )
    except FileNotFoundError:
        LOG.warning("ffmpeg not found, copying %s with its malformed comment header", src.name)
        shutil.copy2(src, dst)


def copy_if_changed(src: Path, dst: Path) -> bool:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_size == src.stat().st_size and dst.stat().st_mtime >= src.stat().st_mtime:
        return False
    shutil.copy2(src, dst)
    return True


def copy_assets(data_dir: Path, assets_dir: Path) -> dict[str, list[str]]:
    copied = {"textures": [], "audio": []}
    canonical = canonical_images(data_dir)
    for p in sorted(data_dir.rglob("*")):
        if not p.is_file():
            continue
        suffix = p.suffix.lower()
        if p.relative_to(data_dir).as_posix().lower() in SKIP_FILES:
            continue
        if suffix in IMAGE_SUFFIXES and canonical[p] != p:
            remove_stale_copy(assets_dir / "textures" / p.relative_to(data_dir))
            continue
        if suffix == ".wav" and not is_pcm_wav(p):
            dst = assets_dir / "audio" / p.name
            if not dst.exists():
                transcode_wav(p, dst)
                LOG.info("transcoded %s to PCM", p.name)
                copied["audio"].append(p.name)
            continue
        if suffix in IMAGE_SUFFIXES:
            rel = p.relative_to(data_dir)
            if copy_if_changed(p, assets_dir / "textures" / rel):
                copied["textures"].append(rel.as_posix())
        elif suffix == ".ogg":
            dst = assets_dir / "audio" / p.name
            if not dst.exists() or dst.stat().st_mtime < p.stat().st_mtime:
                remux_ogg(p, dst)
                copied["audio"].append(p.name)
        elif suffix in AUDIO_SUFFIXES:
            if copy_if_changed(p, assets_dir / "audio" / p.name):
                copied["audio"].append(p.name)
    LOG.info("copied %d textures, %d sounds", len(copied["textures"]), len(copied["audio"]))
    return copied


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("data_dir", type=Path)
    ap.add_argument("assets_dir", type=Path)
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    copy_assets(args.data_dir, args.assets_dir)


if __name__ == "__main__":
    main()
