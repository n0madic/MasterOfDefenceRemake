#!/usr/bin/env python3
"""Convert a Quake II MD2 model into a .glb with morph targets.

    python3 tools/md2togltf.py IN.md2 SKIN.jpg OUT.glb --textures-dir godot/assets/textures --data-dir Data/

Reproduces blitz3d/md2rep.cpp:
- vertices are unique (vertex index, texcoord index) pairs; UV = (s / skinWidth, t / skinHeight);
- Blitz reads MD2 (x, y, z) as (y, z, x) (scale/translate permuted the same way), which
  becomes (y, z, -x) in Godot (tools/blitzconv.py::md2_to_godot);
- Blitz emits triangles as (v0, v2, v1); with the mirror + winding swap of C1 the Godot
  order is the original MD2 order (v0, v1, v2);
- one animation `md2`: frame k is shown at t = k (one-hot morph weights), plus a final key
  at t = N equal to frame 0, because Blitz's loop mode blends the last frame towards the
  first (`render_b == anim_last -> anim_first`). Views play `seek(fmod(t, N))`.

Normals are recomputed from geometry per frame (area weighted), not from the MD2 normal
table.
"""
from __future__ import annotations

import argparse
import json
import logging
import math
import os
import shutil
import struct
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from blitzconv import md2_to_godot
from copy_assets import canonical_images
from gltfwriter import COMPONENT_UINT, TARGET_ARRAY_BUFFER, TARGET_ELEMENT_ARRAY_BUFFER, GltfBuilder

LOG = logging.getLogger("md2togltf")

HEADER = "<4si10i5i"
HEADER_SIZE = struct.calcsize(HEADER)
ANIMATION_NAME = "md2"
IMAGE_MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}

Vec3 = tuple[float, float, float]


@dataclass
class MD2:
    skin_w: int
    skin_h: int
    frames: list[list[Vec3]]  # per frame, per unique vertex, Godot coordinates
    uvs: list[tuple[float, float]]
    tris: list[tuple[int, int, int]]
    frame_names: list[str]


def load_md2(path: Path) -> MD2:
    d = path.read_bytes()
    (ident, ver, skin_w, skin_h, frame_size, n_skins, n_verts, n_st, n_tris, n_gl, n_frames,
     ofs_skins, ofs_st, ofs_tris, ofs_frames, ofs_gl) = struct.unpack_from(HEADER, d, 0)[:16]
    if ident != b"IDP2" or ver != 8:
        raise ValueError(f"not an MD2 v8 file: {path}")
    st = [struct.unpack_from("<hh", d, ofs_st + 4 * i) for i in range(n_st)]
    raw_tris = [struct.unpack_from("<6H", d, ofs_tris + 12 * i) for i in range(n_tris)]
    unique: dict[tuple[int, int], int] = {}
    uvs: list[tuple[float, float]] = []
    tris: list[tuple[int, int, int]] = []
    for t in raw_tris:
        idx = []
        for j in range(3):
            key = (t[j], t[3 + j])
            if key not in unique:
                unique[key] = len(uvs)
                s, tt = st[key[1]]
                uvs.append((s / skin_w, tt / skin_h))
            idx.append(unique[key])
        tris.append((idx[0], idx[1], idx[2]))
    order = sorted(unique.items(), key=lambda kv: kv[1])
    frames: list[list[Vec3]] = []
    names: list[str] = []
    for f in range(n_frames):
        base = ofs_frames + f * frame_size
        scale = struct.unpack_from("<3f", d, base)
        trans = struct.unpack_from("<3f", d, base + 12)
        names.append(d[base + 24 : base + 40].split(b"\0", 1)[0].decode("latin-1"))
        vbase = base + 40
        verts: list[Vec3] = []
        for (vi, _si), _ in order:
            x, y, z, _n = struct.unpack_from("<4B", d, vbase + 4 * vi)
            p = (x * scale[0] + trans[0], y * scale[1] + trans[1], z * scale[2] + trans[2])
            verts.append(md2_to_godot(p))
        frames.append(verts)
    return MD2(skin_w, skin_h, frames, uvs, tris, names)


def smooth_normals(positions: list[Vec3], tris: list[tuple[int, int, int]]) -> list[Vec3]:
    acc = [[0.0, 0.0, 0.0] for _ in positions]
    for a_i, b_i, c_i in tris:
        a, b, c = positions[a_i], positions[b_i], positions[c_i]
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        for i in (a_i, b_i, c_i):
            acc[i][0] += n[0]
            acc[i][1] += n[1]
            acc[i][2] += n[2]
    out: list[Vec3] = []
    for n in acc:
        length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
        out.append((n[0] / length, n[1] / length, n[2] / length) if length > 0 else (0.0, 1.0, 0.0))
    return out


def bbox(verts: list[Vec3]) -> tuple[Vec3, Vec3]:
    return (tuple(min(v[i] for v in verts) for i in range(3)), tuple(max(v[i] for v in verts) for i in range(3)))


