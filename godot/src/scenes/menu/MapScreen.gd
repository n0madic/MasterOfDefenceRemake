## World map between locations (`_floadmapmenu` / `_fhandlemapmenu` / `_fdrawstoryline`):
## the flag of the current location, the storyline text revealed letter by letter, and
## the hire message.
class_name MapScreen
extends ScreenBase

signal continue_requested

const PIN_PER_TICK := 2  # resources of the next location pinned per tick (see setup)
const MAP_MODEL := "res://assets/models/Menu/map.glb"
const STORY_POS := Vector2(470, 420)
const STORY_SCALE := 0.95
const FLAG_COLOR := Color(1.0, 203.0 / 255.0, 0.0)
const HIRE_POS := Vector2(400, 560)
const REVEAL_MIN := 0.005
const REVEAL_MAX := 0.015

var game: SimGame
var story: BlitzText
var warm_pending := false  # the next location's resources are still being read
var alpha := PackedFloat32Array()
var inc := PackedFloat32Array()
var rng := RandomNumberGenerator.new()


func setup(g: SimGame, hire_message: String) -> void:
	game = g
	# The next location's models: read on the loader thread (or a few per tick without
	# one), then drawn off screen a few per frame while the story is read (see ModelWarmup),
	# so "continue" finds them ready.
	warm_pending = true
	ModelWarmup.preload_in_background(game.data, game, game.location)
	var m := make_menu(MAP_MODEL, ["map_continue"])
	m.seek(float(g.location) - 0.001)
	# `EntityColor point<L>, 255, 203, 0`: the dot of the current location turns gold.
	var point := m.find_node("point%d" % g.location)
	if point != null:
		BlitzAnimator.tint(point, FLAG_COLOR)
	story = text(STORY_POS, g.data.storyline(g.location), Hud.COLOR_STORY, STORY_SCALE)
	var n := story.letter_count()
	alpha.resize(n)
	inc.resize(n)
	for i in n:
		alpha[i] = 0.0
		inc[i] = rng.randf_range(REVEAL_MIN, REVEAL_MAX)
	story.letter_alpha = alpha
	if hire_message != "":
		var t := text(HIRE_POS, hire_message, Hud.COLOR_LIFES, 0.9)
		t.center_x = true
	AudioManager.play_music("res://assets/audio/menu.ogg")


func _tick() -> void:
	if warm_pending and ModelWarmup.pin_some(game.data, game, game.location, PIN_PER_TICK):
		_warm()
	var changed := false
	for i in alpha.size():
		if alpha[i] < 1.0:
			alpha[i] = minf(alpha[i] + inc[i], 1.0)
			changed = true
	if changed:
		story.letter_alpha = alpha


func _warm() -> void:
	warm_pending = false
	ModelWarmup.warm(get_tree().root, game.data, game, game.location, ModelWarmup.MAP_BATCH)


func _on_item(name: String) -> void:
	if name == "map_continue":
		continue_requested.emit()
