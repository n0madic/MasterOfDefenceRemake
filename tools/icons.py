"""Launcher icons of every supported platform from the one master render (`art/icon_1024.png`,
made by godot/tools/render_icon.gd). The import stage writes them all into `<import>/icons`;
each port copies the files its bundles need (tools/targets/godot.py, tools/targets/defold/icons.py).

- `icon_256.png`: the Godot project icon (favicon, the smaller iOS sizes, the editor), so
  the web page does not ship the 1024 px master as its favicon;
- `android_<N>.png`: the legacy launcher PNGs (Godot takes the 192 px one);
- `android_{fg,bg,mono}_432.png`: the adaptive icon layers (API 26+). Adaptive icons are
  masked to the inner ~66%, so the art is kept inside that safe zone; the themed
  (monochrome) layer is the silhouette in white, its alpha carrying the shape;
- `ios_app_store_1024.png`, `ios_<N>.png`: iOS icons must be opaque, so the art sits on the
  background colour;
- `icon.icns` (macOS), `icon.ico` (Windows, the web favicon).
"""
from __future__ import annotations

import logging
from pathlib import Path

from PIL import Image

LOG = logging.getLogger("icons")

MASTER = Path(__file__).resolve().parent.parent / "art" / "icon_1024.png"
PROJECT_ICON_SIZE = 256
ANDROID_SIZES = (36, 48, 72, 96, 144, 192)
IOS_SIZES = (76, 120, 152, 167, 180)
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)
ADAPTIVE_SIZE = 432  # the 108 dp adaptive layers at xxxhdpi
ADAPTIVE_ART_SIZE = 272
APP_STORE_SIZE = 1024
BACKGROUND = (0x1D, 0x2A, 0x1A, 0xFF)  # dark forest green, the palette of the game's menu
ADAPTIVE_LAYERS = {"foreground": "android_fg_432.png", "background": "android_bg_432.png",
                   "monochrome": "android_mono_432.png"}
APP_STORE = "ios_app_store_1024.png"


def android_icon(size: int) -> str:
    return f"android_{size}.png"


def ios_icon(size: int) -> str:
    return f"ios_{size}.png"


def _scaled(image: Image.Image, size: int) -> Image.Image:
    return image if image.size == (size, size) else image.resize((size, size), Image.Resampling.LANCZOS)


def generate_icons(master: Path, out_dir: Path) -> list[str]:
    """Write every icon into `out_dir`; returns the file names."""
    icon = Image.open(master).convert("RGBA")
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[str] = []

    def save(image: Image.Image, name: str, **params) -> None:
        image.save(out_dir / name, **params)
        written.append(name)

    save(_scaled(icon, PROJECT_ICON_SIZE), f"icon_{PROJECT_ICON_SIZE}.png")
    for size in ANDROID_SIZES:
        save(_scaled(icon, size), android_icon(size))

    foreground = Image.new("RGBA", (ADAPTIVE_SIZE, ADAPTIVE_SIZE), (0, 0, 0, 0))
    margin = (ADAPTIVE_SIZE - ADAPTIVE_ART_SIZE) // 2
    foreground.paste(_scaled(icon, ADAPTIVE_ART_SIZE), (margin, margin))
    save(foreground, ADAPTIVE_LAYERS["foreground"])
    save(Image.new("RGBA", (ADAPTIVE_SIZE, ADAPTIVE_SIZE), BACKGROUND), ADAPTIVE_LAYERS["background"])
    mono = Image.new("RGBA", foreground.size, (255, 255, 255, 0))
    mono.putalpha(foreground.getchannel("A"))
    save(mono, ADAPTIVE_LAYERS["monochrome"])

    store = Image.alpha_composite(Image.new("RGBA", (APP_STORE_SIZE, APP_STORE_SIZE), BACKGROUND),
                                  _scaled(icon, APP_STORE_SIZE)).convert("RGB")
    save(store, APP_STORE)
    for size in IOS_SIZES:
        save(_scaled(store, size), ios_icon(size))

    save(icon, "icon.icns")  # Pillow writes every ICNS size from 16 to 1024 px
    save(icon, "icon.ico", sizes=[(s, s) for s in ICO_SIZES])
    LOG.info("wrote %d icons to %s", len(written), out_dir)
    return written
