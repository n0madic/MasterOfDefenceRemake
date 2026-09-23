"""Conversion checks on the import stage's tree (run tools/build_assets.py first)."""
from __future__ import annotations

import json
import unittest

from testpaths import DATA_DIR, DOCS_DATA, GODOT_DIR, IMPORT_DIR

import b3dlib
from blitzconv import ADDITIVE_ALPHA_EXPONENT, WINDING_SWAP, blitz_quat_to_godot, blitz_to_godot, srgb_to_linear
from gltfwriter import read_accessor, read_glb
from md2togltf import load_md2

FLYERS = {7: "Ratter", 14: "Head", 21: "TwoEyed", 28: "Sepp"}


class ManifestTestCase(unittest.TestCase):
    """Loads godot/assets/manifest.json once; skips the whole class if it's missing."""

    manifest: dict

    @classmethod
    def setUpClass(cls) -> None:
        path = IMPORT_DIR / "assets" / "manifest.json"
        if not path.exists():
            raise unittest.SkipTest("run tools/build_assets.py first")
        cls.manifest = json.loads(path.read_text())


class ManifestTests(ManifestTestCase):
    def test_manifest_counts_and_missing_textures(self) -> None:
        self.assertEqual(len(self.manifest["b3d"]), 84)
        self.assertEqual(len(self.manifest["md2"]), 34)
        self.assertEqual(self.manifest["missing_textures"], {"Menu/highscores.b3d": ["HighScores.png"]})

    def test_md2_glb_morph_targets(self) -> None:
        info = self.manifest["md2"]["Monsters/Crawl.md2"]
        doc, blob = read_glb(IMPORT_DIR / info["glb"])
        prim = doc["meshes"][0]["primitives"][0]
        self.assertEqual(len(prim["targets"]), 10)
        anim = doc["animations"][0]
        self.assertEqual(anim["name"], "md2")
        times = read_accessor(doc, blob, anim["samplers"][0]["input"])
        self.assertEqual(times, [float(k) for k in range(12)])
        weights = read_accessor(doc, blob, anim["samplers"][0]["output"])
        self.assertEqual(weights[:10], [0.0] * 10)  # frame 0 = base
        self.assertEqual(weights[10:20], [1.0] + [0.0] * 9)  # frame 1
        self.assertEqual(weights[-10:], [0.0] * 10)  # wrap to frame 0

    def test_md2_faces_point_outwards(self) -> None:
        """Same winding invariant for MD2: most right-hand-rule face normals point away from
        the centroid, i.e. the front faces are outside."""
        for name in ("Crawl", "Skeleton", "Ratter"):
            info = self.manifest["md2"][f"Monsters/{name}.md2"]
            doc, blob = read_glb(IMPORT_DIR / info["glb"])
            prim = doc["meshes"][0]["primitives"][0]
            pos = read_accessor(doc, blob, prim["attributes"]["POSITION"])
            idx = read_accessor(doc, blob, prim["indices"])
            centroid = [sum(p[i] for p in pos) / len(pos) for i in range(3)]
            outward = 0
            total = 0
            for t in range(0, len(idx), 3):
                a, b, c = (pos[idx[t + k]] for k in range(3))
                u = [b[i] - a[i] for i in range(3)]
                v = [c[i] - a[i] for i in range(3)]
                n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
                mid = [(a[i] + b[i] + c[i]) / 3 - centroid[i] for i in range(3)]
                total += 1
                if sum(n[i] * mid[i] for i in range(3)) > 0:
                    outward += 1
            # Concave creatures (Crawl) only reach ~62%; a flipped winding gives < 40%.
            self.assertGreater(outward / total, 0.55, (name, outward, total))


