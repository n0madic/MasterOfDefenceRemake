## A one-shot Blitz animation (explosion, death animation, bomb blast): plays the whole
## `b3d` animation at `speed` frames per tick, then frees itself. Mirrors
## `_fcreateexplosion` / `_fcreatedeathanim` / the bomb blast in `_fhandlebombs`.
## `fade_frames > 0` applies `_fupdatedeathanims`: `EntityAlpha (length - t) / fade_frames`.
class_name OneShotView
extends Node3D

var player: AnimationPlayer
var time := 0.0
var speed := 0.2
var length := 0.0
var finished := false
var maps: Array[Dictionary] = []
var brushes: Array[Dictionary] = []
var alpha_entries: Array[Dictionary] = []
var fade_frames := 0.0
var model: Node3D


func setup(model_path: String, at: Vector3, uniform_scale: float, frames_per_tick: float, fade := 0.0) -> void:
	fade_frames = fade
	model = load(model_path).instantiate()
	BlitzAnimator.hide_helpers(model)
	add_child(model)
	player = BlitzAnimator.find_player(model)
	position = at
	scale = Vector3.ONE * uniform_scale
	speed = frames_per_tick
	length = player.get_animation(BlitzAnimator.B3D_ANIMATION).length if player != null else 0.0
	maps = BlitzAnimator.setup_animmaps(model)
	brushes = BlitzAnimator.setup_animbrushes(model)
	if fade_frames > 0.0:
		alpha_entries = BlitzAnimator.alpha_entries(model)
	_seek(0.0)


## Advance `ticks` ticks; returns true when the animation is over (`Animating() = 0`).
func tick(ticks := 1) -> bool:
	if finished:
		return true
	time += speed * ticks
	if time >= length:
		time = length
		finished = true
	_seek(time)
	return finished


func _seek(t: float) -> void:
	BlitzAnimator.seek(player, t)
	BlitzAnimator.update_animmaps(maps)
	BlitzAnimator.update_animbrushes(brushes)
	if fade_frames > 0.0:
		BlitzAnimator.set_alpha_entries(alpha_entries, (length - t) / fade_frames)
