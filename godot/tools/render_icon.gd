## Renders the game icon from the converted Military tower (the original td.ico is a 48x48
## render of the same model) on a transparent background (needs a window, not --headless):
##   godot --path godot -s res://tools/render_icon.gd [-- OUT.png [level] [elev] [yaw]]
## The tower is drawn into an offscreen viewport, cropped to a square around its pixels (the
## ground patch is hidden) and written to res://icons/icon_1024.png, the source of every
## launcher icon (see make_icons.gd).
extends SceneTree

const MODEL := "res://assets/models/Towers/Military.glb"
const DEFAULT_OUT := "res://icons/icon_1024.png"
const OUT_SIZE := 1024
const RENDER_SIZE := 2048  # offscreen viewport, downscaled for the final icon
const DEFAULT_LEVEL := 10
const DEFAULT_ELEVATION := 15.0  # camera pitch above the horizon, degrees
const DEFAULT_YAW := 25.0  # camera turn around the tower, degrees
const IDLE_SEQ_FRAMES := 20  # Tower.gd: idle seq of level L = 2L+1 -> frames 20L..20L+10
const IDLE_FRAME_OFFSET := 5.0
const FLAT_MESH_HEIGHT := 0.5  # the ground patch under the tower has no height
const AMBIENT := Color(0.55, 0.55, 0.55)
const SUN_DIRECTION := Vector3(-50, -30, 0)  # degrees, like a location without B3DEXT_DIRLIGHT
const FOV := 30.0
const PADDING := 0.04  # fraction of the crop side left around the tower
const SETTLE_FRAMES := 4  # frames for the animation and the transforms to apply
const CAPTURE_FRAME := 8

var out := DEFAULT_OUT
var elevation := DEFAULT_ELEVATION
var yaw := DEFAULT_YAW
var viewport: SubViewport
var model: Node3D
var camera: Camera3D
var frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var level := int(args[1]) if args.size() > 1 else DEFAULT_LEVEL
	if args.size() > 2:
		elevation = float(args[2])
	if args.size() > 3:
		yaw = float(args[3])
	viewport = SubViewport.new()
	viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = AMBIENT
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = SUN_DIRECTION
	sun.shadow_enabled = false
	world.add_child(sun)
	model = load(MODEL).instantiate()
	world.add_child(model)
	BlitzAnimator.hide_helpers(model)
	_hide_flat_meshes()
	var player := BlitzAnimator.find_player(model)
	if player != null:
		BlitzAnimator.seek(player, IDLE_SEQ_FRAMES * level + IDLE_FRAME_OFFSET)
	camera = Camera3D.new()
	camera.fov = FOV
	world.add_child(camera)
	camera.current = true


## The ground patch under the tower is a flat mesh: not part of the icon.
func _hide_flat_meshes() -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.get_aabb().size.y < FLAT_MESH_HEIGHT:
			mi.visible = false


func _tower_bounds() -> AABB:
	var aabb := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	return aabb


func _place_camera() -> void:
	var aabb := _tower_bounds()
	var centre := aabb.get_center()
	var radius := aabb.size.length() * 0.5
	var distance := radius / tan(deg_to_rad(FOV * 0.5))
	var dir := Vector3.BACK.rotated(Vector3.RIGHT, deg_to_rad(-elevation)).rotated(Vector3.UP, deg_to_rad(yaw))
	camera.position = centre + dir * distance
	camera.look_at(centre, Vector3.UP)


func _capture() -> void:
	var img := viewport.get_texture().get_image()
	var used := img.get_used_rect()
	var side := int(used.size.x * (1.0 + 2.0 * PADDING))
	var crop := Rect2i(used.position.x - int(used.size.x * PADDING), used.position.y - int(used.size.x * PADDING), side, side)
	crop = crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var icon := img.get_region(crop)
	icon.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
	var err := icon.save_png(out)
	if err != OK:
		push_error("render_icon: cannot write %s (%d)" % [out, err])
		quit(1)
		return
	print("%s %s (crop %s of %s)" % [out, icon.get_size(), crop, img.get_size()])
	quit(0)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == SETTLE_FRAMES:
		_place_camera()
	elif frames == CAPTURE_FRAME:
		_capture()
	return false
