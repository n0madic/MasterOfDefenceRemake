extends SimTestCase


func setup() -> void:
	super.setup()
	game.start_campaign(0)


## `_funloadlocation` deletes the balloon when leaving locations 3-5, so every location
## starts it at the centre of its own camera rectangle; a restart keeps it where it was.
func test_balloon_recentred_per_location() -> void:
	game.next_location()
	game.next_location()
	game.next_location()
	game.enter_location(4)
	game.enter_location(5)
	game.enable_balloon()
	var b5: Dictionary = data.location(5)["bounds"]
	var centre5 := Vector3((b5["x_min"] + b5["x_max"]) / 2.0, SimBalloon.HEIGHT, (b5["z_min"] + b5["z_max"]) / 2.0)
	check_eq(game.balloon.position, centre5, "starts at the centre of location 5")
	game.balloon.move_to(Vector3(140, 0, -20))
	run_until(func(): return not game.balloon.is_moving(), 5000)
	check_near(game.balloon.position.x, 140.0, 0.01, "moved on location 5")
	game.restart_location()
	game.enable_balloon()
	check_near(game.balloon.position.x, 140.0, 0.01, "restart keeps the position")
	game.next_location()
	game.enter_location(6)
	game.enable_balloon()
	var b6: Dictionary = data.location(6)["bounds"]
	var centre6 := Vector3((b6["x_min"] + b6["x_max"]) / 2.0, SimBalloon.HEIGHT, (b6["z_min"] + b6["z_max"]) / 2.0)
	check_eq(game.balloon.position, centre6, "recentred on location 6")
	check(not game.balloon.is_moving(), "tween dropped with the old balloon")
