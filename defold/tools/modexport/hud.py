"""HUD atlas for the Defold GUI: slices of `gui.png` (docs/13) as separate images in one
`.atlas` -- buttons in their three states, slider, progress bar, checkbox, the tooltip
frame and the 16x16 glyphs of the Blitz font (cp1251 byte = glyph index)."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

BIG, SMALL = 64, 32
STYLE_BIG, STYLE_SMALL1, STYLE_SMALL2 = 0, 1, 2
BIG_ICONS = 8
SMALL1_ICONS = 12
SMALL2_ICONS = 13
GLYPH = 16
FONT_ORIGIN = (0, 256)
FIRST_GLYPH, LAST_GLYPH = 33, 255


def button_region(style: int, icon: int, state: int) -> tuple[int, int, int, int]:
    """Atlas rectangle (x, y, w, h) of button `icon` in `style`; `state` 0 normal, 1 hover, 2 pressed."""
    if style == STYLE_BIG:
        return (256 + BIG * state, BIG * (icon - 1), BIG, BIG)
    if style == STYLE_SMALL1:
        return (192 + SMALL * (icon - 1), 64 + SMALL * state, SMALL, SMALL)
    return (128 + SMALL * (icon - 1), 160 + SMALL * state, SMALL, SMALL)


FIXED_REGIONS = {
    "slider_track": (64, 128, 32, 16),
    "slider_knob": (64, 160, 32, 32),
    "progress_frame": (0, 128, 64, 32),
    "progress_fill": (0, 160, 64, 32),
    "frame": (0, 192, 32, 32),
    "textbox": (128, 32, 64, 32),
    "checkbox_off": (192, 32, 16, 16),
    "checkbox_on": (192, 48, 16, 16),
}


def export_hud_atlas(gui_png: Path, out_dir: Path) -> list[str]:
    """Write `assets/hud/*.png` and `assets/hud/hud.atlas`; returns the image names."""
    atlas = Image.open(gui_png).convert("RGBA")
    images_dir = out_dir / "assets" / "hud"
    images_dir.mkdir(parents=True, exist_ok=True)
    regions: dict[str, tuple[int, int, int, int]] = dict(FIXED_REGIONS)
    for icon in range(1, BIG_ICONS + 1):
        for state in range(3):
            regions[f"btn_big_{icon}_{state}"] = button_region(STYLE_BIG, icon, state)
    for icon in range(1, SMALL1_ICONS + 1):
        for state in range(3):
            regions[f"btn_s1_{icon}_{state}"] = button_region(STYLE_SMALL1, icon, state)
    for icon in range(0, SMALL2_ICONS + 1):
        for state in range(3):
            regions[f"btn_s2_{icon}_{state}"] = button_region(STYLE_SMALL2, icon, state)
    for code in range(FIRST_GLYPH, LAST_GLYPH + 1):
        regions[f"g{code}"] = (FONT_ORIGIN[0] + GLYPH * (code % 16), FONT_ORIGIN[1] + GLYPH * (code // 16), GLYPH, GLYPH)
    names = []
    for name, (x, y, w, h) in regions.items():
        atlas.crop((x, y, x + w, y + h)).save(images_dir / f"{name}.png")
        names.append(name)
    lines = []
    for name in names:
        lines += ["images {", f'  image: "/assets/hud/{name}.png"', "}"]
    lines += ["margin: 0", "extrude_borders: 1", "inner_padding: 0"]
    (images_dir / "hud.atlas").write_text("\n".join(lines) + "\n")
    return names


def export_gradient(bmp: Path, out_dir: Path) -> list[list[int]]:
    """The health bar colour gradient (`Gradient.bmp`, 100x1) as RGB triples."""
    img = Image.open(bmp).convert("RGB")
    return [list(img.getpixel((x, 0))) for x in range(img.width)]
