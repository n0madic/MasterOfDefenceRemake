"""Launcher icons of the Defold bundles, picked from the import stage's icon set
(tools/icons.py) so both ports ship the same art.

- Android: the legacy density PNGs (`[android] app_icon_*`) plus an adaptive icon for
  API 26+ as bundle resources: `drawable-anydpi-v26/icon.xml` overrides the engine's
  `@drawable/icon` there, with the foreground/background/monochrome layers.
- iOS: the home-screen PNGs (`[ios] app_icon_*`), opaque.
- macOS `.icns`, Windows `.ico`; the web bundle gets the `.ico` as `favicon.ico`.

The paths are referenced from defold/game.project."""
from __future__ import annotations

import shutil
from pathlib import Path

from icons import ADAPTIVE_LAYERS, ANDROID_SIZES, IOS_SIZES, android_icon, ios_icon

ICONS_DIR = "generated/icons"
BUNDLE_DIR = "generated/bundle"
# The adaptive layers are 108 dp squares; 432 px is their xxxhdpi size.
ADAPTIVE_DENSITY = "xxxhdpi"
ADAPTIVE_ICON_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/icon_background" />
    <foreground android:drawable="@drawable/icon_foreground" />
    <monochrome android:drawable="@drawable/icon_monochrome" />
</adaptive-icon>
"""


def export_icons(icon_set: Path, out: Path) -> list[Path]:
    """Copy every Defold icon under `out` from the icon set; returns the files."""
    icons = out / ICONS_DIR
    res = out / BUNDLE_DIR / "android" / "res"
    copies = {**{name: icons / name for name in [*map(android_icon, ANDROID_SIZES), *map(ios_icon, IOS_SIZES),
                                                  "icon.icns", "icon.ico"]},
              **{name: res / f"drawable-{ADAPTIVE_DENSITY}" / f"icon_{layer}.png" for layer, name in ADAPTIVE_LAYERS.items()}}
    written: list[Path] = []
    for name, dst in [*copies.items(), ("icon.ico", out / BUNDLE_DIR / "web" / "favicon.ico")]:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(icon_set / name, dst)
        written.append(dst)
    xml = res / "drawable-anydpi-v26" / "icon.xml"
    xml.parent.mkdir(parents=True, exist_ok=True)
    xml.write_text(ADAPTIVE_ICON_XML)
    written.append(xml)
    return written
