"""Asset packaging: duplicate textures collapse, import options are pinned in the sidecars."""
from __future__ import annotations

import hashlib
import re
import tempfile
import unittest
from pathlib import Path

from testpaths import GODOT_DIR

from targets.godot import JPG_PARAMS, SCENE_PARAMS, TEXTURE_PARAMS, apply_import_params, ensure_import_params
from textures import canonical_images, copy_textures

RES_TEXTURE = re.compile(r"res://assets/textures/[A-Za-z0-9_/.%]+")


class CanonicalImagesTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.data = Path(self._tmp.name) / "Data"
        for rel, content in {
            "Additional/Skeleton.jpg": b"skin",
            "Monsters/Skeleton.jpg": b"skin",
            "Location1/castle2.jpg": b"castle",
            "Location2/castle2.jpg": b"castle",
            "Menu/castle2.jpg": b"castle",
            "wood.png": b"wood",
            "Additional/wood.png": b"wood",
            "Location3/floor.jpg": b"floor",
        }.items():
            p = self.data / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(content)
        canonical_images.cache_clear()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_runtime_dirs_win_then_alphabetical(self) -> None:
        canonical = canonical_images(self.data)
        rel = {k.relative_to(self.data).as_posix(): v.relative_to(self.data).as_posix() for k, v in canonical.items()}
        self.assertEqual(rel["Additional/Skeleton.jpg"], "Monsters/Skeleton.jpg")
        self.assertEqual(rel["Monsters/Skeleton.jpg"], "Monsters/Skeleton.jpg")
        self.assertEqual(rel["Location1/castle2.jpg"], "Menu/castle2.jpg")
        self.assertEqual(rel["Additional/wood.png"], "wood.png")
        self.assertEqual(rel["Location3/floor.jpg"], "Location3/floor.jpg")

    def test_copy_textures_ships_duplicates_once(self) -> None:
        textures = Path(self._tmp.name) / "textures"
        copied = copy_textures(self.data, textures)
        self.assertEqual(sorted(copied), ["Location3/floor.jpg", "Menu/castle2.jpg", "Monsters/Skeleton.jpg", "wood.png"])
        self.assertEqual(sorted(p.relative_to(textures).as_posix() for p in textures.rglob("*") if p.is_file()), sorted(copied))
        self.assertEqual(copy_textures(self.data, textures), [])  # unchanged files are not copied again


class ImportParamsTests(unittest.TestCase):
    SIDECAR = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://d0a8yq7xsio37"
path="res://.godot/imported/map.jpg-9024.ctex"

[deps]

source_file="res://assets/textures/map.jpg"
dest_files=["res://.godot/imported/map.jpg-9024.ctex"]

[params]

