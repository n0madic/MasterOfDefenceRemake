## Renders a one-shot effect (`*Eff.glb`, death animation, ...) frame by frame:
## godot --path godot --resolution 800x600 -s res://tools/render_effect.gd -- MODEL.glb OUT_DIR [scale] [speed] [distance]
## Writes OUT_DIR/f_<tick>.png after every logic tick until the animation ends.
extends SceneTree

var view: OneShotView
var out_dir := ""
var tick := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: MODEL.glb OUT_DIR [scale] [speed] [distance]")
		quit(1)
		return
	out_dir = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scale := float(args[2]) if args.size() > 2 else 0.7
	var speed := float(args[3]) if args.size() > 3 else 0.2
	var distance := float(args[4]) if args.size() > 4 else 12.0
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.3, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	root3d.add_child(env)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, distance * 0.7, distance * 0.7), Vector3.ZERO)
	view = OneShotView.new()
	root3d.add_child(view)
	view.setup(args[0], Vector3.ZERO, scale, speed)


func _process(_delta: float) -> bool:
	if view == null:
		return true
	if tick > 0:
		var img := get_root().get_texture().get_image()
		img.save_png(out_dir.path_join("f_%03d.png" % (tick - 1)))
	tick += 1
	if view.finished:
		quit()
		return true
	view.tick()
	return false
