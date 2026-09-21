## Simulation state of one tower (`ttowert`, docs/10), including the Blitz animator state
## that gates upgrades (docs/05 "Upgrading").
class_name SimTower
extends RefCounted

const ANIM_NONE := 0
const ANIM_LOOP := 1
const ANIM_ONESHOT := 3
const SEQ_FRAMES := 10
const ANIM_SPEED := 0.1
const TIMER_STEP_MS := 16
const BULLET_SPEED := 0.4
const MIN_DISTANCE_BETWEEN_TOWERS := 5.6

var id := 0
var type := 0
var level := 0
var position := Vector3.ZERO
var yaw_degrees := 0.0
var rate_of_fire := 0
var timer := 0
var land_damage := 0.0
var air_damage := 0.0
var range := 0.0
var freeze := 0.0
var fire := 0.0
var poison_coof := 0
var poison_damage := 0.0
var place_on_road := false
var target_method := 1
var max_upgrades := 0
var bullet_model := ""
var target: SimEnemy = null
var upgrade_pending := false
var spent := 0
var hidden := false
var stopped := false
var selected := false
## Local position of the `fire1` child of the model per animation frame (bullet spawn
## point); a single entry when the node is static. Filled from GameData.tower_model().
var fire_keys := PackedVector3Array([Vector3(0, 4, 0)])

# Blitz Animator state (Animate/AnimSeq/AnimTime/Animating).
var anim_mode := ANIM_NONE
var anim_seq := 0
var anim_time := 0.0


## World position of `fire1` at the current animation frame (Blitz linear key
## interpolation), rotated by the tower's random build yaw.
func fire_point() -> Vector3:
	var local: Vector3
	if fire_keys.size() == 1:
		local = fire_keys[0]
	else:
		var t := model_frame()
		var i := clampi(int(floorf(t)), 0, fire_keys.size() - 1)
		if i >= fire_keys.size() - 1:
			local = fire_keys[fire_keys.size() - 1]
		else:
			local = fire_keys[i].lerp(fire_keys[i + 1], t - i)
	return position + local.rotated(Vector3.UP, deg_to_rad(yaw_degrees))


func idle_seq() -> int:
	return level * 2 + 1


func upgrade_seq() -> int:
	return level * 2


func is_upgrading() -> bool:
	return anim_seq == upgrade_seq()


## Copy per-level parameters from the prototype (`_fcreatetower` / `_ffinishtowerupgrade`).
func apply_proto(p: Dictionary) -> void:
	rate_of_fire = int(p["rate_of_fire_ms"])
	land_damage = float(p["land_damage"])
	air_damage = float(p["air_damage"])
	range = float(p["range"])
	target_method = int(p["target_method"])
	freeze = float(p["freeze"])
	fire = float(p["fire"])
	place_on_road = bool(p["place_on_road"])
	poison_coof = int(p["poison_coof"])
	poison_damage = float(p["poison_damage"])
	max_upgrades = int(p["max_upgrades"])
	bullet_model = str(p["bullet_model"]) if p["bullet_model"] != null else ""


## Blitz `Animate(entity, mode, speed, seq)` with no transition.
func animate(mode: int, seq: int) -> void:
	anim_mode = mode
	anim_seq = seq
	anim_time = 0.0


func animating() -> bool:
	return anim_mode != ANIM_NONE


## Blitz `UpdateWorld(1)` step of the animator (Animator::update with elapsed = 1).
func update_anim() -> void:
	if anim_mode == ANIM_NONE:
		return
	anim_time = Blitz.f32(anim_time + Blitz.f32(ANIM_SPEED))
	match anim_mode:
		ANIM_LOOP:
			anim_time = fmod(anim_time, float(SEQ_FRAMES))
		ANIM_ONESHOT:
			if anim_time >= SEQ_FRAMES:
				anim_time = float(SEQ_FRAMES)
				anim_mode = ANIM_NONE


## Absolute frame inside the model's 0..210 animation, for views. `ExtractAnimSeq` in
## `_fcreatetower` numbers the sequences from 1: seq k = frames [10(k-1), 10k].
func model_frame() -> float:
	return (anim_seq - 1) * SEQ_FRAMES + anim_time


func can_hit(e: SimEnemy) -> bool:
	if e.air:
		return air_damage != 0.0
	return land_damage != 0.0
