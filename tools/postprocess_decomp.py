#!/usr/bin/env python3
"""Make Ghidra output of a Blitz3D module readable.

- FUN_<addr> calls into the runtime are renamed using runtime_syms.txt.
- References to module labels that hold C strings are replaced by the literal.
- Blitz string ops (__bbStrConst etc.) keep their names so the code reads like BASIC.
"""
from __future__ import annotations

import argparse
import logging
import re
import struct
from pathlib import Path

LOG = logging.getLogger("postprocess_decomp")


def load_syms(path: Path) -> dict[str, int]:
    out = {}
    for line in path.read_text().splitlines():
        a, n = line.split()
        out[n] = int(a, 16)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("module_dir", type=Path)
    ap.add_argument("decomp_dir", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0x20000000)
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    code = (args.module_dir / "module.bin").read_bytes()
    runtime = load_syms(args.module_dir / "runtime_syms.txt")
    fun_names = {f"FUN_{addr:08x}": name for name, addr in runtime.items()}
    module = load_syms(args.module_dir / "symbols.txt")

    strings: dict[str, str] = {}
    for name, addr in module.items():
        off = addr - args.base
        end = code.find(b"\0", off)
        if end < 0 or end - off > 400:
            continue
        raw = code[off:end]
        if all(32 <= b < 127 or b in (9, 10, 13) or b >= 128 for b in raw):
            try:
                strings[name] = raw.decode("cp1251")
            except UnicodeDecodeError:
                continue

    args.out_dir.mkdir(parents=True, exist_ok=True)
    fun_re = re.compile(r"FUN_1[0-9a-f]{7}")
    lab_re = re.compile(r"&?\b(_[0-9]+)\b")
    hex_re = re.compile(r"\b0x([0-9a-f]{8})\b")

    def hex_float(m: re.Match) -> str:
        v = struct.unpack("<f", struct.pack("<I", int(m.group(1), 16)))[0]
        if v != 0 and 1e-4 < abs(v) < 1e7:
            return f"{m.group(0)}/*={v:g}f*/"
        return m.group(0)
    n = 0
    for src in sorted(args.decomp_dir.glob("*.c")):
        text = src.read_text()
        text = fun_re.sub(lambda m: fun_names.get(m.group(0), m.group(0)), text)

        def repl(m: re.Match) -> str:
            s = strings.get(m.group(1))
            if s is None:
                return m.group(0)
            return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

        text = lab_re.sub(repl, text)
        text = hex_re.sub(hex_float, text)
        (args.out_dir / src.name).write_text(text)
        n += 1
    LOG.info("processed %d files, %d string labels, %d runtime names", n, len(strings), len(fun_names))


if __name__ == "__main__":
    main()
