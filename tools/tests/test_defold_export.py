"""Checks of the Defold export (defold/tools/export_defold.py) against the generated
godot/assets of Location1 (run tools/convert_all.py first)."""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from testpaths import GODOT_DIR, ROOT

from blitzconv import srgb_to_linear
from gltfwriter import read_accessor, read_glb

TOOLS = ROOT / "defold" / "tools"


def load_exporter():
    sys.path.insert(0, str(TOOLS))
    spec = importlib.util.spec_from_file_location("export_defold", TOOLS / "export_defold.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DefoldExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not (GODOT_DIR / "assets" / "models" / "Location1" / "Location1.glb").exists():
            raise unittest.SkipTest("run tools/convert_all.py first")
        cls.module = load_exporter()
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls.tmp.name)
        cls.exporter = cls.module.Exporter(1, GODOT_DIR, cls.out)
        cls.exporter.run()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def glb(self, name: str):
        return read_glb(self.out / "assets" / "models" / f"{name}.glb")

    def test_colour_round_trip(self) -> None:
        from modexport.materials import gltf_color_to_blitz, linear_to_srgb
        for c in (0.0, 0.05, 0.3185468059531732, 0.6, 1.0):
            self.assertAlmostEqual(linear_to_srgb(srgb_to_linear(c)), c, places=5)
        self.assertAlmostEqual(gltf_color_to_blitz([0.0, 0.0, 0.0, 0.5 ** 1.5], additive=True)[3], 0.5, places=6)

    def test_location_helpers_zones_and_animations_dropped(self) -> None:
        doc, _ = self.glb("Location1")
        names = {n["name"] for n in doc["nodes"]}
        for helper in ("CamPath", "Camera01", "B3DEXT_CAMERA", "B3DEXT_DIRLIGHT", "Direct01", "road", "noparking"):
            self.assertNotIn(helper, names)
        self.assertIn("houses", names)
        self.assertNotIn("animations", doc)
        self.assertNotIn("skins", doc)
        self.assertNotIn("images", doc)

    def test_main_collection_follows_the_location(self) -> None:
        collection = (self.out / "generated" / "main.collection").read_text()
        self.assertIn('prototype: "/generated/go/Location1.go"', collection)
        self.assertIn('id: "ground_texture"', collection)
        self.assertIn('value: "/assets/textures/Towers/dno1.png"', collection)
        self.assertTrue((self.out / "assets" / "textures" / "Towers" / "dno1.png").exists())
        project = (ROOT / "defold" / "game.project").read_text()
        self.assertIn("main_collection = /generated/main.collectionc", project)

    def test_location_materials_per_brush_and_order(self) -> None:
        doc, _ = self.glb("Location1")
        names = [m["name"] for m in doc["materials"]]
        self.assertIn("01 - Default#5", names)  # road02, no order
        self.assertIn("01 - Default#5@order15", names)  # way, EntityOrder 15
        self.assertIn("07 - Default#1@order30", names)
        self.assertNotIn("13 - Default#0", names)  # invisible zone brush
        model = (self.out / "generated" / "models" / "Location1.model").read_text()
        for name in names:
            self.assertIn(f'name: "{name}"', model)

    def test_tower_is_skinned_with_a_joint_per_node(self) -> None:
        doc, blob = self.glb("Towers_Military")
        self.assertEqual(len(doc["skins"]), 1)
        skin = doc["skins"][0]
        mesh_node = next(n for n in doc["nodes"] if "mesh" in n)
        self.assertEqual(mesh_node["name"], "Mesh")
        self.assertEqual(mesh_node["skin"], 0)
        self.assertIn("gun02", [doc["nodes"][j]["name"] for j in skin["joints"]])
        anim = doc["animations"][0]
        self.assertEqual(anim["name"], "b3d")
        self.assertGreater(len(anim["channels"]), 0)
        prim = doc["meshes"][0]["primitives"][0]
        joints = read_accessor(doc, blob, prim["attributes"]["JOINTS_0"])
        weights = read_accessor(doc, blob, prim["attributes"]["WEIGHTS_0"])
        self.assertEqual(weights[0], (1.0, 0.0, 0.0, 0.0))
        self.assertTrue(all(j[1] == 0 and j[2] == 0 and j[3] == 0 for j in joints))
        # The base is its own component so the runtime can retexture it.
        self.assertTrue((self.out / "assets" / "models" / "Towers_Military_dno.glb").exists())
        go = (self.out / "generated" / "go" / "Towers_Military.go").read_text()
        self.assertIn('id: "dno"', go)
        self.assertIn('id: "main"', go)
        meta = self.exporter.models["Towers/Military"]
        self.assertTrue(meta["skinned"])
        self.assertEqual(meta["frames"], 210.0)

    def test_sheared_tower_uses_manual_bone_skinning(self) -> None:
        # Nature's hierarchy (non-uniform scale + rotation) carries shear that Defold's
        # SRT bones cannot hold, so it is posed by the `bone_matrices` array constant.
        nature = self.exporter.models["Towers/Nature"]
        self.assertFalse(nature["skinned"])
        self.assertIsNotNone(nature["bones"])
        self.assertEqual(nature["bones"]["count"], 15)
        self.assertEqual(nature["bones"]["frames"], 211)
        blob = (self.out / "generated" / "bones" / "Towers_Nature.bin").read_bytes()
        self.assertEqual(len(blob), 211 * 15 * 16 * 4)  # frames * joints * mat4 * float32
        vp = (self.out / "generated" / "materials" / "Towers_Nature_0.vp").read_text()
        self.assertIn("uniform", vp)
        self.assertIn("mat4 bone_matrices[15]", vp)
        self.assertIn("bone_matrices[int(bone_indices.x", vp)
        # The normal uses the cofactor (inverse-transpose) of the bone, not mat3(bone), so a
        # non-uniformly-scaled joint (the flat base) is lit correctly rather than going dark.
        self.assertIn("cross(bone3[1], bone3[2])", vp)
        self.assertNotIn("mat3(bone) * normal", vp)
        material = (self.out / "generated" / "materials" / "Towers_Nature_0.material").read_text()
        self.assertIn("CONSTANT_TYPE_USER_MATRIX4", material)
        # Skinning-capable towers without shear keep Defold's own animation.
        military = self.exporter.models["Towers/Military"]
        self.assertIsNone(military["bones"])
        self.assertTrue(military["skinned"])

    def test_bone_poses_reproduce_the_full_matrix_world_transform(self) -> None:
        from modexport.models import ModelExporter, load_sidecar, _basis_shear_degrees
        from b3d2gltf import mat_mul
        import struct
        glb = GODOT_DIR / "assets" / "models" / "Towers" / "Nature.glb"
        exp = ModelExporter("Towers/Nature", glb, load_sidecar(glb), self.out, self.out, self.exporter.light)
        self.assertTrue(exp.sheared)
        joints = exp._joint_order()
        # A leaf joint really is sheared (which is the whole reason for this path).
        self.assertTrue(any(_basis_shear_degrees(exp.world[j]) > 1.0 for j in joints))
        blob = (self.out / "generated" / "bones" / "Towers_Nature.bin").read_bytes()
        frame = 70  # inside a mid-level idle loop
        stride = len(joints) * 16 * 4
        world = exp._world_anim(float(frame), {})
        for j, joint in enumerate(joints):
            off = frame * stride + j * 16 * 4
            pose = [list(struct.unpack_from("<4f", blob, off + r * 16)) for r in range(4)]
            # The pose IS the joint's full animated world matrix (no inverse-bind): the mesh
            # keeps its joint-local vertices, so the runtime forms the world position as
            # pose * local. Never inverting a joint transform is what keeps a degenerate
            # scale from producing a near-singular matrix (see the death-soul test below).
            expected = world[joint]
            for r in range(4):
                for c in range(4):
                    self.assertAlmostEqual(pose[r][c], expected[r][c], places=4)

    def test_billboard_node_faces_the_camera(self) -> None:
        """The Magic tower's crown ring (`B3D_BB_1_Object01`) is a Blitz billboard; drawn as a
        static quad it lay tilted on its side. It gets its own material variant whose shader
        replaces the joint's rotation by the camera basis (keeping position and scale), which
        needs the bone-matrix path's joint-local vertices."""
        magic = self.exporter.models["Towers/Magic"]
        self.assertIsNotNone(magic["bones"])
        self.assertFalse(magic["skinned"])
        # The ring's texture scrolls (ANIMMAP), so it lives in the tower's `anim` group model.
        models = "".join(p.read_text() for p in (self.out / "generated" / "models").glob("Towers_Magic*.model"))
        self.assertIn("@billboard", models)
        billboard_vps = [p.read_text() for p in (self.out / "generated" / "materials").glob("Towers_Magic_*.vp")
                         if "bb_scale" in p.read_text()]
        self.assertEqual(len(billboard_vps), 1)  # only the crown ring, not the body rings
        self.assertIn("mv[3].xyz + bb_basis * (bb_scale * position.xyz)", billboard_vps[0])
        # PointEntity(node, camera): the node Z aims at the camera position, not the camera axes.
        self.assertIn("bb_z = normalize(mv[3].xyz)", billboard_vps[0])

    def test_degenerate_scale_uses_local_bone_matrix_path(self) -> None:
        """The death soul's frost planes are flattened to scale 0.001 on one axis, whose
        inverse-bind matrix is near-singular and which Defold's skinning renders as garbage
        (the ghost showed up flipped). Such a model must take the bone-matrix path with
        joint-local vertices, exactly as Godot transforms its nodes."""
        from modexport.models import ModelExporter, load_sidecar
        glb = GODOT_DIR / "assets" / "models" / "Towers" / "death.glb"
        exp = ModelExporter("Towers/death", glb, load_sidecar(glb), self.out, self.out, self.exporter.light)
        self.assertFalse(exp.sheared)               # not sheared ...
        self.assertTrue(exp._degenerate_scale)      # ... but a degenerate joint scale ...
        self.assertTrue(exp.bone_posed)             # ... so it is bone-posed all the same.
        death = self.exporter.models["Towers/death"]
        self.assertFalse(death["skinned"])          # posed by bones, not by Defold's rig
        self.assertIsNotNone(death["bones"])
        vp = (self.out / "generated" / "materials" / "Towers_death_0.vp").read_text()
        self.assertIn("bone_matrices[10]", vp)
        # The exported vertices are joint-local (not baked into world space): a flattened
        # plane keeps its full local extent instead of being collapsed by the 0.001, and the
        # inverse-bind matrices are identity (never the near-singular inverse of the scale).
        doc, blob = self.glb("Towers_death")
        pos = read_accessor(doc, blob, doc["meshes"][0]["primitives"][0]["attributes"]["POSITION"])
        self.assertGreater(max(abs(p[1]) for p in pos), 1.0)
        ibm = read_accessor(doc, blob, doc["skins"][0]["inverseBindMatrices"])
        self.assertLessEqual(max(abs(v) for m in ibm for v in m), 1.0 + 1e-4)

    def test_animmap_brushes_get_their_own_components(self) -> None:
        meta = self.exporter.models["Towers/Freeze"]
        self.assertEqual(len(meta["animmaps"]), 2)
        groups = {m["group"] for m in meta["animmaps"]}
        self.assertEqual(groups, {"anim0", "anim1"})
        self.assertEqual(len(meta["animmaps"][0]["keys"]), 111)  # frames 0..110
        for g in groups:
            self.assertIn(g, meta["groups"])
        vp = (self.out / "generated" / "materials" / "Towers_Freeze_1.vp").read_text()
        self.assertIn("uv_offset", "".join((self.out / "generated" / "materials" / f).read_text()
                                           for f in ("Towers_Freeze_0.vp", "Towers_Freeze_1.vp", "Towers_Freeze_2.vp")))

    def test_monster_keeps_morph_targets_and_a_lit_material(self) -> None:
        doc, _ = self.glb("Monsters_Nite")
        prim = doc["meshes"][0]["primitives"][0]
        self.assertEqual(len(prim["targets"]), 10)
        self.assertNotIn("skins", doc)
        meta = self.exporter.models["Monsters/Nite"]
        self.assertEqual(meta["morph_targets"], 10)
        self.assertFalse(meta["skinned"])
        vp = (self.out / "generated" / "materials" / "Monsters_Nite_0.vp").read_text()
        self.assertIn("morph_targets_weights[3]", vp)
        self.assertIn("light_dir", vp)

    def test_hud_panel_groups_and_sphere_maps(self) -> None:
        go = (self.out / "generated" / "go" / "Env.go").read_text()
        self.assertIn('id: "updates"', go)
        self.assertIn('id: "window"', go)
        material = (self.out / "generated" / "materials" / "Env_0.material").read_text()
        self.assertIn('tags: "hud"', material)
        death_fps = [(self.out / "generated" / "materials" / f"Towers_death_{i}.fp").read_text() for i in range(4)]
        self.assertTrue(any("var_sphere_uv" in fp for fp in death_fps))
        # The sphere UV is computed in the shader, so it bypasses the V flip Defold applies
        # to imported texcoords; its V sign must be the opposite of Godot's or every
        # sphere-mapped texture renders upside down (the death soul's ghost pointed up).
        vp = (self.out / "generated" / "materials" / "Towers_death_4.vp").read_text()
        self.assertIn("0.5 + 0.5 * n.y", vp)
        self.assertNotIn("0.5 - 0.5 * n.y", vp)

    def test_tower_base_draws_in_its_own_pass_before_translucent_bodies(self) -> None:
        # The `dno` base decal is tagged for the dedicated `base` pass, which sits between
        # order_0 opaque and order_0 blend so a translucent trunk cannot sort-flip with it.
        for tower in ("Towers_Nature_2", "Towers_Military_2"):
            material = (self.out / "generated" / "materials" / f"{tower}.material").read_text()
            self.assertIn('tags: "base"', material)
        data = (self.out / "generated" / "level_data.lua").read_text()
        opaque = data.index('{tags = {"order_0", "opaque"}')
        base_solid = data.index('{tags = {"base", "opaque"}')
        base = data.index('{tags = {"base", "blend"}')
        body = data.index('{tags = {"order_0", "blend"}')
        self.assertLess(opaque, base_solid)
        self.assertLess(base_solid, base)
        self.assertLess(base, body)
        # The base's alpha-scissor depth companion writes depth (occludes the underground
        # root); its opaque pass is depth-writing, the soft blended copy on top is not.
        self.assertIn('{tags = {"base", "opaque"}, depth_test = true, depth_write = true', data)
        self.assertIn('{tags = {"base", "blend"}, depth_test = true, depth_write = false', data)
        go = (self.out / "generated" / "go" / "Towers_Nature.go").read_text()
        self.assertIn('id: "dno_solid"', go)
        solid = (self.out / "generated" / "models" / "Towers_Nature_dno_solid.model").read_text()
        self.assertIn('mesh: "/assets/models/Towers_Nature_dno.glb"', solid)  # reuses the base glb
        self.assertIn('name: "08 - Defauserglt#2@base"', solid)  # binds to the base's material slot
        self.assertIn("if (c.a < 0.990000) discard", (self.out / "generated" / "materials" / "Towers_Nature_2_solid.fp").read_text())

    def test_level_data_zones_gradient_and_hud_atlas(self) -> None:
        data = (self.out / "generated" / "level_data.lua").read_text()
        self.assertIn("x_min = 50, x_max = 70, z_min = -40, z_max = 0", data)
        self.assertIn('{tags = {"order_30", "opaque"}, depth_test = false', data)
        self.assertIn("grass = {", data)
        self.assertIn("road = {", data)
        self.assertIn("M.gradient = {", data)
        self.assertEqual(len([p for p in (self.out / "assets" / "hud").glob("g*.png")]), 255 - 33 + 1)
        self.assertTrue((self.out / "assets" / "hud" / "btn_big_6_2.png").exists())
        self.assertTrue((self.out / "data" / "raids.json").exists())
        entities = (self.out / "generated" / "entities.go").read_text()
        self.assertIn('id: "factory_Monsters_Ratter"', entities)
        light = self.exporter.light
        self.assertAlmostEqual(sum(c * c for c in light["direction"]), 1.0, places=5)
        self.assertLess(light["direction"][1], 0.0)


if __name__ == "__main__":
    unittest.main()
