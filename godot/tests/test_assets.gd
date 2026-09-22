extends SimTestCase

const ZONES := ["grass", "road", "noparking", "rocks"]
## dot(local +z of the `path` node, direction to key 1) computed with Blitz's own
## quaternion math (Quat::k()) on the original data: only location 2 has the node
## oriented along the road, the others are arbitrary (the game uses PointEntity anyway).
const PATH_FORWARD_DOT := [0.0, 0.025, 1.0, 0.026, 0.035, 0.022, 0.004]


func _load_scene(path: String) -> Node:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	return scene.instantiate()


## Global transform without a running SceneTree (nodes are not "inside tree" in -s mode).
static func _global(node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _find_player(root: Node) -> AnimationPlayer:
	for c in root.get_children():
		if c is AnimationPlayer:
			return c
	return null


func test_all_models_load() -> void:
	var manifest: Dictionary = GameDataScript._read_json("res://assets/manifest.json")
	var count := 0
	for key in manifest["b3d"]:
		var info: Dictionary = manifest["b3d"][key]
		var root := _load_scene("res://" + info["glb"])
		check(root != null, "load " + key)
		if root == null:
			continue
		count += 1
		var frames := int(info["anim_frames"])
		var player := _find_player(root)
		if player != null:
			check(player.has_animation("b3d"), "animation name in " + key)
			var anim := player.get_animation("b3d")
			var expected := float(frames)
			check(absf(anim.length - expected) < 0.01 or frames == 0, "%s: anim length %s vs frames %d" % [key, anim.length, frames])
		root.free()
	for key in manifest["md2"]:
		var info: Dictionary = manifest["md2"][key]
		var root := _load_scene("res://" + info["glb"])
		check(root != null, "load " + key)
		if root == null:
			continue
		count += 1
		var mesh: MeshInstance3D = root.find_child("*", true, false) as MeshInstance3D
		for c in root.get_children():
			if c is MeshInstance3D:
				mesh = c
		check(mesh != null and mesh.mesh.get_blend_shape_count() == int(info["frames"]) - 1, "%s: blend shapes" % key)
		var player := _find_player(root)
		check(player != null and player.has_animation("md2") and absf(player.get_animation("md2").length - float(info["frames"])) < 0.01, "%s: md2 animation" % key)
		root.free()
	check_eq(count, 118, "84 b3d + 34 md2 loaded")


func test_path_nodes_match_exported_keys() -> void:
	for L in range(1, 7):
		var root := _load_scene("res://assets/models/Location%d/Path1.glb" % L)
		check(root != null, "Path1 L%d" % L)
		if root == null:
			continue
		var player := _find_player(root)
		var node: Node3D = root.find_child("path", true, false)
		check(node != null, "path node L%d" % L)
		var keys: PackedVector3Array = data.paths[L]["pos"]
		player.assigned_animation = "b3d"
		for f in [0, 1, 5]:
			player.seek(float(f), true)
			var pos := _global(node).origin
			check(pos.distance_to(keys[f]) < 0.01, "L%d key %d: %s vs %s" % [L, f, pos, keys[f]])
		# C1: Blitz +Z of the node maps to Godot forward (-Z); the dot with the road direction
		# must match the value measured on the original data.
		player.seek(0.0, true)
		var forward := -_global(node).basis.z
		var dir := (keys[1] - keys[0]).normalized()
		check_near(forward.dot(dir), PATH_FORWARD_DOT[L], 0.01, "L%d path node orientation" % L)
		root.free()


func test_location_zones_and_tower_nodes() -> void:
	for L in range(1, 7):
		var root := _load_scene("res://assets/models/Location%d/Location%d.glb" % [L, L])
		check(root != null, "Location%d" % L)
		if root == null:
			continue
		for z in ZONES:
			check(root.find_child(z, true, false) != null, "L%d has %s" % [L, z])
		if L == 3:
			check(root.find_child("grass01", true, false) != null, "L3 has a separate grass01 (not buildable)")
		root.free()
	var tower := _load_scene("res://assets/models/Towers/Military.glb")
	check(tower.find_child("fire1", true, false) != null, "fire1")
	check(tower.find_child("dno", true, false) != null, "dno")
	check_eq(_find_player(tower).get_animation("b3d").length, 210.0, "Military 210 frames")
	tower.free()
	var flame := _load_scene("res://assets/models/Towers/Fire.glb")
	check_eq(_find_player(flame).get_animation("b3d").length, 10.0, "Fire 10 frames")
	flame.free()
	var health := _load_scene("res://assets/models/health.glb")
	check(health != null and _find_player(health) != null, "health bar animation")
	if health:
		health.free()


## Brushes with spherical layers (texture flag 64) get the importer's ShaderMaterial with
## the layer textures loaded; plain brushes stay StandardMaterial3D.
func test_sphere_mapped_brushes_use_shader_material() -> void:
	var death: Node = load("res://assets/models/Towers/death.glb").instantiate()
	var sphere: MeshInstance3D = death.find_child("Sphere01", true, false)
	var m := sphere.get_active_material(0)
	check(m is ShaderMaterial, "Sphere01 uses the sphere shader")
	check_eq(m.resource_name, "01 - Default#3", "material keeps its Blitz brush name")
	check((m as ShaderMaterial).get_shader_parameter("layer0") is Texture2D, "death.png loaded as layer 0")
	check((m as ShaderMaterial).get_shader_parameter("sphere0") == true, "layer 0 is sphere mapped")
	# The additive brush alpha 0.2 is compensated for linear blending: 0.2 ** 1.5.
	var alpha := pow(0.2, 1.5)
	check(BlitzAnimator.material_color(m).is_equal_approx(Color(1, 1, 1, alpha)), "brush colour/alpha kept")
	var plane: MeshInstance3D = death.find_child("Plane01", true, false)
	check(plane.get_active_material(0) is StandardMaterial3D, "plain brushes stay StandardMaterial3D")
	BlitzAnimator.set_alpha(death, 0.5)
	check(is_equal_approx(BlitzAnimator.material_color(sphere.get_active_material(0)).a, alpha * pow(0.5, 1.5)), "EntityAlpha multiplies the brush alpha (compensated)")
	# The cached form the one-shot views use every frame gives the same colours.
	var other: Node = load("res://assets/models/Towers/death.glb").instantiate()
	var entries := BlitzAnimator.alpha_entries(other)
	check(not entries.is_empty(), "alpha entries found")
	BlitzAnimator.set_alpha_entries(entries, 0.5)
	for n in ["Sphere01", "Plane01"]:
		var a: MeshInstance3D = death.find_child(n, true, false)
		var b: MeshInstance3D = other.find_child(n, true, false)
		check(BlitzAnimator.material_color(a.get_active_material(0)).is_equal_approx(BlitzAnimator.material_color(b.get_active_material(0))), "%s: set_alpha_entries == set_alpha" % n)
	BlitzAnimator.set_alpha_entries(entries, 1.0)
	check(is_equal_approx(BlitzAnimator.material_color(other.find_child("Sphere01", true, false).get_active_material(0)).a, alpha), "alpha 1 restores the brush alpha")
	other.free()
	death.free()


## `EntityTexture(dno, LoadTexture("dno<L>.png", 0x20b))`: the ALPHA flag makes every base
## blend, even when the model's own dno brush is untextured and opaque (Freeze).
func test_tower_base_blends_location_texture() -> void:
	game.start_campaign(0)
	game.enter_location(1)
	for type_id in [GameData.TOWER_LAND, GameData.TOWER_ICEROCK]:
		var t := game.build_tower(type_id, Vector3(62, 0, -30), 0, false)
		var view := TowerView.new()
		view.setup(t, data, data.location(1), 1)
		var dno: MeshInstance3D = view.model.find_child("dno", true, false)
		var m := dno.get_active_material(0) as StandardMaterial3D
		check_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "tower %d base uses alpha" % type_id)
		check(m.albedo_texture != null and m.albedo_texture.resource_path.ends_with("dno1.png"), "tower %d base has dno1.png" % type_id)
		if type_id == GameData.TOWER_ICEROCK:
			check(Color(m.albedo_color.r, m.albedo_color.g, m.albedo_color.b).is_equal_approx(TowerView.ICEROCK_TINT), "Icerock base is blue outside L3")
		view.free()


