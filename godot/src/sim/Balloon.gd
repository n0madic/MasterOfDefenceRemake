## The balloon of locations 4-6 (`tballoont`, docs/07). Movement is the `_fflux_translate`
## tween: duration `Round(10 * dist)` ticks with cosine easing, elapsed counted in ticks.
class_name SimBalloon
extends RefCounted

const HEIGHT := 10.0
const BOMB_INTERVAL_TICKS := 200
const BOMB_TRIGGER_DISTANCE := 15.0
const TICKS_PER_UNIT := 10.0

var enabled := false
var position := Vector3.ZERO
var timer := 0
var destination := Vector3.ZERO
var here_marker_visible := false

var _tween_from := Vector3.ZERO
var _tween_to := Vector3.ZERO
var _tween_duration := 0
var _tween_elapsed := -1
var _tweening := false


## `_fmoveballoonto(x, y, z)`: start moving toward the picked road point (own height kept).
func move_to(dest: Vector3) -> void:
	destination = dest
	var from := position
	var d := Vector2(Blitz.round_int(from.x), Blitz.round_int(from.z)).distance_to(
		Vector2(Blitz.round_int(dest.x), Blitz.round_int(dest.z)))
	_tween_duration = Blitz.round_int(TICKS_PER_UNIT * d)
	_tween_from = from
	_tween_to = Vector3(dest.x, from.y, dest.z)
	_tween_elapsed = -1
	_tweening = true
	here_marker_visible = true


func is_moving() -> bool:
	return _tweening


## `_fflux_update(1)` for the translate motion.
func update(_game: SimGame) -> void:
	if not _tweening:
		return
	if _tween_elapsed == -1:
		_tween_elapsed = 0
	else:
		_tween_elapsed += 1
	var t := 0.0
	if _tween_duration > 0:
		t = float(mini(_tween_elapsed, _tween_duration)) / float(_tween_duration)
	var eased := (1.0 - cos(t * PI)) / 2.0
	position = _tween_from.lerp(_tween_to, eased)
	if _tween_elapsed >= _tween_duration:
		_tweening = false
