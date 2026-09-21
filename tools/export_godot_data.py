#!/usr/bin/env python3
"""Export everything the Godot remake needs into godot/data/*.json.

    python3 tools/export_godot_data.py MasterOfDefense_unpacked/Data godot/data

Outputs (all values in Godot coordinates, see tools/blitzconv.py):
- units.json, towers.json           - as export_csv.py, with res:// model paths
- raids.json                        - campaign raids 1..180 + survival table (RaidsData7)
- paths.json                        - enemy path keyframes per location (C1-converted)
- locations.json                    - camera bounds, raid ranges, per-location flags
- texts.json                        - Texts/Helps/Storyline/Tutorial (cp1251 -> UTF-8,
                                      <vd> -> newline, word-wrap as _faddvdtags)
- hud_layout.json, path_times.json  - copied from docs/data (golden values for tests)
"""
from __future__ import annotations

import argparse
import json
import logging
import shutil
from pathlib import Path

import b3dlib
from blitzconv import blitz_quat_to_godot, blitz_to_godot
from export_csv import LAST_CAMPAIGN_RAID, LOCATION_FIRST_RAID, load_raids, load_towers, load_units
from export_paths import read_keys

LOG = logging.getLogger("export_godot_data")

MODELS_ROOT = "res://assets/models"
TOWER_MODELS = {1: "Military", 2: "Magic", 3: "Nature", 4: "Freeze", 5: "Fire"}
TOWER_PLACE_MODELS = {1: "MilitaryPlace", 2: "MagicPlace", 3: "NaturePlace", 4: "FreezePlace", 5: "FirePlace"}
# _floadtowersprototypes: the Flame tower shares MagicEff with the Magic tower (FireEff.b3d
# in the game data is an empty stub: one untextured quad with alpha 0).
TOWER_EFFECT_MODELS = {1: "MilitaryEff", 2: "MagicEff", 3: "NatureEff", 4: "FreezeEff", 5: "MagicEff"}
TEXTURES_ROOT = "res://assets/textures"
AUDIO_ROOT = "res://assets/audio"

# _fsetlocationdata + per-location special cases scattered over _floadlocation.
LOCATION_EXTRA = {
    1: {"balloon": False, "shadows": True, "clear_color": [0, 0, 0], "decoration": "clock", "tutorial_page": 1},
    2: {"balloon": False, "shadows": True, "clear_color": [0, 0, 0], "decoration": "eagle", "tutorial_page": 8},
    3: {"balloon": False, "shadows": True, "clear_color": [0, 0, 0], "decoration": None, "tutorial_page": 0},
    4: {"balloon": True, "shadows": True, "clear_color": [0, 0, 0], "decoration": None, "tutorial_page": 9},
    5: {"balloon": True, "shadows": True, "clear_color": [0, 0, 0], "decoration": None, "tutorial_page": 0},
    6: {"balloon": True, "shadows": False, "clear_color": [192, 212, 223], "decoration": None, "tutorial_page": 0},
}
HELPS_WRAP_MIN_LEN, HELPS_WRAP_WIDTH = 20, 25
TUTORIAL_WRAP_MIN_LEN, TUTORIAL_WRAP_WIDTH = 45, 50
VD = "<vd>"


def add_vd_tags(text: str, width: int) -> str:
    """Port of _faddvdtags: insert <vd> at the last space once `width` characters passed
    since the line start. The space itself is replaced by the tag."""
    i = 1  # 1-based like Blitz Mid()
    col = 0
    while i <= len(text) - 1:
        ch = text[i - 1]
        if ch == "<" and text[i - 1:i + 3] == VD:
            col = -1
            i += 3
        col += 1
        if col == width:
            if ch != " ":
                while text[i - 1] != " ":
                    i -= 1
            text = text[: i - 1] + VD + text[i:]
            col = 0
        i += 1
    return text


def split_lines(path: Path) -> list[str]:
    """Blitz reads the file as one CSV: tokens split on ';' and CR, LF removed."""
    raw = path.read_bytes().decode("cp1251")
    tokens = []
    for tok in raw.replace(";", "\r").split("\r"):
        tokens.append(tok.replace("\n", ""))
    return tokens


def convert_tags(s: str) -> str:
    return s.replace(VD, "\n")


def export_texts(data_dir: Path) -> dict:
    texts = split_lines(data_dir / "Texts.txt")
    helps = [add_vd_tags(t, HELPS_WRAP_WIDTH) if len(t) > HELPS_WRAP_MIN_LEN else t for t in split_lines(data_dir / "Helps.txt")]
    story = split_lines(data_dir / "Storyline.txt")
    tutorial = [add_vd_tags(t, TUTORIAL_WRAP_WIDTH) if len(t) > TUTORIAL_WRAP_MIN_LEN else t
                for t in split_lines(data_dir / "Tutorial.txt")]
    return {
        "texts": [convert_tags(t) for t in texts],
        "helps": [convert_tags(t) for t in helps],
        "storyline": [convert_tags(t) for t in story],
        "tutorial": [convert_tags(t) for t in tutorial],
    }