def convert(src: Path, skin: Path | None, dst: Path, data_dir: Path, textures_dir: Path, embed: bool = False) -> dict:
    md2 = load_md2(src)
    b = GltfBuilder()
    n_frames = len(md2.frames)
    base = md2.frames[0]
    base_normals = smooth_normals(base, md2.tris)
    attrs = {
        "POSITION": b.add_accessor(base, "VEC3", target=TARGET_ARRAY_BUFFER, minmax=True),
        "NORMAL": b.add_accessor(base_normals, "VEC3", target=TARGET_ARRAY_BUFFER),
        "TEXCOORD_0": b.add_accessor(md2.uvs, "VEC2", target=TARGET_ARRAY_BUFFER),
    }
    targets = []
    target_names = []
    for f in range(1, n_frames):
        verts = md2.frames[f]
        normals = smooth_normals(verts, md2.tris)
        dpos = [(v[0] - o[0], v[1] - o[1], v[2] - o[2]) for v, o in zip(verts, base)]
        dnrm = [(v[0] - o[0], v[1] - o[1], v[2] - o[2]) for v, o in zip(normals, base_normals)]
        targets.append({
            "POSITION": b.add_accessor(dpos, "VEC3", target=TARGET_ARRAY_BUFFER, minmax=True),
            "NORMAL": b.add_accessor(dnrm, "VEC3", target=TARGET_ARRAY_BUFFER),
        })
        target_names.append(f"frame{f:03d}")
    material: dict = {
        "name": src.stem,
        "pbrMetallicRoughness": {"baseColorFactor": [1.0, 1.0, 1.0, 1.0], "metallicFactor": 0.0, "roughnessFactor": 1.0},
        "alphaMode": "OPAQUE",
        "doubleSided": False,
    }
    skin_rel: str | None = None
    if skin is not None and skin.exists():
        skin = canonical_images(data_dir).get(skin, skin)
        rel = skin.relative_to(data_dir)
        copy_to = textures_dir / rel
        copy_to.parent.mkdir(parents=True, exist_ok=True)
        if not copy_to.exists() or copy_to.stat().st_size != skin.stat().st_size:
            shutil.copy2(skin, copy_to)
        if embed:
            view = b.add_buffer_view(skin.read_bytes())
            b.images.append({"bufferView": view, "mimeType": IMAGE_MIME[skin.suffix.lower()], "name": skin.name})
            b.samplers.append({"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497})
            b.textures.append({"sampler": 0, "source": 0})
            tex = 0
        else:
            uri = PurePosixPath(os.path.relpath(copy_to.resolve(), dst.parent.resolve())).as_posix()
            tex = b.add_texture(uri)
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex, "texCoord": 0}
        skin_rel = rel.as_posix()
    mat = b.add_material(material)
    flat_indices = [i for t in md2.tris for i in t]
    mesh = b.add_mesh({
        "name": src.stem,
        "primitives": [{
            "attributes": attrs,
            "indices": b.add_accessor(flat_indices, "SCALAR", COMPONENT_UINT, target=TARGET_ELEMENT_ARRAY_BUFFER),
            "material": mat,
            "mode": 4,
            "targets": targets,
        }],
        "weights": [0.0] * len(targets),
        "extras": {"targetNames": target_names},
    })
    node = b.add_node({"name": src.stem, "mesh": mesh})
    # Animation: frame k at t = k (one-hot), frame 0 again at t = N.
    times = [float(k) for k in range(n_frames + 1)]
    weights: list[float] = []
    for k in range(n_frames + 1):
        frame = k % n_frames
        for t in range(1, n_frames):
            weights.append(1.0 if t == frame else 0.0)
    inp = b.add_accessor(times, "SCALAR", minmax=True)
    out = b.add_accessor(weights, "SCALAR")
    b.add_animation({
        "name": ANIMATION_NAME,
        "samplers": [{"input": inp, "output": out, "interpolation": "LINEAR"}],
        "channels": [{"sampler": 0, "target": {"node": node, "path": "weights"}}],
    })
    dst.parent.mkdir(parents=True, exist_ok=True)
    b.write_glb(dst, [node])
    boxes = [bbox(f) for f in md2.frames]
    sidecar = {
        "source": src.relative_to(data_dir).as_posix() if data_dir in src.resolve().parents or src.is_relative_to(data_dir) else str(src),
        "skin": skin_rel,
        "frames": n_frames,
        "vertices": len(base),
        "triangles": len(md2.tris),
        "bbox_min": [min(bx[0][i] for bx in boxes) for i in range(3)],
        "bbox_max": [max(bx[1][i] for bx in boxes) for i in range(3)],
        "frame_names": md2.frame_names,
    }
    dst.with_suffix("").with_suffix(".md2.json").write_text(json.dumps(sidecar, indent=1) + "\n")
    LOG.info("wrote %s (%d frames, %d verts, %d tris)", dst, n_frames, len(base), len(md2.tris))
    return sidecar


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("skin", type=Path, nargs="?")
    ap.add_argument("dst", type=Path)
    ap.add_argument("--data-dir", type=Path, required=True)
    ap.add_argument("--textures-dir", type=Path, required=True)
    ap.add_argument("--embed", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    convert(args.src.resolve(), args.skin.resolve() if args.skin else None, args.dst, args.data_dir.resolve(),
            args.textures_dir.resolve(), args.embed)


if __name__ == "__main__":
    main()
