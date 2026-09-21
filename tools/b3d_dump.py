#!/usr/bin/env python3
"""Dump the chunk/node tree of a Blitz3D .b3d file (BB3D chunked format).

Printer over tools/b3dlib.py: textures, brushes and the NODE hierarchy with names,
transforms, mesh stats (vertex/triangle counts, brush ids), animation ranges, keyframe
counts and bone weights.
"""
from __future__ import annotations

import argparse
import logging
from pathlib import Path

import b3dlib

LOG = logging.getLogger("b3d_dump")


def fmt3(v: tuple[float, ...]) -> str:
    return "(" + ", ".join(f"{x:.3f}" for x in v) + ")"


def dump_node(node: b3dlib.Node, depth: int, out: list[str], print_keys: bool) -> None:
    ind = "  " * depth
    out.append(f"{ind}NODE {node.name!r} pos={fmt3(node.pos)} scale={fmt3(node.scale)} rot(wxyz)={fmt3(node.rot)}")
    if node.mesh is not None:
        m = node.mesh
        out.append(f"{ind}  MESH brush={m.brush} verts={len(m.verts)} tris={m.tri_count} tri_brushes={m.brush_ids}")
    if node.bone is not None:
        out.append(f"{ind}  BONE weights={len(node.bone)}")
    if node.anim is not None:
        out.append(f"{ind}  ANIM flags={node.anim.flags} frames={node.anim.frames} fps={node.anim.fps}")
    for child in node.children:
        dump_node(child, depth + 1, out, print_keys)
    if node.keys:
        frames = sorted(node.keys)
        kinds = sorted({k for v in node.keys.values() for k in v})
        out.append(f"{ind}  KEYS {kinds} frames {frames[0]}..{frames[-1]} ({len(frames)} keys)")
        if print_keys:
            for fr in frames:
                parts = " ".join(f"{k}={fmt3(v)}" for k, v in node.keys[fr].items())
                out.append(f"{ind}    f{fr}: {parts}")


def dump(f: b3dlib.B3DFile, print_keys: bool = False) -> list[str]:
    out = [f"BB3D version {f.version}"]
    for i, t in enumerate(f.textures):
        out.append(f"  TEX[{i}] {t.name!r} flags={t.flags} blend={t.blend}")
    for i, b in enumerate(f.brushes):
        out.append(f"  BRUSH[{i}] {b.name!r} rgba={fmt3(b.rgba)} blend={b.blend} fx={b.fx} tex={b.textures}")
    dump_node(f.root, 1, out, print_keys)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--names-only", action="store_true", help="print only NODE names and animation info")
    ap.add_argument("--keys", action="store_true", help="print every keyframe (positions/rotations)")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    for path in args.files:
        f = b3dlib.load(path)
        print(f"=== {path} ({path.stat().st_size} bytes, {len(f.nodes())} nodes)")
        for line in dump(f, args.keys):
            if args.names_only and not any(k in line for k in ("NODE", "ANIM", "KEYS", "BB3D")):
                continue
            print(line)


if __name__ == "__main__":
    main()