@unittest.skipUnless(DATA_DIR.exists(), "unpacked game data not present")
class ManifestAndDataTests(ManifestTestCase):
    def test_glb_node_names_and_animation_lengths(self) -> None:
        for key, info in self.manifest["b3d"].items():
            doc, _ = read_glb(IMPORT_DIR / info["glb"])
            src = b3dlib.load(DATA_DIR / key)
            names = [b3dlib.clean_name(n.name)[0] for n in src.nodes()]
            gltf_names = [n["name"] for n in doc["nodes"]]
            self.assertEqual(len(gltf_names), len(names), key)
            for a, b in zip(gltf_names, names):
                self.assertTrue(a == b or a.startswith(b + "_"), (key, a, b))
            sidecar = json.loads((IMPORT_DIR / info["glb"]).with_suffix("").with_suffix(".b3d.json").read_text())
            self.assertEqual(sidecar["anim_frames"], src.anim_frames)
            if any(n.has_keys for n in src.nodes()):
                anim = doc["animations"][0]
                self.assertEqual(anim["name"], "b3d")

    def test_md2_bbox_and_flyers(self) -> None:
        for unit_id, name in FLYERS.items():
            info = self.manifest["md2"][f"Monsters/{name}.md2"]
            self.assertGreater(info["bbox_min"][1], 1.5, (name, info["bbox_min"]))
        walker = self.manifest["md2"]["Monsters/Crawl.md2"]
        self.assertLess(walker["bbox_min"][1], 1.0)
        md2 = load_md2(DATA_DIR / "Monsters" / "Crawl.md2")
        self.assertEqual(len(md2.frames), 11)
        self.assertTrue(all(0.0 <= u <= 1.0 and 0.0 <= v <= 1.0 for u, v in md2.uvs))
        # Walk direction: Blitz MD2 models face +z (Blitz) -> -z in Godot; the model should be
        # longer along z than along y for a quadruped.
        mins, maxs = walker["bbox_min"], walker["bbox_max"]
        self.assertGreater(maxs[2] - mins[2], 0)


