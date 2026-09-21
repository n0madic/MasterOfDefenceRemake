extends SimTestCase

## Tick counts must equal tools/simulate_path.py output (docs/data/path_times.json).
func test_travel_times() -> void:
	var golden: Dictionary = GameDataScript._read_json("res://data/path_times.json")
	for L in range(1, 7):
		var entry: Dictionary = golden["location%d" % L]
		for run in entry["runs"]:
			var pf := PathFollower.new()
			pf.setup(data.paths[L], Vector3.ZERO)
			var speed := float(run["raid_speed"]) / 10.0
			var ticks := 0
			while not pf.finished():
				pf.advance(speed, speed * PathFollower.MARKER_FRAMES_PER_SPEED)
				ticks += 1
				if ticks > 1_000_000:
					break
			check_eq(ticks, int(run["ticks"]), "L%d speed %s" % [L, run["raid_speed"]])


func test_enemy_walks_to_castle() -> void:
	game.start_campaign(0)
	var e := game.create_enemy(false, 1)
	var start := e.position
	var ticks := run_until(func(): return e.id == 0, 3000)
	check(ticks > 900 and ticks < 980, "raid 1 monster reaches the end in ~938 ticks, got %d" % ticks)
	check_eq(game.lifes, 97, "full-health monster costs 3 inhabitants")
	check(start.distance_to(data.paths[1]["pos"][0]) < 1.5, "spawns at key 0")
