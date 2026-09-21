extends SimTestCase


## Every location (and survival) warms a non-empty, duplicate-free list of existing models
## that covers at least one monster of the location and every placement marker.
func test_paths_cover_monsters_and_markers() -> void:
	var markers: Array[String] = []
	for type in range(1, GameData.TOWER_TYPES + 1):
		markers.append(str(data.tower_model(type)["place_model"]))
	for L in range(1, GameData.LOCATIONS + 1):
		game.start_campaign(0)
		game.enter_location(L)
		_check_paths(ModelWarmup.paths_for(data, game, data.location(L), L), "location %d" % L)
	game.start_survival()
	_check_paths(ModelWarmup.paths_for(data, game, data.location(SimSurvival.LOCATION), SimSurvival.LOCATION), "survival")


func _check_paths(paths: Array[String], label: String) -> void:
	check(not paths.is_empty(), "%s: paths" % label)
	var seen := {}
	var monsters := 0
	for p in paths:
		check(not seen.has(p), "%s: %s listed twice" % [label, p])
		seen[p] = true
		check(ResourceLoader.exists(p), "%s: %s exists" % [label, p])
		if p.contains("/Monsters/"):
			monsters += 1
	check(monsters > 0, "%s: at least one monster model" % label)
	for type in range(1, GameData.TOWER_TYPES + 1):
		check(seen.has(str(data.tower_model(type)["place_model"])), "%s: place model of tower %d" % [label, type])
		check(seen.has(str(data.tower_model(type)["effect_model"])), "%s: effect model of tower %d" % [label, type])
	for p in ModelWarmup.FIXED_PATHS:
		check(seen.has(p), "%s: %s" % [label, p])


## `paths_for` reads the tables only: the simulation's random stream is left alone.
func test_paths_leave_the_rng_alone() -> void:
	game.start_campaign(0)
	game.enter_location(2)
	var before := game.rng.rng.state
	ModelWarmup.paths_for(data, game, data.location(2), 2)
	check_eq(game.rng.rng.state, before, "rng untouched")


## Headless `warm` loads and pins every path (models, scene, HUD, ground texture) and
## draws nothing.
func test_warm_pins_every_path_headless() -> void:
	game.start_campaign(0)
	game.enter_location(3)
	var before := tree.root.get_child_count()
	ModelWarmup.warm(tree.root, data, game, 3)
	for p in ModelWarmup.all_paths(data, game, 3):
		check(ModelWarmup.is_pinned(p), "%s pinned" % p)
	check(ModelWarmup.is_pinned(str(data.location(3)["ground_texture"])), "ground texture pinned")
	check(not ModelWarmup.is_running(), "no warm-up node in headless")
	check_eq(tree.root.get_child_count(), before, "nothing added to the tree")
