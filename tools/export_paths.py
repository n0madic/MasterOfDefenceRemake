#!/usr/bin/env python3
"""Export enemy path waypoints from Data/Location*/Path1.b3d into JSON.

The game animates the 'path' node (position keyframes) and enemies chase it,
so the keyframe positions are the level's waypoints in world units.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import b3dlib

PATH_NODE = "path"


def path_file(data_dir: Path, location: int) -> Path:
    """`Location<N>/Path1.b3d` of `data_dir`, matched case-insensitively."""
    folder = next(d for d in data_dir.iterdir() if d.name.lower() == f"location{location}")
    return next(f for f in folder.iterdir() if f.name.lower() == "path1.b3d")


def path_keys(path: Path) -> tuple[int, list[dict]]:
    """(anim_frames, [{frame, pos, rot_wxyz?}, ...]) of the `path` node, Blitz coordinates,
    positions rounded to 3 and rotations to 4 decimals."""
    b3d = b3dlib.load(path)
    node = b3d.root.find(PATH_NODE)
    if node is None:
        raise ValueError(f"{path}: no {PATH_NODE!r} node")
    keys = []
    for frame in sorted(node.keys):
        rec = node.keys[frame]
        out: dict = {"frame": frame}
        if "pos" in rec:
            out["pos"] = [round(v, 3) for v in rec["pos"]]
        if "rot" in rec:
            out["rot_wxyz"] = [round(v, 4) for v in rec["rot"]]
        keys.append(out)
    return b3d.anim_frames, keys


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("data_dir", type=Path, help="unpacked game Data directory")
    ap.add_argument("out", type=Path)
    args = ap.parse_args()
    result = {}
    for loc in range(1, 7):
        src = path_file(args.data_dir, loc)
        frames, keys = path_keys(src)
        result[f"location{loc}"] = {
            "file": str(src.relative_to(args.data_dir)),
            "anim_frames": frames,
            "waypoints": keys,
        }
    args.out.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
