extends SimTestCase


func test_survival_setup_and_raids() -> void:
	game.start_survival()
	check(game.survival_mode, "mode")
	check_eq(game.location, 2, "location 2")
	check_eq(game.lifes, 100, "lifes")
	check_eq(game.gold, 250, "gold")
	check_eq(game.experience, 100, "experience")
	check_eq(game.curlevel, 1, "raid 1")
	var r := game.current_raid()
	check_eq(r["monsters"].size(), 10, "10 monsters in raid 1")
	for id in r["monsters"]:
		check(id >= 1 and id <= 30, "unit id in 1..30")
	check(not r["boss"], "no boss raids")
	check_eq(r["life"], 85, "life from RaidsData7")
	game.curlevel = 18
	check_eq(game.current_raid()["monsters"].size(), 11, "raid 18 has 11")
	game.curlevel = 200
	check_eq(game.current_raid()["monsters"].size(), 21, "raid 200 has 21")
	game.curlevel = 201
	var beyond := game.current_raid()
	check_eq(beyond["monsters"].size(), 21, "raid 201 keeps growing the count")
	check_eq(beyond["life"], game.data.survival[200]["life"], "raid 201 repeats the last table row")


func test_survival_air_armor_and_income() -> void:
	game.start_survival()
	game.curlevel = 50
	var flyer := game.create_enemy(false, 7)
	check_eq(flyer.armor, Blitz.round_int(float(data.survival[50]["armor"]) * 0.8), "air armor x0.8")
	var walker := game.create_enemy(false, 1)
	check_eq(walker.armor, int(data.survival[50]["armor"]), "ground armor unchanged")
	game.lifes = 80
	game.gold = 0
	game.delete_enemy(flyer, false, false)
	game.delete_enemy(walker, true, true)
	check_eq(game.gold, int(data.survival[50]["gold"]) + Blitz.round_int(0.6 * 80.0), "income = round(rate * lifes)")
	check_eq(game.curlevel, 51, "raid +1 without location limits")
	check_near(game.units_life_multiplier, 1.0, 1e-9, "no auto-balance in survival")
