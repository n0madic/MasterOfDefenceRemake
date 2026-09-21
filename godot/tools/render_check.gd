## Visual smoke check of converted assets (needs a window, not --headless):
##   godot --path godot --resolution 800x600 -s res://tools/render_check.gd -- [L] [out.png]
## Renders Location L with a Military tower and a Crawl at path key 0 facing key 1.
extends SceneTree

const GameDataScript := preload("res://src/autoload/GameData.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var L := int(args[0]) if args.size() > 0 else 1
	var out := args[1] if args.size() > 1 else "user://render_check_L%d.png" % L
	var data: Node = GameDataScript.new()
	data.load_all()
	var world := Node3D.new()
	root.add_child(world)
	var loc: Node = load("res://assets/models/Location%d/Location%d.glb" % [L, L]).instantiate()
	world.add_child(loc)
	var keys: PackedVector3Array = data.paths[L]["pos"]
	var tower: Node3D = load("res://assets/models/Towers/Military.glb").instantiate()
	world.add_child(tower)
	tower.position = keys[3] + Vector3(6, 0, 0)
	var ap: AnimationPlayer = tower.get_node("AnimationPlayer")
	ap.assigned_animation = "b3d"
	ap.seek(11.0, true)  # idle of level 0
	var monster := args[4] if args.size() > 4 else "Crawl"
	var crawl: Node3D = load("res://assets/models/Monsters/%s.glb" % monster).instantiate()
	world.add_child(crawl)
	crawl.position = keys[2]
	crawl.look_at_from_position(keys[2], keys[3], Vector3.UP)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-60, 30, 0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	world.add_child(env)
	var cam := Camera3D.new()
	world.add_child(cam)
	var bounds: Dictionary = data.location(L)["bounds"]
	var pivot := Vector3((bounds["x_min"] + bounds["x_max"]) / 2.0, 0, (bounds["z_min"] + bounds["z_max"]) / 2.0)
	if args.size() > 2:
		pivot = keys[int(args[2])]
	var height := float(args[3]) if args.size() > 3 else 30.0
	cam.look_at_from_position(pivot + Vector3(0, height, height * 0.7), pivot, Vector3.UP)
	cam.fov = 60
	cam.current = true
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))
	data.free()
	quit(0)
