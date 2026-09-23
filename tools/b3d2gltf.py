#!/usr/bin/env python3
"""Convert a Blitz3D .b3d file into a glTF binary (.glb) plus a JSON sidecar.

    python3 tools/b3d2gltf.py IN.b3d OUT.glb --data-dir Data/ --textures-dir build/import/assets/textures

Conventions (see docs/12 and the remake plan):
- coordinates are mirrored with tools/blitzconv.py (C1), triangle winding reordered;
- node names are the B3D Extensions "clean" names (`B3D_ORDR_30_grass` -> `grass`); the
  entity order, billboard flag and B3DEXT_* tags go to the sidecar `OUT.b3d.json`;
- every node with KEYS is animated in one animation called `b3d`, 1 frame = 1.0 s (C2);
- each brush becomes a glTF material (alpha mode from the texture/brush flags, double sided
  for fx&16, KHR_materials_unlit for fx&1); brush blend ADD/MULTIPLY, vertex colours,
  lightmap layers (second UV set) and other Blitz-only state go to the sidecar, from where
  `addons/b3d_import/b3d_post_import.gd` applies them to StandardMaterial3D;
- texture position/scale/rotation (TexturePosition/ScaleTexture/RotateTexture) are baked
  into the UVs, per primitive, so no texture transform extension is needed;
- textures are copied to `<textures-dir>/<path relative to Data>` and referenced by a
  relative URI (or embedded with --embed). Blitz derives alpha for textures loaded with
  the ALPHA flag but no alpha channel (alpha = mean RGB, colour whitened unless the RGB
  flag is set) and for MASKED textures (black = transparent) — gxruntime/ddutil.cpp
  `buildAlpha`/`buildMask`; such textures are written as derived PNGs
  (`<stem>__alpha.png`, `<stem>__alphaw.png`, `<stem>__mask.png`);
- BONE chunks become a glTF skin on the mesh node (JOINTS_0/WEIGHTS_0, inverse bind
  matrices from the rest pose of the bone nodes, as Blitz `MeshModel::createBones`
  snapshots `-bone->getWorldTform()` at load time); `--no-skin` keeps the bones rigid.
"""
from __future__ import annotations

import argparse
import json
import logging
import math
import shutil
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

from PIL import Image

import b3dlib
from b3dlib import TEX_FLAG_CLAMP_U, TEX_FLAG_CLAMP_V, B3DFile, Brush, Mesh, Node, Texture
from blitzconv import blitz_color_to_gltf, blitz_quat_to_godot, blitz_to_godot, triangle_indices
from gltfwriter import COMPONENT_UBYTE, COMPONENT_UINT, TARGET_ARRAY_BUFFER, TARGET_ELEMENT_ARRAY_BUFFER, GltfBuilder
from mat4 import Mat4, mat_column_major, mat_inverse_affine, mat_mul, trs_matrix
from textures import canonical_images

LOG = logging.getLogger("b3d2gltf")

ANIMATION_NAME = "b3d"
MAX_JOINTS_PER_VERTEX = 4
TEX_FLAG_RGB = 0x1
TEX_FLAG_SPHERE = 0x40
TEX_BLEND_MULTIPLY2 = 5
# Textures the original never ships / replaces at run time.
KNOWN_MISSING = {"dno.png": "Towers/dno1.png", "highscores.png": None}
IMAGE_MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".bmp": "image/bmp"}


