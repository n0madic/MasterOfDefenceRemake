#!/usr/bin/env python3
"""Recover Blitz3D runtime symbol addresses from a Blitz3D executable.

The runtime registers commands with rtSym("<decl string>", func), compiled as
`push func; push decl_string; call ...`. This scans .text for that pattern and
derives the linker symbol name exactly like bbruntime_dll.cpp::link() does:
'_'-prefixed names get one more '_', others become "_f" + lowercased identifier.
"""
from __future__ import annotations

import argparse
import logging
import struct
from pathlib import Path

import pefile

LOG = logging.getLogger("find_runtime_syms")


def link_name(decl: str) -> str:
    t = decl
    if t[0] == "_":
        return "_" + t
    if t[0] == "!":
        t = t[1:]
    if not t[0].isalnum():
        t = t[1:]
    for k, c in enumerate(t):
        if not (c.isalnum() or c == "_"):
            t = t[:k]
            break
    return "_f" + t.lower()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("exe", type=Path)
    ap.add_argument("out", type=Path)
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    pe = pefile.PE(str(args.exe))
    base = pe.OPTIONAL_HEADER.ImageBase
    text = next(s for s in pe.sections if s.Name.startswith(b".text"))
    text_lo, text_hi = base + text.VirtualAddress, base + text.VirtualAddress + text.Misc_VirtualSize
    img_lo, img_hi = base, base + pe.OPTIONAL_HEADER.SizeOfImage
    data = text.get_data()
    found: dict[str, int] = {}
    i = 0
    while i < len(data) - 10:
        if data[i] == 0x68 and data[i + 5] == 0x68:
            func = struct.unpack_from("<I", data, i + 1)[0]
            sptr = struct.unpack_from("<I", data, i + 6)[0]
            if img_lo <= func < img_hi and img_lo <= sptr < img_hi:
                try:
                    raw = pe.get_data(sptr - base, 256)
                except pefile.PEFormatError:
                    i += 1
                    continue
                s = raw.split(b"\0", 1)[0].decode("latin-1", "replace")
                if s and all(32 <= ord(c) < 127 for c in s):
                    name = link_name(s)
                    found.setdefault(name, func)
        i += 1
    LOG.info("found %d runtime symbols", len(found))
    with open(args.out, "w") as f:
        for name, addr in sorted(found.items(), key=lambda kv: kv[1]):
            f.write(f"{addr:08x} {name}\n")


if __name__ == "__main__":
    main()
