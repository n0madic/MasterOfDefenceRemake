"""Launcher icons of the Defold bundles, derived from the Godot port's icons (`godot/icons`,
made by godot/tools/make_icons.gd) so both ports ship the same art.

- Android: the legacy density PNGs (`[android] app_icon_*`) plus an adaptive icon for
  API 26+ as bundle resources: `drawable-anydpi-v26/icon.xml` overrides the engine's
  `@drawable/icon` there, with the Godot port's foreground/background/monochrome layers.
- iOS: the home-screen PNGs (`[ios] app_icon_*`), from the opaque App Store master.
- macOS `.icns`, Windows `.ico`; the web bundle gets the `.ico` as `favicon.ico`.

The paths are referenced from defold/game.project."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ICONS_DIR = "generated/icons"
BUNDLE_DIR = "generated/bundle"
ANDROID_SIZES = (36, 48, 72, 96, 144, 192)
IOS_SIZES = (76, 120, 152, 167, 180)
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)
# The adaptive layers are 108 dp squares; 432 px is their xxxhdpi size.
ADAPTIVE_DENSITY = "xxxhdpi"
ADAPTIVE_LAYERS = {"foreground": "android_fg_432.png", "background": "android_bg_432.png",
                   "monochrome": "android_mono_432.png"}
ADAPTIVE_ICON_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/icon_background" />
    <foreground android:drawable="@drawable/icon_foreground" />
    <monochrome android:drawable="@drawable/icon_monochrome" />
</adaptive-icon>
"""


def _scaled(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def export_icons(godot_icons: Path, out: Path) -> list[Path]:
    """Write every Defold icon under `out` from the PNGs in `godot_icons`; returns the files."""
    master = Image.open(godot_icons / "icon_1024.png").convert("RGBA")
    store = Image.open(godot_icons / "ios_app_store_1024.png").convert("RGB")  # iOS icons must be opaque
    icons = out / ICONS_DIR
    icons.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    def save(image: Image.Image, path: Path, **params) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, **params)
        written.append(path)

    for size in ANDROID_SIZES:
        save(_scaled(master, size), icons / f"android_{size}.png")
    for size in IOS_SIZES:
        save(_scaled(store, size), icons / f"ios_{size}.png")
    save(master, icons / "icon.icns")  # Pillow writes every ICNS size from 16 to 1024 px
    ico_sizes = [(s, s) for s in ICO_SIZES]
    save(master, icons / "icon.ico", sizes=ico_sizes)
    save(master, out / BUNDLE_DIR / "web" / "favicon.ico", sizes=ico_sizes)

    res = out / BUNDLE_DIR / "android" / "res"
    for layer, name in ADAPTIVE_LAYERS.items():
        save(Image.open(godot_icons / name), res / f"drawable-{ADAPTIVE_DENSITY}" / f"icon_{layer}.png")
    xml = res / "drawable-anydpi-v26" / "icon.xml"
    xml.parent.mkdir(parents=True, exist_ok=True)
    xml.write_text(ADAPTIVE_ICON_XML)
    written.append(xml)
    return written