## `EntityOrder > 0` (the stacked ground layers): a shader that writes the far-plane depth
## and never stores it, ordered by render_priority = -order; negative orders drop the depth
## test instead, except location zones.
func test_ordered_layers_emulate_zmode_disable() -> void:
	var l1 := _load_scene("res://assets/models/Location1/Location1.glb")
	var grass: MeshInstance3D = l1.find_child("grass", true, false)
	var m := grass.get_active_material(0)
	check(m is ShaderMaterial, "L1 grass (order 30) uses the far-depth shader")
	if m is ShaderMaterial:
		check(m.shader.code.contains("DEPTH = 0.0"), "far-plane depth")
		check(m.shader.code.contains("depth_draw_never"), "no depth write")
		check_eq(m.render_priority, -30, "priority = -order")
	var way: MeshInstance3D = l1.find_child("way", true, false)
	check_eq(way.get_active_material(0).render_priority, -15, "way (order 15) drawn after grass")
	l1.free()
	var l6 := _load_scene("res://assets/models/Location6/Location6.glb")
	var np := l6.find_child("noparking", true, false).get_active_material(0) as StandardMaterial3D
	check(np != null and not np.no_depth_test, "zone with order -1 keeps the depth test")
	l6.free()


## Multi-layer brushes use the Blitz combine shader; the ones Blitz draws opaque (Location1
## castle: texture x lightmap) stay in the opaque pass, blended ones write ALPHA.
func test_multilayer_shader_keeps_opaque_brushes_opaque() -> void:
	var l1 := _load_scene("res://assets/models/Location1/Location1.glb")
	var houses: MeshInstance3D = l1.find_child("houses", true, false)
	var found := false
	for i in houses.mesh.get_surface_count():
		var m := houses.get_active_material(i)
		if m.resource_name.begins_with("wetwe"):
			found = true
			check(m is ShaderMaterial, "castle brush (2 layers) uses the shader")
			check(not (m as ShaderMaterial).shader.code.contains("ALPHA ="), "castle stays opaque")
	check(found, "castle brush found")
	l1.free()
	var l5 := _load_scene("res://assets/models/Location5/Location5.glb")
	var np: MeshInstance3D = l5.find_child("noparking", true, false)
	var m5 := np.get_active_material(0)
	check(m5 is ShaderMaterial and (m5 as ShaderMaterial).shader.code.contains("ALPHA = c.a"), "additive mud brush blends")
	l5.free()


