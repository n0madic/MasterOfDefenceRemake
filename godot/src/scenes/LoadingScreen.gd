## The "Loading..." plank of the original (`Loading.png`) on black, shown the moment a
## location is requested: the load that follows stalls the frame for a while (models,
## textures, then the shader compiles of the warm-up), and the sheet is the reaction the
## player sees to the button meanwhile. Drawn above the warm-up's own black overlay.
class_name LoadingScreen
extends CanvasLayer

const TEXTURE := "res://assets/textures/Menu/Loading.png"
const LAYER := 129
const RECT := Rect2(-4000, -4000, 12000, 12000)
## Frames the sheet outlives the location's first frame (the HUD's own variants compile
## there), and the most it waits for a warm-up still drawing under it.
const LINGER_FRAMES := 2
const MAX_WARMUP_FRAMES := 120

var plank: TextureRect


func _init() -> void:
	layer = LAYER
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.position = RECT.position
	rect.size = RECT.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	plank = TextureRect.new()
	plank.texture = load(TEXTURE)
	plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plank)


func _ready() -> void:
	_centre()
	get_viewport().size_changed.connect(_centre)


func _centre() -> void:
	var canvas := get_viewport().get_visible_rect().size
	plank.position = (canvas - plank.texture.get_size()) / 2.0


## The location is up: stay while its warm-up still draws (the compiles), plus a frame or
## two, then go (at once in headless, where no frame is ever drawn).
func finish() -> void:
	if DisplayManager.headless():
		queue_free()
		return
	_finish(self)


## Waits on the script, not on the node: the tree may drop it before the frames pass.
static func _finish(node: Node) -> void:
	var waited := 0
	while ModelWarmup.is_running() and waited < MAX_WARMUP_FRAMES:
		await RenderingServer.frame_post_draw
		waited += 1
	for i in LINGER_FRAMES:
		await RenderingServer.frame_post_draw
	if is_instance_valid(node):
		node.queue_free()
