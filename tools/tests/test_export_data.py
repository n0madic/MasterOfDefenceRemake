from __future__ import annotations

import json
import unittest

from testpaths import GODOT_DIR

from export_godot_data import add_vd_tags, on_disk_name


class ExportDataTests(unittest.TestCase):
    def test_add_vd_tags_wraps_at_last_space(self) -> None:
        # _faddvdtags quirk: after an inserted tag the scan resumes at "vd>", so those three
        # characters count towards the next line, which is therefore 3 columns shorter.
        text = "aaaa bbbb cccc dddd eeee"
        self.assertEqual(add_vd_tags(text, 10), "aaaa bbbb<vd>cccc<vd>dddd<vd>eeee")

    def test_add_vd_tags_resets_on_existing_tag(self) -> None:
        text = "aaaa bbbb<vd>cccc dddd eeee ffff"
        self.assertEqual(add_vd_tags(text, 10), "aaaa bbbb<vd>cccc dddd<vd>eeee<vd>ffff")

    def test_exported_data_shapes(self) -> None:
        data = GODOT_DIR / "data"
        units = json.loads((data / "units.json").read_text())
        self.assertEqual(len(units), 34)
        self.assertTrue(units[0]["model"].startswith("res://assets/models/Monsters/"))
        raids = json.loads((data / "raids.json").read_text())
        self.assertEqual(len(raids["campaign"]), 180)
        self.assertEqual(len(raids["survival"]), 200)
        paths = json.loads((data / "paths.json").read_text())
        self.assertEqual([paths[str(L)]["anim_frames"] for L in range(1, 7)], [20, 100, 30, 80, 70, 100])
        locs = json.loads((data / "locations.json").read_text())
        self.assertEqual(locs["1"]["bounds"], {"x_min": 50, "x_max": 70, "z_min": -40, "z_max": 0})
        texts = json.loads((data / "texts.json").read_text())
        self.assertEqual(texts["texts"][0], "Upgrade")

    def test_unit_model_paths_match_the_files_case(self) -> None:
        """An exported pck is case-sensitive: `Male.md2` in the table is `male.glb` on disk."""
        units = json.loads((GODOT_DIR / "data" / "units.json").read_text())
        models = GODOT_DIR / "assets" / "models" / "Monsters"
        if not models.is_dir():
            self.skipTest("godot/assets not converted")
        on_disk = {f.name for f in models.iterdir()}
        for u in units:
            self.assertIn(u["model"].rsplit("/", 1)[1], on_disk, u["model"])

    def test_on_disk_name_matches_case_insensitively(self) -> None:
        models = GODOT_DIR / "assets" / "models" / "Monsters"
        if not models.is_dir():
            self.skipTest("godot/assets not converted")
        self.assertEqual(on_disk_name(models, "Male.glb"), "male.glb")
        self.assertEqual(on_disk_name(models, "Nothing.glb"), "Nothing.glb")


if __name__ == "__main__":
    unittest.main()
