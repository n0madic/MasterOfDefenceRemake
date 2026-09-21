## A Blitz menu scene (`Menu/*.b3d`): a converted glb parented to the camera 10 units in
## front and facing it squarely (the original's `TurnEntity 45,0,0` only cancels the
## 45-degree pitch of the game camera set by `_floadgraphics`), with named item meshes
## ("punkts") that are picked with the mouse (`_fcreatepunkt` / `_fhandlepunkts`).
## The selection cursor `sel.b3d` is copied onto the hovered item with the brightness
## ramp of the original (docs/09).
class_name MenuScene3D
extends Node3D

signal item_clicked(name: String)
signal item_hovered(name: String)

const SEL_MODEL := "res://assets/models/Menu/sel.glb"
const DISTANCE := 10.0
const LAYER_ITEMS := 4
const SEL_SPEED := 0.2
const SEL_FIRST := 3.0
const SEL_LAST := 13.0
const SEL_BRIGHT_STEP := 0.2
const SEL_BRIGHT_MAX := 0.9
const SEL_FADE_STEP := 0.05
const SEL_FADE_MIN := 0.1

var scene: Node3D
var player: AnimationPlayer
var camera: Camera3D
var items: Dictionary = {}  # name -> Node3D
var areas: Dictionary = {}  # Area3D -> name
var anim_time := 0.0
var anim_speed := 0.0
var anim_mode := SimTower.ANIM_NONE
var anim_length := 0.0  # last frame of the running range (the clip length by default)
var anim_start := 0.0  # first frame of the running range (`ExtractAnimSeq`)
var clip_length := 0.0
var sel: Node3D
var sel_player: AnimationPlayer
var sel_time := SEL_FIRST
var sel_maps: Array[Dictionary] = []
var sel_brushes: Array[Dictionary] = []
var sel_brightness := 0.0
var hovered := ""
var enabled := true
## Pickable nodes that are not menu items (no cursor, no click): slider backs.
var passive: Dictionary = {}  # name -> true
var disabled: Dictionary = {}  # name -> true (`EntityPickMode 0`: visible but not pickable)


func load_scene(path: String, cam: Camera3D, item_names: Array) -> void:
	camera = cam
	scene = load(path).instantiate()
	add_child(scene)
	BlitzAnimator.hide_helpers(scene)
	player = BlitzAnimator.find_player(scene)
	clip_length = player.get_animation(BlitzAnimator.B3D_ANIMATION).length if player != null else 0.0
	anim_length = clip_length
	cam.add_child(self)
	position = Vector3(0, 0, -DISTANCE)
	for n in item_names:
		var node: Node3D = scene.find_child(n, true, false)
		if node == null:
			push_warning("menu item %s not found in %s" % [n, path])
			continue
		items[n] = node
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			var area := Area3D.new()
			area.collision_layer = 1 << (LAYER_ITEMS - 1)
			area.collision_mask = 0
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(mi.mesh.get_faces())
			cs.shape = shape
			area.add_child(cs)
			mi.add_child(area)
			areas[area] = n
	sel = load(SEL_MODEL).instantiate()
	BlitzAnimator.hide_helpers(sel)
	add_child(sel)
	sel.visible = false
	sel_player = BlitzAnimator.find_player(sel)
	# The frost cursor scrolls its texture (ANIMMAP) and fades its brush (ANIMBRUSH alpha).
	sel_maps = BlitzAnimator.setup_animmaps(sel)
	sel_brushes = BlitzAnimator.setup_animbrushes(sel)


## `EntityPickMode(node, 2)`: make `node` pickable under `n`; `is_passive` nodes are picked
## with `pick()` but never hovered or clicked as items.
func register_item(n: String, node: Node3D, is_passive := false) -> void:
	items[n] = node
	if is_passive:
		passive[n] = true
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var area := Area3D.new()
		area.collision_layer = 1 << (LAYER_ITEMS - 1)
		area.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mi.mesh.get_faces())
		cs.shape = shape
		area.add_child(cs)
		mi.add_child(area)
		areas[area] = n


func find_node(n: String) -> Node3D:
	return scene.find_child(n, true, false)


## Blitz `Animate(mesh, mode, speed)` on the whole clip.
func animate(mode: int, speed: float) -> void:
	animate_range(mode, speed, 0.0, clip_length)


## Blitz `Animate(mesh, mode, speed, seq)` on an extracted sequence `first..last`: a
## negative speed starts at `last` and stops at `first`, never below it.
func animate_range(mode: int, speed: float, first: float, last: float) -> void:
	anim_mode = mode
	anim_speed = speed
	anim_start = first
	anim_length = last
	anim_time = first if speed >= 0.0 else last
	BlitzAnimator.seek(player, anim_time)


