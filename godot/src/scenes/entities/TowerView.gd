## Visual mirror of a SimTower: the animated model (seeked to `model_frame()`), the
## recoloured `dno` base, selection ring and range circle.
class_name TowerView
extends Node3D

const RANGE_MODEL := "res://assets/models/Towers/range.glb"
const SELECTION_MODEL := "res://assets/models/Towers/selection.glb"
const SELECTION_SPEED := 1.0
const ICEROCK_TINT := Color(0.0, 110.0 / 255.0, 1.0)
const PICK_BOX := Vector3(2.8, 8.4, 2.8)

var tower: SimTower
var model: Node3D
var player: AnimationPlayer
var maps: Array[Dictionary] = []
var range_ring: Node3D
var selection: Node3D
var selection_player: AnimationPlayer
var selection_time := 0.0


func setup(t: SimTower, data: Node, location: Dictionary, location_number: int) -> void:
	tower = t
	var info: Dictionary = data.tower_model(t.type)
	model = load(info["model"]).instantiate()
	add_child(model)
	BlitzAnimator.hide_helpers(model)
	player = BlitzAnimator.find_player(model)
	maps = BlitzAnimator.setup_animmaps(model)  # Magic/Freeze/Fire scroll their textures
	paint_base(model, t.type, location, location_number)
	range_ring = load(RANGE_MODEL).instantiate()
	BlitzAnimator.hide_helpers(range_ring)
	add_child(range_ring)
	range_ring.visible = false
	selection = load(SELECTION_MODEL).instantiate()
	BlitzAnimator.hide_helpers(selection)
	add_child(selection)
	selection.visible = false
	selection_player = BlitzAnimator.find_player(selection)
	var box := BoxShape3D.new()
	box.size = PICK_BOX
	add_child(Picker.make_area(Picker.LAYER_TOWERS, "tower_id", t.id, box, Vector3(0, PICK_BOX.y / 2.0, 0)))
	position = t.position
	rotation_degrees.y = t.yaw_degrees
	sync()


## `_fpositiontower`: the base gets the location's ground texture and tint; Icerock outside
## location 3 is painted blue. `dno<L>.png` is loaded with the ALPHA flag (0x20b) in the
## original, so the base blends whatever the model's own dno brush is (Freeze's is untextured
## and opaque). Returns the material copies made for `model` (the only alpha-blended variant
## of the tower shader, which `ModelWarmup` keeps alive).
static func paint_base(model: Node3D, type: int, location: Dictionary, location_number: int) -> Array[Material]:
	var out: Array[Material] = []
	var dno: MeshInstance3D = model.find_child("dno", true, false)
	if dno == null:
		return out
	var tint_rgb: Array = location["tower_tint_rgb"]
	var tint := Color(tint_rgb[0] / 255.0, tint_rgb[1] / 255.0, tint_rgb[2] / 255.0)
	if type == GameData.TOWER_ICEROCK and location_number != 3:
		tint = ICEROCK_TINT
	var tex_path: String = location["ground_texture"]
	for i in dno.mesh.get_surface_count():
		var m := dno.get_active_material(i)
		if m is StandardMaterial3D:
			var own := BlitzAnimator.copy_material(m) as StandardMaterial3D
			if ResourceLoader.exists(tex_path):
				BlitzAnimator.set_material_texture(own, load(tex_path))
				own.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			BlitzAnimator.set_material_color(own, Color(tint.r, tint.g, tint.b, own.albedo_color.a))
			dno.set_surface_override_material(i, own)
			out.append(own)
	return out


## `uv_frame`: the frame that drives the type's shared texture scroll (`_fupdateextanims`
## updates the ANIMMAPs of one tower per type; `PositionTexture` acts on the texture every
## copy shares), -1 = this tower's own frame. The selection ring's animation is the view's
## own clock and advances by the frame's `ticks`.
func sync(uv_frame := -1.0, ticks := 1) -> void:
	BlitzAnimator.seek(player, tower.model_frame())
	BlitzAnimator.update_animmaps(maps, uv_frame)
	range_ring.visible = tower.selected
	if tower.selected:
		range_ring.scale = Vector3(tower.range * 2.0, 1.0, tower.range * 2.0)
	selection.visible = tower.selected
	if tower.selected and selection_player != null:
		var frames := selection_player.get_animation(BlitzAnimator.B3D_ANIMATION).length
		selection_time = fmod(selection_time + SELECTION_SPEED * ticks, maxf(frames, 1.0))
		BlitzAnimator.seek(selection_player, selection_time)
