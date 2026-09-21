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
