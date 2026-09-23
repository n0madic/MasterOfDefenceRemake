"""Checks of the Defold export (defold/tools/export_defold.py) against the generated
godot/assets of Location1 (run tools/convert_all.py first)."""
from __future__ import annotations

import importlib.util
import re
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
        cls.exporter = cls.module.Exporter([1, 6], GODOT_DIR, cls.out)
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

    def test_location_collections_set_the_location_and_its_ground(self) -> None:
        for location in (1, 6):
            collection = (self.out / "generated" / "collections" / f"location{location}.collection").read_text()
            self.assertIn(f'name: "location{location}"', collection)
            self.assertIn(f'prototype: "/generated/go/Location{location}.go"', collection)
            self.assertIn('prototype: "/main/location/location.go"', collection)
            self.assertIn(f'value: "{location}"', collection)
            self.assertIn(f'value: "/assets/textures/Towers/dno{location}.png"', collection)
            self.assertTrue((self.out / "assets" / "textures" / "Towers" / f"dno{location}.png").exists())
        index = (self.out / "generated" / "locations.lua").read_text()
        self.assertIn('[6] = require("generated.locations.l6")', index)
        project = (ROOT / "defold" / "game.project").read_text()
        self.assertIn("main_collection = /main/main.collectionc", project)

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
        exp = ModelExporter("Towers/Nature", glb, load_sidecar(glb), self.out, self.out)
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
        exp = ModelExporter("Towers/death", glb, load_sidecar(glb), self.out, self.out)
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
        data = (self.out / "generated" / "render_passes.lua").read_text()
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
        self.assertIn('mesh: "/assets/models/Towers_Nature_dno_solid.glb"', solid)
        self.assertIn('name: "08 - Defauserglt#2@base"', solid)  # binds to the base's material slot
        self.assertIn("if (c.a < 0.990000) discard", (self.out / "generated" / "materials" / "Towers_Nature_2_solid.fp").read_text())

    def test_location_data_zones_light_gradient_and_hud_atlas(self) -> None:
        data = (self.out / "generated" / "locations" / "l1.lua").read_text()
        self.assertIn("x_min = 50, x_max = 70, z_min = -40, z_max = 0", data)
        self.assertIn("grass = {", data)
        self.assertIn("road = {", data)
        self.assertIn('M.music = "music1"', data)
        self.assertIn("M.shadows = false", (self.out / "generated" / "locations" / "l6.lua").read_text())
        passes = (self.out / "generated" / "render_passes.lua").read_text()
        self.assertIn('{tags = {"order_30", "opaque"}, depth_test = false', passes)
        self.assertIn("M.gradient = {", (self.out / "generated" / "common.lua").read_text())
        self.assertEqual(len([p for p in (self.out / "assets" / "hud").glob("g*.png")]), 255 - 33 + 1)
        self.assertTrue((self.out / "assets" / "hud" / "btn_big_6_2.png").exists())
        self.assertTrue((self.out / "data" / "raids.json").exists())
        entities = (self.out / "generated" / "entities.go").read_text()
        self.assertIn('id: "factory_Monsters_Ratter"', entities)
        light = self.exporter.light(1)
        self.assertAlmostEqual(sum(c * c for c in light["direction"]), 1.0, places=5)
        self.assertLess(light["direction"][1], 0.0)

    def test_render_passes_cover_every_scene_order(self) -> None:
        passes = (self.out / "generated" / "render_passes.lua").read_text()
        for location in (1, 6):
            nodes = self.module.load_sidecar(self.exporter.location_glb(location))["nodes"]
            for order in {int(n["order"]) for n in nodes.values() if int(n.get("order", 0)) > 0}:
                self.assertIn(f'"order_{order}"', passes)

    def test_lit_materials_take_the_light_from_the_render_script(self) -> None:
        # The light is not baked: every lit material carries the same neutral defaults and
        # the render script passes the scene's light in a constant buffer.
        from modexport.materials import NEUTRAL_LIGHT
        material = (self.out / "generated" / "materials" / "Monsters_Crawl_0.material").read_text()
        self.assertIn('name: "light_dir"', material)
        ambient = material[material.index('name: "ambient"'):]
        self.assertIn(f"x: {NEUTRAL_LIGHT['ambient'][0]:.6f}", ambient[:200])
        self.assertIn('name: "point_light1"', material)
        vp = (self.out / "generated" / "materials" / "Monsters_Crawl_0.vp").read_text()
        self.assertIn("point_light(point_light0, point_color0, p.xyz, n)", vp)

    def test_menu_is_lit_by_its_omni_lights_only(self) -> None:
        # `_floadmenu`: AmbientLight 0,0,0 and env.b3d's two B3DEXT_OMNILIGHT (white, default
        # range); no directional light.
        menus = (self.out / "generated" / "menus.lua").read_text()
        env = menus[menus.index('M["Menu/env"]'):]
        light = env[env.index("light = "):env.index("\n", env.index("light = "))]
        self.assertIn("color = {0.000000, 0.000000, 0.000000}, ambient = {0.000000, 0.000000, 0.000000}", light)
        self.assertEqual(light.count("range = 1000.000000, color = {1.000000, 1.000000, 1.000000}"), 2)
        # Omni01 (Blitz z 778.86 -> glTF -778.86).
        self.assertIn("{209.728302, 371.694672, -778.856873}", light)

    def test_translucent_brushes_are_ordered_like_blitz_entities(self) -> None:
        # Blitz sorts translucent entities by their origins; one Defold model has one origin,
        # so the exporter ranks the brushes (`<layer>_l<rank>` passes, farthest first).
        def tags_of(model_name: str, texture: str) -> list[str]:
            model = (self.out / "generated" / "models" / f"{model_name}.model").read_text()
            block = model[:model.index(texture)]
            material = block[block.rindex('material: "') + len('material: "'):]
            text = (self.out / material[:material.index('"')].lstrip("/")).read_text()
            return re.findall(r'tags: "([^"]+)"', text)

        # The menu's title stands in front of the road under it (they flickered).
        road, title = tags_of("Menu_env", "road.png")[0], tags_of("Menu_env", "NameMenu.png")[0]
        self.assertRegex(road, r"^world_l\d+$")
        passes = (self.out / "generated" / "render_passes.lua").read_text()
        self.assertLess(passes.index(f'"{road}", "blend"'), passes.index(f'"{title}", "blend"'))
        # The sign's planks and posts share a brush: its depth companion keeps the posts
        # behind the planks (they drew over them in the browser) and hides the captions the
        # settings flight moves behind the planks.
        solid = tags_of("Menu_buttons_solid", "buttonsfon.png")
        self.assertEqual(solid, ["hud_solid", "opaque"])
        self.assertIn('{tags = {"hud_solid", "opaque"}, depth_test = true, depth_write = true, color_write = false', passes)
        fp = (self.out / "generated" / "materials" / "Menu_buttons_0_solid.fp").read_text()
        self.assertIn("discard", fp)
        # A depth companion's glb holds only its brushes: Defold draws a primitive whose
        # material the model does not list with one it does, so the survival sheet's
        # captions wrote depth and cut black holes in the planks under them.
        doc, _ = read_glb(self.out / "assets" / "models" / "Menu_Send_solid.glb")
        self.assertEqual([m["name"] for m in doc["materials"]], ["01 - Default#0"])

    def test_hud_panel_nodes_are_ordered_like_blitz_entities(self) -> None:
        # The HUD panel (Env) is static: each translucent node gets its own `panel_l<rank>`
        # pass by the distance of its origin from the HUD camera. The time-speed track and
        # its reset mark lie over the wood (in the browser they drew under it).
        model = (self.out / "generated" / "models" / "Env.model").read_text()
        passes = (self.out / "generated" / "render_passes.lua").read_text()

        def pass_indices(texture: str) -> list[int]:
            out = []
            for block in model.split("materials {")[1:]:
                if texture in block:
                    material = re.search(r'material: "([^"]+)"', block).group(1)
                    tag = re.search(r'tags: "([^"]+)"', (self.out / material.lstrip("/")).read_text()).group(1)
                    self.assertRegex(tag, r"^panel_l\d+$")
                    out.append(passes.index(f'"{tag}", "blend"'))
            return out

        wood, track = pass_indices("wood.png"), pass_indices("timespeed.png")
        self.assertEqual((len(wood), len(track)), (2, 2))
        self.assertLess(max(wood), min(track))
        # The panel draws before the sheets over it (their depth companions and layers).
        self.assertLess(max(track), passes.index('"hud_solid", "opaque"'))

    def test_loading_sheet_takes_its_run_time_entity_orders(self) -> None:
        # `_floadmenu`: EntityOrder fon, -5 / loading, -6 -- drawn over the menu sheets, across
        # the whole canvas (the curtain covers Wide's sides too).
        model = (self.out / "generated" / "models" / "Menu_loading.model").read_text()
        tags = set()
        for material in re.findall(r'material: "([^"]+)"', model):
            text = (self.out / material.lstrip("/")).read_text()
            tags.add(re.search(r'tags: "(canvas[^"]*)"', text).group(1))
        self.assertEqual(tags, {"canvas_m5", "canvas_m6"})
        passes = (self.out / "generated" / "render_passes.lua").read_text()
        self.assertIn('{tags = {"canvas_m5", "blend"}, depth_test = false, depth_write = false, color_write = true, '
                      'blend = "blend", canvas = true}', passes)
        # Blitz's order: all of -5 before any of -6.
        self.assertLess(passes.index('"canvas_m5", "blend"'), passes.index('"hud_m6", "blend"'))

    def test_menu_sheets_are_posed_pickable_and_layered(self) -> None:
        menus = (self.out / "generated" / "menus.lua").read_text()
        buttons = menus[menus.index('M["Menu/buttons"]'):]
        for item in ("start", "hardcore", "settings", "credits", "exit", "highscores", "ok"):
            self.assertIn(f'["{item}"] = {{joint = ', buttons[:buttons.index('\n}')])
        models = (self.out / "generated" / "models.lua").read_text()
        sheet = models[models.index('M["Menu/SendTD"]'):]
        sheet = sheet[:sheet.index('\n}')]
        self.assertIn("bones = {count = 7", sheet)
        self.assertIn("joint_parents = {0, 1, 2, 1, 1, 5, 1}", sheet)  # captions are children of their planks
        # The captions over the planks draw in a later depth layer than the planks.
        model = (self.out / "generated" / "models" / "Menu_buttons.model").read_text()

        def layer_of(texture: str) -> int:
            block = model[:model.index(texture)]
            material = block[block.rindex('material: "') + len('material: "'):]
            material = material[:material.index('"')]
            text = (self.out / material.lstrip("/")).read_text()
            return int(re.search(r'tags: "hud_l(\d+)"', text).group(1))

        planks, captions = layer_of("buttonsfon.png"), layer_of("ButtonTexts.png")
        self.assertLess(planks, captions)
        passes = (self.out / "generated" / "render_passes.lua").read_text()
        self.assertLess(passes.index(f'"hud_l{planks}", "blend"'), passes.index(f'"hud_l{captions}", "blend"'))
        # The main menu camera follows cameraEnv's Camera01 over its 20 frames.
        camera = menus[menus.index('M["Menu/cameraEnv"]'):]
        self.assertIn("fov_h = 60.0", camera)
        self.assertEqual(camera[:camera.index('\n}')].count("{pos = {"), 21)

    def test_location_collections_carry_the_end_sheets(self) -> None:
        collection = (self.out / "generated" / "collections" / "location1.collection").read_text()
        for ident in ("congr", "gameover", "sel"):
            self.assertIn(f'id: "{ident}"', collection)
        self.assertIn("z: -10.0", collection)

    def test_location_decorations_and_background(self) -> None:
        l1 = (self.out / "generated" / "locations" / "l1.lua").read_text()
        self.assertIn('M.clock = {hours = "clock_hours", minutes = "clock_minutes", seconds = "clock_seconds"}', l1)
        collection = (self.out / "generated" / "collections" / "location1.collection").read_text()
        self.assertIn('prototype: "/generated/go/Location1_little_arrow.go"', collection)
        # The hands are no longer part of the scene model.
        doc, _ = self.glb("Location1")
        self.assertNotIn("little_arrow", {n.get("name") for n in doc["nodes"]})
        hand, _ = self.glb("Location1_little_arrow")
        self.assertNotIn("translation", hand["nodes"][0])  # at the game object's origin
        # `_floadlocation`: CameraClsColor (192, 212, 223) on location 6, black elsewhere.
        self.assertIn("M.clear_color = {0.000000, 0.000000, 0.000000}", l1)
        l6 = (self.out / "generated" / "locations" / "l6.lua").read_text()
        self.assertIn("M.clear_color = {0.752941, 0.831373, 0.874510}", l6)

    def test_river_frames_come_from_the_water_atlas(self) -> None:
        models = (self.out / "generated" / "models.lua").read_text()
        l1 = models[models.index('M["Location1"]'):]
        self.assertIn('{group = "river", columns = 8, rows = 8, frames = 63, step = 1.000000}', l1[:l1.index("\n}")])
        go = (self.out / "generated" / "go" / "Location1.go").read_text()
        self.assertIn('id: "river"', go)

    def test_sounds_are_grouped_for_the_volume_settings(self) -> None:
        sounds = (self.out / "generated" / "sounds.go").read_text()
        music = sounds[sounds.index('id: "music1"'):]
        self.assertIn('group: \\"music\\"', music[:300])
        click = sounds[sounds.index('id: "click"'):]
        self.assertIn('group: \\"sfx\\"', click[:300])

    def test_compressed_textures_are_block_aligned(self) -> None:
        # WebGL rejects BC textures whose sides are not multiples of 4 (Sve/Thorn skins are 1x1).
        from PIL import Image
        textures = [p for p in (self.out / "assets" / "textures").rglob("*") if p.suffix in (".png", ".jpg")]
        self.assertIn("Sve.jpg", {p.name for p in textures})
        for path in textures:
            with Image.open(path) as image:
                self.assertEqual([side % self.module.TEXTURE_BLOCK for side in image.size], [0, 0], path)
        with Image.open(self.out / "assets" / "textures" / "Monsters" / "Sve.jpg") as sve:
            self.assertEqual(sve.size, (4, 4))
            self.assertEqual(len(sve.getcolors()), 1)  # still one solid colour

    def test_long_sounds_ship_as_mono_vorbis_and_effects_as_pcm(self) -> None:
        import shutil
        import subprocess
        if not (shutil.which("ffmpeg") and shutil.which("oggenc")):
            self.skipTest("needs ffmpeg and oggenc")
        audio = self.out / "assets" / "audio"
        self.assertGreater(self.module.wav_seconds(GODOT_DIR / "assets" / "audio" / "congr.wav"), 9.0)
        self.assertLess(self.module.wav_seconds(GODOT_DIR / "assets" / "audio" / "rebutton.wav"), 0.1)
        sounds = (self.out / "generated" / "sounds.go").read_text()
        for name in ("congr.ogg", "tlen.ogg", "click.ogg", "rebutton.wav", "menu.ogg"):
            self.assertIn(f"/assets/audio/{name}", sounds)
            self.assertTrue((audio / name).exists(), name)
        self.assertNotIn("menu.wav", sounds)
        self.assertEqual(sounds.count('id: "menu"'), 1)
        channels = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "csv=p=0",
                                   str(audio / "music1.ogg")], capture_output=True, text=True, check=True).stdout
        self.assertEqual(channels.strip(), "1")  # the original music is mono

    def test_game_project_icons_are_exported(self) -> None:
        from PIL import Image
        project = (ROOT / "defold" / "game.project").read_text()
        icons = re.findall(r"^(app_icon\w*|bundle_resources) = /(\S+)$", project, re.M)
        self.assertEqual(len(icons), 14)  # android 6 + ios 5 + icns + ico + bundle resources
        for key, path in icons:
            self.assertTrue((self.out / path).exists(), f"{key} -> {path}")
            size = re.fullmatch(r"app_icon_(\d+)x\1", key)
            if size:
                self.assertEqual(Image.open(self.out / path).size, (int(size[1]),) * 2, key)
        bundle = self.out / dict(icons)["bundle_resources"]
        res = bundle / "android" / "res"
        xml = (res / "drawable-anydpi-v26" / "icon.xml").read_text()
        for layer in re.findall(r'android:drawable="@drawable/(\w+)"', xml):
            self.assertTrue((res / "drawable-xxxhdpi" / f"{layer}.png").exists(), layer)
        self.assertTrue((bundle / "web" / "favicon.ico").exists())
        self.assertEqual(Image.open(self.out / "generated" / "icons" / "ios_180.png").mode, "RGB")  # opaque

if __name__ == "__main__":
    unittest.main()
