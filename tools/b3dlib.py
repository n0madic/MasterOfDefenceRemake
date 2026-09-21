"""Parser for the Blitz3D B3D chunked format (BB3D/TEXS/BRUS/NODE/MESH/VRTS/TRIS/BONE/KEYS/ANIM).

Builds an in-memory tree with the same semantics as blitz3d/loader_b3d.cpp:

- textures carry `flags & 0xFFFF` (LoadTexture flags) and bit 0x10000 = use the second
  texture-coordinate set (lightmaps);
- brushes have rgba, shininess, blend (1 alpha, 2 multiply, 3 add) and fx bits
  (1 full-bright, 2 vertex colours, 4 flat shaded, 8 no fog, 16 no culling, 32 force alpha);
- a MESH may carry a mesh-level brush (applied to every surface) and each TRIS chunk has
  its own brush id (-1 = none);
- BONE chunks hold (vertex index, weight) pairs referring to the vertices of the nearest
  MESH ancestor; KEYS hold per-frame position/scale/rotation keys; ANIM gives the
  animation length in frames.

Nothing here converts coordinates; see blitzconv.py for that.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

Vec2 = tuple[float, float]
Vec3 = tuple[float, float, float]
Vec4 = tuple[float, float, float, float]

TEX_FLAG_ALPHA = 0x2
TEX_FLAG_MASKED = 0x4
TEX_FLAG_CLAMP_U = 0x10
TEX_FLAG_CLAMP_V = 0x20
TEX_FLAG_UV2 = 0x10000

BRUSH_BLEND_ALPHA = 1
BRUSH_BLEND_MULTIPLY = 2
BRUSH_BLEND_ADD = 3

FX_FULLBRIGHT = 1
FX_VERTEX_COLORS = 2
FX_FLAT_SHADED = 4
FX_NO_FOG = 8
FX_NO_CULLING = 16
FX_FORCE_ALPHA = 32

VRTS_HAS_NORMALS = 1
VRTS_HAS_COLORS = 2


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

    def f32s(self, n: int) -> tuple[float, ...]:
        v = struct.unpack_from(f"<{n}f", self.d, self.p)
        self.p += 4 * n
        return v

    def cstr(self) -> str:
        e = self.d.index(b"\0", self.p)
        s = self.d[self.p : e].decode("cp1251", "replace")
        self.p = e + 1
        return s


@dataclass
class Texture:
    name: str
    flags: int
    blend: int
    pos: Vec2
    scale: Vec2
    rot: float

    @property
    def uses_uv2(self) -> bool:
        return bool(self.flags & TEX_FLAG_UV2)

    @property
    def has_alpha(self) -> bool:
        return bool(self.flags & TEX_FLAG_ALPHA)

    @property
    def is_masked(self) -> bool:
        return bool(self.flags & TEX_FLAG_MASKED)


@dataclass
class Brush:
    name: str
    rgba: Vec4
    shininess: float
    blend: int
    fx: int
    textures: list[int]  # texture indices per layer, -1 = none

    @property
    def layers(self) -> list[int]:
        return [t for t in self.textures if t >= 0]

    def is_blended(self, textures: list["Texture"]) -> bool:
        """Whether Blitz alpha-blends this brush (`Brush::getBlend` != BLEND_REPLACE):
        blend ADD/MULTIPLY, an ALPHA (not MASKED) layer, force alpha (fx 32) or brush
        alpha < 1. Only then do the vertex alphas of an `EntityFX 2` mesh reach the
        screen (D3D takes the diffuse alpha from the vertex colour, D3DMCS_COLOR1)."""
        layers = [textures[t] for t in self.layers]
        if self.blend in (BRUSH_BLEND_MULTIPLY, BRUSH_BLEND_ADD):
            return True
        if self.blend == BRUSH_BLEND_ALPHA:
            if any(t.has_alpha and not t.is_masked for t in layers):
                return True
        elif len(layers) == 1 and layers[0].has_alpha and not layers[0].is_masked:
            return True
        return bool(self.fx & FX_FORCE_ALPHA) or self.rgba[3] < 1.0

    def uses_vertex_alpha(self, textures: list["Texture"]) -> bool:
        return bool(self.fx & FX_VERTEX_COLORS) and self.is_blended(textures)


@dataclass
class Vertex:
    pos: Vec3
    normal: Vec3 | None
    color: Vec4 | None
    uv: list[tuple[float, ...]]


@dataclass
class TriangleSet:
    brush: int
    indices: list[tuple[int, int, int]]


@dataclass
class Mesh:
    brush: int
    flags: int = 0
    tc_sets: int = 0
    tc_size: int = 0
    verts: list[Vertex] = field(default_factory=list)
    tri_sets: list[TriangleSet] = field(default_factory=list)

    @property
    def has_normals(self) -> bool:
        return bool(self.flags & VRTS_HAS_NORMALS)

    @property
    def has_colors(self) -> bool:
        return bool(self.flags & VRTS_HAS_COLORS)

    @property
    def tri_count(self) -> int:
        return sum(len(t.indices) for t in self.tri_sets)

    @property
    def brush_ids(self) -> list[int]:
        return sorted({t.brush for t in self.tri_sets})


@dataclass
class Anim:
    flags: int
    frames: int
    fps: float


@dataclass
class Node:
    name: str
    pos: Vec3
    scale: Vec3
    rot: Vec4  # (w, x, y, z)
    mesh: Mesh | None = None
    bone: list[tuple[int, float]] | None = None
    keys: dict[int, dict[str, tuple[float, ...]]] = field(default_factory=dict)
    keys_flags: int = 0
    anim: Anim | None = None
    children: list["Node"] = field(default_factory=list)
    parent: "Node | None" = field(default=None, repr=False)

    @property
    def has_keys(self) -> bool:
        return bool(self.keys)

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()

    def find(self, name: str) -> "Node | None":
        for n in self.walk():
            if n.name == name:
                return n
        return None

    def mesh_ancestor(self) -> "Node | None":
        n = self.parent
        while n is not None:
            if n.mesh is not None:
                return n
            n = n.parent
        return None


@dataclass
class B3DFile:
    version: int
    textures: list[Texture]
    brushes: list[Brush]
    root: Node
    path: Path | None = None

    def nodes(self):
        return list(self.root.walk())

    @property
    def anim_frames(self) -> int:
        """Animation length: the longest ANIM chunk in the file (0 when there is none)."""
        return max((n.anim.frames for n in self.root.walk() if n.anim), default=0)


def _parse_vertices(r: Reader, end: int, mesh: Mesh) -> None:
    mesh.flags, mesh.tc_sets, mesh.tc_size = r.i32(), r.i32(), r.i32()
    while r.p < end:
        pos = r.f32s(3)
        normal = r.f32s(3) if mesh.flags & VRTS_HAS_NORMALS else None
        color = None
        if mesh.flags & VRTS_HAS_COLORS:
            color = tuple(min(1.0, max(0.0, c)) for c in r.f32s(4))
        uv = [r.f32s(mesh.tc_size) for _ in range(mesh.tc_sets)]
        mesh.verts.append(Vertex(pos, normal, color, uv))


def _parse_mesh(r: Reader, end: int) -> Mesh:
    mesh = Mesh(brush=r.i32())
    while r.p < end:
        tag = r.tag()
        size = r.i32()
        cend = r.p + size
        if tag == "VRTS":
            _parse_vertices(r, cend, mesh)
        elif tag == "TRIS":
            brush = r.i32()
            n = (cend - r.p) // 12
            idx = [struct.unpack_from("<3i", r.d, r.p + 12 * i) for i in range(n)]
            mesh.tri_sets.append(TriangleSet(brush, idx))
        r.p = cend
    return mesh


def _parse_node(r: Reader, end: int, parent: Node | None) -> Node:
    name = r.cstr()
    pos = r.f32s(3)
    scl = r.f32s(3)
    rot = r.f32s(4)
    node = Node(name, pos, scl, rot, parent=parent)
    while r.p < end:
        tag = r.tag()
        size = r.i32()
        cend = r.p + size
        if tag == "MESH":
            node.mesh = _parse_mesh(r, cend)
        elif tag == "BONE":
            n = (cend - r.p) // 8
            node.bone = [struct.unpack_from("<if", r.d, r.p + 8 * i) for i in range(n)]
        elif tag == "KEYS":
            flags = r.i32()
            node.keys_flags |= flags
            while r.p < cend:
                frame = r.i32()
                rec = node.keys.setdefault(frame, {})
                if flags & 1:
                    rec["pos"] = r.f32s(3)
                if flags & 2:
                    rec["scale"] = r.f32s(3)
                if flags & 4:
                    rec["rot"] = r.f32s(4)
        elif tag == "ANIM":
            node.anim = Anim(r.i32(), r.i32(), r.f32())
        elif tag == "NODE":
            node.children.append(_parse_node(r, cend, node))
        r.p = cend
    return node


def parse(data: bytes, path: Path | None = None) -> B3DFile:
    r = Reader(data)
    tag = r.tag()
    if tag != "BB3D":
        raise ValueError(f"not a B3D file: {path}")
    size = r.i32()
    end = r.p + size
    version = r.i32()
    textures: list[Texture] = []
    brushes: list[Brush] = []
    root: Node | None = None
    while r.p < end:
        tag = r.tag()
        size = r.i32()
        cend = r.p + size
        if tag == "TEXS":
            while r.p < cend:
                name = r.cstr()
                flags, blend = r.i32(), r.i32()
                tpos = r.f32s(2)
                tscale = r.f32s(2)
                trot = r.f32()
                textures.append(Texture(name, flags, blend, tpos, tscale, trot))
        elif tag == "BRUS":
            n_tex = r.i32()
            while r.p < cend:
                name = r.cstr()
                rgba = r.f32s(4)
                shin = r.f32()
                blend, fx = r.i32(), r.i32()
                texs = [r.i32() for _ in range(n_tex)]
                brushes.append(Brush(name, rgba, shin, blend, fx, texs))
        elif tag == "NODE":
            root = _parse_node(r, cend, None)
        r.p = cend
    if root is None:
        raise ValueError(f"no NODE chunk in {path}")
    return B3DFile(version, textures, brushes, root, path)


def load(path: Path) -> B3DFile:
    return parse(Path(path).read_bytes(), Path(path))


# --- B3D Extensions naming conventions (_fext_loadentity) ---------------------------------

ORDER_PREFIX = "B3D_ORDR_"
BILLBOARD_PREFIX = "B3D_BB_1_"
EXT_TAGS = ("B3DEXT_BGCOLOR", "B3DEXT_AMBIENT", "B3DEXT_DIRLIGHT", "B3DEXT_CAMERA")


def clean_name(name: str) -> tuple[str, dict]:
    """Strip `B3D_ORDR_<n>_` / `B3D_BB_1_` prefixes; return (clean name, extra attributes)."""
    attrs: dict = {}
    changed = True
    while changed:
        changed = False
        if name.startswith(ORDER_PREFIX):
            rest = name[len(ORDER_PREFIX):]
            num, _, tail = rest.partition("_")
            attrs["order"] = int(num)
            name = tail
            changed = True
        if name.startswith(BILLBOARD_PREFIX):
            attrs["billboard"] = True
            name = name[len(BILLBOARD_PREFIX):]
            changed = True
    return name, attrs
