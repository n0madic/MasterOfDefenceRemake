## Wide-screen layout of the HUD: the 800x600 box stays centred in the canvas, but every
## floating group keeps its corner or edge of the window. 2D widgets hang under per-anchor
## roots (see Hud); the quads of the camera-attached 3D panel get their vertices shifted
## per anchor, which also stretches the plain planks and the tutorial pointer lines that
## run between two anchors.
##
## An anchor is a Vector2 of -1 / 0 / 1 per axis: the shift in canvas pixels is
## `anchor * ui_offset` (-1 = left / top edge, 0 = centred with the box, 1 = right / bottom).
## A mesh rule is either an anchor for all of its vertices, or a dictionary with
## piecewise-linear rules per axis: `"u"` / `"v"` (texture coordinates) or `"x"` (local x)
## map to `[t_a, t_b, anchor_a, anchor_b]` -- below `t_a` the vertex takes `anchor_a`, above
## `t_b` `anchor_b`, in between it blends, so the strip between the thresholds stretches;
## `"ax"` / `"ay"` set a constant anchor for an axis. The mesh is cut along the thresholds
## so the blend is exact. Vertices in a quad are kept in file order (winding preserved).
class_name HudLayout
extends RefCounted

const TOP_LEFT := Vector2(-1, -1)
const TOP_CENTRE := Vector2(0, -1)
const TOP_RIGHT := Vector2(1, -1)
const BOTTOM_LEFT := Vector2(-1, 1)
const BOTTOM_CENTRE := Vector2(0, 1)
const BOTTOM_RIGHT := Vector2(1, 1)
const CENTRE := Vector2(0, 0)

## `Env.glb`: the planks and icons of the panel. The plain planks (`wood.png`) run between
## a post and the info panel and stretch; `Plane10` holds both posts in one mesh.
const ENV_RULES := {
	"leftUp": TOP_LEFT, "goldIcon": TOP_LEFT, "gold": TOP_LEFT, "expa": TOP_LEFT, "expaIcon": TOP_LEFT,
	"rightUp": TOP_RIGHT, "inhabsIcon": TOP_RIGHT, "inhabs": TOP_RIGHT,
	"raids": TOP_CENTRE,
	"infopanel": BOTTOM_CENTRE, "reset": BOTTOM_CENTRE, "beguny": BOTTOM_CENTRE,
	"leftside": {"u": [0.0, 1.0, -1.0, 0.0], "ay": 1.0},
	"rightside": {"u": [0.0, 1.0, 0.0, 1.0], "ay": 1.0},
	"Plane10": {"x": [-0.5, 0.5, -1.0, 1.0], "ay": 1.0},
}
## `faces.glb`: the portrait inside the info panel.
const FACES_RULES := {"Plane13": BOTTOM_CENTRE}
## `tutorial.glb`: pointer lines cut from `Lines.png`. The labelled ones sit next to their
## target and move with it; the L-shaped ones hang from the (centred) sheet down to the
## bottom panel: the strip holding only the horizontal / vertical line stretches while
## the drops onto the buttons stay rigid.
const TUTORIAL_RULES := {
	"gold": TOP_LEFT, "expa": TOP_LEFT, "people": TOP_RIGHT,
	"speed": BOTTOM_CENTRE,
	"create": {"u": [0.25, 0.32, -1.0, 0.0], "v": [0.60, 0.70, 0.0, 1.0]},
	"upgrade": {"u": [0.71, 0.84, 0.0, 1.0], "v": [0.60, 0.66, 0.0, 1.0]},
	"delete": {"u": [0.86, 0.94, 0.0, 1.0], "v": [0.60, 0.615, 0.0, 1.0]},
	"updExpa": {"v": [0.60, 0.70, 0.0, 1.0]},
}

## Registered meshes: {"mi", "panel", "mesh", "material", "rest", "normals", "uvs",
## "anchors", "basis_inv", "upp"}.
var entries: Array[Dictionary] = []


## Register the meshes of `model` (a child of `panel`, which hangs on the camera) named in
## `rules`; their meshes are rebuilt once with the cuts the rules need.
func register(model: Node3D, rules: Dictionary, panel: Node3D) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not rules.has(mi.name):
			continue
		var rule: Variant = rules[mi.name]
		var tris := _triangles(mi.mesh)
		for cut in _cuts(rule):
			tris = _clip(tris, cut[0], cut[1])
		var rest := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var anchors := PackedVector2Array()
		for tri in tris:
			for v in tri:
				rest.append(v["p"])
				normals.append(v["n"])
				uvs.append(v["uv"])
				anchors.append(_anchor(rule, v["p"], v["uv"]))
		var chain := _to_camera(mi, panel)
		var mesh := ArrayMesh.new()
		entries.append({
			"mi": mi, "panel": panel, "mesh": mesh, "material": mi.mesh.surface_get_material(0),
			"rest": rest, "normals": normals, "uvs": uvs, "anchors": anchors,
			"basis_inv": chain.basis.inverse(),
			# Depth of the quad itself: some nodes keep their offset in the vertices.
			"upp": units_per_pixel(-(chain * mi.mesh.get_aabb().get_center()).z),
		})
		mi.mesh = mesh
	apply(Vector2.ZERO)


