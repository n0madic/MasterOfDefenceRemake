extends SceneTree
func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.5
	cam.far = 3000
	world.add_child(cam)
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.2, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment = e
	world.add_child(env)
	var scene: Node3D = load("res://assets/models/Menu/env.glb").instantiate()
	world.add_child(scene)
	var cs: Node3D = load("res://assets/models/Menu/cameraEnv.glb").instantiate()
	world.add_child(cs)
	var n: Node3D = cs.find_child("Camera01", true, false)
	await process_frame
	cam.global_transform = n.global_transform * Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO)
	print("cam ", cam.global_position, " fwd ", -cam.global_transform.basis.z, " up ", cam.global_transform.basis.y)
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-501/menu_env.png")
	quit(0)
