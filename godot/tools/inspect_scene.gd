## Debug helper: godot --headless --path godot -s res://tools/inspect_scene.gd -- res://assets/models/X.glb
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for path in args:
		var scene: PackedScene = load(path)
		if scene == null:
			print("cannot load ", path)
			continue
		var root := scene.instantiate()
		print("=== ", path)
		_dump(root, 0)
		root.free()
	quit(0)


func _dump(n: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + n.name + " (" + n.get_class() + ")"
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		line += " surfaces=%d" % mi.mesh.get_surface_count()
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var sm := m as StandardMaterial3D
				line += " [%s tex=%s alpha=%s cull=%s unshaded=%s]" % [sm.resource_name, sm.albedo_texture != null, sm.transparency, sm.cull_mode, sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED]
		if mi.mesh.get_blend_shape_count() > 0:
			line += " blendshapes=%d" % mi.mesh.get_blend_shape_count()
	if n is AnimationPlayer:
		var ap := n as AnimationPlayer
		for a in ap.get_animation_list():
			var anim := ap.get_animation(a)
			line += " anim %s len=%s tracks=%d" % [a, anim.length, anim.get_track_count()]
	print(line)
	for c in n.get_children():
		_dump(c, depth + 1)
