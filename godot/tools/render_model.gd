## Renders one converted model in front of a camera (needs a window, not --headless):
##   godot --path godot --resolution 800x600 -s res://tools/render_model.gd -- MODEL.glb OUT.png [frame] [distance] [tint] [rot_x] [rot_y]
## The model is placed `distance` units ahead of the camera, the `b3d` animation is sought
## to `frame`, and `tint` (a hex colour) is applied with BlitzAnimator.tint.
extends SceneTree

var frames := 0
var out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	out = args[1] if args.size() > 1 else "user://render_model.png"
	var frame := float(args[2]) if args.size() > 2 else 0.0
	var distance := float(args[3]) if args.size() > 3 else 10.0
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	world.add_child(cam)
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.2, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment = e
	world.add_child(env)
	var model: Node3D = load(path).instantiate()
	world.add_child(model)
	model.position = Vector3(0, 0, -distance)
	if args.size() > 5:
		model.rotation_degrees = Vector3(float(args[5]), float(args[6]) if args.size() > 6 else 0.0, 0)
	BlitzAnimator.hide_helpers(model)
	var player := BlitzAnimator.find_player(model)
	if player != null:
		BlitzAnimator.seek(player, frame)
	if args.size() > 4:
		BlitzAnimator.tint(model, Color.html(args[4]))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_active_material(0)
		print(mi.name, " aabb ", (mi as MeshInstance3D).get_aabb(), " scale ", (mi as Node3D).scale, " material ", m)
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			print("  albedo ", sm.albedo_color, " blend ", sm.blend_mode, " tex ", sm.albedo_texture, " transparency ", sm.transparency, " shading ", sm.shading_mode)
		elif m is ShaderMaterial:
			var shm := m as ShaderMaterial
			print("  shader albedo ", shm.get_shader_parameter("albedo"), " layer0 ", shm.get_shader_parameter("layer0"), " layer1 ", shm.get_shader_parameter("layer1"))


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		quit(0)
	return false