def export_paths(data_dir: Path) -> dict:
    result = {}
    for loc in range(1, 7):
        folder = next(d for d in data_dir.iterdir() if d.name.lower() == f"location{loc}")
        path_file = next(f for f in folder.iterdir() if f.name.lower() == "path1.b3d")
        frames, nodes = read_keys(path_file.read_bytes())
        merged: dict[int, dict] = {}
        for k in nodes["path"]:
            merged.setdefault(k["frame"], {}).update(k)
        keys = []
        for f in sorted(merged):
            rec = merged[f]
            out = {"frame": f, "pos": list(blitz_to_godot(tuple(rec["pos"])))}
            if "rot_wxyz" in rec:
                out["rot_wxyz"] = list(blitz_quat_to_godot(tuple(rec["rot_wxyz"])))
            keys.append(out)
        result[str(loc)] = {"anim_frames": frames, "keys": keys}
    return result


def fire_point_keys(data_dir: Path, model: str) -> dict:
    """Position of the `fire1` child (bullet spawn) per animation frame, Godot coordinates.

    `fire1` is a direct, unscaled child of the scene root in every tower model, so its
    local position is the offset from the tower origin. Animated towers (Military, Nature)
    move it with the upgrade level; the others keep it static.
    """
    b3d = b3dlib.load(data_dir / "Towers" / f"{model}.b3d")
    node = b3d.root.find("fire1")
    if node is None:
        return {"static": [0.0, 0.0, 0.0]}
    if node.parent is not b3d.root or node.parent.scale != (1.0, 1.0, 1.0):
        raise ValueError(f"{model}: fire1 is not an unscaled root child")
    if not node.keys:
        return {"static": list(blitz_to_godot(node.pos))}
    frames = sorted(node.keys)
    if frames != list(range(frames[0], frames[-1] + 1)) or frames[0] != 0:
        raise ValueError(f"{model}: fire1 keys are not contiguous from frame 0")
    return {"keys": [list(blitz_to_godot(node.keys[f]["pos"])) for f in frames]}


def export_locations(raids: dict) -> dict:
    out = {}
    for loc in range(1, 7):
        base = raids["locations"][loc]
        first = LOCATION_FIRST_RAID[loc]
        last = LOCATION_FIRST_RAID[loc + 1] - 1 if loc < 6 else LAST_CAMPAIGN_RAID
        out[str(loc)] = {
            # Camera pivot bounds, Godot coordinates (Blitz z1..z2 mirrors to -z2..-z1).
            "bounds": {"x_min": base["x1"], "x_max": base["x2"], "z_min": -base["z2"], "z_max": -base["z1"]},
            "first_raid": first, "last_raid": last, "raids": last - first + 1,
            "ground_texture": f"{TEXTURES_ROOT}/Towers/{base['ground_texture']}",
            "tower_tint_rgb": base["tower_tint_rgb"],
            "scene": f"{MODELS_ROOT}/Location{loc}/Location{loc}.glb",
            "path_scene": f"{MODELS_ROOT}/Location{loc}/Path1.glb",
            "music": f"{AUDIO_ROOT}/music{loc}.ogg",
            "start_gold": 200 + 20 * loc,
            **LOCATION_EXTRA[loc],
        }
    return out


def on_disk_name(folder: Path, name: str) -> str:
    """The spelling of `name` in `folder` (matched case-insensitively), or `name` itself."""
    if folder.is_dir():
        for f in folder.iterdir():
            if f.name.lower() == name.lower():
                return f.name
    return name


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("data_dir", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--docs-data", type=Path, default=Path(__file__).resolve().parent.parent / "docs" / "data")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    out = args.out_dir
    out.mkdir(parents=True, exist_ok=True)

    units = load_units(args.data_dir)
    monsters_dir = args.data_dir / "Monsters"
    for u in units:
        # The table spells some files differently from the disk (Male.md2 vs male.md2);
        # Blitz did not care, an exported pck is case-sensitive.
        stem = Path(on_disk_name(monsters_dir, Path(u["model"]).name)).with_suffix("").name
        u["model"] = f"{MODELS_ROOT}/Monsters/{stem}.glb"
        if u["texture"]:
            u["texture"] = f"{TEXTURES_ROOT}/Monsters/{on_disk_name(monsters_dir, Path(u['texture']).name)}"
    towers = load_towers(args.data_dir)
    for t in towers.values():
        type_id = t["type_id"]
        t["model"] = f"{MODELS_ROOT}/Towers/{TOWER_MODELS[type_id]}.glb"
        t["place_model"] = f"{MODELS_ROOT}/Towers/{TOWER_PLACE_MODELS[type_id]}.glb"
        t["effect_model"] = f"{MODELS_ROOT}/Towers/{TOWER_EFFECT_MODELS[type_id]}.glb"
        t["anim_frames"] = b3dlib.load(args.data_dir / "Towers" / f"{TOWER_MODELS[type_id]}.b3d").anim_frames
        t["fire1"] = fire_point_keys(args.data_dir, TOWER_MODELS[type_id])
        for lv in t["levels"]:
            if lv["bullet_model"]:
                lv["bullet_model"] = f"{MODELS_ROOT}/Towers/{lv['bullet_model']}.glb"
    raids = load_raids(args.data_dir)
    files = {
        "units.json": units,
        "towers.json": towers,
        "raids.json": {"location_first_raid": raids["location_first_raid"], "campaign": raids["campaign"],
                       "survival": raids["survival"]},
        "paths.json": export_paths(args.data_dir),
        "locations.json": export_locations(raids),
        "texts.json": export_texts(args.data_dir),
    }
    for name, payload in files.items():
        (out / name).write_text(json.dumps(payload, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        LOG.info("wrote %s", out / name)
    for name in ("hud_layout.json", "path_times.json"):
        shutil.copy(args.docs_data / name, out / name)
        LOG.info("wrote %s", out / name)


if __name__ == "__main__":
    main()
