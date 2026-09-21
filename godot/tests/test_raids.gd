extends SimTestCase


func setup() -> void:
	super.setup()
	game.start_campaign(0)


func test_spawn_timeline() -> void:
	var spawns: Array = []
	game.enemy_spawned.connect(func(_e): spawns.append(game.tick_count))
	run_ticks(1300)
	# 10.0 / 0.01 = 1000 ticks of waiting (float32 accumulation), then one monster per 40 ticks.
	check_eq(spawns.size(), 5, "raid 1 has 5 monsters")
	check(spawns[0] >= 1039 and spawns[0] <= 1042, "first spawn at ~1040, got %d" % spawns[0])
	for i in range(1, spawns.size()):
		var gap: int = spawns[i] - spawns[i - 1]
		check(gap >= 39 and gap <= 41, "spawn gap %d" % gap)
	check(sounds.has("start"), "start sound")
	check(not game.level_finished, "raid in progress")
	check(game.create_enemies_mode == false, "spawning done")
	check_eq(game.enemies_amount, 5, "5 alive")
	for e in game.enemies:
		check_eq(e.unit_id, 10, "Nite")
		check_eq(e.max_life, 30.0, "life 30")
		check_eq(e.armor, 2, "armor")
		check_near(e.speed, 0.103, 1e-6, "speed")
		check_near(e.scale, 1.0 + 1.0 / 250.0, 1e-6, "scale grows with raid")


func test_inhabitants_loss_table() -> void:
	# Round(life% / (3*res + 33)): full health at resistance 0 -> 3; 50% -> 2; 40% -> 1; < 16.5% -> 0.
	var cases := [[100.0, 0, 3], [50.0, 0, 2], [40.0, 0, 1], [16.0, 0, 0], [100.0, 5, 2], [23.0, 5, 0]]
	dummy_enemy(Vector3.ZERO)  # keeps enemies_amount > 0 so raids never end here
	for c in cases:
		game.skills.ppl_resistance = int(c[1])
		game.lifes = 100
		var e := game.create_enemy(false, 1)
		e.life = e.max_life * float(c[0]) / 100.0
		e.path.time = float(e.path.frames)  # already past the end
		game.update_enemies()
		check_eq(100 - game.lifes, int(c[2]), "life%% %s res %s" % [c[0], c[1]])
	check_eq(game.monsters_killed_by_inhabitants, 2, "two monsters killed by people")


func test_boss_costs_five_times() -> void:
	game.curlevel = 6
	var e := game.create_enemy(true, 12)
	check(e.boss, "boss flag")
	check_near(e.scale, 1.64, 1e-6, "boss scale")
	e.path.time = float(e.path.frames)
	game.update_enemies()
	check_eq(game.lifes, 100 - 15, "boss x5")


func test_worker_adds_life_and_is_ignored_by_towers() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, data.paths[1]["pos"][0])
	var w := game.create_enemy(false, 32)
	check(w.worker, "worker")
	check_eq(game.enemies_amount, 0, "workers are not counted")
	run_ticks(100)
	check(t.target == null, "towers ignore workers")
	w.path.time = float(w.path.frames)
	game.update_enemies()
	check_eq(game.lifes, 101, "worker adds a life")


func test_healer_stats() -> void:
	game.curlevel = 46
	var h := game.create_enemy(false, 31)
	check_eq(h.max_life, 2.0 * float(data.raid(46)["life"]), "healer life x2")
	check_eq(h.gold, 2 * int(data.raid(46)["gold"]), "healer gold x2")
	var hb := game.create_enemy(true, 31)
	check_eq(hb.max_life, float(data.raid(46)["life"]) / 2.0, "boss healer life /2")
	check_eq(hb.gold, Blitz.idiv(int(data.raid(46)["gold"]), 10), "boss healer gold /10")
	game.delete_enemy(hb, false, false)
	# Healing: a neighbour 1 unit away gains healer/(d*10) = 4 per tick.
	var e := dummy_enemy(h.position + Vector3(1, 0, 0), false, 1000.0)
	e.life = 500.0
	h.speed = 0.0
	game.update_enemies()
	check_near(e.life, 504.0, 1e-3, "healed 4/tick at distance 1")


func test_kill_gives_gold_and_raid_end_income() -> void:
	game.gold = 0
	var e := game.create_enemy(false, 1)
	game.level_finished = false
	game.delete_enemy(e, true, true)
	check_eq(game.gold, 1 + 60, "kill gold + round(0.6*100) income")
	check_eq(game.experience, 20, "raid experience")
	check_eq(game.curlevel, 2, "next raid")
	check(game.level_finished, "waiting again")
	check(messages.any(func(m): return m["text"].begins_with("You have received 60")), "income message")
	check(messages.any(func(m): return m["text"].begins_with("Well done")), "first raid message")


