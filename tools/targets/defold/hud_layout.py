"""Wide-screen anchors of the HUD's 3D panel (the Godot port's `HudLayout.gd`): the 800x600
box stays centred in the canvas, but every floating group keeps its corner or edge of the
window. Each vertex gets an anchor (-1 / 0 / 1 per axis: left / top edge, centred with the
box, right / bottom edge; fractions blend), written to the glb as `TEXCOORD_1`; the vertex
shader shifts it by the render script's `hud_shift` (MaterialVariant.anchored).

A rule is an anchor for all of a node's vertices, or a dict with piecewise-linear rules per
axis: `"u"` / `"v"` (texture coordinates) or `"x"` (local x) map to `(t_a, t_b, anchor_a,
anchor_b)` -- below `t_a` the vertex takes `anchor_a`, above `t_b` `anchor_b`, in between it
blends, so the strip between the thresholds stretches; `"ax"` / `"ay"` set a constant anchor
for an axis. The mesh is cut along the thresholds so the blend is exact; triangles keep their
file order and winding."""
from __future__ import annotations

from typing import Callable, Union

Anchor = tuple[float, float]
Rule = Union[Anchor, dict]

TOP_LEFT: Anchor = (-1.0, -1.0)
TOP_CENTRE: Anchor = (0.0, -1.0)
TOP_RIGHT: Anchor = (1.0, -1.0)
BOTTOM_CENTRE: Anchor = (0.0, 1.0)
CENTRE: Anchor = (0.0, 0.0)

# `Env`: the planks and icons of the panel. The plain planks (`wood.png`) run between a post
# and the info panel and stretch; `Plane10` holds both posts in one mesh.
ENV_RULES: dict[str, Rule] = {
    "leftUp": TOP_LEFT, "goldIcon": TOP_LEFT, "gold": TOP_LEFT, "expa": TOP_LEFT, "expaIcon": TOP_LEFT,
    "rightUp": TOP_RIGHT, "inhabsIcon": TOP_RIGHT, "inhabs": TOP_RIGHT,
    "raids": TOP_CENTRE,
    "infopanel": BOTTOM_CENTRE, "reset": BOTTOM_CENTRE, "beguny": BOTTOM_CENTRE,
    "leftside": {"u": (0.0, 1.0, -1.0, 0.0), "ay": 1.0},
    "rightside": {"u": (0.0, 1.0, 0.0, 1.0), "ay": 1.0},
    "Plane10": {"x": (-0.5, 0.5, -1.0, 1.0), "ay": 1.0},
}
# `faces`: the portrait inside the info panel.
FACES_RULES: dict[str, Rule] = {"Plane13": BOTTOM_CENTRE}
# `tutorial`: pointer lines cut from `Lines.png`. The labelled ones sit next to their target
# and move with it; the L-shaped ones hang from the (centred) sheet down to the bottom panel:
# the strip holding only the horizontal / vertical line stretches while the drops onto the
# buttons stay rigid.
TUTORIAL_RULES: dict[str, Rule] = {
    "gold": TOP_LEFT, "expa": TOP_LEFT, "people": TOP_RIGHT,
    "speed": BOTTOM_CENTRE,
    "create": {"u": (0.25, 0.32, -1.0, 0.0), "v": (0.60, 0.70, 0.0, 1.0)},
    "upgrade": {"u": (0.71, 0.84, 0.0, 1.0), "v": (0.60, 0.66, 0.0, 1.0)},
    "delete": {"u": (0.86, 0.94, 0.0, 1.0), "v": (0.60, 0.615, 0.0, 1.0)},
    "updExpa": {"v": (0.60, 0.70, 0.0, 1.0)},
}
# Model key -> rules.
MODEL_RULES: dict[str, dict[str, Rule]] = {"Env": ENV_RULES, "faces": FACES_RULES, "tutorial": TUTORIAL_RULES}

