## Window mode, vsync, gamma (`_fsetgamma`: the D3D gamma ramp of the original, here a
## full-screen pass over the frame) and the screen layout. What can be applied depends on
## the platform: the desktop owns its window, the browser grants fullscreen only from a
## user gesture, a phone decides everything itself.
##
## Layout: the game is authored for an 800x600 canvas (`BOX`). In the "4:3" mode the canvas
## is letterboxed into the window; in "Wide" the canvas expands along the axis that has room
## and the 800x600 box (2D layers in `GROUP_BOX_LAYER`) is centred in it, while the cameras
## (`GROUP_BOX_CAMERA`) keep the original 4:3 frame visible and show more world around it.
## The expansion follows the window aspect up to `aspect_limits` (a location narrows its
## scroll range to keep the wider frame inside the level and caps the aspect where that
## range would collapse, see CameraRig); beyond the limits the canvas is letterboxed again.
extends Node

## Emitted after `canvas_size`, `ui_offset` and the registered layers/cameras were updated.
signal layout_changed

const BOX := Vector2(800, 600)
const WIDE := "WideScreen"  # setting: 0 = 4:3 letterbox, 1 = wide
const GROUP_BOX_LAYER := "box_layer"
const GROUP_BOX_CAMERA := "box_camera"
const FOV_H := 60.0  # the original horizontal fov of the 800x600 frame
const NO_ASPECT_LIMITS := Vector2(0.0, INF)
const NO_POSITION := Vector2i(-1, -1)  # `WindowX` / `WindowY`: never saved -> centre the window

