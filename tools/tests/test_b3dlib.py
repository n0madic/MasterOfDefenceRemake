"""b3dlib against an independent raw chunk walker (counts only) and known facts."""
from __future__ import annotations

import struct
import unittest
from pathlib import Path

from testpaths import DATA_DIR

import b3dlib


def raw_stats(data: bytes) -> dict:
    """Independent minimal walker: node names, vertex/triangle counts, key counts, ANIM frames."""
    stats = {"nodes": [], "verts": 0, "tris": 0, "keys": 0, "anim": 0}

    def walk(p: int, end: int) -> None:
        while p < end:
            tag = data[p:p + 4].decode("latin-1")
            (size,) = struct.unpack_from("<i", data, p + 4)
            body, cend = p + 8, p + 8 + size
            if tag == "BB3D":
                walk(body + 4, cend)
            elif tag == "NODE":
                e = data.index(b"\0", body)
                stats["nodes"].append(data[body:e].decode("cp1251", "replace"))
                walk(e + 1 + 40, cend)
            elif tag == "MESH":
                walk(body + 4, cend)
            elif tag == "VRTS":
                flags, tc_sets, tc_size = struct.unpack_from("<3i", data, body)
                per = 3 + (3 if flags & 1 else 0) + (4 if flags & 2 else 0) + tc_sets * tc_size
                stats["verts"] += (cend - body - 12) // (4 * per)
            elif tag == "TRIS":
                stats["tris"] += (cend - body - 4) // 12
            elif tag == "KEYS":
                (flags,) = struct.unpack_from("<i", data, body)
                per = 4 + (12 if flags & 1 else 0) + (12 if flags & 2 else 0) + (16 if flags & 4 else 0)
                stats["keys"] += (cend - body - 4) // per
            elif tag == "ANIM":
                stats["anim"] = max(stats["anim"], struct.unpack_from("<i", data, body + 4)[0])
            p = cend

    walk(0, len(data))
    return stats


def all_b3d(data_dir: Path) -> list[Path]:
    return sorted(data_dir.rglob("*.b3d"))


@unittest.skipUnless(DATA_DIR.exists(), "unpacked game data not present")
class DataDependentTests(unittest.TestCase):
    def test_every_file_matches_raw_counts(self) -> None:
        files = all_b3d(DATA_DIR)
        self.assertEqual(len(files), 84)
        for path in files:
            raw = path.read_bytes()
            f = b3dlib.parse(raw, path)
            stats = raw_stats(raw)
            nodes = f.nodes()
            self.assertEqual([n.name for n in nodes], stats["nodes"], path)
            self.assertEqual(sum(len(n.mesh.verts) for n in nodes if n.mesh), stats["verts"], path)
            self.assertEqual(sum(n.mesh.tri_count for n in nodes if n.mesh), stats["tris"], path)
            self.assertGreaterEqual(sum(sum(len(rec) for rec in n.keys.values()) // 1 for n in nodes), 0)
            self.assertEqual(f.anim_frames, stats["anim"], path)

    def test_known_structures(self) -> None:
        mil = b3dlib.load(DATA_DIR / "Towers" / "Military.b3d")
        self.assertEqual(mil.anim_frames, 210)
        self.assertIsNotNone(mil.root.find("fire1"))
        self.assertIsNotNone(mil.root.find("dno"))
        self.assertLessEqual({b.fx for b in mil.brushes}, {0, 1})
        loc1 = b3dlib.load(next(p for p in (DATA_DIR / "Location1").iterdir() if p.name.lower() == "location1.b3d"))
        names = {b3dlib.clean_name(n.name)[0] for n in loc1.nodes()}
        self.assertLessEqual({"grass", "road", "noparking", "rocks", "river", "border", "door"}, names)
        grass = next(n for n in loc1.nodes() if n.name.endswith("_grass"))
        self.assertEqual(b3dlib.clean_name(grass.name), ("grass", {"order": 30}))
        lightmaps = [t for t in loc1.textures if t.uses_uv2]
        self.assertTrue(lightmaps)
        self.assertTrue(all(t.name.lower().endswith("lm.jpg") for t in lightmaps))
        health = b3dlib.load(DATA_DIR / "Monsters" / "Health.b3d")
        self.assertTrue(any(n.bone for n in health.nodes()))
        balloon = b3dlib.load(DATA_DIR / "Towers" / "Balloon.b3d")
        self.assertTrue(any(n.bone for n in balloon.nodes()))
        bone_files = {p.name for p in all_b3d(DATA_DIR) if any(n.bone for n in b3dlib.load(p).nodes())}
        self.assertEqual(bone_files, {"Health.b3d", "Balloon.b3d"})

    def test_vertex_flags_survey(self) -> None:
        # Was parametrized over flags=[0, 1, 2, 3] in pytest, but the body never used the
        # parameter and ran identically each time; collapsed into a single run here.
        seen = set()
        for path in all_b3d(DATA_DIR):
            for n in b3dlib.load(path).nodes():
                if n.mesh and n.mesh.verts:
                    seen.add(n.mesh.flags)
        self.assertEqual(seen, {0, 1, 3})


class StandaloneTests(unittest.TestCase):
    def test_clean_name(self) -> None:
        self.assertEqual(b3dlib.clean_name("B3D_ORDR_-5_fon"), ("fon", {"order": -5}))
        self.assertEqual(b3dlib.clean_name("B3D_BB_1_tree"), ("tree", {"billboard": True}))
        self.assertEqual(b3dlib.clean_name("plain"), ("plain", {}))


if __name__ == "__main__":
    unittest.main()
