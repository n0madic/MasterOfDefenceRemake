#!/usr/bin/env python3
"""Print field types of every Blitz `Type` in an extracted module.

Blitz3D compiles each `Type` into a BBObjType descriptor (see bbruntime/basic.h):

    int type;              // BBTYPE_OBJ (5)
    BBObj used, free;      // two 20-byte list heads
    int fieldCnt;
    BBType *fieldTypes[];  // __bbIntType / __bbFltType / __bbStrType / other _t* / vector

Field names are not preserved, but the field *kinds* are, which is enough to
tell an int counter from a float or an object handle when reading the decompiled
code. Requires module.bin (relocated), symbols.txt and runtime_syms.txt produced
by extract_blitz_module.py.
"""
from __future__ import annotations

import argparse
import logging
import struct
from pathlib import Path

LOG = logging.getLogger("dump_types")

BBTYPE_OBJ = 5
BBTYPE_VEC = 6
HEADER_FIELDCNT = 4 + 20 + 20  # type + used + free


def load_syms(path: Path) -> dict[int, str]:
    out: dict[int, str] = {}
    with path.open() as fh:
        for line in fh:
            addr, name = line.split()
            out[int(addr, 16)] = name
    return out


def describe(addr: int, names: dict[int, str], mod: bytes, base: int) -> str:
    name = names.get(addr)
    if name in ("__bbIntType", "__bbFltType", "__bbStrType", "__bbCStrType"):
        return name[4:-4].lower()
    # Vector (Blitz `Field x[N]`) descriptors have no symbol of their own; the
    # linker only emits a numeric label (`_NNN`) at that address. `size` is the
    # element count (Blitz `Field x[N]` compiles to N+1 elements).
    off = addr - base
    if 0 <= off + 12 <= len(mod):
        kind, size, elem = struct.unpack_from("<iii", mod, off)
        if kind == BBTYPE_VEC:
            return f"vec[{size}] of {describe(elem, names, mod, base)}"
    if name:
        return name
    return f"?0x{addr:08x}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("module_dir", type=Path, help="directory with module.bin/symbols.txt/runtime_syms.txt")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0x20000000)
    ap.add_argument("types", nargs="*", help="only these type names (default: all _t*)")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    mod = (args.module_dir / "module.bin").read_bytes()
    names = load_syms(args.module_dir / "symbols.txt")
    names.update(load_syms(args.module_dir / "runtime_syms.txt"))

    wanted = set(args.types)
    for addr in sorted(names):
        name = names[addr]
        if not name.startswith("_t") or (wanted and name not in wanted):
            continue
        off = addr - args.base
        if not (0 <= off + HEADER_FIELDCNT + 4 <= len(mod)):
            continue
        kind = struct.unpack_from("<i", mod, off)[0]
        if kind != BBTYPE_OBJ:
            LOG.debug("%s is not an object type (kind=%d)", name, kind)
            continue
        cnt = struct.unpack_from("<i", mod, off + HEADER_FIELDCNT)[0]
        if not (0 < cnt < 256):
            continue
        print(f"{name} ({cnt} fields)")
        for i in range(cnt):
            ptr = struct.unpack_from("<I", mod, off + HEADER_FIELDCNT + 4 + 4 * i)[0]
            print(f"  +0x{4 * i:02x} {describe(ptr, names, mod, args.base)}")


if __name__ == "__main__":
    main()
