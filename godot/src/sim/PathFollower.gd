## Port of tools/simulate_path.py: the enemy chases an animated marker (`path` node of a
## per-enemy copy of Path1.b3d). See docs/03 "Enemy path".
##
##   marker = P(t)                       # linear interpolation between integer keyframes
##   if |body - marker| < 1: t += step   # SetAnimTime(copy, AnimTime + speed/4)
##   body += dir(body -> marker) * move  # PointEntity + MoveEntity, may overshoot
##   finished when t > frames - 1        # AnimTime > AnimLength - 1
class_name PathFollower
extends RefCounted

const CATCH_UP_DISTANCE := 1.0
const MARKER_FRAMES_PER_SPEED := 0.25

var keys: PackedVector3Array
var rots: Array[Quaternion]
var frames: int
## Random per-enemy offset of the whole path copy (Blitz MoveEntity(copy, Rnd(-1,1), 0, Rnd(0,1))).
var offset := Vector3.ZERO
## Blitz AnimTime of the path copy, in frames.
var time := 0.0
var body := Vector3.ZERO
## Direction the body is facing (unit vector), updated by PointEntity.
var facing := Vector3.FORWARD


func setup(path: Dictionary, path_offset: Vector3) -> void:
	keys = path["pos"]
	rots = path["rot"]
	frames = int(path["frames"])
	offset = path_offset
	time = 0.0
	body = marker_position()
	if rots.size() > 0:
		facing = rots[0] * Vector3.FORWARD


## Position of the `path` marker at the current animation time (Blitz Animation::getPosition).
func marker_position() -> Vector3:
	return position_at(time) + offset


func position_at(t: float) -> Vector3:
	var i := int(floorf(t))
	if i >= keys.size() - 1:
		return keys[keys.size() - 1]
	if i < 0:
		return keys[0]
	return keys[i].lerp(keys[i + 1], t - i)


## One tick of `_fupdateenemies` movement. `speed` is the body step, `marker_step` is what
## AnimTime advances by when the body is close enough (speed/4 normally, scaled when frozen).
func advance(speed: float, marker_step: float) -> void:
	var marker := marker_position()
	if body.distance_to(marker) < CATCH_UP_DISTANCE:
		# SetAnimTime takes time mod AnimLength (frames).
		time = fmod(time + marker_step, float(frames))
		marker = marker_position()
	var delta := marker - body
	var d := delta.length()
	if d > 0.0:
		facing = delta / d
		body += facing * speed


func finished() -> bool:
	return time > frames - 1