@dataclass
class TextureIndex:
    """Case-insensitive lookup of texture files under Data/."""
    data_dir: Path
    by_relpath: dict[str, Path] = field(default_factory=dict)
    by_basename: dict[str, list[Path]] = field(default_factory=dict)
    canonical: dict[Path, Path] = field(default_factory=dict)

    def __post_init__(self) -> None:
        for p in self.data_dir.rglob("*"):
            if p.is_file() and p.suffix.lower() in IMAGE_MIME:
                rel = p.relative_to(self.data_dir).as_posix().lower()
                self.by_relpath[rel] = p
                self.by_basename.setdefault(p.name.lower(), []).append(p)
        self.canonical = canonical_images(self.data_dir)

    def resolve(self, name: str, own_dir: Path) -> Path | None:
        """The file Blitz would load, replaced by its shipped copy when it is a duplicate."""
        found = self._resolve(name, own_dir)
        return self.canonical.get(found, found) if found is not None else None

    def _resolve(self, name: str, own_dir: Path) -> Path | None:
        """Blitz looks in the model's directory first; we then search the whole Data/."""
        clean = PurePosixPath(name.replace("\\", "/"))
        base = clean.name.lower()
        candidate = own_dir / clean.name
        for p in self.by_basename.get(base, []):
            if p.parent.resolve() == candidate.parent.resolve():
                return p
        rel = (own_dir / clean).resolve()
        try:
            key = rel.relative_to(self.data_dir.resolve()).as_posix().lower()
            if key in self.by_relpath:
                return self.by_relpath[key]
        except ValueError:
            pass
        hits = self.by_basename.get(base, [])
        if hits:
            return sorted(hits)[0]
        substitute = KNOWN_MISSING.get(base, "missing")
        if substitute == "missing":
            LOG.warning("texture %r not found (referenced from %s)", name, own_dir)
            return None
        if substitute is None:
            return None
        return self.by_relpath.get(substitute.lower())


def derive_texture(src: Path, dst_dir: Path, flags: int) -> Path:
    """Copy `src` into `dst_dir`, generating alpha the way Blitz3D does when needed.

    Returns the path of the file to reference (the plain copy or a derived PNG).
    """
    dst_dir.mkdir(parents=True, exist_ok=True)
    plain = dst_dir / src.name
    if not plain.exists() or plain.stat().st_size != src.stat().st_size:
        shutil.copy2(src, plain)
    masked = bool(flags & b3dlib.TEX_FLAG_MASKED)
    alpha = bool(flags & b3dlib.TEX_FLAG_ALPHA)
    if not (masked or alpha):
        return plain
    with Image.open(src) as im:
        has_alpha = im.mode in ("RGBA", "LA") or "transparency" in im.info
        if masked:
            suffix = "__mask"
        elif not has_alpha:
            suffix = "__alpha" if flags & TEX_FLAG_RGB else "__alphaw"
        else:
            return plain
        derived = dst_dir / f"{src.stem}{suffix}.png"
        if derived.exists() and derived.stat().st_mtime >= src.stat().st_mtime:
            return derived
        rgba = im.convert("RGBA")
        px = rgba.load()
        w, h = rgba.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if masked:
                    a = 0 if (r, g, b) == (0, 0, 0) else 255
                else:
                    a = (r + g + b) // 3
                    if suffix == "__alphaw":
                        r, g, b = 255, 255, 255
                px[x, y] = (r, g, b, a)
        rgba.save(derived)
    return derived


def relative_uri(from_dir: Path, target: Path) -> str:
    """POSIX relative path from `from_dir` to `target` (os.path.relpath semantics)."""
    import os
    return PurePosixPath(os.path.relpath(target, from_dir)).as_posix()


def uv_transform(tex: Texture, uv: tuple[float, float]) -> tuple[float, float]:
    """Apply Blitz's texture matrix (Texture::getMatrix, row-vector convention)."""
    if tex.pos == (0.0, 0.0) and tex.scale == (1.0, 1.0) and tex.rot == 0.0:
        return (uv[0], uv[1])
    c, s = math.cos(tex.rot), math.sin(tex.rot)
    u, v = uv
    return (tex.scale[0] * (c * u + s * v) + tex.pos[0], tex.scale[1] * (-s * u + c * v) + tex.pos[1])


