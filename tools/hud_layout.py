#!/usr/bin/env python3
"""Project the quads of Data/Env.b3d (the in-game HUD panel) to 800x600 screen space.

The game parents Env.b3d to the main camera translated 10 units forward
(`_floadgraphics`); the camera has a 60 degree horizontal FOV
(`_fsetfov` -> CameraZoom 1/tan 30). Every HUD element is a textured quad, so
its screen rectangle follows from its world-space vertices:

    half_w = z / zoom,  half_h = half_w * 600 / 800
    sx = 400 * (1 + x / half_w),  sy = 300 * (1 - y / half_h)

Quaternion math mirrors blitz3d/geom.h (note the reversed cross product in
Quat*Quat) so that node rotations are applied exactly like the engine does.
"""
from __future__ import annotations

import argparse
import json
import logging
import math
import struct
from dataclasses import dataclass, field
from pathlib import Path

LOG = logging.getLogger("hud_layout")

VIRTUAL_W, VIRTUAL_H = 800.0, 600.0
CAMERA_OFFSET_Z = 10.0
FOV_DEG = 60.0

Vec = tuple[float, float, float]


def v_add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_mul(a: Vec, b: Vec) -> Vec:
    return (a[0] * b[0], a[1] * b[1], a[2] * b[2])


def v_scale(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s, a[2] * s)


def v_dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


@dataclass(frozen=True)
class Quat:
    w: float
    v: Vec

    def __mul__(self, q: "Quat") -> "Quat":
        # blitz3d geom.h: Quat(w*q.w-v.dot(q.v), q.v.cross(v)+q.v*w+v*q.w)
        return Quat(
            self.w * q.w - v_dot(self.v, q.v),
            v_add(v_add(v_cross(q.v, self.v), v_scale(q.v, self.w)), v_scale(self.v, q.w)),
        )

    def conj(self) -> "Quat":
        return Quat(self.w, v_scale(self.v, -1.0))

    def rotate(self, p: Vec) -> Vec:
        return (self * Quat(0.0, p) * self.conj()).v


@dataclass
class Node:
    name: str
    pos: Vec
    scale: Vec
    rot: Quat
    verts: list[Vec] = field(default_factory=list)
    children: list["Node"] = field(default_factory=list)


class Reader:
    def __init__(self, data: bytes):
        self.d = data
        self.p = 0

    def tag(self) -> str:
        t = self.d[self.p : self.p + 4].decode("latin-1")
        self.p += 4
        return t

    def i32(self) -> int:
        (v,) = struct.unpack_from("<i", self.d, self.p)
        self.p += 4
        return v

    def f32(self) -> float:
        (v,) = struct.unpack_from("<f", self.d, self.p)
        self.p += 4
        return v

    def cstr(self) -> str:
        e = self.d.index(b"\0", self.p)
        s = self.d[self.p : e].decode("cp1251", "replace")
        self.p = e + 1
        return s


def parse_node(r: Reader, end: int) -> Node:
    name = r.cstr()
    pos = (r.f32(), r.f32(), r.f32())
    scl = (r.f32(), r.f32(), r.f32())
    rot = Quat(r.f32(), (r.f32(), r.f32(), r.f32()))
    node = Node(name, pos, scl, rot)
    while r.p < end:
        tag = r.tag()
        size = r.i32()
        cend = r.p + size
        if tag == "NODE":
            node.children.append(parse_node(r, cend))
        elif tag == "MESH":
            r.i32()  # brush
            while r.p < cend:
                sub = r.tag()
                ssize = r.i32()
                send = r.p + ssize
                if sub == "VRTS":
                    flags, tc_sets, tc_size = r.i32(), r.i32(), r.i32()
                    per = 3 + (3 if flags & 1 else 0) + (4 if flags & 2 else 0) + tc_sets * tc_size
                    while r.p < send:
                        node.verts.append((r.f32(), r.f32(), r.f32()))
                        r.p += 4 * (per - 3)
                r.p = send
        r.p = cend
    return node


def parse_file(data: bytes) -> Node:
    r = Reader(data)
    assert r.tag() == "BB3D"
    end = r.p + r.i32()
    r.i32()  # version
    while r.p < end:
        tag = r.tag()
        size = r.i32()
        cend = r.p + size
        if tag == "NODE":
            return parse_node(r, cend)
        r.p = cend
    raise ValueError("no root NODE chunk")


def world_quads(node: Node, parent_pos: Vec, parent_rot: Quat, parent_scale: Vec, out: dict[str, list[Vec]]) -> None:
    pos = v_add(parent_pos, parent_rot.rotate(v_mul(parent_scale, node.pos)))
    rot = parent_rot * node.rot
    scale = v_mul(parent_scale, node.scale)
    if node.verts:
        out[node.name] = [v_add(pos, rot.rotate(v_mul(scale, v))) for v in node.verts]
    for child in node.children:
        world_quads(child, pos, rot, scale, out)


def project(p: Vec, zoom: float) -> tuple[float, float]:
    z = p[2] + CAMERA_OFFSET_Z
    half_w = z / zoom
    half_h = half_w * VIRTUAL_H / VIRTUAL_W
    return (VIRTUAL_W / 2 * (1 + p[0] / half_w), VIRTUAL_H / 2 * (1 - p[1] / half_h))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("b3d", type=Path)
    ap.add_argument("--json", type=Path, help="write rectangles as JSON")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    root = parse_file(args.b3d.read_bytes())
    quads: dict[str, list[Vec]] = {}
    world_quads(root, (0.0, 0.0, 0.0), Quat(1.0, (0.0, 0.0, 0.0)), (1.0, 1.0, 1.0), quads)
    zoom = 1.0 / math.tan(math.radians(FOV_DEG / 2))

    result: dict[str, dict[str, float]] = {}
    print(f"{'node':12} {'x':>6} {'y':>6} {'w':>6} {'h':>6}   depth")
    for name, verts in quads.items():
        pts = [project(v, zoom) for v in verts]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        depth = sum(v[2] for v in verts) / len(verts) + CAMERA_OFFSET_Z
        rect = {"x": min(xs), "y": min(ys), "w": max(xs) - min(xs), "h": max(ys) - min(ys), "depth": depth}
        result[name] = {k: round(v, 1) for k, v in rect.items()}
        print(f"{name:12} {rect['x']:6.1f} {rect['y']:6.1f} {rect['w']:6.1f} {rect['h']:6.1f}   {depth:.2f}")
    if args.json:
        args.json.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n")
        LOG.info("wrote %s", args.json)


if __name__ == "__main__":
    main()
