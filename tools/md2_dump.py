#!/usr/bin/env python3
"""Print MD2 (Quake II model) header info and frame names for each file."""
from __future__ import annotations

import argparse
import struct
from pathlib import Path

HEADER = "<4si10i5i"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--frames", action="store_true", help="list frame names")
    args = ap.parse_args()
    for f in args.files:
        d = f.read_bytes()
        (ident, ver, skinw, skinh, framesize, nskins, nverts, ntex, ntris, nglcmds, nframes,
         ofs_skins, ofs_st, ofs_tris, ofs_frames, ofs_glcmds) = struct.unpack_from(HEADER, d, 0)[:16]
        names = []
        for i in range(nframes):
            off = ofs_frames + i * framesize + 24
            names.append(d[off:off + 16].split(b"\0", 1)[0].decode("latin-1"))
        groups: dict[str, int] = {}
        for n in names:
            key = n.rstrip("0123456789")
            groups[key] = groups.get(key, 0) + 1
        print(f"{f.name:14} ver={ver} skin={skinw}x{skinh} verts={nverts} tris={ntris} frames={nframes} groups={groups}")
        if args.frames:
            print("   ", ", ".join(names))


if __name__ == "__main__":
    main()
