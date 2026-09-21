extends SimTestCase


func setup() -> void:
	super.setup()
	game.start_campaign(0)
	game.experience = 100000


static func product(levels: int, inc: float) -> float:
	var m := 1.0
	for k in range(1, levels + 1):
		m *= 1.0 + inc * k
	return m


func test_damage_ten_levels() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, Vector3(60, 0, -20))
	var bought := 0
	while game.skills.can_buy(SimSkills.Id.DAMAGE, game.experience):
		game.skills.operate(game, SimSkills.Id.DAMAGE, false)
		bought += 1
	check_eq(bought, 10, "10 damage levels (float32 cap at 1.05)")
	check_eq(game.experience, 100000 - 500, "price 50 each")
	var expected := 20.0 * product(10, 0.005)
	check_near(float(game.protos[1][0]["land_damage"]), expected, 0.002, "proto land damage x1.3104")
	check_near(t.land_damage, expected, 0.002, "built tower damage")
	check_near(product(10, 0.005), 1.3104, 0.0005, "docs/06 product")


func test_range_twelve_levels() -> void:
	var bought := 0
	while game.skills.can_buy(SimSkills.Id.RANGE, game.experience):
		game.skills.operate(game, SimSkills.Id.RANGE, false)
		bought += 1
	check_eq(bought, 12, "12 range levels (cap 1.06)")
	check_near(float(game.protos[1][0]["range"]), 10.0 * product(12, 0.005), 0.002, "range x1.47")
	check_near(product(12, 0.005), 1.47, 0.005, "docs/06 product")


func test_speed_five_levels_rounded_each_step() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, Vector3(60, 0, -20))
	for i in 5:
		check(game.skills.can_buy(SimSkills.Id.SPEED, game.experience), "can buy %d" % i)
		game.skills.operate(game, SimSkills.Id.SPEED, false)
	check(not game.skills.can_buy(SimSkills.Id.SPEED, game.experience), "cap at 5")
	var rate := 982
	for k in range(1, 6):
		rate = Blitz.round_int(float(rate) * Blitz.f32(1.0 - 0.02 * k))
	check_eq(int(game.protos[1][0]["rate_of_fire_ms"]), rate, "proto rate")
	check_eq(t.rate_of_fire, rate, "tower rate")
	check(rate >= 717 and rate <= 720, "x0.732 -> ~719, got %d" % rate)


func test_downgrade_and_cancel() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, Vector3(60, 0, -20))
	var exp0 := game.experience
	game.skills.operate(game, SimSkills.Id.DAMAGE, false)
	game.skills.operate(game, SimSkills.Id.DAMAGE, false)
	game.skills.operate(game, SimSkills.Id.DAMAGE, true)
	check_eq(game.experience, exp0 - 100 + 25, "minus refunds half")
	check_eq(game.skills.damage_level, 1, "level 1")
	check_near(t.land_damage, 20.0 * 1.005, 1e-4, "one level left")
	game.skills.cancel(game)
	check_eq(game.experience, exp0, "cancel restores experience")
	check_eq(game.skills.damage_level, 0, "cancel restores level")
	check_near(t.land_damage, 20.0, 1e-4, "cancel restores damage")
	check_near(float(game.protos[1][5]["land_damage"]), float(data.proto(1, 5)["land_damage"]), 1e-4, "proto restored")
	check(game.skills.query.is_empty(), "queue cleared")


func test_magic_levels_and_fire6() -> void:
	for i in 5:
		game.skills.operate(game, SimSkills.Id.FIRE, false)
	check(not game.skills.can_buy(SimSkills.Id.FIRE, game.experience), "fire capped at 5")
	check(game.skills.can_buy(SimSkills.Id.FIRE6, game.experience), "fire 6 offered")
	game.skills.operate(game, SimSkills.Id.FIRE6, false)
	check_eq(game.skills.fire_magic, 6, "fire magic 6")
	check_eq(game.experience, 100000 - 500 - 200, "prices")
	game.skills.operate(game, SimSkills.Id.SELL, false)
	check_near(game.skills.sell_rate, 0.8, 1e-6, "sell +0.05")
	for i in 4:
		game.skills.operate(game, SimSkills.Id.SELL, false)
	check_near(game.skills.sell_rate, 1.0, 1e-6, "sell capped at 1.0")
	for i in 20:
		game.skills.operate(game, SimSkills.Id.GOLD, false)
	check_near(game.skills.gold_rate, 1.0, 1e-5, "gold rate 1.0 after 20")


func test_reapply_from_levels_matches_purchases() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, Vector3(60, 0, -20))
	for i in 5:
		game.skills.operate(game, SimSkills.Id.SPEED, false)
		game.skills.operate(game, SimSkills.Id.DAMAGE, false)
	var rate := t.rate_of_fire
	var dmg := t.land_damage
	# Simulate a reload: fresh prototypes and a rebuilt tower, then reapply.
	game.reset_protos()
	t.apply_proto(game.protos[1][0])
	game.skills.reapply_from_levels(game, SimSkills.Kind.SPEED)
	game.skills.reapply_from_levels(game, SimSkills.Kind.DAMAGE)
	check_eq(t.rate_of_fire, rate, "rate restored")
	check_near(t.land_damage, dmg, 1e-4, "damage restored")
	game.reset_protos()
	t.apply_proto(game.protos[1][0])
	game.reproduce_original_bugs = true
	game.skills.reapply_from_levels(game, SimSkills.Kind.SPEED)
	var buggy := 982
	for k in 5:
		buggy = Blitz.round_int(float(buggy) * game.skills.speed_upgrader)
	check_eq(t.rate_of_fire, buggy, "original bug: x0.9^5")
