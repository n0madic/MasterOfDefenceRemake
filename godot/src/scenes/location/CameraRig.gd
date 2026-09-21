## Camera of the location (`_fupdatecamera` / `_fcontrolcamera`): a pivot at height 30
## moves inside the location rectangle 1 unit per tick; the camera position eases towards
## the pivot by 1/20 per tick. The camera looks 45 degrees down along -Z (Blitz +Z).
##
## Wide screen: the scroll rectangle of the data keeps the 4:3 frame inside the level, so
## for a wider (or taller) canvas it is narrowed by as much as the ground footprint of the
## frame grew (`fit_bounds`) -- at the edge the camera then shows what 4:3 showed. Where the
## rectangle would collapse the canvas is capped instead (`aspect_limits_for`, letterbox).
class_name CameraRig
extends Node3D

const PIVOT_HEIGHT := 30.0
const SCROLL_STEP := 1.0
const SMOOTHING := 20.0
const PITCH_DEGREES := -45.0
const EDGE_PIXELS := 1

var pivot := Vector3.ZERO
var data_bounds := Rect2(0, 0, 100, 100)  # the location's scroll rectangle (x: x_min..x_max, y: z_min..z_max)
var bounds := data_bounds  # `data_bounds` narrowed for the current canvas
var camera: Camera3D
var scroll_enabled := true
## Scrolling with the mouse at the window edge; off once a touch is seen (the emulated
## pointer parks wherever the finger left the screen), on again with a real mouse motion.
var edge_scroll_enabled := true


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.5
	camera.far = 600.0
	camera.rotation_degrees = Vector3(PITCH_DEGREES, 0, 0)
	add_child(camera)
	camera.current = true
	DisplayManager.register_camera(camera)
	DisplayManager.layout_changed.connect(_refit)


## Release the limits -- a successor rig (quick load, restart) may already own them.
func _exit_tree() -> void:
	DisplayManager.release_aspect_limits(self)


func setup(location: Dictionary) -> void:
	var b: Dictionary = location["bounds"]
	data_bounds = Rect2(float(b["x_min"]), float(b["z_min"]), float(b["x_max"]) - float(b["x_min"]), float(b["z_max"]) - float(b["z_min"]))
	bounds = data_bounds
	pivot = Vector3(bounds.position.x + bounds.size.x / 2.0, PIVOT_HEIGHT, bounds.position.y + bounds.size.y / 2.0)
	camera.position = pivot
	DisplayManager.set_aspect_limits(aspect_limits_for(data_bounds), self)
	_refit()


## Narrow the scroll rectangle to the current canvas and keep the pivot inside it.
func _refit() -> void:
	bounds = fit_bounds(data_bounds, DisplayManager.canvas_size)
	pivot.x = clampf(pivot.x, bounds.position.x, bounds.end.x)
	pivot.z = clampf(pivot.z, bounds.position.y, bounds.end.y)


## Ground footprint of the camera frame for a canvas of `canvas` pixels (camera at rest on
## its pivot): distance ahead of the camera of the far (top) and near (bottom) screen edges
## and the half-width of the frame at the far edge, where it is widest.
static func frame(canvas: Vector2) -> Dictionary:
	var params := DisplayManager.camera_params(canvas)
	var aspect := canvas.x / canvas.y
	var tan_half: float = tan(deg_to_rad(float(params["fov"]) / 2.0))
	var tan_half_v := tan_half if params["keep_aspect"] == Camera3D.KEEP_HEIGHT else tan_half / aspect
	var tan_half_h := tan_half * aspect if params["keep_aspect"] == Camera3D.KEEP_HEIGHT else tan_half
	var half_v := atan(tan_half_v)
	var pitch := deg_to_rad(-PITCH_DEGREES)
	var top := pitch - half_v  # angle of the top ray below the horizon
	var bottom := minf(pitch + half_v, PI / 2.0)
	var far := PIVOT_HEIGHT / tan(top) if top > 0.0 else INF
	var near := PIVOT_HEIGHT / tan(bottom)
	var depth_top := PIVOT_HEIGHT / sin(top) * cos(half_v) if top > 0.0 else INF
	return {"far": far, "near": near, "half_w": depth_top * tan_half_h}


