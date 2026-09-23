"""The Godot port's backend: the import stage's tree (tools/source_import.py) -> godot/.

- `assets/` and `data/` are mirrored into godot/assets and godot/data (`sync_tree`: hard
  links where the file system allows, copies otherwise; files the import stage no longer
  makes are deleted together with their `.import` sidecars);
- the sounds are encoded from the original into godot/assets/audio (`export_audio`);
- the launcher icons Godot's export presets name are copied into godot/icons;
- the import options are pinned in the `.import` sidecars (`apply_import_params`).

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

import json
import logging
import os
import re
import shutil
from pathlib import Path

from audio import audio_sources, remux_ogg, transcode_wav, wav_info
from icons import ADAPTIVE_LAYERS, APP_STORE, PROJECT_ICON_SIZE, android_icon
from textures import copy_if_changed

LOG = logging.getLogger("targets.godot")

IMPORT_SUFFIX = ".import"
# The icons the project and its export presets name (res://icons/...): import stage name ->
# name in godot/icons.
LEGACY_ANDROID_SIZE = 192
GODOT_ICONS = {f"icon_{PROJECT_ICON_SIZE}.png": f"icon_{PROJECT_ICON_SIZE}.png",
               android_icon(LEGACY_ANDROID_SIZE): f"android_main_{LEGACY_ANDROID_SIZE}.png",
               **{name: name for name in ADAPTIVE_LAYERS.values()},
               APP_STORE: APP_STORE}

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


def _remove_with_sidecar(path: Path) -> None:
    for f in (path, path.with_name(path.name + IMPORT_SUFFIX)):
        if f.exists():
            f.unlink()
            LOG.info("removed %s", f)


def _remove_empty_dirs(root: Path) -> None:
    for d in sorted((p for p in root.rglob("*") if p.is_dir()), reverse=True):
        if not any(d.iterdir()):
            d.rmdir()


def sync_tree(src: Path, dst: Path, keep: tuple[str, ...] = ()) -> int:
    """Mirror the files of `src` into `dst`; returns the number of files (re)placed. A file is
    hard-linked (copied across file systems) unless it already matches (same inode, or same
    size and mtime). Files of `dst` that `src` lacks are deleted with their `.import`
    sidecars, except under the top-level directories `keep` (filled by another step);
    Godot's own `.import` sidecars of mirrored files stay."""
    wanted: set[Path] = set()
    placed = 0
    for p in sorted(src.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(src)
        wanted.add(rel)
        target = dst / rel
        if target.exists():
            a, b = p.stat(), target.stat()
            if a.st_ino == b.st_ino or (a.st_size == b.st_size and a.st_mtime_ns == b.st_mtime_ns):
                continue
            target.unlink()
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.link(p, target)
        except OSError:
            shutil.copy2(p, target)
        placed += 1
    for p in sorted(dst.rglob("*")):
        rel = p.relative_to(dst)
        if not p.is_file() or rel.parts[0] in keep:
            continue
        source = rel.with_name(rel.name[:-len(IMPORT_SUFFIX)]) if rel.name.endswith(IMPORT_SUFFIX) else rel
        if source not in wanted:
            _remove_with_sidecar(dst / source)
            if p.exists():
                p.unlink()
    _remove_empty_dirs(dst)
    LOG.info("synced %s -> %s: %d files placed", src, dst, placed)
    return placed


def _outdated(src: Path, dst: Path) -> bool:
    return not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime


def export_audio(data_dir: Path, audio_dir: Path) -> list[str]:
    """Every sound of the original into `audio_dir`, in a form Godot loads cleanly: the Ogg
    Vorbis streams remuxed without their malformed comment header, non-PCM wavs (oops2.wav
    is MP3 inside RIFF) transcoded to 16-bit PCM, the rest copied. Returns the file names."""
    sources = audio_sources(data_dir)
    for name, src in sources.items():
        dst = audio_dir / name
        if src.suffix.lower() == ".ogg":
            if _outdated(src, dst):
                remux_ogg(src, dst)
        elif (info := wav_info(src)) is None or not info.pcm:
            if _outdated(src, dst):
                transcode_wav(src, dst)
                LOG.info("transcoded %s to PCM", name)
        else:
            copy_if_changed(src, dst)
    if audio_dir.is_dir():
        for p in sorted(audio_dir.iterdir()):
            if p.is_file() and not p.name.endswith(IMPORT_SUFFIX) and p.name not in sources:
                _remove_with_sidecar(p)
    LOG.info("%d sounds in %s", len(sources), audio_dir)
    return list(sources)


def export_icons(icons_dir: Path, godot_dir: Path) -> None:
    out = godot_dir / "icons"
    out.mkdir(parents=True, exist_ok=True)
    for name, target in GODOT_ICONS.items():
        copy_if_changed(icons_dir / name, out / target)


def export(import_dir: Path, data_dir: Path, godot_dir: Path) -> None:
    """Build the Godot project's generated resources (then `godot --import` imports them)."""
    sync_tree(import_dir / "assets", godot_dir / "assets", keep=("audio",))
    sync_tree(import_dir / "data", godot_dir / "data")
    export_audio(data_dir, godot_dir / "assets" / "audio")
    export_icons(import_dir / "icons", godot_dir)
    apply_import_params(godot_dir)