func seek(t: float) -> void:
	anim_mode = SimTower.ANIM_NONE
	anim_time = t
	BlitzAnimator.seek(player, t)


func animating() -> bool:
	return anim_mode != SimTower.ANIM_NONE


## One logic tick: scene animation, cursor ramp, hover detection.
func tick(mouse: Vector2) -> void:
	if anim_mode != SimTower.ANIM_NONE and player != null:
		anim_time += anim_speed
		if anim_mode == SimTower.ANIM_LOOP:
			anim_time = anim_start + fposmod(anim_time - anim_start, anim_length - anim_start)
		elif anim_time <= anim_start and anim_speed < 0.0:
			anim_time = anim_start
			anim_mode = SimTower.ANIM_NONE
		elif anim_time >= anim_length and anim_speed > 0.0:
			anim_time = anim_length
			anim_mode = SimTower.ANIM_NONE
		BlitzAnimator.seek(player, anim_time)
	var over := pick(mouse) if enabled else ""
	if passive.has(over):
		over = ""
	if over != hovered:
		if over != "":
			if hovered == "":
				AudioManager.play("rebutton")
			_place_cursor(items[over])
			sel.visible = true
			sel_brightness = 0.0
			item_hovered.emit(over)
		hovered = over
	if hovered != "":
		sel_brightness = SEL_BRIGHT_MAX if sel_brightness + SEL_BRIGHT_STEP >= SEL_BRIGHT_MAX and sel_brightness < SEL_BRIGHT_MAX else minf(sel_brightness + SEL_BRIGHT_STEP, 1.0)
	elif sel.visible:
		sel_brightness -= SEL_FADE_STEP
		if sel_brightness <= SEL_FADE_MIN:
			sel.visible = false
	if sel.visible:
		BlitzAnimator.tint(sel, Color(sel_brightness, sel_brightness, sel_brightness))
		sel_time += SEL_SPEED
		if sel_time >= SEL_LAST:
			sel_time = SEL_FIRST
		BlitzAnimator.seek(sel_player, sel_time)
		BlitzAnimator.update_animmaps(sel_maps)
		BlitzAnimator.update_animbrushes(sel_brushes)


## `AlignEntity` + `OrientEntity` of the cursor to the item, then `TurnEntity 90,0,0`
## (Blitz pitch +90 = Godot -90 about X); the cursor keeps its own scale.
func _place_cursor(node: Node3D) -> void:
	sel.global_position = node.global_position
	sel.global_basis = node.global_basis.orthonormalized()
	sel.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90.0))


func pick(mouse: Vector2) -> String:
	if camera == null or not is_inside_tree():
		return ""
	var space := camera.get_world_3d().direct_space_state
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 << (LAYER_ITEMS - 1))
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return ""
	var name: String = areas.get(hit["collider"], "")
	if name != "" and (disabled.has(name) or not (items[name] as Node3D).visible):
		return ""
	return name


func click(mouse: Vector2) -> void:
	if not enabled:
		return
	var name := pick(mouse)
	if name != "" and not passive.has(name):
		AudioManager.play("click")
		item_clicked.emit(name)


func set_item_enabled(name: String, on: bool) -> void:
	if on:
		disabled.erase(name)
	else:
		disabled[name] = true


func set_item_visible(name: String, on: bool) -> void:
	if items.has(name):
		(items[name] as Node3D).visible = on


## Drop an item for good together with its text label: the sheets keep the caption on a
## separate `PlaneNN` mesh floating in front of the plank.
func remove_item(name: String, label: String) -> void:
	set_item_visible(name, false)
	var node := find_node(label)
	if node != null:
		node.visible = false


## Move an item sideways, keeping the move through the sheet's fly-in animation: the
## node's position keys are shifted on a private copy of the animation (the imported
## library is shared by every instance of the model).
func offset_item(name: String, delta: Vector3) -> void:
	var node := find_node(name)
	if node == null:
		return
	node.position += delta
	if player == null or player.get_animation_library_list().is_empty():
		return
	var lib_name: StringName = player.get_animation_library_list()[0]
	var lib := player.get_animation_library(lib_name).duplicate() as AnimationLibrary
	var anim := lib.get_animation(BlitzAnimator.B3D_ANIMATION).duplicate() as Animation
	lib.remove_animation(BlitzAnimator.B3D_ANIMATION)
	lib.add_animation(BlitzAnimator.B3D_ANIMATION, anim)
	player.remove_animation_library(lib_name)
	player.add_animation_library(lib_name, lib)
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D or path.get_name(path.get_name_count() - 1) != StringName(name):
			continue
		for k in anim.track_get_key_count(i):
			anim.track_set_key_value(i, k, anim.track_get_key_value(i, k) + delta)
