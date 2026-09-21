extends SimTestCase


func test_units() -> void:
	check_eq(data.units.size() - 1, 34, "units")
	check_eq(data.unit(1)["name"], "Crawl", "unit 1")
	check_eq(data.unit(31)["healer"], 40, "healer")
	check(data.unit(7)["air"] and data.unit(14)["air"] and data.unit(21)["air"] and data.unit(28)["air"], "air units")
	check(data.unit(32)["worker"] and data.unit(33)["worker"] and data.unit(34)["worker"], "workers")
	check(str(data.unit(1)["model"]).begins_with("res://assets/models/Monsters/"), "model path")


func test_towers() -> void:
	check_eq(data.tower_protos.size() - 1, 5, "tower types")
	for t in range(1, 6):
		check_eq(data.tower_protos[t].size(), 11, "levels of type %d" % t)
	var land0 := data.proto(1, 0)
	check_eq(land0["land_damage"], 20.0, "land dmg")
	check_eq(land0["rate_of_fire_ms"], 982, "land rate")
	check_eq(land0["price"], 30, "land price")
	check_eq(land0["max_upgrades"], 10, "land max")
	check_eq(data.proto(2, 0)["max_upgrades"], 5, "magic max")
	check_eq(data.proto(5, 0)["place_on_road"], true, "flame on road")
	check_eq(data.proto(5, 0)["range"], 5.0, "flame range")
	check_eq(data.proto(4, 0)["freeze"], 15, "icerock freeze")


func test_raids() -> void:
	check_eq(data.raids.size() - 1, 180, "campaign raids")
	var bosses := []
	for n in range(1, 181):
		if data.raid(n)["boss"]:
			bosses.append(n)
	check_eq(bosses, [6, 12, 26, 36, 45, 54, 60, 70, 84, 94, 100, 109, 116, 130, 135, 144, 151, 165, 170, 180], "boss raids")
	check_eq(data.location_first_raid, [0, 1, 16, 46, 71, 101, 136], "first raids")
	check_eq(data.raid(16)["location"], 2, "raid 16 location")
	check_eq(data.survival.size() - 1, 200, "survival rows")
	check_eq(data.survival[1]["life"], 85, "survival life")


func test_locations_and_paths() -> void:
	var frames := [0, 20, 100, 30, 80, 70, 100]
	for L in range(1, 7):
		check_eq(data.paths[L]["frames"], frames[L], "frames L%d" % L)
		check_eq(data.paths[L]["pos"].size(), frames[L] + 1, "keys L%d" % L)
		var loc := data.location(L)
		check_eq(loc["first_raid"], data.location_first_raid[L], "first raid L%d" % L)
	check_eq(data.location(6)["last_raid"], 180, "last raid L6")
	check_eq(data.location(5)["start_gold"], 300, "start gold L5 (before +50 special case)")
	check(data.location(4)["balloon"] and not data.location(3)["balloon"], "balloon flags")
	# C1: on location 2 the artist oriented the path node along the road (Blitz +Z, which
	# is Godot -Z after the mirror); with the correct quaternion convention the exported
	# rotation of key 0 faces key 1.
	var p: Dictionary = data.paths[2]
	var q: Quaternion = p["rot"][0]
	var forward := q * Vector3.FORWARD
	var dir: Vector3 = (p["pos"][1] - p["pos"][0]).normalized()
	check(forward.dot(dir) > 0.99, "L2 path key 0 faces key 1 (dot %f)" % forward.dot(dir))


func test_texts() -> void:
	check_eq(data.text(0), "Upgrade", "text 0")
	check_eq(data.text(46), "You have received", "text 46")
	check_eq(data.text(57), "Tower upgraded", "text 57")
	check(data.help(0).begins_with("Cold Magic adds a new\n"), "helps wrapped at 25")
	check(data.tutorial_page(1).contains("\n"), "tutorial wrapped")
	check(data.storyline(1).begins_with("Hordes of evil monsters\n"), "storyline")
