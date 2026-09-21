## Tower placement marker (`*Place.b3d`): follows the cursor over the location, green
## when the tower can be placed, red otherwise; the range circle is shown only when allowed.
class_name PlaceMarkerView
extends Node3D

const RANGE_MODEL := "res://assets/models/Towers/range.glb"
const COLOR_OK := Color(0.0, 250.0 / 255.0, 0.0)
const COLOR_BAD := Color(250.0 / 255.0, 0.0, 0.0)

var marker: Node3D
var marker_mats: Array[Material] = []
var range_ring: Node3D
var can_place := false


func setup(place_model: String, tower_range: float) -> void:
	marker = load(place_model).instantiate()
	BlitzAnimator.hide_helpers(marker)
	add_child(marker)
	range_ring = load(RANGE_MODEL).instantiate()
	BlitzAnimator.hide_helpers(range_ring)
	add_child(range_ring)
	range_ring.scale = Vector3(tower_range * 2.0, 1.0, tower_range * 2.0)
	marker_mats = BlitzAnimator.owned_materials(marker)
	_apply_allowed(false)


## Called every frame while placing: recolours only on a change.
func set_allowed(allowed: bool) -> void:
	if allowed != can_place:
		_apply_allowed(allowed)


func _apply_allowed(allowed: bool) -> void:
	can_place = allowed
	BlitzAnimator.tint_materials(marker_mats, COLOR_OK if allowed else COLOR_BAD)
	range_ring.visible = allowed
