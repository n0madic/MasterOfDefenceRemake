extends SimTestCase

## Headless run through the whole campaign (180 raids over 6 locations) with a scripted
## builder: towers along the road, cheat gold, waits skipped. Checks the progression
## machinery end to end (spawns, raid ends, balance, location transitions, survival).
func test_full_campaign_headless() -> void:
	game.start_campaign(0)
	var completed := {"n": 0}
	game.location_completed.connect(func(): completed["n"] += 1)
	var over := {"v": false}
	game.game_over.connect(func(): over["v"] = true)
	var total_ticks := 0
	for L in range(1, 7):
		if L > 1:
			game.next_location()
			game.enter_location(L)
		if bool(data.location(L)["balloon"]):
			game.enable_balloon()
		_build_defence()
		var target := game.last_raid_of_location()
		var guard := 0
		while completed["n"] < L and not over["v"] and guard < 1500000:
			if game.level_finished and not game.create_enemies_mode and game.ingame_time < 9.0:
				game.ingame_time = 9.9  # skip the wait between raids
			game.tick()
			guard += 1
			total_ticks += 1
		check(completed["n"] == L, "location %d completed (raid %d/%d, ticks %d)" % [L, game.curlevel, target, guard])
		check(not over["v"], "no game over on location %d" % L)
		if over["v"]:
			break
	check_eq(game.curlevel, 180, "ended on raid 180")
	check(game.next_location(), "campaign finished after location 6")
	check(game.lifes > 0, "score = lifes %d" % game.lifes)
	print("    campaign ticks: %d" % total_ticks)


func _build_defence() -> void:
	game.gold = 100000
	game.experience = 100000
	game.skills.cold_magic = 5
	game.skills.fire_magic = 5
	game.skills.poison_magic = 5
	var keys: PackedVector3Array = game.path["pos"]
	var count := keys.size()
	var types := [GameData.TOWER_LAND, GameData.TOWER_MAGIC, GameData.TOWER_PLANT, GameData.TOWER_ICEROCK]
	var i := 0
	# Towers far enough from the spawn point that the first monster survives until the
	# raid is fully spawned (otherwise `enemies_amount == 0` ends the raid early, as in
	# the original), so every raid runs travel, arrival and end-of-raid accounting.
	for k in range(4, count - 2, maxi(count / 12, 1)):
		var p := keys[k] + Vector3(6 if i % 2 == 0 else -6, 0, 0)
		if game.is_too_close_to_tower(p) or p.distance_to(keys[0]) < 40.0:
			continue
		var t := game.build_tower(types[i % types.size()], p)
		if t != null:
			# Cheat: max level parameters at once.
			t.level = t.max_upgrades
			t.apply_proto(game.protos[t.type][t.level])
			t.land_damage *= 8.0
			t.air_damage *= 8.0
			t.animate(SimTower.ANIM_LOOP, t.idle_seq())
		i += 1


func test_survival_50_raids_headless() -> void:
	game.start_survival()
	var over := {"v": false}
	game.game_over.connect(func(): over["v"] = true)
	_build_defence()
	var guard := 0
	while game.curlevel <= 50 and not over["v"] and guard < 1500000:
		if game.level_finished and not game.create_enemies_mode and game.ingame_time < 9.0:
			game.ingame_time = 9.9
		game.tick()
		guard += 1
	check(game.curlevel > 50, "survived 50 raids (raid %d, ticks %d)" % [game.curlevel, guard])
	check(not over["v"], "no game over")
	check_near(game.units_life_multiplier, 1.0, 1e-9, "no auto-balance")


## `_fnextlocation` (location 6 done) adds `(gold - 100) \ 100 + extralifes` to the lives,
## then `_fcreatehighscoresmenu` adds `(gold - 100) \ 100` once more when gold > 200.
func test_campaign_score_converts_gold_twice() -> void:
	var cases := [
		{"gold": 500, "lifes": 10, "extra": 0, "score": 18},
		{"gold": 500, "lifes": 10, "extra": 3, "score": 21},
		{"gold": 150, "lifes": 10, "extra": 0, "score": 10},
		{"gold": 250, "lifes": 10, "extra": 0, "score": 12},
	]
	for c in cases:
		game.start_campaign(0)
		game.location = GameData.LOCATIONS
		game.gold = c["gold"]
		game.lifes = c["lifes"]
		game.extra_lifes = c["extra"]
		check(game.next_location(), "campaign finished")
		check_eq(game.lifes, c["score"], "score for gold %d, lifes %d, extra %d" % [c["gold"], c["lifes"], c["extra"]])