## The scroll rectangle for `canvas`: `data` shrunk by the growth of the frame footprint
## over the 4:3 one on each side (collapsed to its centre when the frame outgrew it).
static func fit_bounds(data: Rect2, canvas: Vector2) -> Rect2:
	var f0 := frame(DisplayManager.BOX)
	var f := frame(canvas)
	var dx: float = f["half_w"] - f0["half_w"]
	var d_far: float = f["far"] - f0["far"]
	var d_near: float = f0["near"] - f["near"]
	var r := Rect2(data.position + Vector2(dx, d_far), data.size - Vector2(2.0 * dx, d_far + d_near))
	if r.size.x < 0.0:
		r.position.x = data.get_center().x
		r.size.x = 0.0
	if r.size.y < 0.0:
		r.position.y = data.get_center().y
		r.size.y = 0.0
	return r


## Window aspects (min, max) up to which `fit_bounds` still has room in `data`: the frame's
## half-width grows linearly with the aspect; on the taller side both the far edge and the
## width at it grow, the limit is found by bisection on the canvas height.
static func aspect_limits_for(data: Rect2) -> Vector2:
	var f0 := frame(DisplayManager.BOX)
	var box_aspect: float = DisplayManager.BOX.x / DisplayManager.BOX.y
	var max_aspect: float = box_aspect * (1.0 + data.size.x / 2.0 / float(f0["half_w"]))
	var lo: float = DisplayManager.BOX.y
	var hi: float = DisplayManager.BOX.x * 4.0
	for i in 40:
		var mid := (lo + hi) / 2.0
		var r := fit_bounds(data, Vector2(DisplayManager.BOX.x, mid))
		if r.size.x > 0.0 and r.size.y > 0.0:
			lo = mid
		else:
			hi = mid
	return Vector2(DisplayManager.BOX.x / lo, max_aspect)


func jump_to(pos: Vector3) -> void:
	pivot = Vector3(pos.x, PIVOT_HEIGHT, pos.z)
	camera.position = pivot


const LOOK_BACK := 20.0


## `_fmovecameratoentity`: the pivot moves 20 units behind the entity (Blitz z - 20 =
## Godot z + 20, towards the camera side), clamped to the bounds.
func move_to(pos: Vector3) -> void:
	pivot = Vector3(clampf(pos.x, bounds.position.x, bounds.end.x), PIVOT_HEIGHT,
		clampf(pos.z + LOOK_BACK, bounds.position.y, bounds.end.y))


## Touch panning: the pivot and the camera move together by `delta` (x / z), the pivot kept
## inside the bounds -- moving the camera alone would be undone by the easing of `tick`.
func pan(delta: Vector3) -> void:
	var before := pivot
	pivot.x = clampf(pivot.x + delta.x, bounds.position.x, bounds.end.x)
	pivot.z = clampf(pivot.z + delta.z, bounds.position.y, bounds.end.y)
	camera.position += pivot - before


## The point of the ground plane (y = 0) under viewport position `screen`; the ground under
## the pivot when the ray does not reach the plane.
func ground_point(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if dir.y >= -0.001:
		return Vector3(pivot.x, 0.0, pivot.z)
	return origin - dir * (origin.y / dir.y)


## `ticks` logic ticks of scrolling + easing (the input is sampled once for all of them).
## `mouse` is the viewport-space mouse position. The step and the 1/20 easing are per tick,
## so the loop runs `ticks` times on plain arithmetic and the camera is moved once.
func tick(mouse: Vector2, viewport_size: Vector2, ticks := 1) -> void:
	var left := false
	var right := false
	var up := false
	var down := false
	if scroll_enabled:
		# Edge scrolling only while the cursor is inside the window (Blitz clamps MouseX/Y
		# to the screen in full-screen mode; a cursor outside a window must not scroll).
		var inside := Rect2(Vector2(-EDGE_PIXELS, -EDGE_PIXELS), viewport_size + Vector2(2 * EDGE_PIXELS, 2 * EDGE_PIXELS)).has_point(mouse)
		var edge := edge_scroll_enabled and inside
		left = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) or (edge and mouse.x < EDGE_PIXELS)
		right = Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) or (edge and mouse.x > viewport_size.x - 2)
		up = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or (edge and mouse.y < EDGE_PIXELS)
		down = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or (edge and mouse.y > viewport_size.y - 2)
	var pos := camera.position
	for i in ticks:
		if left and pivot.x > bounds.position.x:
			pivot.x -= SCROLL_STEP
		if right and pivot.x < bounds.end.x:
			pivot.x += SCROLL_STEP
		# Blitz "up" (z += 1) is towards the far side of the map: Godot -z.
		if up and pivot.z > bounds.position.y:
			pivot.z -= SCROLL_STEP
		if down and pivot.z < bounds.end.y:
			pivot.z += SCROLL_STEP
		pos += (pivot - pos) / SMOOTHING
	camera.position = pos