## The original parks unused pointers just outside the 800x600 frame (the tutorial
## animation moves them ~3.8 units down); a wider or taller canvas would show them, so
## after a seek every registered mesh of `model` that lies entirely outside the 4:3 frame
## is hidden and the others shown.
func cull_parked(model: Node3D) -> void:
	for e in entries:
		var mi: MeshInstance3D = e["mi"]
		if not model.is_ancestor_of(mi):
			continue
		var box: AABB = _to_camera(mi, e["panel"]) * _rest_aabb(e["rest"])
		var half_w := -box.get_center().z * tan(deg_to_rad(DisplayManager.FOV_H / 2.0))
		var half_h := half_w * DisplayManager.BOX.y / DisplayManager.BOX.x
		mi.visible = box.position.x < half_w and box.end.x > -half_w and box.position.y < half_h and box.end.y > -half_h


static func _rest_aabb(rest: PackedVector3Array) -> AABB:
	var box := AABB(rest[0], Vector3.ZERO)
	for v in rest:
		box = box.expand(v)
	return box


## World units per canvas pixel at `depth` in front of the camera: the cameras keep the
## vertical fov of the 800x600 frame, so this does not depend on the screen mode.
static func units_per_pixel(depth: float) -> float:
	return 2.0 * depth * tan(deg_to_rad(DisplayManager.FOV_H / 2.0)) / DisplayManager.BOX.x


## Shift every registered vertex by its anchor's share of the box `offset` (pixels), kept
## inside the safe insets (see `DisplayManager.anchor_shift_for`).
func apply(offset: Vector2, safe_min := Vector2.ZERO, safe_max := Vector2.ZERO) -> void:
	for e in entries:
		var rest: PackedVector3Array = e["rest"]
		var anchors: PackedVector2Array = e["anchors"]
		var basis_inv: Basis = e["basis_inv"]
		var upp: float = e["upp"]
		var verts := PackedVector3Array()
		verts.resize(rest.size())
		for i in rest.size():
			var px := DisplayManager.anchor_shift_for(anchors[i], offset, safe_min, safe_max) * upp
			verts[i] = rest[i] + basis_inv * Vector3(px.x, -px.y, 0.0)  # screen y down, world y up
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = e["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = e["uvs"]
		var mesh: ArrayMesh = e["mesh"]
		mesh.clear_surfaces()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if e["material"] != null:
			mesh.surface_set_material(0, e["material"])


## Transform of `n` into camera space: up the chain to `panel` (whose own transform is the
## panel offset from the camera).
static func _to_camera(n: Node3D, panel: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != panel and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return panel.transform * t


static func _anchor(rule: Variant, p: Vector3, uv: Vector2) -> Vector2:
	if rule is Vector2:
		return rule
	var a := Vector2(float(rule.get("ax", 0.0)), float(rule.get("ay", 0.0)))
	if rule.has("u"):
		a.x = _blend(rule["u"], uv.x)
	if rule.has("x"):
		a.x = _blend(rule["x"], p.x)
	if rule.has("v"):
		a.y = _blend(rule["v"], uv.y)
	return a


static func _blend(r: Array, t: float) -> float:
	if t <= float(r[0]):
		return float(r[2])
	if t >= float(r[1]):
		return float(r[3])
	return lerpf(float(r[2]), float(r[3]), (t - float(r[0])) / (float(r[1]) - float(r[0])))


## The cut lines a rule needs: [key callable, threshold] pairs.
static func _cuts(rule: Variant) -> Array:
	var out := []
	if rule is Vector2:
		return out
	var keys := {
		"u": func(v: Dictionary) -> float: return v["uv"].x,
		"v": func(v: Dictionary) -> float: return v["uv"].y,
		"x": func(v: Dictionary) -> float: return v["p"].x,
	}
	for k in keys:
		if rule.has(k):
			out.append([keys[k], float(rule[k][0])])
			out.append([keys[k], float(rule[k][1])])
	return out


## The mesh's first surface as triangles of {"p", "n", "uv"} vertices.
static func _triangles(mesh: Mesh) -> Array:
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var index: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if index.is_empty():
		index.resize(verts.size())
		for i in verts.size():
			index[i] = i
	var out := []
	for t in range(0, index.size() - 2, 3):
		var tri := []
		for k in 3:
			var i := index[t + k]
			tri.append({
				"p": verts[i],
				"n": normals[i] if i < normals.size() else Vector3.UP,
				"uv": uvs[i] if i < uvs.size() else Vector2.ZERO,
			})
		out.append(tri)
	return out


## Cut every triangle along `key(v) == c` (Sutherland-Hodgman against both half-planes);
## a triangle entirely on one side comes back unchanged.
static func _clip(tris: Array, key: Callable, c: float) -> Array:
	var out := []
	for tri in tris:
		for keep_below in [true, false]:
			var poly := []
			for i in 3:
				var a: Dictionary = tri[i]
				var b: Dictionary = tri[(i + 1) % 3]
				var fa: float = key.call(a) - c
				var fb: float = key.call(b) - c
				var ina := fa <= 0.0 if keep_below else fa >= 0.0
				var inb := fb <= 0.0 if keep_below else fb >= 0.0
				if ina:
					poly.append(a)
				if ina != inb:
					poly.append(_lerp_vertex(a, b, fa / (fa - fb)))
			for k in range(1, poly.size() - 1):
				out.append([poly[0], poly[k], poly[k + 1]])
	return out


static func _lerp_vertex(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"p": a["p"].lerp(b["p"], t),
		"n": a["n"].lerp(b["n"], t).normalized(),
		"uv": a["uv"].lerp(b["uv"], t),
	}