compress/mode=0
compress/lossy_quality=0.7
mipmaps/generate=true
detect_3d/compress_to=0
"""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.godot = Path(self._tmp.name)
        (self.godot / "assets" / "textures").mkdir(parents=True)
        (self.godot / "assets" / "models").mkdir(parents=True)
        (self.godot / ".godot" / "imported").mkdir(parents=True)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _params(self, sidecar: Path) -> dict[str, str]:
        section = sidecar.read_text().split("[params]", 1)[1]
        return dict(line.split("=", 1) for line in section.splitlines() if "=" in line)

    def test_existing_sidecar_is_patched_and_products_dropped(self) -> None:
        jpg = self.godot / "assets" / "textures" / "map.jpg"
        jpg.write_bytes(b"x")
        sidecar = jpg.with_name("map.jpg.import")
        sidecar.write_text(self.SIDECAR)
        product = self.godot / ".godot" / "imported" / "map.jpg-9024.ctex"
        product.write_bytes(b"ctex")
        product.with_suffix(".md5").write_text("md5")
        self.assertTrue(ensure_import_params(self.godot, jpg, "texture", {**TEXTURE_PARAMS, **JPG_PARAMS}))
        params = self._params(sidecar)
        self.assertEqual(params["compress/mode"], "1")
        self.assertEqual(params["compress/lossy_quality"], "0.85")
        self.assertEqual(params["mipmaps/generate"], "true")
        self.assertIn('uid="uid://d0a8yq7xsio37"', sidecar.read_text())
        self.assertFalse(product.exists())
        self.assertFalse(product.with_suffix(".md5").exists())
        # Second run: nothing to do.
        self.assertFalse(ensure_import_params(self.godot, jpg, "texture", {**TEXTURE_PARAMS, **JPG_PARAMS}))

    def test_missing_texture_sidecar_gets_a_minimal_one(self) -> None:
        jpg = self.godot / "assets" / "textures" / "new.jpg"
        jpg.write_bytes(b"x")
        self.assertTrue(ensure_import_params(self.godot, jpg, "texture", {**TEXTURE_PARAMS, **JPG_PARAMS}))
        text = jpg.with_name("new.jpg.import").read_text()
        self.assertTrue(text.startswith('[remap]\n\nimporter="texture"\n'))
        self.assertEqual(self._params(jpg.with_name("new.jpg.import")),
                         {"mipmaps/generate": "true", "detect_3d/compress_to": "0",
                          "compress/mode": "1", "compress/lossy_quality": "0.85"})

    def test_missing_scene_sidecar_is_left_to_importer_defaults(self) -> None:
        glb = self.godot / "assets" / "models" / "new.glb"
        glb.write_bytes(b"x")
        self.assertFalse(ensure_import_params(self.godot, glb, None, SCENE_PARAMS))
        self.assertFalse(glb.with_name("new.glb.import").exists())

    def test_apply_import_params_covers_jpg_png_and_glb(self) -> None:
        textures = self.godot / "assets" / "textures"
        (textures / "a.jpg").write_bytes(b"x")
        (textures / "b.png").write_bytes(b"x")
        glb = self.godot / "assets" / "models" / "m.glb"
        glb.write_bytes(b"x")
        glb.with_name("m.glb.import").write_text('[remap]\n\nimporter="scene"\n\n[params]\n\nanimation/fps=30\n')
        self.assertEqual(apply_import_params(self.godot), 3)
        self.assertEqual(self._params(textures / "a.jpg.import")["compress/mode"], "1")
        self.assertNotIn("compress/mode", self._params(textures / "b.png.import"))
        self.assertEqual(self._params(glb.with_name("m.glb.import"))["animation/fps"], "1")


class GeneratedAssetsTests(unittest.TestCase):
    """Checks on the generated godot/assets (run tools/build_assets.py first)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.textures = GODOT_DIR / "assets" / "textures"
        if not (GODOT_DIR / "assets" / "manifest.json").exists():
            raise unittest.SkipTest("run tools/build_assets.py first")

    def test_runtime_texture_paths_exist(self) -> None:
        """Paths hard-coded in src/ and data/ must survive the duplicate collapsing."""
        refs: set[str] = set()
        for folder in ("src", "data"):
            for p in (GODOT_DIR / folder).rglob("*"):
                if p.suffix in (".gd", ".json"):
                    refs.update(RES_TEXTURE.findall(p.read_text()))
        self.assertGreater(len(refs), 40)
        # `Menu/Titul%d.png` is a format template (Titul1..3).
        refs = {r.replace("%d", "1") for r in refs}
        missing = [r for r in refs if not (GODOT_DIR / r[len("res://"):]).exists()]
        self.assertEqual(missing, [])

    def test_no_duplicate_texture_content(self) -> None:
        seen: dict[str, Path] = {}
        for p in sorted(self.textures.rglob("*")):
            if p.suffix.lower() in (".jpg", ".png", ".bmp") and "__" not in p.stem:
                digest = hashlib.md5(p.read_bytes()).hexdigest()
                self.assertNotIn(digest, seen, f"{p} duplicates {seen.get(digest)}")
                seen[digest] = p

    def test_sidecars_pin_lossy_jpg_and_one_key_per_frame(self) -> None:
        jpgs = sorted(self.textures.rglob("*.jpg.import"))
        glbs = sorted((GODOT_DIR / "assets" / "models").rglob("*.glb.import"))
        if not jpgs or not glbs:
            raise unittest.SkipTest("run godot --import first")
        for sidecar in jpgs:
            self.assertIn("\ncompress/mode=1\n", sidecar.read_text(), sidecar)
        for sidecar in glbs:
            self.assertIn("\nanimation/fps=1\n", sidecar.read_text(), sidecar)
