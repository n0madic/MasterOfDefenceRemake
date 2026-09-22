"""One Godot-pipeline glb (+ `.b3d.json` sidecar) -> Defold model resources.

Defold's model component plays only skeletal (and morph target) animations, while the
B3D scenes animate plain nodes (tower guns, effect spheres, path markers). Every model
with node animation is therefore rewritten as a skinned mesh: each kept node becomes a
joint, the vertices are baked into rest-pose world space and weighted 1.0 to their node's
joint, and the node animation channels drive the joints. Static models keep their rigid
node hierarchy (Defold flattens it into per-mesh world transforms).

Per-component state in Defold (`go.set` of a constant or texture) applies to every mesh of
the component, so the primitives whose materials need runtime control of their own are
split into separate glbs / model components ("groups"): `dno` (the tower base that gets
the location's ground texture and tint), `anim` (brushes with a B3DEXT_ANIMMAP scroll).
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

from b3d2gltf import mat_column_major, mat_inverse_affine, mat_mul, trs_matrix
from gltfwriter import (
    COMPONENT_UBYTE,
    COMPONENT_UINT,
    COMPONENT_USHORT,
    TARGET_ARRAY_BUFFER,
    TARGET_ELEMENT_ARRAY_BUFFER,
    GltfBuilder,
    read_accessor,
    read_glb,
)

from .materials import MaterialVariant, gltf_color_to_blitz

HELPER_PREFIXES = ("B3DEXT_", "Camera0")
HELPER_NODES = {"CamPath"}
GROUP_MAIN, GROUP_ANIM = "main", "anim"
# Nodes that become components of their own so the runtime can retexture / hide them:
# the tower base (`dno`), the HUD panel's skills sheet and window.
GROUP_NODES = {"dno", "updates", "window"}
IDENTITY = [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]
Mat4 = list[list[float]]


def node_matrix(node: dict) -> Mat4:
    t = tuple(node.get("translation", [0.0, 0.0, 0.0]))
    r = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = tuple(node.get("scale", [1.0, 1.0, 1.0]))
    return trs_matrix(t, (r[3], r[0], r[1], r[2]), s)


def transform_point(m: Mat4, p) -> tuple[float, float, float]:
    return tuple(m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3] for i in range(3))


def normal_matrix(m: Mat4) -> Mat4:
    """Inverse transpose of the upper 3x3 (as a 4x4 with no translation)."""
    inv = mat_inverse_affine([row[:3] + [0.0] for row in m[:3]] + [[0.0, 0.0, 0.0, 1.0]])
    return [[inv[j][i] for j in range(3)] + [0.0] for i in range(3)] + [[0.0, 0.0, 0.0, 1.0]]


def transform_normal(nm: Mat4, n) -> tuple[float, float, float]:
    v = (nm[0][0] * n[0] + nm[0][1] * n[1] + nm[0][2] * n[2],
         nm[1][0] * n[0] + nm[1][1] * n[1] + nm[1][2] * n[2],
         nm[2][0] * n[0] + nm[2][1] * n[1] + nm[2][2] * n[2])
    length = (v[0] ** 2 + v[1] ** 2 + v[2] ** 2) ** 0.5 or 1.0
    return (v[0] / length, v[1] / length, v[2] / length)


def determinant3(m: Mat4) -> float:
    a = m
    return (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
            - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))


def sample_track(times: list[float], values: list, t: float):
    """Linear interpolation of a glTF sampler at time `t` (clamped to the key range)."""
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    lo, hi = 0, len(times) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if times[mid] <= t:
            lo = mid
        else:
            hi = mid
    f = (t - times[lo]) / (times[hi] - times[lo]) if times[hi] > times[lo] else 0.0
    a, b = values[lo], values[hi]
    return tuple(a[i] + (b[i] - a[i]) * f for i in range(len(a)))


def _sample_vec(track: tuple[list[float], list], frame: float):
    return sample_track(track[0], track[1], frame)


def _sample_quat(track: tuple[list[float], list], frame: float) -> tuple[float, float, float, float]:
    """glTF (x, y, z, w) quaternion sampled with shortest-arc nlerp, matching a Blitz
    linear key blend closely enough for the 0.1-frame animation steps."""
    times, values = track
    if frame <= times[0]:
        return tuple(values[0])
    if frame >= times[-1]:
        return tuple(values[-1])
    lo, hi = 0, len(times) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        lo, hi = (mid, hi) if times[mid] <= frame else (lo, mid)
    f = (frame - times[lo]) / (times[hi] - times[lo]) if times[hi] > times[lo] else 0.0
    a, b = values[lo], list(values[hi])
    if sum(a[i] * b[i] for i in range(4)) < 0.0:
        b = [-x for x in b]
    q = [a[i] + (b[i] - a[i]) * f for i in range(4)]
    n = math.sqrt(sum(x * x for x in q)) or 1.0
    return tuple(x / n for x in q)


def _basis_shear_degrees(m: Mat4) -> float:
    """Largest deviation from 90 degrees between the world basis axes (columns): a measure
    of the shear an SRT transform cannot represent."""
    cols = [[m[r][c] for r in range(3)] for c in range(3)]

    def angle(u, v):
        du = math.sqrt(sum(x * x for x in u))
        dv = math.sqrt(sum(x * x for x in v))
        if du < 1e-9 or dv < 1e-9:
            return 90.0
        cos = max(-1.0, min(1.0, sum(u[i] * v[i] for i in range(3)) / (du * dv)))
        return math.degrees(math.acos(cos))

    return max(abs(90.0 - angle(cols[0], cols[1])),
               abs(90.0 - angle(cols[0], cols[2])),
               abs(90.0 - angle(cols[1], cols[2])))


class ModelExporter:
    """`key` names the outputs (e.g. `Towers/Military` -> `Towers_Military`)."""

    def __init__(self, key: str, glb_path: Path, sidecar: dict | None, out_dir: Path, textures_root: Path, light: dict,
                 *, hud: bool = False, lit_default: bool = False):
        self.key = key
        self.slug = key.replace("/", "_")
        self.glb_path = glb_path
        self.doc, self.blob = read_glb(glb_path)
        self.sidecar = sidecar or {}
        self.node_info: dict = self.sidecar.get("nodes", {})
        self.material_info: dict = self.sidecar.get("materials", {})
        self.out_dir = out_dir
        self.textures_root = textures_root.resolve()
        self.light = light
        self.hud = hud
        self.lit_default = lit_default
        self.variants: dict[tuple, MaterialVariant] = {}
        self.textures: dict[str, str] = {}
        self.kept: list[int] = []
        self.parent: dict[int, int | None] = {}
        self.world: dict[int, Mat4] = {}
        self.local: dict[int, Mat4] = {}
        self.animmap_materials: dict[str, int] = {}  # sidecar material name -> ANIMMAP tag node index
        self.channels: dict[int, dict[str, tuple[list[float], list]]] = {}  # node -> path -> (times, values)
        self.frames = 0.0
        self.groups: dict[str, list[tuple[int, dict, MaterialVariant]]] = {}  # group -> [(node, primitive, variant)]
        self._sheared: bool | None = None  # cached: the check samples several animation frames
        self._collect()

    # --- scene analysis ------------------------------------------------------------------

    def _is_helper(self, node: dict) -> bool:
        name = node.get("name", "")
        return name.startswith(HELPER_PREFIXES) or name in HELPER_NODES

    def _collect(self) -> None:
        nodes = self.doc["nodes"]
        roots = self.doc["scenes"][self.doc.get("scene", 0)]["nodes"]

        def walk(index: int, parent: int | None, parent_world: Mat4) -> None:
            node = nodes[index]
            local = node_matrix(node)
            world = mat_mul(parent_world, local)
            self.local[index] = local
            self.world[index] = world
            if self._is_helper(node):
                return
            self.kept.append(index)
            self.parent[index] = parent
            for child in node.get("children", []):
                walk(child, index, world)

        for r in roots:
            walk(r, None, IDENTITY)
        # Animation channels of every node (helpers included: UVPOS keys feed the ANIMMAPs).
        for anim in self.doc.get("animations", []):
            for ch in anim["channels"]:
                target = ch["target"]
                sampler = anim["samplers"][ch["sampler"]]
                times = read_accessor(self.doc, self.blob, sampler["input"])
                values = read_accessor(self.doc, self.blob, sampler["output"])
                self.channels.setdefault(target["node"], {})[target["path"]] = (times, values)
                if times:
                    self.frames = max(self.frames, float(times[-1]))
        for name, info in self.node_info.items():
            if "animmap_material" in info:
                idx = next((i for i, n in enumerate(nodes) if n.get("name") == name), None)
                if idx is not None:
                    self.animmap_materials[str(info["animmap_material"])] = idx
        for index in self.kept:
            node = nodes[index]
            if "mesh" not in node:
                continue
            order = int(self.node_info.get(node["name"], {}).get("order", 0))
            for prim in self.doc["meshes"][node["mesh"]]["primitives"]:
                gm = self.doc["materials"][prim["material"]]
                if node["name"] in GROUP_NODES:
                    group = node["name"]
                elif gm["name"] in self.animmap_materials:
                    # One component per scrolling brush: the UV offset is per component.
                    group = GROUP_ANIM + str(list(self.animmap_materials).index(gm["name"]))
                else:
                    group = GROUP_MAIN
                variant = self._variant(prim["material"], order, group, len(prim.get("targets", [])),
                                        billboard=self._is_billboard(index))
                if not variant.invisible:
                    self.groups.setdefault(group, []).append((index, prim, variant))

    TRS_PATHS = ("translation", "rotation", "scale")
    SHEAR_TOLERANCE = 1.0  # degrees; above this a joint's world basis is not orthogonal

    @property
    def skinned(self) -> bool:
        """Node (TRS) animation on a kept node; MD2 morph weights do not count."""
        return any(path in self.TRS_PATHS for index in self.kept for path in self.channels.get(index, {}))

    def _sample_local(self, index: int, frame: float) -> Mat4:
        """The node's local matrix at `frame`, TRS channels sampled (Blitz linear keys)."""
        ch = self.channels.get(index, {})
        node = self.doc["nodes"][index]
        t = _sample_vec(ch["translation"], frame) if "translation" in ch else node.get("translation", [0.0, 0.0, 0.0])
        r = _sample_quat(ch["rotation"], frame) if "rotation" in ch else node.get("rotation", [0.0, 0.0, 0.0, 1.0])
        s = _sample_vec(ch["scale"], frame) if "scale" in ch else node.get("scale", [1.0, 1.0, 1.0])
        return trs_matrix(tuple(t), (r[3], r[0], r[1], r[2]), tuple(s))

    def _world_anim(self, frame: float, cache: dict[int, Mat4]) -> dict[int, Mat4]:
        """World matrix of every kept joint at `frame`, composed with full 4x4 matrices."""
        def world(index: int) -> Mat4:
            if index not in cache:
                local = self._sample_local(index, frame)
                parent = self.parent[index]
                cache[index] = local if parent is None else mat_mul(world(parent), local)
            return cache[index]
        for index in self.kept:
            world(index)
        return cache

    # A joint flattened on one axis (a small scale next to a normal one) has an
    # inverse-bind matrix that is near-singular along that axis, which Defold's skinning
    # turns to garbage; e.g. the death soul's frost planes are scaled to 0.001 on Y while
    # 1.0 on X/Z. A *uniform* small scale (the tower-shot effect spheres at 0.0005) inverts
    # cleanly and skins fine, so the trigger is the anisotropy, not the size. Godot never
    # inverts the scale (it transforms nodes by their world matrix); the bone-matrix path
    # mirrors that.
    DEGENERATE_SCALE = 0.01
    DEGENERATE_RATIO = 10.0

    @property
    def sheared(self) -> bool:
        """True when any joint's animated world basis carries shear (non-orthogonal axes),
        which Defold's SRT-bone skinning cannot represent (only Nature on location 1)."""
        if self._sheared is None:
            self._sheared = False
            if self.skinned:
                last = int(self.frames)
                for frame in {0, last, last // 2}:
                    world = self._world_anim(float(frame), {})
                    if any(_basis_shear_degrees(world[i]) > self.SHEAR_TOLERANCE for i in self.kept):
                        self._sheared = True
                        break
        return self._sheared

    @property
    def _degenerate_scale(self) -> bool:
        """True when any kept joint's rest scale is flattened on one axis -- a small
        component beside a much larger one -- so its inverse-bind matrix is near-singular
        along that axis (the death soul's flat frost planes). A uniform small scale is not
        degenerate: it inverts cleanly and Defold skins it fine."""
        if not self.skinned:
            return False
        for i in self.kept:
            s = [abs(v) for v in self.doc["nodes"][i].get("scale", [1.0, 1.0, 1.0])]
            if min(s) < self.DEGENERATE_SCALE and max(s) > min(s) * self.DEGENERATE_RATIO:
                return True
        return False

    @property
    def bone_posed(self) -> bool:
        """True when the model must be posed by baked full bone matrices instead of
        Defold's SRT-bone skinning: its world basis shears, or a joint's scale is
        near-degenerate (a near-singular inverse-bind). The runtime fills the
        `bone_matrices[]` array from the baked poses; Defold's own rig is not played.
        The mesh is kept in *local* space and the pose is the full world matrix (no
        inverse-bind), so the near-singular inverse is never formed -- as in Godot."""
        return self.sheared or self._degenerate_scale or self._animated_billboard

    @property
    def _animated_billboard(self) -> bool:
        """A camera-facing node in an animated model (the Magic tower's crown ring): the
        billboard shader needs the joint's own origin and scale, which only the bone-matrix
        path (joint-local vertices, full world matrix) provides."""
        return self.skinned and any("mesh" in self.doc["nodes"][i] and self._is_billboard(i) for i in self.kept)

    def _is_billboard(self, index: int) -> bool:
        """A Blitz `B3D_BB_1_` node (sidecar `billboard`): it always faces the camera."""
        return bool(self.node_info.get(self.doc["nodes"][index].get("name", ""), {}).get("billboard"))

    def _variant(self, material_index: int, order: int, group: str, targets: int, *,
                 billboard: bool = False) -> MaterialVariant:
        key = (material_index, order, group, billboard)
        if key not in self.variants:
            gm = self.doc["materials"][material_index]
            info = self.material_info.get(gm["name"], {})
            self.variants[key] = MaterialVariant(
                f"{self.slug}_{len(self.variants)}", gm, info, order=order, hud=self.hud,
                skinned=self.skinned, morph_targets=targets, animmap=group.startswith(GROUP_ANIM), lit_default=self.lit_default,
                bone_count=len(self.kept) if self.bone_posed else 0, ground_base=group == "dno",
                billboard=billboard)
        return self.variants[key]

    def texture_resource(self, uri: str) -> str:
        if uri not in self.textures:
            src = (self.glb_path.parent / uri).resolve()
            rel = src.relative_to(self.textures_root)
            self.textures[uri] = "/assets/textures/" + rel.as_posix()
        return self.textures[uri]

    def layer_uri(self, variant: MaterialVariant, layer: dict, material_index: int) -> str | None:
        if layer.get("from_gltf"):
            tex = self.doc["materials"][material_index]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            image = self.doc["textures"][tex]["source"]
            return self.doc["images"][image].get("uri")
        return layer.get("uri")

    # --- glb output ----------------------------------------------------------------------

    def _joint_order(self) -> list[int]:
        return list(self.kept)  # parents precede children (depth-first walk)

    def _add_primitive(self, b: GltfBuilder, index: int, prim: dict, variant: MaterialVariant, material_id: int,
                       joint_of: dict[int, int] | None) -> dict:
        attrs = prim["attributes"]
        positions = read_accessor(self.doc, self.blob, attrs["POSITION"])
        normals = read_accessor(self.doc, self.blob, attrs["NORMAL"])
        indices = list(read_accessor(self.doc, self.blob, prim["indices"]))
        bake = joint_of is not None
        if bake and not self.bone_posed:
            # Defold's own SRT skinning: the vertices are baked into rest-pose world space
            # and weighted 1.0 to their joint (Defold flattens the hierarchy).
            w = self.world[index]
            nm = normal_matrix(w)
            positions = [transform_point(w, p) for p in positions]
            normals = [transform_normal(nm, n) for n in normals]
            if determinant3(w) < 0:
                # The converter stored mirrored meshes reversed for Godot's cull flip;
                # baked into world space the triangles need their file order back.
                indices = [i for tri in zip(indices[0::3], indices[1::3], indices[2::3]) for i in (tri[0], tri[2], tri[1])]
        # A bone-posed model keeps its vertices in each joint's *local* space; the runtime
        # multiplies them by the joint's full world matrix (`bone_matrices`, no inverse-bind),
        # so a near-singular inverse of a degenerate joint scale is never formed.
        if variant.double_sided:
            indices = indices + [i for tri in zip(indices[0::3], indices[1::3], indices[2::3]) for i in (tri[0], tri[2], tri[1])]
        out_attrs = {
            "POSITION": b.add_accessor(positions, "VEC3", target=TARGET_ARRAY_BUFFER, minmax=True),
            "NORMAL": b.add_accessor(normals, "VEC3", target=TARGET_ARRAY_BUFFER),
            "TEXCOORD_0": b.add_accessor(read_accessor(self.doc, self.blob, attrs["TEXCOORD_0"]), "VEC2", target=TARGET_ARRAY_BUFFER),
        }
        if len(variant.layers) > 1:
            uv1 = read_accessor(self.doc, self.blob, attrs["TEXCOORD_1"]) if "TEXCOORD_1" in attrs else [(0.0, 0.0)] * len(positions)
            out_attrs["TEXCOORD_1"] = b.add_accessor(uv1, "VEC2", target=TARGET_ARRAY_BUFFER)
        if variant.vertex_colors:
            if "COLOR_0" in attrs:
                colors = [tuple(gltf_color_to_blitz(list(c), additive=variant.blend == 3)) for c in read_accessor(self.doc, self.blob, attrs["COLOR_0"])]
            else:
                colors = [(1.0, 1.0, 1.0, 1.0)] * len(positions)  # Blitz's default vertex colour
            out_attrs["COLOR_0"] = b.add_accessor(colors, "VEC4", target=TARGET_ARRAY_BUFFER)
        if bake:
            j = joint_of[index]
            out_attrs["JOINTS_0"] = b.add_accessor([(j, 0, 0, 0)] * len(positions), "VEC4", COMPONENT_UBYTE, target=TARGET_ARRAY_BUFFER)
            out_attrs["WEIGHTS_0"] = b.add_accessor([(1.0, 0.0, 0.0, 0.0)] * len(positions), "VEC4", target=TARGET_ARRAY_BUFFER)
        component = COMPONENT_USHORT if len(positions) <= 0xFFFF else COMPONENT_UINT
        out = {
            "attributes": out_attrs,
            "indices": b.add_accessor(indices, "SCALAR", component, target=TARGET_ELEMENT_ARRAY_BUFFER),
            "material": material_id,
            "mode": 4,
        }
        targets = prim.get("targets", [])
        if targets:
            out["targets"] = [{
                "POSITION": b.add_accessor(read_accessor(self.doc, self.blob, t["POSITION"]), "VEC3", target=TARGET_ARRAY_BUFFER, minmax=True),
                "NORMAL": b.add_accessor(read_accessor(self.doc, self.blob, t["NORMAL"]), "VEC3", target=TARGET_ARRAY_BUFFER),
            } for t in targets]
        return out

    def _gltf_material(self, b: GltfBuilder, variant: MaterialVariant, ids: dict[str, int]) -> int:
        if variant.base_name not in ids:
            ids[variant.base_name] = b.add_material({
                "name": variant.name,
                "pbrMetallicRoughness": {"baseColorFactor": variant.color, "metallicFactor": 0.0, "roughnessFactor": 1.0},
                "doubleSided": variant.double_sided,
                "alphaMode": "OPAQUE" if variant.pass_class == "opaque" else "BLEND",
            })
        return ids[variant.base_name]

    def _write_rigid_glb(self, prims: list, path: Path) -> None:
        b = GltfBuilder(generator="MasterOfDefence defold export")
        ids: dict[str, int] = {}
        by_node: dict[int, list] = {}
        for index, prim, variant in prims:
            by_node.setdefault(index, []).append((prim, variant))
        new_index: dict[int, int] = {}

        def emit(index: int) -> int | None:
            node = self.doc["nodes"][index]
            children = [c for c in (emit(ci) for ci in node.get("children", []) if ci in self.parent) if c is not None]
            out: dict = {"name": node.get("name", f"node{index}")}
            for key in ("translation", "rotation", "scale"):
                if key in node:
                    out[key] = node[key]
            if index in by_node:
                out["mesh"] = b.add_mesh({"name": node.get("name", "mesh"), "primitives": [
                    self._add_primitive(b, index, prim, variant, self._gltf_material(b, variant, ids), None)
                    for prim, variant in by_node[index]]})
            if children:
                out["children"] = children
            if "mesh" not in out and not children:
                return None
            new_index[index] = b.add_node(out)
            return new_index[index]

        roots = [r for r in (emit(i) for i in self.kept if self.parent[i] is None) if r is not None]
        b.write_glb(path, roots)

    def _write_skinned_glb(self, prims: list, path: Path) -> None:
        b = GltfBuilder(generator="MasterOfDefence defold export")
        ids: dict[str, int] = {}
        joints = self._joint_order()
        joint_of = {index: j for j, index in enumerate(joints)}
        new_index: dict[int, int] = {}
        # Joint nodes first, in hierarchy order, with their rest TRS.
        for index in joints:
            node = self.doc["nodes"][index]
            out: dict = {"name": node.get("name", f"node{index}")}
            for key in ("translation", "rotation", "scale"):
                if key in node:
                    out[key] = node[key]
            new_index[index] = b.add_node(out)
        for index in joints:
            children = [new_index[c] for c in self.doc["nodes"][index].get("children", []) if c in joint_of]
            if children:
                b.nodes[new_index[index]]["children"] = children
        primitives = [self._add_primitive(b, index, prim, variant, self._gltf_material(b, variant, ids), joint_of)
                      for index, prim, variant in prims]
        mesh = b.add_mesh({"name": self.slug, "primitives": primitives})
        # A bone-posed model keeps local-space vertices and poses them through the
        # `bone_matrices` constant, so Defold's own rig is off and its inverse-bind matrices
        # are unused -- emit identity ones to avoid importing the near-singular inverse of a
        # degenerate joint scale (which would be near-singular, e.g. the frost planes).
        if self.bone_posed:
            ibm = [mat_column_major(IDENTITY) for _ in joints]
        else:
            ibm = [mat_column_major(mat_inverse_affine(self.world[index])) for index in joints]
        skin = b.add_skin({
            "name": self.slug,
            "joints": [new_index[i] for i in joints],
            "skeleton": new_index[joints[0]],
            "inverseBindMatrices": b.add_accessor(ibm, "MAT4"),
        })
        mesh_node = b.add_node({"name": "Mesh", "mesh": mesh, "skin": skin})
        # One animation fully specifying every joint's pose. Defold's runtime leaves a
        # joint's un-keyed TRS channel at the *animation's* value rather than the bind
        # pose, so a joint whose bind rotation is not identity but which is only keyed in
        # translation/scale (the death soul's frost shards, or its un-keyed body) ended up
        # flipped. Emit all three channels for each joint, filling any the source omits
        # with a constant two-key track at the joint's bind value. (Helper UVPOS nodes are
        # baked into the model metadata instead.)
        channels, samplers = [], []
        for index in joints:
            for path_name, (times, values) in self.channels.get(index, {}).items():
                if path_name not in self.TRS_PATHS:
                    continue
                element = "VEC4" if path_name == "rotation" else "VEC3"
                samplers.append({
                    "input": b.add_accessor(list(times), "SCALAR", minmax=True),
                    "output": b.add_accessor(list(values), element),
                    "interpolation": "LINEAR",
                })
                channels.append({"sampler": len(samplers) - 1, "target": {"node": new_index[index], "path": path_name}})
        if not channels:
            # A skeleton without keys: give the root a two-key identity track so the
            # animation exists and `cursor` stays valid.
            root = self.doc["nodes"][joints[0]]
            t = root.get("translation", [0.0, 0.0, 0.0])
            samplers.append({"input": b.add_accessor([0.0, max(self.frames, 1.0)], "SCALAR", minmax=True),
                             "output": b.add_accessor([tuple(t), tuple(t)], "VEC3"), "interpolation": "LINEAR"})
            channels.append({"sampler": 0, "target": {"node": new_index[joints[0]], "path": "translation"}})
        b.add_animation({"name": "b3d", "channels": channels, "samplers": samplers})
        b.write_glb(path, [new_index[joints[0]], mesh_node])

    # --- ANIMMAP keys ----------------------------------------------------------------------

    def animmap_keys(self) -> list[dict]:
        """Per ANIMMAP material: the UV offset per integer frame, Blitz `PositionTexture(-x, -y)`."""
        out = []
        nodes = self.doc["nodes"]
        for n, (material_name, tag_index) in enumerate(self.animmap_materials.items()):
            uvpos = next((c for c in nodes[tag_index].get("children", []) if nodes[c].get("name", "").startswith("B3DEXT_UVPOS")), None)
            if uvpos is None:
                continue
            track = self.channels.get(uvpos, {}).get("translation")
            frames = int(self.frames) if track else 0
            keys = []
            for f in range(frames + 1):
                p = sample_track(track[0], track[1], float(f)) if track else nodes[uvpos].get("translation", [0.0, 0.0, 0.0])
                keys.append([round(-p[0], 6), round(-p[1], 6)])
            out.append({"group": GROUP_ANIM + str(n), "material": material_name, "keys": keys})
        return out

    # --- Defold resources ----------------------------------------------------------------

    def run(self) -> dict:
        models_dir = self.out_dir / "assets" / "models"
        gen = self.out_dir / "generated"
        mat_dir = gen / "materials"
        model_dir = gen / "models"
        go_dir = gen / "go"
        for d in (models_dir, mat_dir, model_dir, go_dir):
            d.mkdir(parents=True, exist_ok=True)
        skinned = self.skinned
        # A bone-posed model keeps the skinned mesh's per-vertex joint index but is posed by
        # the runtime through the `bone_matrices` constant, so Defold's own rig is not played.
        rigged = skinned or self.bone_posed
        components = []
        for group, prims in self.groups.items():
            suffix = "" if group == GROUP_MAIN else f"_{group}"
            glb = models_dir / f"{self.slug}{suffix}.glb"
            if rigged:
                self._write_skinned_glb(prims, glb)
            else:
                self._write_rigid_glb(prims, glb)
            variants = []
            for _, _, v in prims:
                if v not in variants:
                    variants.append(v)
            mat_index = {v: next(k[0] for k, vv in self.variants.items() if vv is v) for v in variants}
            self._write_model(mat_dir, model_dir, self.slug + suffix, suffix, variants, mat_index, rigged)
            components.append((group, f"/generated/models/{self.slug}{suffix}.model"))
            # The base decal also draws as an alpha-scissor opaque brush that writes depth
            # (occluding the tower's underground root); it reuses the base's glb.
            if group == "dno":
                solids = [v.solid_variant() for v in variants]
                solid_index = {s: mat_index[v] for s, v in zip(solids, variants)}
                self._write_model(mat_dir, model_dir, self.slug + suffix + "_solid", suffix, solids, solid_index, rigged)
                components.append(("dno_solid", f"/generated/models/{self.slug}{suffix}_solid.model"))
        go = []
        for group, path in components:
            go += ["components {", f'  id: "{group}"', f'  component: "{path}"', "}"]
        (go_dir / f"{self.slug}.go").write_text("\n".join(go) + "\n")
        bones = self._write_bone_poses(gen) if self.bone_posed else None
        return {
            "go": f"/generated/go/{self.slug}.go",
            "frames": self.frames,
            # A bone-posed model is not "skinned" to the runtime: it is posed by `bones`, not
            # by a Defold animation cursor.
            "skinned": skinned and not self.bone_posed,
            "bones": bones,
            "groups": [g for g, _ in components],
            "animmaps": [m for m in self.animmap_keys() if any(g == m["group"] for g, _ in components)],
            "morph_targets": max((v.morph_targets for v in self.variants.values()), default=0),
            "textures": dict(self.textures),
        }

    def _write_model(self, mat_dir: Path, model_dir: Path, model_name: str, glb_suffix: str,
                     variants: list, mat_index: dict, rigged: bool) -> None:
        """Write a `.model` (and its variants' materials) referencing the glb `slug+glb_suffix`."""
        model = [f'mesh: "/assets/models/{self.slug}{glb_suffix}.glb"', 'name: "unnamed"']
        for v in variants:
            (mat_dir / f"{v.base_name}.vp").write_text(v.vertex_program())
            (mat_dir / f"{v.base_name}.fp").write_text(v.fragment_program())
            (mat_dir / f"{v.base_name}.material").write_text(v.material_file(self.light, "/generated/materials"))
            model += ["materials {", f'  name: "{v.bind_name}"', f'  material: "/generated/materials/{v.base_name}.material"']
            for i, layer in enumerate(v.layers):
                uri = self.layer_uri(v, layer, mat_index[v])
                if uri:
                    model += ["  textures {", f'    sampler: "{v.sampler_name(i)}"', f'    texture: "{self.texture_resource(uri)}"', "  }"]
            model.append("}")
        if rigged:
            # The sheared model keeps the skeleton/animation (so the vertex format has the
            # joint index) but no `default_animation`, so Defold leaves the rig at the bind
            # pose and the `bone_matrices` constant alone drives the mesh.
            model += [f'skeleton: "/assets/models/{self.slug}{glb_suffix}.glb"', f'animations: "/assets/models/{self.slug}{glb_suffix}.glb"']
            if not self.bone_posed:
                model.append('default_animation: "b3d"')
        model.append("create_go_bones: false")
        (model_dir / f"{model_name}.model").write_text("\n".join(model) + "\n")

    def _write_bone_poses(self, gen: Path) -> dict:
        """Bake the full world matrix of every joint at each integer frame into a float32
        blob the runtime uploads to `bone_matrices`. The mesh vertices are in joint-local
        space (see `_add_primitive`), so the pose is `world_anim(joint)` with no
        inverse-bind -- exactly how Godot transforms the nodes, and the only way to avoid
        forming the near-singular inverse of a degenerate joint scale. A full-matrix
        composition also preserves shear. Layout: frame-major, joint order `self.kept`,
        16 floats row-major per matrix."""
        joints = self._joint_order()
        frame_count = int(self.frames) + 1
        data = bytearray()
        for f in range(frame_count):
            world = self._world_anim(float(f), {})
            for joint in joints:
                for row in world[joint]:
                    data += struct.pack("<4f", *row)
        bones_dir = gen / "bones"
        bones_dir.mkdir(parents=True, exist_ok=True)
        (bones_dir / f"{self.slug}.bin").write_bytes(data)
        return {"count": len(joints), "frames": frame_count, "resource": f"/generated/bones/{self.slug}.bin"}


def load_sidecar(glb_path: Path) -> dict | None:
    path = glb_path.with_suffix(".b3d.json")
    if path.exists():
        return json.loads(path.read_text())
    return None
