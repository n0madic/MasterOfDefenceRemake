extends SimTestCase


func test_save_and_restore_identical_state() -> void:
	game.start_campaign(1)
	game.location = 3
	game.enter_location(3)
	game.experience = 5000
	game.gold = 900
	for i in 3:
		game.skills.operate(game, SimSkills.Id.DAMAGE, false)
		game.skills.operate(game, SimSkills.Id.SPEED, false)
		game.skills.operate(game, SimSkills.Id.RANGE, false)
	game.skills.operate(game, SimSkills.Id.COLD, false)
	game.skills.operate(game, SimSkills.Id.GOLD, false)
	game.skills.operate(game, SimSkills.Id.SELL, false)
	var t1 := game.build_tower(GameData.TOWER_LAND, Vector3(60, 0, -30))
	var t2 := game.build_tower(GameData.TOWER_ICEROCK, Vector3(70, 0, -30))
	game.select_tower(t1)
	game.gold = 1000
	game.upgrade_selected_tower()
	run_until(func(): return t1.anim_seq == t1.idle_seq() and t1.level == 1 and not t1.upgrade_pending and t1.land_damage != 20.0 * game.skills.damage_upgrader, 400)
	game.curlevel = 50
	game.lifes = 77
	game.missed[48] = 2
	game.units_life_multiplier = 0.93
	var payload := SaveGame.serialize(game)
	# Round-trip through JSON like the file on disk.
	var restored: Dictionary = JSON.parse_string(JSON.stringify(payload))
	var g2 := SimGame.new(data, 1)
	SaveGame.restore(g2, restored)
	check_eq(g2.location, 3, "location")
	check_eq(g2.curlevel, 50, "curlevel")
	check_eq(g2.lifes, 77, "lifes")
	check_eq(g2.gold, game.gold, "gold")
	check_eq(g2.titul, 1, "titul")
	check_eq(g2.experience, game.experience, "experience")
	check_eq(g2.missed[48], 2, "missed")
	check_near(g2.units_life_multiplier, 0.93, 1e-6, "balance multiplier")
	check_eq(g2.skills.damage_level, 3, "damage level")
	check_eq(g2.skills.cold_magic, 1, "cold")
	check_near(g2.skills.gold_rate, game.skills.gold_rate, 1e-6, "gold rate")
	check_eq(g2.towers.size(), 2, "towers")
	var r1 := g2.towers[0]
	var r2 := g2.towers[1]
	check_eq(r1.type, GameData.TOWER_LAND, "type")
	check_eq(r1.level, 1, "level")
	check_eq(r1.spent, 30 + 20, "spent = sum of prices")
	check_near(r1.land_damage, t1.land_damage, 1e-3, "damage restored via skills")
	check_near(r1.range, t1.range, 1e-3, "range restored")
	check_eq(r1.rate_of_fire, t1.rate_of_fire, "rate restored")
	check_near(r2.freeze, t2.freeze, 1e-6, "freeze")
	check_eq(r1.position, t1.position, "position")
	for type in range(1, 6):
		for lv in 11:
			check_near(float(g2.protos[type][lv]["land_damage"]), float(game.protos[type][lv]["land_damage"]), 1e-3, "proto damage %d/%d" % [type, lv])
			check_eq(int(g2.protos[type][lv]["rate_of_fire_ms"]), int(game.protos[type][lv]["rate_of_fire_ms"]), "proto rate %d/%d" % [type, lv])
	# Both games evolve the same way for a deterministic spawn timeline.
	g2.rng = Blitz.Random.new(7)
	game.rng = Blitz.Random.new(7)
	for i in 1200:
		game.tick()
		g2.tick()
	check_eq(g2.enemies.size(), game.enemies.size(), "same enemies after 1200 ticks")
	check_eq(g2.gold, game.gold, "same gold after 1200 ticks")


## `_floadgame` rebuilds towers through `_fpositiontower(0, yaw)`: no placement sound.
func test_restore_does_not_replay_build_sounds() -> void:
	game.start_campaign(0)
	game.enter_location(1)
	game.build_tower(GameData.TOWER_LAND, Vector3(60, 0, -30))
	game.build_tower(GameData.TOWER_MAGIC, Vector3(70, 0, -30))
	var payload := SaveGame.serialize(game)
	sounds.clear()
	var g2 := SimGame.new(data, 1)
	g2.start_campaign(0)
	g2.enter_location(1)
	var heard := []
	g2.sound.connect(func(n, _p): heard.append(n))
	SaveGame.restore(g2, payload)
	check_eq(g2.towers.size(), 2, "towers restored")
	check_eq(heard, [], "no build sounds on restore")
