#!/usr/bin/env python3
"""Build the Defold project's generated resources from the Godot pipeline's output.

Reads `godot/assets` (glb models with `.b3d.json` sidecars, textures, sounds) and
`godot/data` (game tables) and writes into the Defold subproject:

- `assets/models/*.glb`, `generated/materials/*`, `generated/models/*.model`,
  `generated/go/*.go` -- every model of the location, the towers, bullets, effects, the
  monsters and the HUD panel (see modexport/models.py);
- `assets/textures/...`, `assets/audio/...` -- the textures and sounds they use;
- `assets/hud/` -- the GUI atlas cut from `gui.png` (modexport/hud.py);
- `data/*.json` -- the game tables (custom resources);
- `generated/level_data.lua` -- camera bounds, background/ambient/light, render passes,
  the build zones of the location, the gradient of the health bar;
- `generated/models.lua` -- per model: game object, animation length, groups, ANIMMAP keys;
- `generated/entities.go` -- one factory per model;
- `generated/main.collection` -- the bootstrap collection: the location's scene and the
  level controller with the location's tower ground texture.

Usage: python3 defold/tools/export_defold.py [--location 1] [--godot godot] [--out defold]
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from gltfwriter import read_accessor  # noqa: E402
from modexport.hud import export_gradient, export_hud_atlas  # noqa: E402
from modexport.models import ModelExporter, load_sidecar, transform_point  # noqa: E402

ZONE_NODES = ["grass", "road", "noparking", "rocks"]
TOWER_MODELS = ["Military", "Magic", "Nature", "Freeze", "Fire"]
TOWER_EXTRAS = ["MilitaryPlace", "MagicPlace", "NaturePlace", "FreezePlace", "FirePlace",
                "MilitaryEff", "MagicEff", "NatureEff", "FreezeEff", "PoisonEff",
                "range", "selection", "shadow", "death"]
BULLET_MODELS = [f"{t}{i}" for t in ("military", "magic", "nature", "freeze") for i in range(1, 6)]
ROOT_MODELS = ["health", "Env", "faces"]
DATA_FILES = ["units.json", "towers.json", "raids.json", "paths.json", "locations.json", "texts.json", "hud_layout.json"]
SOUND_EXTENSIONS = (".wav", ".ogg")


def quat_rotate(q: list[float], v: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z, w = q
    tx = 2.0 * (y * v[2] - z * v[1])
    ty = 2.0 * (z * v[0] - x * v[2])
    tz = 2.0 * (x * v[1] - y * v[0])
    return (v[0] + w * tx + (y * tz - z * ty), v[1] + w * ty + (z * tx - x * tz), v[2] + w * tz + (x * ty - y * tx))


def normalized(v: tuple[float, float, float]) -> list[float]:
    n = math.sqrt(sum(c * c for c in v)) or 1.0
    return [v[0] / n, v[1] / n, v[2] / n]


def fmt(v: float) -> str:
    return f"{v:.6f}"


def lua_list(values) -> str:
    return "{" + ", ".join(str(v) for v in values) + "}"


class Exporter:
    def __init__(self, location: int, godot_dir: Path, out_dir: Path):
        self.location = location
        self.godot = godot_dir
        self.out = out_dir
        self.models_dir = godot_dir / "assets" / "models"
        self.textures_dir = godot_dir / "assets" / "textures"
        self.textures: dict[str, str] = {}
        self.models: dict[str, dict] = {}
        loc_dir = self.models_dir / f"Location{location}"
        self.location_glb = loc_dir / f"Location{location}.glb"
        self.location_sidecar = load_sidecar(self.location_glb) or {}
        self.light = self._light()

    # --- scene light -------------------------------------------------------------------

    def _light(self) -> dict:
        """Ambient / directional light of the location from the B3DEXT_* tag nodes (the
        sidecar keeps their raw Blitz positions = RGB values)."""
        from gltfwriter import read_glb
        doc, _ = read_glb(self.location_glb)
        scene = self.location_sidecar.get("scene", {})
        ambient = [float(c) for c in scene.get("B3DEXT_AMBIENT", {}).get("pos", [0.5, 0.5, 0.5])]
        bg = [float(c) for c in scene.get("B3DEXT_BGCOLOR", {}).get("pos", [0.0, 0.0, 0.0])]
        dirlight = scene.get("B3DEXT_DIRLIGHT")
        color = [1.0, 1.0, 1.0]
        direction = normalized((-0.5, -0.8, -0.3))
        if dirlight is not None:
            color = [float(c) for c in dirlight["pos"]]
            # `_fext_initlight`: CreateLight(parent) + TurnEntity 90,0,0 -> the light shines
            # along the parent's -Y (see LocationView._setup_lights / MainMenu.CAMERA_FIX).
            holder = next((n for n in doc["nodes"] if n.get("name") == dirlight["parent"]), None)
            if holder is not None:
                direction = normalized(quat_rotate(holder.get("rotation", [0.0, 0.0, 0.0, 1.0]), (0.0, -1.0, 0.0)))
        return {"ambient": ambient, "color": color, "direction": direction, "background": bg}

    # --- models --------------------------------------------------------------------------

    def export_model(self, key: str, glb: Path, *, hud: bool = False, lit_default: bool = False) -> dict:
        exporter = ModelExporter(key, glb, load_sidecar(glb), self.out, self.textures_dir, self.light, hud=hud, lit_default=lit_default)
        meta = exporter.run()
        self.textures.update(meta.pop("textures"))
        self.models[key] = meta
        return meta

    def export_models(self) -> None:
        self.export_model(f"Location{self.location}", self.location_glb)
        for name in TOWER_MODELS + TOWER_EXTRAS + BULLET_MODELS:
            self.export_model(f"Towers/{name}", self.models_dir / "Towers" / f"{name}.glb")
        for glb in sorted((self.models_dir / "Monsters").glob("*.glb")):
            if glb.stem == "Health":
                self.export_model("Monsters/Health", glb)
            else:
                self.export_model(f"Monsters/{glb.stem}", glb, lit_default=True)
        for name in ROOT_MODELS:
            self.export_model(name, self.models_dir / f"{name}.glb", hud=name in ("Env", "faces"))

    def copy_textures(self) -> None:
        for uri, resource in self.textures.items():
            dst = self.out / resource.lstrip("/")
            dst.parent.mkdir(parents=True, exist_ok=True)
            src = self.textures_dir / Path(resource).relative_to("/assets/textures")
            shutil.copyfile(src, dst)
        # Tower bases take the location's ground texture at runtime.
        for L in range(1, 7):
            src = self.textures_dir / "Towers" / f"dno{L}.png"
            if src.exists():
                dst = self.out / "assets" / "textures" / "Towers" / f"dno{L}.png"
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)

    # --- zones ---------------------------------------------------------------------------

    def zones(self) -> dict[str, list[list[float]]]:
        """World-space triangles of the build zones of the location (`CameraPick` targets)."""
        exporter = ModelExporter(f"Location{self.location}", self.location_glb, self.location_sidecar, self.out, self.textures_dir, self.light)
        out: dict[str, list[list[float]]] = {}
        nodes = exporter.doc["nodes"]
        for index in exporter.kept:
            node = nodes[index]
            if node.get("name") not in ZONE_NODES or "mesh" not in node:
                continue
            tris = out.setdefault(node["name"], [])
            w = exporter.world[index]
            for prim in exporter.doc["meshes"][node["mesh"]]["primitives"]:
                positions = [transform_point(w, p) for p in read_accessor(exporter.doc, exporter.blob, prim["attributes"]["POSITION"])]
                indices = read_accessor(exporter.doc, exporter.blob, prim["indices"])
                for a, b, c in zip(indices[0::3], indices[1::3], indices[2::3]):
                    tris.append([round(v, 4) for p in (positions[a], positions[b], positions[c]) for v in p])
        return out

    # --- data / audio / hud --------------------------------------------------------------

    def copy_data(self) -> None:
        data_dir = self.out / "data"
        data_dir.mkdir(parents=True, exist_ok=True)
        for name in DATA_FILES:
            shutil.copyfile(self.godot / "data" / name, data_dir / name)

    def copy_audio(self) -> list[str]:
        audio_dir = self.out / "assets" / "audio"
        audio_dir.mkdir(parents=True, exist_ok=True)
        names = []
        ffmpeg = shutil.which("ffmpeg")
        for src in sorted((self.godot / "assets" / "audio").iterdir()):
            if src.suffix not in SOUND_EXTENSIONS:
                continue
            dst = audio_dir / src.name
            if src.suffix == ".ogg" and ffmpeg:
                # The original's Vorbis streams (remuxed by the Godot pipeline) fail in the
                # engine's web decoder; a plain re-encode plays everywhere (ffmpeg's own
                # Vorbis encoder is stereo only).
                subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", str(src), "-ac", "2", "-c:a", "vorbis", "-strict", "-2", "-q:a", "5", str(dst)], check=True)
            else:
                shutil.copyfile(src, dst)
            names.append(src.name)
        return names

    # --- generated Lua / go ----------------------------------------------------------------

    def write_level_data(self) -> None:
        loc = json.loads((self.godot / "data" / "locations.json").read_text())[str(self.location)]
        bounds = loc["bounds"]
        orders = sorted({int(info["order"]) for info in self.location_sidecar.get("nodes", {}).values() if "order" in info and int(info["order"]) > 0}, reverse=True)
        passes = []
        for order in orders:
            for cls in ("opaque", "blend", "add", "mul"):
                passes.append({"tags": [f"order_{order}", cls], "depth_test": False, "depth_write": False, "blend": cls})
        # The opaque world writes depth first, then the tower base decals (`dno`) draw on
        # top of it, then the translucent tower bodies. Giving the base its own pass before
        # order_0 blend keeps a translucent trunk from sort-flipping with its own base
        # (which shimmered and shifted colour as the camera moved).
        passes.append({"tags": ["order_0", "opaque"], "depth_test": True, "depth_write": True, "blend": "opaque"})
        # The base decal's opaque (alpha-scissored) footprint writes depth so the underground
        # root is occluded; its blended layers (if any) do not.
        passes.append({"tags": ["base", "opaque"], "depth_test": True, "depth_write": True, "blend": "opaque"})
        for cls in ("blend", "add", "mul"):
            passes.append({"tags": ["base", cls], "depth_test": True, "depth_write": False, "blend": cls})
        for cls in ("blend", "add", "mul"):
            passes.append({"tags": ["order_0", cls], "depth_test": True, "depth_write": False, "blend": cls})
        hud_passes = [{"tags": ["hud", cls], "depth_test": True, "depth_write": cls == "opaque", "blend": cls} for cls in ("opaque", "blend", "add", "mul")]
        gradient = export_gradient(self.textures_dir / "Monsters" / "Gradient.bmp", self.out)
        tint = loc["tower_tint_rgb"]
        lines = ["-- Generated by defold/tools/export_defold.py -- do not edit.", "local M = {}", "",
                 f"M.location = {self.location}",
                 "M.bounds = {x_min = %s, x_max = %s, z_min = %s, z_max = %s}" % (bounds["x_min"], bounds["x_max"], bounds["z_min"], bounds["z_max"]),
                 "M.clear_color = {%s, %s, %s}" % tuple(fmt(c) for c in self.light["background"]),
                 "M.tower_tint = {%s, %s, %s}" % tuple(fmt(c / 255.0) for c in tint),
                 f"M.shadows = {'true' if loc.get('shadows', True) else 'false'}",
                 f"M.music = \"{Path(loc['music']).name}\"",
                 f"M.first_raid = {loc.get('first_raid', 1)}",
                 "M.passes = {"]
        for p in passes:
            lines.append("    {tags = {%s}, depth_test = %s, depth_write = %s, blend = \"%s\"}," % (
                ", ".join(f'"{t}"' for t in p["tags"]), str(p["depth_test"]).lower(), str(p["depth_write"]).lower(), p["blend"]))
        lines += ["}", "M.hud_passes = {"]
        for p in hud_passes:
            lines.append("    {tags = {%s}, depth_test = %s, depth_write = %s, blend = \"%s\"}," % (
                ", ".join(f'"{t}"' for t in p["tags"]), str(p["depth_test"]).lower(), str(p["depth_write"]).lower(), p["blend"]))
        lines += ["}", "-- Build zones: flat triangle lists (x1, y1, z1, x2, ...) in world space.", "M.zones = {"]
        for zone, tris in self.zones().items():
            flat = [v for tri in tris for v in tri]
            lines.append(f"    {zone} = {lua_list(flat)},")
        lines += ["}", "-- Health bar colours (Gradient.bmp), index 1..100.", "M.gradient = {"]
        for rgb in gradient:
            lines.append("    {%s, %s, %s}," % tuple(fmt(c / 255.0) for c in rgb))
        lines += ["}", "", "return M", ""]
        (self.out / "generated" / "level_data.lua").write_text("\n".join(lines))

    def write_models_lua(self) -> None:
        lines = ["-- Generated by defold/tools/export_defold.py -- do not edit.", "local M = {}", ""]
        for key, meta in self.models.items():
            groups = ", ".join(f"{g} = true" for g in meta["groups"])
            lines.append(f'M["{key}"] = {{')
            lines.append(f'    go = "{meta["go"]}", factory = "factory_{key.replace("/", "_")}", frames = {fmt(meta["frames"])}, skinned = {str(meta["skinned"]).lower()},')
            lines.append(f'    morph_targets = {meta["morph_targets"]}, groups = {{{groups}}},')
            if meta.get("bones"):
                b = meta["bones"]
                lines.append(f'    bones = {{count = {b["count"]}, frames = {b["frames"]}, resource = "{b["resource"]}"}},')
            if meta["animmaps"]:
                lines.append("    animmaps = {")
                for m in meta["animmaps"]:
                    keys = ", ".join("{%s, %s}" % (fmt(u), fmt(v)) for u, v in m["keys"])
                    lines.append(f'        {{group = "{m["group"]}", keys = {{{keys}}}}},')
                lines.append("    },")
            lines.append("}")
        lines += ["", "return M", ""]
        (self.out / "generated" / "models.lua").write_text("\n".join(lines))

    def write_entities_go(self) -> None:
        lines = []
        for key, meta in self.models.items():
            lines += ["embedded_components {", f'  id: "factory_{key.replace("/", "_")}"', '  type: "factory"',
                      f'  data: "prototype: \\"{meta["go"]}\\"\\n"', "}"]
        (self.out / "generated" / "entities.go").write_text("\n".join(lines) + "\n")

    def write_sounds_go(self, names: list[str]) -> None:
        lines = []
        seen: set[str] = set()
        for name in names:
            stem = Path(name).stem
            if stem in seen:
                continue  # menu.wav / menu.ogg: the component id is the stem
            seen.add(stem)
            loop = "1" if stem.startswith("music") or stem in ("tlen", "water") else "0"
            lines += ["embedded_components {", f'  id: "{stem}"', '  type: "sound"',
                      f'  data: "sound: \\"/assets/audio/{name}\\"\\nlooping: {loop}\\ngain: 1.0\\n"', "}"]
        (self.out / "generated" / "sounds.go").write_text("\n".join(lines) + "\n")

    def ground_texture(self) -> str:
        """The tower base (`dno`) texture of the location, set by `_fpositiontower`."""
        return f"/assets/textures/Towers/dno{self.location}.png"

    def write_main_collection(self) -> None:
        """The bootstrap collection (game.project `main_collection`): the location's scene and
        the level controller, whose `ground_texture` script property is the location's."""
        instances = [("location", self.models[f"Location{self.location}"]["go"], None),
                     ("entities", "/generated/entities.go", None), ("sounds", "/generated/sounds.go", None),
                     ("camera", "/main/camera.go", None), ("level", "/main/level.go", ("script", "ground_texture", self.ground_texture()))]
        lines = ['name: "main"']
        for ident, prototype, prop in instances:
            lines += ["instances {", f'  id: "{ident}"', f'  prototype: "{prototype}"']
            if prop:
                component, name, value = prop
                lines += ["  component_properties {", f'    id: "{component}"', "    properties {", f'      id: "{name}"',
                          f'      value: "{value}"', "      type: PROPERTY_TYPE_HASH", "    }", "  }"]
            lines.append("}")
        (self.out / "generated" / "main.collection").write_text("\n".join(lines) + "\n")

    def run(self) -> None:
        (self.out / "generated").mkdir(parents=True, exist_ok=True)
        self.export_models()
        self.copy_textures()
        self.copy_data()
        export_hud_atlas(self.textures_dir / "gui.png", self.out)
        self.write_level_data()
        self.write_models_lua()
        self.write_entities_go()
        self.write_sounds_go(self.copy_audio())
        self.write_main_collection()
        skinned = sum(1 for m in self.models.values() if m["skinned"])
        print(f"{len(self.models)} models ({skinned} skinned), {len(self.textures)} textures -> {self.out}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--location", type=int, default=1)
    ap.add_argument("--godot", type=Path, default=ROOT / "godot", help="Godot project with converted assets")
    ap.add_argument("--out", type=Path, default=ROOT / "defold", help="Defold project directory")
    args = ap.parse_args()
    Exporter(args.location, args.godot.resolve(), args.out.resolve()).run()


if __name__ == "__main__":
    main()