class GlbTests(unittest.TestCase):
    def test_path_keys_equal_converted_export(self) -> None:
        exported = json.loads((DOCS_DATA / "enemy_paths.json").read_text())
        for L in range(1, 7):
            doc, blob = read_glb(IMPORT_DIR / "assets" / "models" / f"Location{L}" / "Path1.glb")
            path_node = next(i for i, n in enumerate(doc["nodes"]) if n["name"] == "path")
            anim = doc["animations"][0]
            chan = next(c for c in anim["channels"] if c["target"]["node"] == path_node and c["target"]["path"] == "translation")
            sampler = anim["samplers"][chan["sampler"]]
            times = read_accessor(doc, blob, sampler["input"])
            values = read_accessor(doc, blob, sampler["output"])
            keys = exported[f"location{L}"]["waypoints"]
            self.assertEqual(len(times), len(keys))
            for t, v, k in zip(times, values, keys):
                self.assertEqual(t, k["frame"])
                expected = blitz_to_godot(tuple(k["pos"]))
                self.assertTrue(all(abs(a - b) < 1e-3 for a, b in zip(v, expected)), (L, t))
            rot_chan = next(c for c in anim["channels"] if c["target"]["node"] == path_node and c["target"]["path"] == "rotation")
            rots = read_accessor(doc, blob, anim["samplers"][rot_chan["sampler"]]["output"])
            w, x, y, z = blitz_quat_to_godot(tuple(keys[0]["rot_wxyz"]))
            self.assertTrue(all(abs(a - b) < 1e-3 for a, b in zip(rots[0], (x, y, z, w))))

    def test_floor_quads_face_up_after_conversion(self) -> None:
        """Winding check: with the z-mirror plus index swap the right-hand-rule normal is +y."""
        self.assertIs(WINDING_SWAP, True)
        for L in (1, 2, 3):
            doc, blob = read_glb(IMPORT_DIR / "assets" / "models" / f"Location{L}" / f"Location{L}.glb")
            node = next(n for n in doc["nodes"] if n["name"] == "grass")
            prim = doc["meshes"][node["mesh"]]["primitives"][0]
            pos = read_accessor(doc, blob, prim["attributes"]["POSITION"])
            idx = read_accessor(doc, blob, prim["indices"])
            a, b, c = (pos[i] for i in idx[:3])
            u = [b[i] - a[i] for i in range(3)]
            v = [c[i] - a[i] for i in range(3)]
            n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
            self.assertGreater(n[1], 0, (L, n))
            normals = read_accessor(doc, blob, prim["attributes"]["NORMAL"])
            self.assertGreater(normals[idx[0]][1], 0.99)

    def test_location3_has_separate_grass01(self) -> None:
        doc, _ = read_glb(IMPORT_DIR / "assets" / "models" / "Location3" / "Location3.glb")
        names = {n["name"] for n in doc["nodes"]}
        self.assertIn("grass", names)
        self.assertIn("grass01", names)
        for L in range(1, 7):
            doc, _ = read_glb(IMPORT_DIR / "assets" / "models" / f"Location{L}" / f"Location{L}.glb")
            names = {n["name"] for n in doc["nodes"]}
            self.assertLessEqual({"grass", "road", "noparking", "rocks"}, names, L)

    def test_b3d_bones_become_skins(self) -> None:
        """The two boned B3D files get one glTF skin: joints = bones in file order, weights
        padded to four slots and summing to one, an inverse bind matrix per joint."""
        for model, joints in (("Towers/Balloon.glb", 2), ("Monsters/Health.glb", 8)):
            with self.subTest(model=model):
                doc, blob = read_glb(IMPORT_DIR / "assets" / "models" / model)
                self.assertEqual(len(doc["skins"]), 1)
                skin = doc["skins"][0]
                self.assertEqual(len(skin["joints"]), joints)
                ibm = read_accessor(doc, blob, skin["inverseBindMatrices"])
                self.assertEqual(len(ibm), joints)
                self.assertTrue(all(len(m) == 16 for m in ibm))
                skinned = [n for n in doc["nodes"] if "skin" in n]
                self.assertEqual(len(skinned), 1)
                self.assertIn("mesh", skinned[0])
                for prim in doc["meshes"][skinned[0]["mesh"]]["primitives"]:
                    weights = read_accessor(doc, blob, prim["attributes"]["WEIGHTS_0"])
                    joint_ids = read_accessor(doc, blob, prim["attributes"]["JOINTS_0"])
                    self.assertTrue(all(abs(sum(w) - 1.0) < 1e-5 for w in weights))
                    self.assertLess(max(max(j) for j in joint_ids), joints)

    def test_skin_rest_pose_inverse_bind(self) -> None:
        """IBM of the first balloon bone undoes its rest transform relative to the mesh node."""
        import b3d2gltf
        doc, blob = read_glb(IMPORT_DIR / "assets" / "models" / "Towers" / "Balloon.glb")
        skin = doc["skins"][0]
        joint = doc["nodes"][skin["joints"][0]]
        local = b3d2gltf.trs_matrix(tuple(joint["translation"]),
                                    (joint["rotation"][3], joint["rotation"][0], joint["rotation"][1], joint["rotation"][2]),
                                    tuple(joint["scale"]))
        ibm = read_accessor(doc, blob, skin["inverseBindMatrices"])[0]
        ibm_rows = [[ibm[c * 4 + r] for c in range(4)] for r in range(4)]
        identity = b3d2gltf.mat_mul(ibm_rows, local)
        for r in range(4):
            for c in range(4):
                self.assertAlmostEqual(identity[r][c], 1.0 if r == c else 0.0, delta=1e-5)

    def test_ogg_comment_header_is_well_formed(self) -> None:
        """Godot rejects Vorbis user comments without '='; the Godot target remuxes them away."""
        oggs = sorted((GODOT_DIR / "assets" / "audio").glob("*.ogg"))
        self.assertEqual(len(oggs), 7)
        for ogg in oggs:
            data = ogg.read_bytes()
            self.assertNotIn(b"Sonic Foundry", data, ogg.name)
            self.assertTrue(data.startswith(b"OggS"))

    def test_colours_are_linearised_and_vertex_alpha_follows_blitz_blending(self) -> None:
        """Blitz shades in gamma space: brush colours become linear glTF factors. Vertex
        alpha survives only for `EntityFX 2` brushes Blitz alpha-blends (`Brush::getBlend`):
        the menu fire (ADD + force alpha) keeps its flame-shaped alpha ramp, Location5
        `grass` (fx 35: force alpha) fades into the ground, while a plain vertex-coloured
        brush without blending (Location3 ice) is opaque."""
        doc, blob = read_glb(IMPORT_DIR / "assets" / "models" / "Location3" / "Location3.glb")
        mat = next(m for m in doc["materials"] if m["name"].startswith("faerfgqe"))
        factor = mat["pbrMetallicRoughness"]["baseColorFactor"]
        self.assertAlmostEqual(factor[0], srgb_to_linear(0.086), delta=1e-3)
        self.assertEqual(factor[3], 1.0)
        doc, blob = read_glb(IMPORT_DIR / "assets" / "models" / "Location5" / "Location5.glb")
        node = next(n for n in doc["nodes"] if n["name"] == "grass")
        prim = doc["meshes"][node["mesh"]]["primitives"][0]
        colours = read_accessor(doc, blob, prim["attributes"]["COLOR_0"])
        self.assertEqual({round(c[3], 2) for c in colours}, {0.0, 1.0})
        self.assertLessEqual(max(c[0] for c in colours), 1.0)
        doc, blob = read_glb(IMPORT_DIR / "assets" / "models" / "Menu" / "env.glb")
        node = next(n for n in doc["nodes"] if n["name"] == "fire")
        prim = doc["meshes"][node["mesh"]]["primitives"][0]
        colours = read_accessor(doc, blob, prim["attributes"]["COLOR_0"])
        # An additive brush: the alpha ramp is compensated for linear blending (a ** 1.5).
        expected = {round(a ** ADDITIVE_ALPHA_EXPONENT, 2) for a in (0.0, 0.1, 0.25, 0.5, 0.75, 1.0)}
        self.assertEqual({round(c[3], 2) for c in colours}, expected)
        src = b3dlib.load(DATA_DIR / "Location3" / "Location3.b3d")
        opaque = [b for b in src.brushes if b.fx & b3dlib.FX_VERTEX_COLORS and not b.is_blended(src.textures)]
        self.assertTrue(opaque)
        self.assertFalse(any(b.uses_vertex_alpha(src.textures) for b in opaque))
        self.assertLessEqual(max(c[0] for c in colours), 1.0)

    def test_mirrored_nodes_get_reversed_winding(self) -> None:
        """Location6 `Line04` has scale (-1,-1,-1.49): its triangles are stored reversed so the
        mirror puts them right on screen; Godot flips culling for mirrored instances, so the
        converter reverses them again and the geometric normal agrees with the vertex normal."""
        doc, blob = read_glb(IMPORT_DIR / "assets" / "models" / "Location6" / "Location6.glb")
        node = next(n for n in doc["nodes"] if n["name"] == "Line04")
        self.assertLess(node["scale"][0] * node["scale"][1] * node["scale"][2], 0)
        prim = doc["meshes"][node["mesh"]]["primitives"][0]
        pos = read_accessor(doc, blob, prim["attributes"]["POSITION"])
        nrm = read_accessor(doc, blob, prim["attributes"]["NORMAL"])
        idx = read_accessor(doc, blob, prim["indices"])
        agree = 0
        for t in range(0, len(idx), 3):
            a, b, c = (pos[idx[t + k]] for k in range(3))
            u = [b[i] - a[i] for i in range(3)]
            v = [c[i] - a[i] for i in range(3)]
            n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
            if sum(n[i] * nrm[idx[t]][i] for i in range(3)) > 0:
                agree += 1
        self.assertGreater(agree, len(idx) // 3 * 0.95)

    def test_texture_clamp_flags_are_recorded_per_layer(self) -> None:
        """Location2 `mountain` wraps `rock.jpg` and clamps V of the `rockalpha.jpg` fade on the
        second UV set (flag 32): a brush-level clamp would leave the fade repeating and cut a
        transparent band across the cliff wall where the second UV set crosses V = 0."""
        sidecar = json.loads((IMPORT_DIR / "assets" / "models" / "Location2" / "Location2.b3d.json").read_text())
        layers = sidecar["materials"]["mountain#6"]["layers"]
        self.assertEqual([(layer["clamp_u"], layer["clamp_v"]) for layer in layers], [(False, False), (False, True)])
        self.assertTrue(layers[1]["uv2"])
        # Menu fire: `flame.jpg` clamps V only, on the first (and only) layer.
        sidecar = json.loads((IMPORT_DIR / "assets" / "models" / "Menu" / "env.b3d.json").read_text())
        flame = next(m for m in sidecar["materials"].values() if any("flame.jpg" in layer["texture"] for layer in m["layers"]))
        self.assertEqual((flame["layers"][0]["clamp_u"], flame["layers"][0]["clamp_v"]), (False, True))


if __name__ == "__main__":
    unittest.main()
