#!/usr/bin/env python3
"""Extract the compiled Blitz3D program module from a Blitz3D executable.

Blitz3D stores the user program as RCDATA resource 1111 with this layout
(see blitz-research/blitz3d linker/linker.cpp, BBModule::createExe):

    int32 code_size; uint8 code[code_size];
    int32 num_syms;  { cstring name; int32 offset; } * num_syms
    int32 num_rels;  { cstring symbol; int32 offset; } * num_rels   (pc-relative)
    int32 num_abss;  { cstring symbol; int32 offset; } * num_abss   (absolute)

Runtime symbols (_bb*, _f<command>) are resolved against the exe's export table.
Outputs a relocated code blob plus a symbol map for loading into Ghidra.
"""
from __future__ import annotations

import argparse
import logging
import struct
import sys
from pathlib import Path

import pefile

LOG = logging.getLogger("extract_blitz_module")
RES_TYPE_RCDATA = 10
RES_ID_MODULE = 1111


def read_cstr(buf: bytes, pos: int) -> tuple[str, int]:
    end = buf.index(b"\0", pos)
    return buf[pos:end].decode("latin-1"), end + 1


def read_table(buf: bytes, pos: int) -> tuple[list[tuple[str, int]], int]:
    (n,) = struct.unpack_from("<i", buf, pos)
    pos += 4
    out = []
    for _ in range(n):
        name, pos = read_cstr(buf, pos)
        (val,) = struct.unpack_from("<i", buf, pos)
        pos += 4
        out.append((name, val))
    return out, pos


def find_module_resource(pe: pefile.PE) -> bytes:
    for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if t.id != RES_TYPE_RCDATA:
            continue
        for e in t.directory.entries:
            if e.id != RES_ID_MODULE:
                continue
            lang = e.directory.entries[0]
            rva, size = lang.data.struct.OffsetToData, lang.data.struct.Size
            return pe.get_data(rva, size)
    raise SystemExit("RCDATA/1111 resource not found: not a Blitz3D executable?")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("exe", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0x20000000)
    ap.add_argument("--runtime-syms", type=Path, help="'addr name' lines from find_runtime_syms.py")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    pe = pefile.PE(str(args.exe))
    image_base = pe.OPTIONAL_HEADER.ImageBase
    exports = {
        e.name.decode(): image_base + e.address
        for e in pe.DIRECTORY_ENTRY_EXPORT.symbols
        if e.name
    }
    if args.runtime_syms:
        for line in args.runtime_syms.read_text().splitlines():
            addr, name = line.split()
            exports.setdefault(name, int(addr, 16))
    LOG.info("runtime symbols available: %d", len(exports))

    blob = find_module_resource(pe)
    (code_size,) = struct.unpack_from("<i", blob, 0)
    code = bytearray(blob[4 : 4 + code_size])
    pos = 4 + code_size
    syms, pos = read_table(blob, pos)
    rels, pos = read_table(blob, pos)
    abss, pos = read_table(blob, pos)
    LOG.info("code=%d bytes, symbols=%d, rel relocs=%d, abs relocs=%d", code_size, len(syms), len(rels), len(abss))

    base = args.base
    local = {name: base + off for name, off in syms}
    missing: set[str] = set()

    def resolve(name: str) -> int | None:
        if name in local:
            return local[name]
        if name in exports:
            return exports[name]
        missing.add(name)
        return None

    for name, off in rels:
        dest = resolve(name)
        if dest is None:
            continue
        p = base + off
        (v,) = struct.unpack_from("<i", code, off)
        struct.pack_into("<i", code, off, v + (dest - p))
    for name, off in abss:
        dest = resolve(name)
        if dest is None:
            continue
        (v,) = struct.unpack_from("<i", code, off)
        struct.pack_into("<i", code, off, v + dest)
    if missing:
        LOG.warning("unresolved symbols (%d): %s", len(missing), sorted(missing)[:20])

    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "module.bin").write_bytes(code)
    with open(args.out_dir / "symbols.txt", "w") as f:
        for name, off in sorted(syms, key=lambda s: s[1]):
            f.write(f"{base + off:08x} {name}\n")
    # Absolute-reloc targets that are data (strings, globals) — useful to know what a code site references.
    with open(args.out_dir / "relocs.txt", "w") as f:
        for name, off in sorted(rels, key=lambda s: s[1]):
            f.write(f"rel {base + off:08x} {name}\n")
        for name, off in sorted(abss, key=lambda s: s[1]):
            f.write(f"abs {base + off:08x} {name}\n")
    LOG.info("written to %s (base 0x%x)", args.out_dir, base)


if __name__ == "__main__":
    main()
