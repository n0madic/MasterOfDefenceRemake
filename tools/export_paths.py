#!/usr/bin/env python3
"""Export enemy path waypoints from Data/Location*/Path1.b3d into JSON.

The game animates the 'path' node (position keyframes) and enemies chase it,
so the keyframe positions are the level's waypoints in world units.
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


def read_keys(data: bytes) -> tuple[int, dict[str, list[dict]]]:
    """Return (anim_frames, {node_name: [{frame,pos,rot}...]})."""
    nodes: dict[str, list[dict]] = {}
    frames = [0]

    def walk(p: int, end: int, node: str | None) -> None:
        while p < end:
            tag = data[p:p + 4].decode("latin-1")
            (size,) = struct.unpack_from("<i", data, p + 4)
            body, cend = p + 8, p + 8 + size
            if tag == "BB3D":
                walk(body + 4, cend, node)
            elif tag == "NODE":
                e = data.index(b"\0", body)
                name = data[body:e].decode("cp1251", "replace")
                walk(e + 1 + 4 * 10, cend, name)
            elif tag == "ANIM":
                frames[0] = max(frames[0], struct.unpack_from("<i", data, body + 4)[0])
            elif tag == "KEYS" and node is not None:
                (flags,) = struct.unpack_from("<i", data, body)
                q = body + 4
                while q < cend:
                    (frame,) = struct.unpack_from("<i", data, q)
                    q += 4
                    rec: dict = {"frame": frame}
                    if flags & 1:
                        rec["pos"] = [round(v, 3) for v in struct.unpack_from("<3f", data, q)]
                        q += 12
                    if flags & 2:
                        q += 12
                    if flags & 4:
                        rec["rot_wxyz"] = [round(v, 4) for v in struct.unpack_from("<4f", data, q)]
                        q += 16
                    nodes.setdefault(node, []).append(rec)
            p = cend

    walk(0, len(data), None)
    return frames[0], nodes


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("data_dir", type=Path, help="unpacked game Data directory")
    ap.add_argument("out", type=Path)
    args = ap.parse_args()
    result = {}
    for loc in range(1, 7):
        folder = next(d for d in args.data_dir.iterdir() if d.name.lower() == f"location{loc}")
        path_file = next(f for f in folder.iterdir() if f.name.lower() == "path1.b3d")
        frames, nodes = read_keys(path_file.read_bytes())
        keys = nodes["path"]
        merged: dict[int, dict] = {}
        for k in keys:
            merged.setdefault(k["frame"], {}).update(k)
        result[f"location{loc}"] = {
            "file": str(path_file.relative_to(args.data_dir)),
            "anim_frames": frames,
            "waypoints": [merged[f] for f in sorted(merged)],
        }
    args.out.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
