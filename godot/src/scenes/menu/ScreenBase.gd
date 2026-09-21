## Base of the 3D menu screens: own camera + black environment (or, with `overlay_camera`
## set before entering the tree, the sheet hangs on that camera over the running scene as
## the original's game-over / congratulations sheets do over the location), a MenuScene3D
## driven by the Ticker, mouse clicks forwarded to the scene, and a 2D layer for BlitzText.
##
## A screen with its own camera also owns the wide-mode aspect range: the menu sheets and
## their backdrops are built for the 4:3 frame (parked items and the ends of the backdrop
## sit right outside it), so the default is a strict 4:3; a screen whose environment has
## some slack widens `aspect_limits` before `_ready`.
class_name ScreenBase
extends Node

const ASPECT_4_3 := Vector2(4.0 / 3.0, 4.0 / 3.0)

var aspect_limits := ASPECT_4_3
var camera: Camera3D
var world: Node3D
var canvas: CanvasLayer
var menu: MenuScene3D
var closed := false
var overlay_camera: Camera3D


func _ready() -> void:
	if overlay_camera != null:
		camera = overlay_camera
	else:
		world = Node3D.new()
		world.name = "World"
		add_child(world)
		camera = Camera3D.new()
		camera.near = 0.5
		camera.far = 2000.0
		world.add_child(camera)
		camera.current = true
		DisplayManager.register_camera(camera)  # a borrowed camera is registered by its owner
		DisplayManager.set_aspect_limits(aspect_limits, self)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color.BLACK
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.5, 0.5, 0.5)
		env.environment = e
		world.add_child(env)
	canvas = CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	DisplayManager.register_layer(canvas)
	Ticker.ticked.connect(_on_ticked)
	Ticker.paused = false


## Release the aspect range -- `close()` frees deferred, so the successor may own it by now.
func _exit_tree() -> void:
	if overlay_camera == null:
		DisplayManager.release_aspect_limits(self)


func make_menu(path: String, item_names: Array) -> MenuScene3D:
	var m := MenuScene3D.new()
	m.load_scene(path, camera, item_names)
	m.item_clicked.connect(_on_item)
	if menu == null:
		menu = m
	return m


func text(pos: Vector2, s: String, color: Color, scale_value := 1.0, spacing := 5.0) -> BlitzText:
	var t := BlitzText.new()
	t.position = pos
	t.text = s
	t.color = color
	t.text_scale = scale_value
	t.spacing = spacing
	canvas.add_child(t)
	return t


func _on_ticked() -> void:
	if closed:
		return
	var mouse := get_viewport().get_mouse_position()
	for c in camera.get_children():
		if c is MenuScene3D:
			c.tick(mouse)
	_tick()


## Per-tick hook for subclasses.
func _tick() -> void:
	pass


func _on_item(_name: String) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if closed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for c in camera.get_children():
			if c is MenuScene3D:
				c.click(event.position)


func close() -> void:
	closed = true
	if Ticker.ticked.is_connected(_on_ticked):
		Ticker.ticked.disconnect(_on_ticked)
	if menu != null and overlay_camera != null:
		menu.queue_free()  # parented to the borrowed camera, not to this screen
	queue_free()