## B3D Extensions keep RGB in the node position; the converter mirrors z, so the readers
## must un-mirror it (a negative blue turned every location's light yellow).
func test_extension_colour_nodes_unmirror_to_valid_rgb() -> void:
	var l6 := _load_scene("res://assets/models/Location6/Location6.glb")
	for n in ["B3DEXT_AMBIENT", "B3DEXT_DIRLIGHT", "B3DEXT_BGCOLOR"]:
		var node := l6.find_child(n, true, false) as Node3D
		var c := Blitz.to_godot(node.position)
		check(c.x >= 0 and c.y >= 0 and c.z >= 0 and c.z <= 1.0, "%s -> rgb %s" % [n, c])
	check(Blitz.to_godot((l6.find_child("B3DEXT_DIRLIGHT", true, false) as Node3D).position).is_equal_approx(Vector3.ONE), "L6 light is white")
	l6.free()


## `EntityColor` through the cached material list matches the recursive form; the copies
## are per instance, the scene's own materials stay untouched. (One instance at a time:
## the dummy renderer complains when two instances with override materials coexist.)
func test_tint_materials_matches_tint() -> void:
	var a: Node = load("res://assets/models/Towers/MilitaryPlace.glb").instantiate()
	BlitzAnimator.tint(a, PlaceMarkerView.COLOR_BAD)
	var via_tint := BlitzAnimator.material_color(BlitzAnimator.find_mesh(a).get_active_material(0))
	a.free()
	var b: Node = load("res://assets/models/Towers/MilitaryPlace.glb").instantiate()
	var mats := BlitzAnimator.owned_materials(b)
	check(not mats.is_empty(), "materials found")
	BlitzAnimator.tint_materials(mats, PlaceMarkerView.COLOR_BAD)
	var mb := BlitzAnimator.find_mesh(b)
	check(BlitzAnimator.material_color(mb.get_active_material(0)).is_equal_approx(via_tint), "same tint")
	check(via_tint.r > 0.9 and via_tint.g < 0.1, "tinted red")
	check(BlitzAnimator.material_color(mb.mesh.surface_get_material(0)).is_equal_approx(Color.WHITE), "the shared material is untouched")
	b.free()


## The HUD assigns its texts every frame: an unchanged string is not parsed again.
func test_blitz_text_skips_unchanged_text() -> void:
	var t := BlitzText.new()
	t.text = "gold: 10"
	var glyphs := t._glyphs.size()
	var before := t._glyphs
	t.text = "gold: 10"
	check(t._glyphs == before and t._glyphs.size() == glyphs, "same text keeps the parsed glyphs")
	t.text = "gold: 100"
	check_eq(t._glyphs.size(), glyphs + 1, "a new text is parsed")
	t.free()


## The importer's `solid_pass`: the alpha-textured tower base writes depth for its solid
## texels only (a scissored second pass), never from the blended pass itself, which cut
## holes into Location6's rocks under a tower.
func test_alpha_textured_brushes_get_a_scissored_solid_pass() -> void:
	var root := _load_scene("res://assets/models/Towers/Military.glb")
	check(root != null, "Military.glb")
	if root == null:
		return
	var dno := root.find_child("dno", true, false) as MeshInstance3D
	var m := dno.get_active_material(0) as StandardMaterial3D
	check(m != null and m.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY, "blended pass writes no depth")
	var solid := m.next_pass as StandardMaterial3D
	check(solid != null and solid.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "scissored solid pass")
	check(solid != null and solid.next_pass == null, "single extra pass")
	check_near(solid.alpha_scissor_threshold if solid != null else 0.0, 0.99, 0.001, "solid threshold")
	root.free()