# A vertex: attribute name (glTF, e.g. POSITION, TEXCOORD_0) -> tuple of floats.
Vertex = dict[str, tuple[float, ...]]

AXIS_KEYS: dict[str, Callable[[Vertex], float]] = {
    "u": lambda v: v["TEXCOORD_0"][0],
    "v": lambda v: v["TEXCOORD_0"][1],
    "x": lambda v: v["POSITION"][0],
}


def _blend(r: tuple[float, float, float, float], t: float) -> float:
    if t <= r[0]:
        return r[2]
    if t >= r[1]:
        return r[3]
    return r[2] + (r[3] - r[2]) * (t - r[0]) / (r[1] - r[0])


def anchor_of(rule: Rule, v: Vertex) -> Anchor:
    if isinstance(rule, tuple):
        return rule
    ax, ay = float(rule.get("ax", 0.0)), float(rule.get("ay", 0.0))
    if "u" in rule:
        ax = _blend(rule["u"], AXIS_KEYS["u"](v))
    if "x" in rule:
        ax = _blend(rule["x"], AXIS_KEYS["x"](v))
    if "v" in rule:
        ay = _blend(rule["v"], AXIS_KEYS["v"](v))
    return (ax, ay)


def cuts(rule: Rule) -> list[tuple[Callable[[Vertex], float], float]]:
    """The cut lines a rule needs: (key, threshold) pairs."""
    if isinstance(rule, tuple):
        return []
    return [(AXIS_KEYS[k], float(rule[k][i])) for k in AXIS_KEYS if k in rule for i in (0, 1)]


def _lerp_vertex(a: Vertex, b: Vertex, t: float) -> Vertex:
    out = {name: tuple(x + (y - x) * t for x, y in zip(a[name], b[name])) for name in a}
    if "NORMAL" in out:
        n = out["NORMAL"]
        length = sum(c * c for c in n) ** 0.5 or 1.0
        out["NORMAL"] = tuple(c / length for c in n)
    return out


def clip(tris: list[list[Vertex]], key: Callable[[Vertex], float], c: float) -> list[list[Vertex]]:
    """Cut every triangle along `key(v) == c` (Sutherland-Hodgman against both half-planes);
    a triangle entirely on one side comes back unchanged."""
    out = []
    for tri in tris:
        for keep_below in (True, False):
            poly = []
            for i in range(3):
                a, b = tri[i], tri[(i + 1) % 3]
                fa, fb = key(a) - c, key(b) - c
                ina = fa <= 0.0 if keep_below else fa >= 0.0
                inb = fb <= 0.0 if keep_below else fb >= 0.0
                if ina:
                    poly.append(a)
                if ina != inb:
                    poly.append(_lerp_vertex(a, b, fa / (fa - fb)))
            out += [[poly[0], poly[k], poly[k + 1]] for k in range(1, len(poly) - 1)]
    return out


def anchor_mesh(attrs: dict[str, list], indices: list[int], rule: Rule | None) -> tuple[dict[str, list], list[int], list[Anchor]]:
    """A primitive's vertex attributes and indices cut along its rule's thresholds, with an
    anchor per vertex (the centre without a rule). Without cuts the mesh is unchanged."""
    count = len(attrs["POSITION"])
    if rule is None:
        return attrs, indices, [CENTRE] * count
    lines = cuts(rule)
    if not lines:
        verts = [{name: tuple(values[i]) for name, values in attrs.items()} for i in range(count)]
        return attrs, indices, [anchor_of(rule, v) for v in verts]
    tris = [[{name: tuple(values[i]) for name, values in attrs.items()} for i in indices[t:t + 3]]
            for t in range(0, len(indices) - 2, 3)]
    for key, c in lines:
        tris = clip(tris, key, c)
    verts = [v for tri in tris for v in tri]
    out = {name: [v[name] for v in verts] for name in attrs}
    return out, list(range(len(verts))), [anchor_of(rule, v) for v in verts]
