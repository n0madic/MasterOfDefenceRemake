## Simulation state of one enemy (`tenemyt`, docs/10). No scene nodes here.
class_name SimEnemy
extends RefCounted

var id := 0  # sequential handle, for views and saves
var unit_id := 0
var air := false
var worker := false
var healer := 0
var boss := false
var speed := 0.0  # units per tick
var freeze := 0.0
var burn_time := 0.0
var burn_damage := 0.0
var poison_time := 0.0
var poison_damage := 0.0
var max_life := 0.0
var life := 0.0
var anim_speed := 0.0
var armor := 0
var gold := 0
var selected := false
var scale := 1.0
## Visual: MD2 walk-cycle time in frames (AnimateMD2 speed), for views only.
var md2_time := 0.0
var md2_speed := 0.0
## Visual effect currently attached (0 none, 1 fire, 2 poison) and its size.
var effect_kind := 0
var effect_size := 0.0

var path := PathFollower.new()


var position: Vector3:
	get:
		return path.body


var facing: Vector3:
	get:
		return path.facing


## World point bullets aim at (air units are hit 3 above their road position).
func aim_point() -> Vector3:
	return path.body + Vector3(0, 3, 0) if air else path.body


func life_percent() -> float:
	return life * (100.0 / max_life)


func reached_end() -> bool:
	return path.finished()