func test_missed_and_balance() -> void:
	game.lifes = 97
	var e := game.create_enemy(false, 1)
	game.delete_enemy(e, true, true)
	check_eq(game.missed[2], 3, "missed stored under the incremented raid number")
	check_near(game.units_life_multiplier, 0.97, 1e-6, "m -= 3/100")
	check(messages.any(func(m): return m["text"] == "3 of your inhabitants were killed"), "message")
	# Three clean raids in a row (checked from raid 4 on) -> +0.03 each, capped by 1 + location/10.
	for i in 5:
		e = game.create_enemy(false, 1)
		game.delete_enemy(e, true, true)
	check_near(game.units_life_multiplier, 1.06, 1e-6, "0.97 + 3 * 0.03")
	for i in 5:
		e = game.create_enemy(false, 1)
		game.delete_enemy(e, true, true)
	check_near(game.units_life_multiplier, 1.1, 1e-6, "capped at 1 + location/10")
	game.lifes = 10
	e = game.create_enemy(false, 1)
	game.delete_enemy(e, true, true)
	check_near(game.units_life_multiplier, 0.7, 1e-6, "few lifes -> 0.7")
	game.lifes = 250
	e = game.create_enemy(false, 1)
	game.delete_enemy(e, true, true)
	check_near(game.units_life_multiplier, 1.3, 1e-6, "many lifes -> 1.3")


func test_location_end_and_next_location() -> void:
	game.curlevel = 15
	var done := {"v": false}
	game.location_completed.connect(func(): done["v"] = true)
	var e := game.create_enemy(false, 1)
	game.delete_enemy(e, true, true)
	check(done["v"], "location completed after raid 15")
	check_eq(game.curlevel, 15, "raid number stays")
	game.gold = 450
	check(not game.next_location(), "campaign continues")
	check_eq(game.location, 2, "location 2")
	check_eq(game.extra_lifes, 3, "(450-100)\\100 people employed")
	check_eq(game.gold, 240, "200 + 20*2")
	check_eq(game.experience, 20 + 20, "+10*L")
	game.enter_location(2)
	check_eq(game.curlevel, 16, "first raid of location 2")
	game.location = 4
	game.gold = 0
	game.next_location()
	check_eq(game.gold, 350, "location 5 starts with 350")


func test_extra_lifes_walk_out_one_per_raid_wait() -> void:
	game.extra_lifes = 2
	var spawned: Array = []
	game.enemy_spawned.connect(func(e): spawned.append([game.tick_count, e.worker]))
	run_ticks(700)
	check_eq(spawned.size(), 1, "one worker at ingame time 6.0")
	check(spawned[0][1], "it is a worker")
	check(spawned[0][0] >= 599 and spawned[0][0] <= 602, "at ~600 ticks, got %d" % spawned[0][0])
	check_eq(game.extra_lifes, 1, "one left")


func test_wait_timer_stops_while_raid_is_alive() -> void:
	# `_fhandlelevels` runs only while `_vlevelfinished = 1`: a raid in progress never
	# starts the next spawn cycle, however long it takes.
	run_ticks(1300)
	check(not game.level_finished, "raid 1 in progress")
	var spawned := {"n": 0}
	game.enemy_spawned.connect(func(_e): spawned["n"] += 1)
	var frozen := game.ingame_time
	run_ticks(600)
	check(not game.enemies.is_empty(), "monsters still walking")
	check_near(game.ingame_time, frozen, 1e-6, "timer frozen while the raid is alive")
	run_ticks(900)
	check_eq(spawned["n"], 0, "no spawns while the raid is alive")


func test_game_over() -> void:
	game.lifes = 1
	var over := {"v": false}
	game.game_over.connect(func(): over["v"] = true)
	var e := game.create_enemy(false, 1)
	e.path.time = float(e.path.frames)
	game.update_enemies()
	check(over["v"], "game over emitted")
	check_eq(game.lifes, 0, "lifes clamp at 0")


func test_cheats_cannot_lose() -> void:
	game.cheats = true
	game.lifes = 1
	var over := {"v": false}
	game.game_over.connect(func(): over["v"] = true)
	var reached := {"lost": -1}
	game.enemy_reached_end.connect(func(_e, lost): reached["lost"] = lost)
	var e := game.create_enemy(true, 12)
	e.path.time = float(e.path.frames)
	game.update_enemies()
	check(not over["v"], "no game over")
	check_eq(game.lifes, 1, "inhabitants untouched")
	check(reached["lost"] > 0, "the would-be loss is still reported")
	var gold := game.gold
	var t := game.build_tower(GameData.TOWER_LAND, data.paths[1]["pos"][0])
	check(t != null, "tower built")
	check_eq(game.gold, gold, "gold not spent")
	check_eq(t.spent, game.tower_price(GameData.TOWER_LAND), "nominal price still tracked for selling")
	game.select_tower(t)
	check(game.upgrade_selected_tower(), "upgrade started")
	check_eq(game.gold, gold, "upgrade not charged")
	game.experience = 100
	game.skills.operate(game, SimSkills.Id.COLD, false)
	check_eq(game.skills.cold_magic, 1, "skill bought")
	check_eq(game.experience, 100, "experience not spent")
	game.skills.operate(game, SimSkills.Id.COLD, true)
	check_eq(game.experience, 100, "downgrade refunds nothing")
