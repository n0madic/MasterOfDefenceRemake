extends TestCase


func test_round_half_even() -> void:
	check_eq(Blitz.round_int(22.5), 22, "22.5")
	check_eq(Blitz.round_int(23.5), 24, "23.5")
	check_eq(Blitz.round_int(0.5), 0, "0.5")
	check_eq(Blitz.round_int(1.5), 2, "1.5")
	check_eq(Blitz.round_int(2.4), 2, "2.4")
	check_eq(Blitz.round_int(2.6), 3, "2.6")
	check_eq(Blitz.round_int(-0.5), 0, "-0.5")
	check_eq(Blitz.round_int(-1.5), -2, "-1.5")
	check_eq(Blitz.round_int(-2.5), -2, "-2.5")
	check_eq(Blitz.round_int(-2.7), -3, "-2.7")
	# Tower sale: 30 gold spent at 0.75 sell rate -> 22.5 -> 22.
	check_eq(Blitz.round_int(0.75 * 30), 22, "sell 30")


func test_idiv() -> void:
	check_eq(Blitz.idiv(7, 2), 3, "7\\2")
	check_eq(Blitz.idiv(-7, 2), -3, "-7\\2")
	check_eq(Blitz.idiv(37, 18), 2, "37\\18")


func test_f32() -> void:
	check(Blitz.f32(0.1) != 0.1, "0.1 must lose precision")
	check_near(Blitz.f32(0.1), 0.1, 1e-7, "f32(0.1)")
	# 1000 additions of 0.01 in float32 do not reach exactly 10.0.
	var acc := 0.0
	var ticks := 0
	while acc < 10.0:
		acc = Blitz.f32(acc + Blitz.f32(0.01))
		ticks += 1
		if ticks > 2000:
			break
	check(ticks >= 999 and ticks <= 1001, "float32 accumulation of 0.01 reaches 10 after ~1000 ticks, got %d" % ticks)


func test_coords() -> void:
	check_eq(Blitz.to_godot(Vector3(1, 2, 3)), Vector3(1, 2, -3), "to_godot")
	# Blitz identity quaternion maps to Godot identity.
	var q := Blitz.quat_to_godot(1, 0, 0, 0)
	check(q.is_equal_approx(Quaternion.IDENTITY), "identity quat")
	# Env.b3d quads rotated (0.707, 0.707, 0, 0) face the camera (+Z in Godot, towards a
	# camera looking down -Z): the quad normal +Y must map to +Z.
	var hud := Blitz.quat_to_godot(0.7071068, 0.7071068, 0, 0)
	check((hud * Vector3.UP).is_equal_approx(Vector3(0, 0, 1)), "HUD quad faces the camera")


func test_random_seeded() -> void:
	var a := Blitz.Random.new(42)
	var b := Blitz.Random.new(42)
	for i in 10:
		check_eq(a.rand(1, 30), b.rand(1, 30), "seeded rand")
	for i in 100:
		var v := a.rand(1, 30)
		check(v >= 1 and v <= 30, "rand range")
		var f := a.rnd(-1.0, 1.0)
		check(f >= -1.0 and f <= 1.0, "rnd range")


## Alpha-textured brushes carry a second, alpha-scissored pass (`next_pass`) that writes the
## depth of their solid texels; per-instance copies and every runtime change must reach it.
func _two_pass_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.next_pass = StandardMaterial3D.new()
	return m


func test_copy_material_copies_the_solid_pass() -> void:
	var m := _two_pass_material()
	var own := BlitzAnimator.copy_material(m) as StandardMaterial3D
	check(own != m and own.next_pass != null, "copied with a solid pass")
	check(own.next_pass != m.next_pass, "the solid pass is not shared with the source")
	var plain := BlitzAnimator.copy_material(StandardMaterial3D.new()) as StandardMaterial3D
	check(plain.next_pass == null, "no solid pass invented")


func test_material_setters_reach_the_solid_pass() -> void:
	var m := _two_pass_material()
	var solid := m.next_pass as StandardMaterial3D
	var tex := PlaceholderTexture2D.new()
	BlitzAnimator.set_material_color(m, Color(0.2, 0.4, 0.6, 0.5))
	BlitzAnimator.set_material_texture(m, tex)
	BlitzAnimator.set_material_uv_offset(m, Vector3(0.25, -0.5, 0))
	check_eq(solid.albedo_color, Color(0.2, 0.4, 0.6, 0.5), "colour and alpha")
	check(solid.albedo_texture == tex, "texture")
	check_eq(solid.uv1_offset, Vector3(0.25, -0.5, 0), "uv offset")