def face_normals(mesh: Mesh, positions: list[tuple[float, float, float]]) -> list[tuple[float, float, float]]:
    """MeshModel::updateNormals: area-weighted accumulation of face normals per vertex."""
    acc = [[0.0, 0.0, 0.0] for _ in positions]
    for ts in mesh.tri_sets:
        for tri in ts.indices:
            a, b, c = (positions[i] for i in triangle_indices(tri))
            u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
            n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
            for i in tri:
                acc[i][0] += n[0]
                acc[i][1] += n[1]
                acc[i][2] += n[2]
    out = []
    for n in acc:
        length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
        out.append((n[0] / length, n[1] / length, n[2] / length) if length > 0 else (0.0, 1.0, 0.0))
    return out


def node_local_matrix(node: Node) -> Mat4:
    return trs_matrix(blitz_to_godot(node.pos), blitz_quat_to_godot(node.rot), tuple(node.scale))


class Converter:
    def __init__(self, b3d: B3DFile, out_path: Path, data_dir: Path, textures_dir: Path,
                 embed: bool = False, skin: bool = True):
        self.b3d = b3d
        self.out_path = out_path
        self.data_dir = data_dir
        self.textures_dir = textures_dir
        self.embed = embed
        self.skin = skin
        self.builder = GltfBuilder()
        self.index = TextureIndex(data_dir)
        self.own_dir = b3d.path.parent if b3d.path else data_dir
        self.material_ids: dict[int, int] = {}
        self.texture_uris: dict[int, str | None] = {}
        self.sidecar: dict = {
            "source": b3d.path.relative_to(data_dir).as_posix() if b3d.path else None,
            "anim_frames": b3d.anim_frames,
            "nodes": {},
            "materials": {},
            "scene": {},
            "missing_textures": [],
        }
        self.used_names: dict[str, int] = {}
        self.node_ids: dict[int, int] = {}  # id(Node) -> gltf node index
        self.skins: list[tuple[int, list[Node]]] = []  # (gltf mesh-node index, joint nodes)

    # --- textures ------------------------------------------------------------------------

    def texture_uri(self, tex_id: int) -> str | None:
        if tex_id in self.texture_uris:
            return self.texture_uris[tex_id]
        tex = self.b3d.textures[tex_id]
        src = self.index.resolve(tex.name, self.own_dir)
        uri: str | None = None
        if src is None:
            self.sidecar["missing_textures"].append(tex.name)
        else:
            rel = src.relative_to(self.data_dir)
            dst = derive_texture(src, self.textures_dir / rel.parent, tex.flags)
            if self.embed:
                uri = self.builder_embed_image(dst)
            else:
                uri = relative_uri(self.out_path.parent.resolve(), dst.resolve())
        self.texture_uris[tex_id] = uri
        return uri

    def builder_embed_image(self, src: Path) -> str:
        view = self.builder.add_buffer_view(src.read_bytes())
        self.builder.images.append({"bufferView": view, "mimeType": IMAGE_MIME[src.suffix.lower()], "name": src.name})
        return f"__embedded__{len(self.builder.images) - 1}"

    def gltf_texture(self, tex_id: int) -> int | None:
        uri = self.texture_uri(tex_id)
        if uri is None:
            return None
        if uri.startswith("__embedded__"):
            image = int(uri[len("__embedded__"):])
            key = (uri, 0)
            if key not in self.builder._texture_index:
                if not self.builder.samplers:
                    self.builder.samplers.append({"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497})
                self.builder.textures.append({"sampler": 0, "source": image})
                self.builder._texture_index[key] = len(self.builder.textures) - 1
            return self.builder._texture_index[key]
        return self.builder.add_texture(uri)

    # --- materials -----------------------------------------------------------------------

    def material(self, brush_id: int) -> int:
        if brush_id in self.material_ids:
            return self.material_ids[brush_id]
        if brush_id < 0:
            brush = Brush("default", (1.0, 1.0, 1.0, 1.0), 0.0, b3dlib.BRUSH_BLEND_ALPHA, 0, [])
        else:
            brush = self.b3d.brushes[brush_id]
        name = f"{brush.name}#{brush_id}"
        layers = brush.layers
        base_layer = next((t for t in layers if not (self.b3d.textures[t].flags & TEX_FLAG_SPHERE)), None)
        mat: dict = {
            "name": name,
            "pbrMetallicRoughness": {"baseColorFactor": blitz_color_to_gltf(brush.rgba, additive=brush.blend == b3dlib.BRUSH_BLEND_ADD), "metallicFactor": 0.0, "roughnessFactor": 1.0},
            "doubleSided": bool(brush.fx & b3dlib.FX_NO_CULLING),
        }
        alpha_mode = "OPAQUE"
        if brush.rgba[3] < 1.0 or brush.blend == b3dlib.BRUSH_BLEND_ADD or brush.fx & b3dlib.FX_FORCE_ALPHA:
            alpha_mode = "BLEND"
        info: dict = {
            "blend": brush.blend, "fx": brush.fx, "vertex_colors": bool(brush.fx & b3dlib.FX_VERTEX_COLORS),
            "layers": [],
        }
        if base_layer is not None:
            tex = self.b3d.textures[base_layer]
            gt = self.gltf_texture(base_layer)
            if gt is not None:
                mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": gt, "texCoord": 0}
            if tex.is_masked and alpha_mode == "OPAQUE":
                alpha_mode = "MASK"
                mat["alphaCutoff"] = 0.5
            elif tex.has_alpha:
                alpha_mode = "BLEND"
            if tex.blend == TEX_BLEND_MULTIPLY2:
                info["modulate2x"] = True
        for layer_pos, t in enumerate(layers):
            tex = self.b3d.textures[t]
            # Clamping is a per-layer texture flag: Location2 `mountain` wraps `rock.jpg` and
            # clamps V of the `rockalpha.jpg` fade on its second UV set.
            entry = {"texture": tex.name, "flags": tex.flags, "blend": tex.blend, "uv2": tex.uses_uv2,
                     "sphere": bool(tex.flags & TEX_FLAG_SPHERE), "uri": self.texture_uri(t),
                     "clamp_u": bool(tex.flags & TEX_FLAG_CLAMP_U), "clamp_v": bool(tex.flags & TEX_FLAG_CLAMP_V)}
            info["layers"].append(entry)
            if layer_pos > 0 and t != base_layer and not entry["sphere"]:
                gt = self.gltf_texture(t)
                if gt is not None and "detail" not in info:
                    info["detail"] = {"texture_index": gt, "uri": self.texture_uri(t), "uv2": tex.uses_uv2,
                                      "blend": tex.blend}
        mat["alphaMode"] = alpha_mode
        if brush.fx & b3dlib.FX_FULLBRIGHT:
            mat["extensions"] = {"KHR_materials_unlit": {}}
            self.builder.extensions_used.add("KHR_materials_unlit")
        idx = self.builder.add_material(mat)
        self.material_ids[brush_id] = idx
        self.sidecar["materials"][name] = info
        return idx

    # --- meshes --------------------------------------------------------------------------

    def bone_nodes(self, node: Node) -> list[Node]:
        """Bones of a mesh node: BONE descendants in file order (Blitz `bones` vector)."""
        if not self.skin:
            return []
        return [n for n in node.walk() if n is not node and n.bone is not None]

    def vertex_joints(self, mesh: Mesh, bones: list[Node]) -> list[tuple[list[int], list[float]]]:
        """Per vertex (joints, weights) padded to 4 slots; the strongest weights win,
        like `MeshLoader::addBone` (MAX_SURFACE_BONES = 4)."""
        per_vertex: list[list[tuple[float, int]]] = [[] for _ in mesh.verts]
        for joint, bone in enumerate(bones):
            for vert, weight in bone.bone or []:
                per_vertex[vert].append((weight, joint))
        out = []
        for entries in per_vertex:
            entries.sort(key=lambda e: -e[0])
            entries = entries[:MAX_JOINTS_PER_VERTEX]
            joints = [j for _, j in entries] + [0] * (MAX_JOINTS_PER_VERTEX - len(entries))
            weights = [w for w, _ in entries] + [0.0] * (MAX_JOINTS_PER_VERTEX - len(entries))
            out.append((joints, weights))
        return out

    def convert_mesh(self, node: Node, name: str) -> int:
        mesh = node.mesh
        assert mesh is not None
        bones = self.bone_nodes(node)
        skin_data = self.vertex_joints(mesh, bones) if bones else []
        positions = [blitz_to_godot(v.pos) for v in mesh.verts]
        if mesh.has_normals:
            normals = [blitz_to_godot(v.normal) for v in mesh.verts]  # type: ignore[arg-type]
        else:
            normals = face_normals(mesh, positions)
        # A mirrored node (negative-determinant scale, Location6 `Line04`) inverts the
        # screen winding; Direct3D culls by that final winding, so such meshes are
        # modelled with reversed triangles. Godot instead flips its front face for
        # mirrored instances, which would undo the modeller's reversal: reverse it here.
        mirrored = False
        n: Node | None = node
        while n is not None:
            if n.scale[0] * n.scale[1] * n.scale[2] < 0:
                mirrored = not mirrored
            n = n.parent
        groups: dict[int, list[tuple[int, int, int]]] = {}
        for ts in mesh.tri_sets:
            brush_id = mesh.brush if mesh.brush != -1 else ts.brush
            tris = [(t[0], t[2], t[1]) for t in ts.indices] if mirrored else list(ts.indices)
            groups.setdefault(brush_id, []).extend(tris)
        primitives = []
        for brush_id, tris in groups.items():
            brush = self.b3d.brushes[brush_id] if brush_id >= 0 else None
            layers = brush.layers if brush else []
            base_layer = next((t for t in layers if not (self.b3d.textures[t].flags & TEX_FLAG_SPHERE)), None)
            detail_layer = next((t for t in layers[1:] if t != base_layer and not (self.b3d.textures[t].flags & TEX_FLAG_SPHERE)), None)
            keep_alpha = brush is not None and brush.uses_vertex_alpha(self.b3d.textures)
            additive = brush is not None and brush.blend == b3dlib.BRUSH_BLEND_ADD
            remap: dict[int, int] = {}
            pos_out: list = []
            nrm_out: list = []
            col_out: list = []
            uv0_out: list = []
            uv1_out: list = []
            joints_out: list = []
            weights_out: list = []
            idx_out: list[int] = []
            for tri in tris:
                for i in triangle_indices(tri):
                    if i not in remap:
                        remap[i] = len(pos_out)
                        v = mesh.verts[i]
                        pos_out.append(positions[i])
                        nrm_out.append(normals[i])
                        if mesh.has_colors:
                            col_out.append(tuple(blitz_color_to_gltf(v.color, keep_alpha=keep_alpha, additive=additive)))
                        uv0_out.append(self._uv(v, base_layer))
                        if detail_layer is not None:
                            uv1_out.append(self._uv(v, detail_layer))
                        if skin_data:
                            joints_out.append(skin_data[i][0])
                            weights_out.append(skin_data[i][1])
                    idx_out.append(remap[i])
            b = self.builder
            attrs = {
                "POSITION": b.add_accessor(pos_out, "VEC3", target=TARGET_ARRAY_BUFFER, minmax=True),
                "NORMAL": b.add_accessor(nrm_out, "VEC3", target=TARGET_ARRAY_BUFFER),
                "TEXCOORD_0": b.add_accessor(uv0_out, "VEC2", target=TARGET_ARRAY_BUFFER),
            }
            if col_out:
                attrs["COLOR_0"] = b.add_accessor(col_out, "VEC4", target=TARGET_ARRAY_BUFFER)
            if uv1_out:
                attrs["TEXCOORD_1"] = b.add_accessor(uv1_out, "VEC2", target=TARGET_ARRAY_BUFFER)
            if joints_out:
                attrs["JOINTS_0"] = b.add_accessor(joints_out, "VEC4", COMPONENT_UBYTE, target=TARGET_ARRAY_BUFFER)
                attrs["WEIGHTS_0"] = b.add_accessor(weights_out, "VEC4", target=TARGET_ARRAY_BUFFER)
            prim = {
                "attributes": attrs,
                "indices": b.add_accessor(idx_out, "SCALAR", COMPONENT_UINT, target=TARGET_ELEMENT_ARRAY_BUFFER),
                "material": self.material(brush_id),
                "mode": 4,
            }
            primitives.append(prim)
        return self.builder.add_mesh({"name": name, "primitives": primitives})

    def _uv(self, v: b3dlib.Vertex, layer: int | None) -> tuple[float, float]:
        if layer is None:
            return tuple(v.uv[0][:2]) if v.uv else (0.0, 0.0)
        tex = self.b3d.textures[layer]
        set_index = 1 if tex.uses_uv2 and len(v.uv) > 1 else 0
        uv = tuple(v.uv[set_index][:2]) if v.uv else (0.0, 0.0)
        return uv_transform(tex, uv)

    # --- nodes ---------------------------------------------------------------------------

    def unique_name(self, name: str) -> str:
        base = name if name else "node"
        if base not in self.used_names:
            self.used_names[base] = 1
            return base
        self.used_names[base] += 1
        return f"{base}_{self.used_names[base]}"

    def convert_node(self, node: Node) -> int:
        clean, attrs = b3dlib.clean_name(node.name)
        name = self.unique_name(clean)
        entry: dict = {"original": node.name}
        entry.update(attrs)
        if node.name.startswith("B3DEXT_"):
            entry["tag"] = node.name
            self.sidecar["scene"][node.name] = {"pos": list(node.pos), "parent": node.parent.name if node.parent else None}
        if node.bone is not None:
            entry["bone"] = True
        if node.name == "B3DEXT_ANIMMAP" and node.mesh is not None and node.mesh.brush >= 0:
            # B3D Extensions animated texture map: the child B3DEXT_UVPOS position keys
            # are the texture offset (negated) of the brush `mesh.brush`.
            self.material(node.mesh.brush)
            entry["animmap_material"] = f"{self.b3d.brushes[node.mesh.brush].name}#{node.mesh.brush}"
        if node.name == "B3DEXT_ANIMBRUSH" and node.mesh is not None and node.mesh.brush >= 0:
            # B3D Extensions animated brush: the child B3DEXT_ALPHA / B3DEXT_COLOR position
            # keys drive the alpha / colour of the brush `mesh.brush` (`_fext_updateanimbrushes`).
            self.material(node.mesh.brush)
            entry["animbrush_material"] = f"{self.b3d.brushes[node.mesh.brush].name}#{node.mesh.brush}"
        if node.has_keys:
            entry["animated"] = True
        self.sidecar["nodes"][name] = entry
        g: dict = {
            "name": name,
            "translation": list(blitz_to_godot(node.pos)),
            "scale": list(node.scale),
        }
        w, x, y, z = blitz_quat_to_godot(node.rot)
        g["rotation"] = [x, y, z, w]
        if node.mesh is not None and node.mesh.verts and node.mesh.tri_count:
            g["mesh"] = self.convert_mesh(node, name)
        idx = self.builder.add_node(g)
        self.node_ids[id(node)] = idx
        bones = self.bone_nodes(node) if "mesh" in g else []
        if bones:
            self.skins.append((idx, bones))
            entry["skinned"] = True
        children = [self.convert_node(c) for c in node.children]
        if children:
            g["children"] = children
        return idx

    # --- animation -----------------------------------------------------------------------

    def convert_animation(self) -> None:
        samplers: list[dict] = []
        channels: list[dict] = []
        for node in self.b3d.root.walk():
            if not node.has_keys:
                continue
            frames = sorted(node.keys)
            target = self.node_ids[id(node)]
            for kind, path in (("pos", "translation"), ("scale", "scale"), ("rot", "rotation")):
                pts = [f for f in frames if kind in node.keys[f]]
                if not pts:
                    continue
                times = [float(f) for f in pts]
                if kind == "pos":
                    values = [blitz_to_godot(node.keys[f]["pos"]) for f in pts]
                elif kind == "scale":
                    values = [tuple(node.keys[f]["scale"]) for f in pts]
                else:
                    values = []
                    for f in pts:
                        w, x, y, z = blitz_quat_to_godot(node.keys[f]["rot"])
                        values.append((x, y, z, w))
                b = self.builder
                inp = b.add_accessor(times, "SCALAR", minmax=True)
                out = b.add_accessor(values, "VEC4" if kind == "rot" else "VEC3")
                samplers.append({"input": inp, "output": out, "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": target, "path": path}})
        if channels:
            self.builder.add_animation({"name": ANIMATION_NAME, "samplers": samplers, "channels": channels})

    # --- skins ---------------------------------------------------------------------------

    def convert_skins(self) -> None:
        """One glTF skin per boned mesh: joints = its bones, inverse bind matrices from the
        rest pose relative to the mesh node (Blitz skins in the mesh's own space)."""
        for mesh_idx, bones in self.skins:
            mesh_node = next(n for n in self.b3d.root.walk() if self.node_ids.get(id(n)) == mesh_idx)
            ibms = []
            for bone in bones:
                chain = []
                n = bone
                while n is not mesh_node:
                    chain.append(n)
                    n = n.parent
                global_m: Mat4 = trs_matrix((0.0, 0.0, 0.0), (1.0, 0.0, 0.0, 0.0), (1.0, 1.0, 1.0))
                for n in reversed(chain):
                    global_m = mat_mul(global_m, node_local_matrix(n))
                ibms.append(mat_column_major(mat_inverse_affine(global_m)))
            skin = {
                "joints": [self.node_ids[id(b)] for b in bones],
                "inverseBindMatrices": self.builder.add_accessor(ibms, "MAT4"),
            }
            self.builder.nodes[mesh_idx]["skin"] = self.builder.add_skin(skin)

    # --- driver --------------------------------------------------------------------------

    def run(self) -> None:
        root = self.convert_node(self.b3d.root)
        self.convert_skins()
        self.convert_animation()
        self.out_path.parent.mkdir(parents=True, exist_ok=True)
        self.builder.write_glb(self.out_path, [root])
        sidecar_path = self.out_path.with_suffix("").with_suffix(".b3d.json")
        sidecar_path.write_text(json.dumps(self.sidecar, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        LOG.info("wrote %s (%d nodes, %d materials)", self.out_path, len(self.builder.nodes), len(self.builder.materials))


def convert(src: Path, dst: Path, data_dir: Path, textures_dir: Path, embed: bool = False, skin: bool = True) -> Converter:
    b3d = b3dlib.load(src)
    conv = Converter(b3d, dst, data_dir, textures_dir, embed=embed, skin=skin)
    conv.run()
    return conv


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--data-dir", type=Path, required=True, help="unpacked Data/ directory (texture search root)")
    ap.add_argument("--textures-dir", type=Path, required=True, help="where textures are copied (build/import/assets/textures)")
    ap.add_argument("--embed", action="store_true", help="embed images in the glb instead of referencing files")
    ap.add_argument("--no-skin", dest="skin", action="store_false", help="keep bones as rigid nodes (no glTF skin)")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    convert(args.src, args.dst, args.data_dir.resolve(), args.textures_dir.resolve(), args.embed, args.skin)


if __name__ == "__main__":
    main()
