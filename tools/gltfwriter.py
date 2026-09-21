"""Minimal glTF 2.0 binary (.glb) writer: buffers, accessors, meshes with morph targets,
materials, textures with external image URIs, node hierarchy, skins and animations.

No external dependencies. Only what b3d2gltf.py / md2togltf.py need.
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

GLB_MAGIC = 0x46546C67
GLB_VERSION = 2
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

COMPONENT_FLOAT = 5126
COMPONENT_UBYTE = 5121
COMPONENT_USHORT = 5123
COMPONENT_UINT = 5125

TARGET_ARRAY_BUFFER = 34962
TARGET_ELEMENT_ARRAY_BUFFER = 34963

ELEMENT_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
COMPONENT_SIZES = {COMPONENT_FLOAT: 4, COMPONENT_UBYTE: 1, COMPONENT_USHORT: 2, COMPONENT_UINT: 4}
COMPONENT_FORMATS = {COMPONENT_FLOAT: "f", COMPONENT_UBYTE: "B", COMPONENT_USHORT: "H", COMPONENT_UINT: "I"}


def _pad(data: bytearray, alignment: int, fill: bytes = b"\0") -> None:
    while len(data) % alignment:
        data.extend(fill)


class GltfBuilder:
    def __init__(self, generator: str = "MasterOfDefence tools"):
        self.bin = bytearray()
        self.buffer_views: list[dict] = []
        self.accessors: list[dict] = []
        self.meshes: list[dict] = []
        self.materials: list[dict] = []
        self.textures: list[dict] = []
        self.images: list[dict] = []
        self.samplers: list[dict] = []
        self.nodes: list[dict] = []
        self.skins: list[dict] = []
        self.animations: list[dict] = []
        self.extensions_used: set[str] = set()
        self.generator = generator
        self._image_index: dict[str, int] = {}
        self._texture_index: dict[tuple[str, int], int] = {}

    # --- binary data -------------------------------------------------------------------

    def add_buffer_view(self, data: bytes, target: int | None = None, byte_stride: int | None = None) -> int:
        _pad(self.bin, 4)
        view = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        if byte_stride is not None:
            view["byteStride"] = byte_stride
        self.bin.extend(data)
        self.buffer_views.append(view)
        return len(self.buffer_views) - 1

    def add_accessor(self, values: list, element: str, component: int = COMPONENT_FLOAT,
                     target: int | None = None, minmax: bool = False, normalized: bool = False) -> int:
        n = ELEMENT_COUNTS[element]
        fmt = COMPONENT_FORMATS[component]
        flat: list = []
        if n == 1:
            flat = list(values)
        else:
            for v in values:
                flat.extend(v)
        data = struct.pack(f"<{len(flat)}{fmt}", *flat)
        view = self.add_buffer_view(data, target)
        acc = {"bufferView": view, "componentType": component, "count": len(values), "type": element}
        if normalized:
            acc["normalized"] = True
        if minmax and values:
            if n == 1:
                acc["min"] = [min(values)]
                acc["max"] = [max(values)]
            else:
                acc["min"] = [min(v[i] for v in values) for i in range(n)]
                acc["max"] = [max(v[i] for v in values) for i in range(n)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    # --- materials / textures ----------------------------------------------------------

    def add_image(self, uri: str) -> int:
        if uri in self._image_index:
            return self._image_index[uri]
        self.images.append({"uri": uri})
        idx = len(self.images) - 1
        self._image_index[uri] = idx
        return idx

    def add_texture(self, uri: str, sampler: int = 0) -> int:
        key = (uri, sampler)
        if key in self._texture_index:
            return self._texture_index[key]
        if not self.samplers:
            self.samplers.append({"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497})
        self.textures.append({"sampler": sampler, "source": self.add_image(uri)})
        idx = len(self.textures) - 1
        self._texture_index[key] = idx
        return idx

    def add_material(self, material: dict) -> int:
        self.materials.append(material)
        return len(self.materials) - 1

    # --- scene ---------------------------------------------------------------------------

    def add_mesh(self, mesh: dict) -> int:
        self.meshes.append(mesh)
        return len(self.meshes) - 1

    def add_node(self, node: dict) -> int:
        self.nodes.append(node)
        return len(self.nodes) - 1

    def add_skin(self, skin: dict) -> int:
        self.skins.append(skin)
        return len(self.skins) - 1

    def add_animation(self, animation: dict) -> int:
        self.animations.append(animation)
        return len(self.animations) - 1

    # --- output --------------------------------------------------------------------------

    def to_json(self, scene_roots: list[int]) -> dict:
        doc: dict = {
            "asset": {"version": "2.0", "generator": self.generator},
            "scene": 0,
            "scenes": [{"nodes": scene_roots}],
            "nodes": self.nodes,
        }
        if self.meshes:
            doc["meshes"] = self.meshes
        if self.materials:
            doc["materials"] = self.materials
        if self.textures:
            doc["textures"] = self.textures
            doc["images"] = self.images
            doc["samplers"] = self.samplers
        if self.skins:
            doc["skins"] = self.skins
        if self.animations:
            doc["animations"] = self.animations
        if self.accessors:
            doc["accessors"] = self.accessors
            doc["bufferViews"] = self.buffer_views
            _pad(self.bin, 4)
            doc["buffers"] = [{"byteLength": len(self.bin)}]
        if self.extensions_used:
            doc["extensionsUsed"] = sorted(self.extensions_used)
        return doc

    def write_glb(self, path: Path, scene_roots: list[int]) -> None:
        doc = self.to_json(scene_roots)
        json_bytes = bytearray(json.dumps(doc, separators=(",", ":")).encode("utf-8"))
        _pad(json_bytes, 4, b" ")
        bin_bytes = bytearray(self.bin)
        _pad(bin_bytes, 4)
        total = 12 + 8 + len(json_bytes) + (8 + len(bin_bytes) if bin_bytes else 0)
        out = bytearray()
        out.extend(struct.pack("<III", GLB_MAGIC, GLB_VERSION, total))
        out.extend(struct.pack("<II", len(json_bytes), CHUNK_JSON))
        out.extend(json_bytes)
        if bin_bytes:
            out.extend(struct.pack("<II", len(bin_bytes), CHUNK_BIN))
            out.extend(bin_bytes)
        Path(path).write_bytes(out)


def read_glb(path: Path) -> tuple[dict, bytes]:
    """Parse a .glb back into (json document, binary chunk) — used by tests."""
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError(f"not a glb: {path}")
    p = 12
    doc: dict = {}
    blob = b""
    while p < length:
        clen, ctype = struct.unpack_from("<II", data, p)
        p += 8
        chunk = data[p : p + clen]
        p += clen
        if ctype == CHUNK_JSON:
            doc = json.loads(chunk.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            blob = bytes(chunk)
    return doc, blob


def read_accessor(doc: dict, blob: bytes, index: int) -> list:
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    n = ELEMENT_COUNTS[acc["type"]]
    fmt = COMPONENT_FORMATS[acc["componentType"]]
    size = COMPONENT_SIZES[acc["componentType"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    flat = struct.unpack_from(f"<{count * n}{fmt}", blob, start)
    if n == 1:
        return list(flat)
    return [tuple(flat[i * n : (i + 1) * n]) for i in range(count)]
