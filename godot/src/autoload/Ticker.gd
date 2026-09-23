## Fixed-step game clock (`_fmainloop`, convention C3):
##
##   period_ms = 1000 \ fps, fps = 40 + slider (slider 20 -> 16 ms = 62.5 ticks/s)
##
## Dragging the slider sets fps = 40 + slider, but the hotkeys set fps directly: N = 60
## (slider 20), M = 120 while the slider is drawn at 100 (not 140); the in-game menu runs
## at 60 without moving the slider and restores the previous fps on close.
##   elapsed = now - last; ticks = elapsed \ period_ms; last += ticks * period_ms
##
## The remainder carries over to the next frame. Implemented with an own millisecond
## accumulator in `_process`, not `_physics_process` or `Engine.time_scale`.
extends Node

signal ticked
## Once per frame after the tick loop, with the number of ticks it ran (> 0): the visual
## side syncs to the simulation here, not per tick, so a stall does not multiply its cost.
signal frame_ticked(ticks: int)
signal speed_changed(fps: int)

const BASE_FPS := 40
const DEFAULT_SLIDER := 20
const FAST_SLIDER := 100
const NORMAL_FPS := 60
const FAST_FPS := 120
const SLIDER_MAX := 100
## Safety cap so a long stall (window hidden) does not replay thousands of ticks at once.
const MAX_TICKS_PER_FRAME := 250

var _slider := DEFAULT_SLIDER
var _fps := BASE_FPS + DEFAULT_SLIDER
## Position of the HUD time slider; assigning it is a slider drag (fps = 40 + slider).
var slider: int:
	get:
		return _slider
	set(v):
		_set_speed(v, BASE_FPS + clampi(v, 0, SLIDER_MAX))
var paused := true
var _accumulator_ms := 0.0
var tick_callback: Callable = Callable()


func fps() -> int:
	return _fps


func period_ms() -> int:
	return Blitz.idiv(1000, fps())


func ticks_per_second() -> float:
	return 1000.0 / float(period_ms())


func _process(delta: float) -> void:
	if paused:
		_accumulator_ms = 0.0
		return
	_accumulator_ms += delta * 1000.0
	var ticks := ticks_for(_accumulator_ms, period_ms())
	_accumulator_ms -= float(ticks * period_ms())
	var n := mini(ticks, MAX_TICKS_PER_FRAME)
	for i in n:
		if tick_callback.is_valid():
			tick_callback.call()
		ticked.emit()
	if n > 0:
		frame_ticked.emit(n)


## Number of whole periods contained in `elapsed_ms` (integer division as in Blitz).
static func ticks_for(elapsed_ms: float, period: int) -> int:
	return Blitz.idiv(int(elapsed_ms), period)


func _set_speed(slider_value: int, fps_value: int) -> void:
	_slider = clampi(slider_value, 0, SLIDER_MAX)
	_fps = fps_value
	speed_changed.emit(_fps)


## Changes the rate only, the slider stays where it is (`_fshowingamemenu`/`_fhideingamemenu`).
func set_fps(fps_value: int) -> void:
	_set_speed(_slider, fps_value)


func set_normal_speed() -> void:
	_set_speed(DEFAULT_SLIDER, NORMAL_FPS)


func set_fast_speed() -> void:
	_set_speed(FAST_SLIDER, FAST_FPS)