const PLATFORM_WEB := "web"
const PLATFORM_MOBILE := "mobile"
const PLATFORM_DESKTOP := "desktop"
const WINDOWED := 2  # `Windowed` setting: 2 = window, 1 = fullscreen
const GAMMA_LAYER := 50  # above the HUD (10) and the debug overlay (20)
const GAMMA_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float gamma = 1.0;
void fragment() {
	COLOR = vec4(pow(texture(screen_tex, SCREEN_UV).rgb, vec3(1.0 / gamma)), 1.0);
}
"""

var gamma_intensity := 0
var wide := false
## Window aspects (min, max) the canvas follows in wide mode; wider / taller windows get bars.
var aspect_limits := NO_ASPECT_LIMITS
var _aspect_owner: Object = null  # the screen / camera rig that set them
## The canvas in pixels (`BOX` in 4:3 and headless) and where the 800x600 box sits in it.
var canvas_size := BOX
var ui_offset := Vector2.ZERO
## Phone safe area as canvas-pixel insets from the left/top (`safe_min`) and right/bottom
## (`safe_max`) canvas edges: notches, rounded corners, the gesture bar. Anchored HUD
## groups stay inside them. Zero on the desktop unless `safe_area_override` simulates one.
var safe_min := Vector2.ZERO
var safe_max := Vector2.ZERO
var safe_area_override := Rect2i()  # --safe-area=L,T,R,B: window-pixel insets for testing
var _gamma_layer: CanvasLayer
var _gamma_material: ShaderMaterial
var _window_size := Vector2i.ZERO  # the window size the current layout was made for


func _ready() -> void:
	get_tree().root.size_changed.connect(_relayout)
	set_process(not headless())


## `size_changed` is the viewport's signal: it stays silent when the window changes but
## the letterboxed canvas does not -- e.g. a 4:3 canvas in a window dragged wider at the
## same height -- which is exactly when the wide canvas should grow. Watch the window too.
func _process(_delta: float) -> void:
	if get_tree().root.size != _window_size:
		_relayout()


static func platform() -> String:
	if OS.has_feature(PLATFORM_WEB):
		return PLATFORM_WEB
	if OS.has_feature(PLATFORM_MOBILE):
		return PLATFORM_MOBILE
	return PLATFORM_DESKTOP


## Gamma exponent for a `GammaIntensity` of -100..100: 0.5 (dark) .. 1 .. 2 (bright).
static func gamma_exponent(intensity: int) -> float:
	return pow(2.0, intensity / 100.0)


static func headless() -> bool:
	return DisplayServer.get_name() == "headless"


## The wide-mode canvas for a window of `window` pixels: the window aspect clamped to
## `limits`, grown from the 800x600 box along the axis that has room.
static func canvas_for(window: Vector2, limits: Vector2) -> Vector2:
	var aspect := clampf(window.x / window.y, minf(limits.x, BOX.x / BOX.y), maxf(limits.y, BOX.x / BOX.y))
	if aspect >= BOX.x / BOX.y:
		return Vector2(round(BOX.y * aspect), BOX.y)
	return Vector2(BOX.x, round(BOX.x / aspect))


## Canvas-pixel insets [min, max] of a safe area given in window pixels: the part of each
## inset that the letterbox bars do not already cover, divided by the canvas scale.
static func safe_insets_for(window: Vector2, canvas: Vector2, insets_min: Vector2, insets_max: Vector2) -> Array[Vector2]:
	var scale := minf(window.x / canvas.x, window.y / canvas.y)
	var bars := (window - canvas * scale) / 2.0
	return [((insets_min - bars) / scale).max(Vector2.ZERO), ((insets_max - bars) / scale).max(Vector2.ZERO)]


## Canvas-pixel shift of a group anchored at `anchor` (-1 / 0 / 1 per axis, fractions
## blend): its share of the box offset, pulled back by the safe inset on its own side.
static func anchor_shift_for(anchor: Vector2, offset: Vector2, insets_min: Vector2, insets_max: Vector2) -> Vector2:
	return Vector2(
		anchor.x * (offset.x - (insets_max.x if anchor.x > 0.0 else insets_min.x)),
		anchor.y * (offset.y - (insets_max.y if anchor.y > 0.0 else insets_min.y)))


func anchor_shift(anchor: Vector2) -> Vector2:
	return anchor_shift_for(anchor, ui_offset, safe_min, safe_max)


## Top-left corner of the 800x600 box centred in a canvas of `canvas` pixels.
static func box_offset(canvas: Vector2) -> Vector2:
	return ((canvas - BOX) / 2.0).round().max(Vector2.ZERO)


## Camera projection for a canvas of `canvas` pixels: the original 4:3 frame stays fully
## visible and centred. A canvas at least as wide as 4:3 keeps the vertical fov of that
## frame (KEEP_HEIGHT), a taller one keeps its horizontal fov (KEEP_WIDTH).
static func camera_params(canvas: Vector2) -> Dictionary:
	if canvas.x / canvas.y >= BOX.x / BOX.y:
		# `get_fovy` takes height / width, as Camera3D itself calls it for KEEP_WIDTH.
		return {"keep_aspect": Camera3D.KEEP_HEIGHT, "fov": Projection.get_fovy(FOV_H, BOX.y / BOX.x)}
	return {"keep_aspect": Camera3D.KEEP_WIDTH, "fov": FOV_H}


## The live window state; on the web it can differ from the saved `Windowed` (fullscreen
## is never restored at start and Esc leaves it), so the settings toggle follows this.
func windowed_value() -> int:
	if headless() or get_window().mode != Window.MODE_FULLSCREEN:
		return WINDOWED
	return 1


## Apply `Windowed` / `VSync` / `GammaIntensity`. `from_input` is set when the call comes
## from the settings "ok" click: a browser accepts fullscreen only inside a user gesture.
func apply(settings: Dictionary, from_input := false) -> void:
	if headless():
		return
	var fullscreen := int(settings["Windowed"]) != WINDOWED
	match platform():
		PLATFORM_DESKTOP:
			if from_input:
				remember_window(settings)  # "ok" re-applies where the window is now, not where it started
			_apply_desktop_window(settings, fullscreen)
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if int(settings["VSync"]) == 1 else DisplayServer.VSYNC_DISABLED)
		PLATFORM_WEB:
			if from_input:
				get_window().mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	set_wide(int(settings[WIDE]) == 1)
	set_gamma(int(settings["GammaIntensity"]))


# ---------------------------------------------------------------- 4:3 / wide layout


## Switch between the letterboxed 4:3 canvas and the expanding one. The relayout is
## explicit: in a 4:3 window the canvas size does not change and `size_changed` stays silent.
func set_wide(on: bool) -> void:
	wide = on
	if headless():
		return
	_relayout()


## The current screen's aspect range (see `canvas_for`), on behalf of `owner`; a screen
## that is freed deferred releases through `release_aspect_limits`, which ignores it once a
## successor took over -- so ownership is by object, not by value.
func set_aspect_limits(limits: Vector2, owner: Object = null) -> void:
	_aspect_owner = owner
	if limits == aspect_limits:
		return
	aspect_limits = limits
	if not headless():
		_relayout()


## Back to following the window, unless someone else owns the limits by now.
func release_aspect_limits(owner: Object) -> void:
	if _aspect_owner == owner:
		set_aspect_limits(NO_ASPECT_LIMITS)


## A 2D layer laid out in 800x600 box coordinates: shifted to the centre of the canvas.
func register_layer(layer: CanvasLayer) -> void:
	layer.add_to_group(GROUP_BOX_LAYER)
	layer.offset = box_offset(_canvas_size())


## A camera of the game or menu world: projected so the 4:3 frame stays in view.
func register_camera(cam: Camera3D) -> void:
	cam.add_to_group(GROUP_BOX_CAMERA)
	_apply_camera(cam, camera_params(_canvas_size()))


func _canvas_size() -> Vector2:
	return get_tree().root.get_visible_rect().size


func _relayout() -> void:
	var root := get_tree().root
	_window_size = root.size
	var target := canvas_for(Vector2(root.size), aspect_limits) if wide else BOX
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if Vector2(root.content_scale_size) != target:
		root.content_scale_size = Vector2i(target)  # re-enters through `size_changed` with the same target
	var canvas := _canvas_size()
	canvas_size = canvas
	ui_offset = box_offset(canvas)
	var insets := _window_safe_insets(root)
	var safe := safe_insets_for(Vector2(root.size), canvas, insets[0], insets[1])
	safe_min = safe[0]
	safe_max = safe[1]
	for layer in get_tree().get_nodes_in_group(GROUP_BOX_LAYER):
		(layer as CanvasLayer).offset = ui_offset
	var params := camera_params(canvas)
	for cam in get_tree().get_nodes_in_group(GROUP_BOX_CAMERA):
		_apply_camera(cam as Camera3D, params)
	layout_changed.emit()


## Safe-area insets in window pixels: the display's safe area against the window on a
## phone (the window is the whole screen there), the override elsewhere.
func _window_safe_insets(root: Window) -> Array[Vector2]:
	if safe_area_override != Rect2i():
		return [Vector2(safe_area_override.position), Vector2(safe_area_override.size)]
	if platform() != PLATFORM_MOBILE:
		return [Vector2.ZERO, Vector2.ZERO]
	var safe := DisplayServer.get_display_safe_area()
	var win := Rect2i(root.position, root.size)
	return [Vector2((safe.position - win.position).max(Vector2i.ZERO)), Vector2((win.end - safe.end).max(Vector2i.ZERO))]


static func _apply_camera(cam: Camera3D, params: Dictionary) -> void:
	cam.keep_aspect = params["keep_aspect"]
	cam.fov = params["fov"]


# ---------------------------------------------------------------- desktop window


## Windowed: the size (and maximized state) the window had when the game last quit.
func _apply_desktop_window(settings: Dictionary, fullscreen: bool) -> void:
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	var size := Vector2i(int(settings["XRes"]), int(settings["YRes"]))
	if size.x > 0 and size.y > 0:
		window.size = size
	# The window opens at the engine's default spot: a restored (larger) size would hang
	# off the screen, so put it where it was, or centre it, inside the usable area.
	var saved := Vector2i(int(settings["WindowX"]), int(settings["WindowY"]))
	var screen := window.current_screen if saved == NO_POSITION else _screen_of(saved, window.current_screen)
	window.position = window_position_for(saved, window.size, DisplayServer.screen_get_usable_rect(screen))
	if int(settings["WindowMaximized"]) == 1:
		window.mode = Window.MODE_MAXIMIZED


## The screen holding `point` (a saved window position may be on a second monitor), else
## `fallback`.
static func _screen_of(point: Vector2i, fallback: int) -> int:
	for i in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(i).has_point(point):
			return i
	return fallback


## Where a window of `size` goes on a screen whose usable area is `usable`: the `saved`
## position pulled back so the window stays inside, or the centre when there is none
## (`NO_POSITION`) or the window does not fit at all.
static func window_position_for(saved: Vector2i, size: Vector2i, usable: Rect2i) -> Vector2i:
	var room := usable.size - size
	if saved == NO_POSITION or room.x < 0 or room.y < 0:
		return usable.position + room / 2
	return saved.clamp(usable.position, usable.position + room)


## Desktop, on quit: remember the window as the user left it (a fullscreen window keeps
## the last windowed size on record).
func remember_window(settings: Dictionary) -> void:
	if headless() or platform() != PLATFORM_DESKTOP:
		return
	var window := get_window()
	match window.mode:
		Window.MODE_WINDOWED:
			settings["XRes"] = window.size.x
			settings["YRes"] = window.size.y
			settings["WindowX"] = window.position.x
			settings["WindowY"] = window.position.y
			settings["WindowMaximized"] = 0
		Window.MODE_MAXIMIZED:
			settings["WindowMaximized"] = 1


# ---------------------------------------------------------------- gamma


func set_gamma(intensity: int) -> void:
	gamma_intensity = intensity
	if headless():
		return
	if _gamma_layer == null:
		_build_gamma_overlay()
	# No screen copy at all while the ramp is flat.
	_gamma_layer.visible = intensity != 0
	_gamma_material.set_shader_parameter("gamma", gamma_exponent(intensity))


func _build_gamma_overlay() -> void:
	var shader := Shader.new()
	shader.code = GAMMA_SHADER
	_gamma_material = ShaderMaterial.new()
	_gamma_material.shader = shader
	_gamma_layer = CanvasLayer.new()
	_gamma_layer.layer = GAMMA_LAYER
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _gamma_material
	_gamma_layer.add_child(rect)
	add_child(_gamma_layer)
