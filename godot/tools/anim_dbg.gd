extends SceneTree
const GameDataScript := preload("res://src/autoload/GameData.gd")
func _initialize() -> void:
	var data: Node = GameDataScript.new()
	data.load_all()
	var game := SimGame.new(data, 12345)
	game.start_campaign(0)
	game.location = 6
	game.enter_location(6)
	game.curlevel = 138
	game.lifes = 100
	print("raid 138: ", data.raid(138))
	var keys: PackedVector3Array = game.path["pos"]
	var events: Array = []
	game.enemy_died.connect(func(e, killed): events.append("died #%d killed=%s t=%.1f" % [e.id, killed, e.path.time]))
	game.enemy_reached_end.connect(func(e, lost): events.append("arrived #%d lost %d" % [e.id, lost]))
	game.gold = 100000
	game.skills.cold_magic = 5
	game.skills.fire_magic = 5
	game.skills.poison_magic = 5
	var types := [GameData.TOWER_LAND, GameData.TOWER_MAGIC, GameData.TOWER_PLANT, GameData.TOWER_ICEROCK]
	var i := 0
	for k in range(4, keys.size() - 2, maxi(keys.size() / 12, 1)):
		var p := keys[k] + Vector3(6 if i % 2 == 0 else -6, 0, 0)
		if game.is_too_close_to_tower(p) or p.distance_to(keys[0]) < 40.0:
			continue
		var t := game.build_tower(types[i % types.size()], p)
		if t != null:
			t.level = t.max_upgrades
			t.apply_proto(game.protos[t.type][t.level])
			t.land_damage *= 8.0
			t.air_damage *= 8.0
			t.animate(SimTower.ANIM_LOOP, t.idle_seq())
		i += 1
	print("towers ", game.towers.size())
	var finished: Array = []
	game.raid_finished.connect(func(n): finished.append("raid %d finished at tick %d curlevel now %d" % [n, game.tick_count, game.curlevel]))
	game.ingame_time = 9.9
	var last := ""
	for tick in 60000:
		game.tick()
		var st := "created %d amount %d mode %s finished %s enemies %d" % [game.enemies_created, game.enemies_amount, game.create_enemies_mode, game.level_finished, game.enemies.size()]
		if st != last and tick < 2600:
			print(tick, ": ", st)
			last = st
		if game.level_finished and game.enemies.is_empty() and tick > 2000:
			break
		if game.level_finished and not game.create_enemies_mode and game.ingame_time < 9.0:
			game.ingame_time = 9.9
	print("after ticks: raid ", game.curlevel, " finished ", game.level_finished, " enemies ", game.enemies.size(), " amount ", game.enemies_amount, " lifes ", game.lifes)
	for e in game.enemies:
		print("  #", e.id, " unit ", e.unit_id, " life ", e.life, "/", e.max_life, " t=", e.path.time, " pos ", e.position, " marker ", e.path.marker_position(), " freeze ", e.freeze, " worker ", e.worker)
	print(events.slice(0, 10))
	print(finished.slice(0, 5), finished.size())
	print("created ", game.enemies_created, " mode ", game.create_enemies_mode, " ingame ", game.ingame_time)
	quit(0)
