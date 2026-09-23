"""Row-major 4x4 matrix and quaternion helpers shared by the converters and the port exporters.

Quaternions are (w, x, y, z) unless a function says otherwise; glTF nodes store (x, y, z, w).
"""
from __future__ import annotations

import math

Mat4 = list[list[float]]  # row-major 4x4
IDENTITY: Mat4 = [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]


def quat_to_mat3(q: tuple[float, float, float, float]) -> list[list[float]]:
    """Textbook rotation matrix (rows) of a unit quaternion (w, x, y, z)."""
    w, x, y, z = q
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ]


def trs_matrix(t: tuple[float, float, float], q: tuple[float, float, float, float], s: tuple[float, float, float]) -> Mat4:
    r = quat_to_mat3(q)
    return [
        [r[0][0] * s[0], r[0][1] * s[1], r[0][2] * s[2], t[0]],
        [r[1][0] * s[0], r[1][1] * s[1], r[1][2] * s[2], t[1]],
        [r[2][0] * s[0], r[2][1] * s[1], r[2][2] * s[2], t[2]],
        [0.0, 0.0, 0.0, 1.0],
    ]


def node_matrix(node: dict) -> Mat4:
    """Local matrix of a glTF node (translation / rotation xyzw / scale)."""
    t = tuple(node.get("translation", [0.0, 0.0, 0.0]))
    r = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = tuple(node.get("scale", [1.0, 1.0, 1.0]))
    return trs_matrix(t, (r[3], r[0], r[1], r[2]), s)


def mat_mul(a: Mat4, b: Mat4) -> Mat4:
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def determinant3(m: Mat4) -> float:
    """Determinant of the upper 3x3 (negative for a mirroring transform)."""
    return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))


def mat_inverse_affine(m: Mat4) -> Mat4:
    """Inverse of an affine matrix (rotation * scale + translation) by 3x3 cofactors."""
    a = [row[:3] for row in m[:3]]
    det = determinant3(m)
    inv = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            minor = [[a[r][c] for c in range(3) if c != i] for r in range(3) if r != j]
            cof = minor[0][0] * minor[1][1] - minor[0][1] * minor[1][0]
            inv[i][j] = ((-1) ** (i + j)) * cof / det
    t = [m[0][3], m[1][3], m[2][3]]
    out = [inv[i] + [-sum(inv[i][k] * t[k] for k in range(3))] for i in range(3)]
    out.append([0.0, 0.0, 0.0, 1.0])
    return out


def mat_column_major(m: Mat4) -> list[float]:
    return [m[r][c] for c in range(4) for r in range(4)]


def transform_point(m: Mat4, p) -> tuple[float, float, float]:
    return tuple(m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3] for i in range(3))


def normal_matrix(m: Mat4) -> Mat4:
    """Inverse transpose of the upper 3x3 (as a 4x4 with no translation)."""
    inv = mat_inverse_affine([row[:3] + [0.0] for row in m[:3]] + [[0.0, 0.0, 0.0, 1.0]])
    return [[inv[j][i] for j in range(3)] + [0.0] for i in range(3)] + [[0.0, 0.0, 0.0, 1.0]]


def transform_normal(nm: Mat4, n) -> tuple[float, float, float]:
    """`n` through the normal matrix `nm` (normalized later, `unit_normal`)."""
    return (nm[0][0] * n[0] + nm[0][1] * n[1] + nm[0][2] * n[2],
            nm[1][0] * n[0] + nm[1][1] * n[1] + nm[1][2] * n[2],
            nm[2][0] * n[0] + nm[2][1] * n[1] + nm[2][2] * n[2])


def unit_normal(n) -> tuple[float, float, float]:
    """`n` normalized; a degenerate normal becomes +Y."""
    length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
    if length < 1e-8:
        return (0.0, 1.0, 0.0)
    return (n[0] / length, n[1] / length, n[2] / length)


def quat_rotate(q: list[float], v: tuple[float, float, float]) -> tuple[float, float, float]:
    """`v` rotated by the glTF (x, y, z, w) quaternion `q`."""
    x, y, z, w = q
    tx = 2.0 * (y * v[2] - z * v[1])
    ty = 2.0 * (z * v[0] - x * v[2])
    tz = 2.0 * (x * v[1] - y * v[0])
    return (v[0] + w * tx + (y * tz - z * ty), v[1] + w * ty + (z * tx - x * tz), v[2] + w * tz + (x * ty - y * tx))


def rigid_pose(m: Mat4) -> tuple[list[float], list[float]]:
    """Position and rotation quaternion (x, y, z, w) of a row-major matrix, its basis
    normalized (the scale is dropped)."""
    cols = [unit_normal((m[0][c], m[1][c], m[2][c])) for c in range(3)]
    (m00, m10, m20), (m01, m11, m21), (m02, m12, m22) = cols
    trace = m00 + m11 + m22
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        q = ((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s)
    elif m00 > m11 and m00 > m22:
        s = math.sqrt(1.0 + m00 - m11 - m22) * 2
        q = (0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
    elif m11 > m22:
        s = math.sqrt(1.0 + m11 - m00 - m22) * 2
        q = ((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s)
    else:
        s = math.sqrt(1.0 + m22 - m00 - m11) * 2
        q = ((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s)
    return [m[0][3], m[1][3], m[2][3]], list(q)
