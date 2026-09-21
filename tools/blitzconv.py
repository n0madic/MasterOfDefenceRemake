"""Blitz3D -> Godot coordinate conventions (convention C1 of the remake plan).

This is the single place on the Python side where handedness is converted; the GDScript
twin is `godot/src/autoload/Blitz.gd` (`Blitz.to_godot`, `Blitz.quat_to_godot`).

Blitz3D is left-handed (x right, y up, z into the screen); Godot is right-handed with
-z forward. Mirroring z keeps x/y as they are, so map coordinates in the docs stay
readable.

Winding (verified on the floor quads of Location1..3, whose stored normals are +y):
in the B3D data `cross(v1 - v0, v2 - v0)` equals the stored (outward) normal, i.e. the
numeric right-hand rule gives the front normal. After mirroring z the same index order
yields `(-nx, -ny, nz)` = the *inward* normal, which glTF (CCW front, right-hand rule)
would cull, so the indices **must be reordered** (`WINDING_SWAP = True`). With the swap
the recomputed normal equals the mirrored stored normal `(nx, ny, -nz)`.
"""
from __future__ import annotations

Vec3 = tuple[float, float, float]
Quat = tuple[float, float, float, float]  # (w, x, y, z)

# Whether triangle indices must be reordered on top of the z-mirror. Kept as a single
# switch so the answer can be verified once in the editor and never re-derived.
WINDING_SWAP = True


def blitz_to_godot(v: Vec3) -> Vec3:
    """Position/scale-free vector: (x, y, z) -> (x, y, -z)."""
    return (v[0], v[1], -v[2])


def blitz_scale_to_godot(v: Vec3) -> Vec3:
    """Scale is unaffected by the mirror."""
    return (v[0], v[1], v[2])


def blitz_quat_to_godot(q: Quat) -> Quat:
    """Quaternion (w, x, y, z) -> (w, x, y, -z).

    Blitz3D builds the rotation matrix from a quaternion transposed relative to the
    textbook formula (blitz3d/geom.h `Quat::i()/j()/k()` are the rows of the standard
    matrix, and `Matrix(q)` uses them as columns), so a file quaternion `q` rotates by the
    *inverse* of the standard interpretation: q_true = conj(q) = (w, -x, -y, -z).
    Conjugating that rotation by the z-mirror negates the x and y axis components, which
    gives (w, x, y, -z). Verified with the HUD scene `Env.b3d`: its quads are rotated
    (0.707, 0.707, 0, 0) and must face the camera.
    """
    w, x, y, z = q
    return (w, x, y, -z)


def md2_to_blitz(v: Vec3) -> Vec3:
    """Blitz3D's MD2 loader reads MD2 (x, y, z) as (y, z, x)."""
    return (v[1], v[2], v[0])


def md2_to_godot(v: Vec3) -> Vec3:
    return blitz_to_godot(md2_to_blitz(v))


def triangle_indices(tri: tuple[int, int, int]) -> tuple[int, int, int]:
    """Index order for a triangle after the mirror (see WINDING_SWAP)."""
    if WINDING_SWAP:
        return (tri[0], tri[2], tri[1])
    return tri


def srgb_to_linear(c: float) -> float:
    """Blitz3D (Direct3D 7) shades in gamma space; glTF colour factors and COLOR_0 are
    linear, so brush and vertex colours are linearised on export."""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


# Blitz adds `alpha * colour` to the frame buffer in gamma space; Godot adds in linear
# space, where the same alpha brightens dark backgrounds far more (0.2 over a 0.12 tree
# trunk: 0.32 in Blitz, 0.5 in Godot). alpha ** 1.5 matches the centre of a glow on dark
# backgrounds (0.36) and stays close on mid-grey ones; a fully linearised alpha would
# under-shoot both (0.24).
ADDITIVE_ALPHA_EXPONENT = 1.5


def blitz_color_to_gltf(rgba: tuple[float, ...], keep_alpha: bool = True, additive: bool = False) -> list[float]:
    """Linearise the RGB of a Blitz colour; the alpha is kept or forced to 1 (vertex
    colours of a brush Blitz draws without alpha blending, see `Brush.uses_vertex_alpha`)
    and compensated for linear additive blending when `additive`."""
    rgb = [srgb_to_linear(max(0.0, min(1.0, c))) for c in rgba[:3]]
    alpha = float(rgba[3]) if keep_alpha and len(rgba) > 3 else 1.0
    if additive:
        alpha = max(0.0, min(1.0, alpha)) ** ADDITIVE_ALPHA_EXPONENT
    return rgb + [alpha]

