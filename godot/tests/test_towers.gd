extends SimTestCase

const ORIGIN := Vector3(60, 0, -20)
const WORKER_UNIT := 32  # Male, an inhabitant


func setup() -> void:
	super.setup()
	game.start_campaign(0)


func test_build_charges_gold() -> void:
	check_eq(game.gold, 200, "start gold")
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	check(t != null, "built")
	check_eq(game.gold, 170, "gold after build")
	check_eq(t.spent, 30, "spent")
	check_eq(t.anim_seq, 1, "idle seq of level 0")
	check_eq(t.rate_of_fire, 982, "rate")
	game.gold = 10
	check(game.build_tower(GameData.TOWER_LAND, ORIGIN + Vector3(10, 0, 0)) == null, "cannot afford")
	check(sounds.has("oops2"), "oops sound")


func test_land_tower_dps_6000_ticks() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	var e := dummy_enemy(ORIGIN + Vector3(5, 0, 0), false, 100000.0, 2)
	# Lambdas capture locals by value, so counters live in a dictionary.
	var c := {"fired": 0, "hits": 0}
	game.bullet_created.connect(func(_b): c["fired"] += 1)
	game.bullet_removed.connect(func(b, exploded): if exploded and b.target != null: c["hits"] += 1)
	run_ticks(6000)
	var fired: int = c["fired"]
	var hits: int = c["hits"]
	# timer += 16 per tick, shoots when timer > 982 -> every 62 ticks.
	check_eq(fired, 6000 / 62, "bullets fired")
	# fire1 of Military level 0 is 4.37 above the tower, enemy 5 away: ~6.6 units at 0.4/tick -> ~17 ticks.
	check(hits >= fired - 1 and hits <= fired, "hits %d of %d" % [hits, fired])
	check_near(100000.0 - e.life, float(hits) * (20.0 - 2.0), 0.01, "damage minus armor")
	check(t.target == e, "sticky target")


func test_armor_blocks_weak_bullets() -> void:
	game.build_tower(GameData.TOWER_LAND, ORIGIN)
	var e := dummy_enemy(ORIGIN + Vector3(5, 0, 0), false, 1000.0, 25)
	run_ticks(200)
	check_eq(e.life, 1000.0, "damage 20 <= armor 25 -> no damage")


func test_upgrade_takes_100_ticks_after_idle_loop() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	game.select_tower(t)
	check(game.upgrade_selected_tower(), "upgrade accepted")
	check_eq(t.level, 1, "level bumped immediately")
	check_eq(game.gold, 150, "gold 200-30-20")
	check_eq(t.land_damage, 20.0, "old damage during the animation")
	var done := {"upgraded": false}
	game.tower_upgraded.connect(func(_t): done["upgraded"] = true)
	var ticks := run_until(func(): return done["upgraded"], 400)
	# Idle loop reaches AnimTime ~10 within 95..100 ticks, then the one-shot lasts 100 ticks.
	check(ticks >= 190 and ticks <= 201, "upgrade finished after %d ticks" % ticks)
	check_eq(t.land_damage, float(data.proto(1, 1)["land_damage"]), "new damage after animation")
	check_eq(t.anim_seq, 3, "idle seq of level 1")
	check(messages.any(func(m): return m["text"] == "Tower upgraded"), "message")
	# A second upgrade right away is refused while the tower is not idle-looping yet? It is idle now.
	check(game.upgrade_selected_tower(), "second upgrade accepted")


func test_upgrade_limits() -> void:
	var t := game.build_tower(GameData.TOWER_MAGIC, ORIGIN)
	game.select_tower(t)
	game.gold = 10000
	for i in 5:
		check(game.upgrade_selected_tower(), "upgrade %d" % i)
		run_until(func(): return t.anim_seq == t.idle_seq() and not t.upgrade_pending and t.level == i + 1 and t.air_damage == float(game.protos[2][i + 1]["air_damage"]), 400)
	check_eq(t.level, 5, "max level")
	check(not game.upgrade_selected_tower(), "no more upgrades")


func test_sell_rounds_half_even() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	game.select_tower(t)
	game.gold = 100
	game.sell_selected_tower()
	# 100 + 0.75*30 = 122.5 -> 122
	check_eq(game.gold, 122, "sell 30 at 0.75 from 100")
	check_eq(game.towers.size(), 0, "tower removed")
	t = game.build_tower(GameData.TOWER_LAND, ORIGIN)
	game.select_tower(t)
	game.gold = 101
	game.sell_selected_tower()
	check_eq(game.gold, 124, "123.5 -> 124")


func test_sticky_target_method_2() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	var near := dummy_enemy(ORIGIN + Vector3(3, 0, 0))
	var far := dummy_enemy(ORIGIN + Vector3(8, 0, 0))
	run_ticks(63)
	check(t.target == far, "Land picks the last created enemy in range")
	run_ticks(200)
	check(t.target == far, "keeps it while in range")
	far.path.body = ORIGIN + Vector3(30, 0, 0)
	run_ticks(63)
	check(t.target == near, "switches when the target leaves the range")


func test_nearest_target_method_1_and_selection_priority() -> void:
	var t := game.build_tower(GameData.TOWER_PLANT, ORIGIN)
	var near := dummy_enemy(ORIGIN + Vector3(3, 0, 0))
	var far := dummy_enemy(ORIGIN + Vector3(8, 0, 0))
	run_ticks(70)
	check(t.target == near, "Plant picks the nearest")
	game.select_enemy(far)
	run_ticks(70)
	check(t.target == far, "selected enemy has priority")


func test_enemy_and_tower_selection_exclude_each_other() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	var e := dummy_enemy(ORIGIN + Vector3(30, 0, 0))
	game.select_tower(t)
	game.select_enemy(e)
	check(game.selected_enemy == e and e.selected, "the monster is selected")
	check(t.target == e, "the selected monster becomes every tower's target")
	check(game.selected_tower == null and not t.selected, "selecting a monster drops the tower")
	game.select_tower(t)
	check(game.selected_enemy == null and not e.selected, "selecting a tower drops the monster")


func test_selected_worker_is_not_targeted() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	var worker := game.create_enemy(false, WORKER_UNIT)
	check(worker.worker, "unit %d is an inhabitant" % WORKER_UNIT)
	game.select_enemy(worker)
	check(game.selected_enemy == worker, "an inhabitant can be selected")
	check(t.target == null, "but the towers do not take it as their target")


func test_type_restrictions() -> void:
	var land := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	var magic := game.build_tower(GameData.TOWER_MAGIC, ORIGIN + Vector3(0, 0, 6))
	var flyer := dummy_enemy(ORIGIN + Vector3(3, 0, 0), true)
	run_ticks(100)
	check(land.target == null, "Land ignores air")
	check(magic.target == flyer, "Magic attacks air")


func test_freeze_overwrites_poison_and_fire_only_if_longer() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	var e := dummy_enemy(ORIGIN + Vector3(5, 0, 0))
	e.freeze = 40.0
	e.poison_time = 50.0
	e.burn_time = 50.0
	var b := SimBullet.new()
	b.id = 99
	b.tower = t
	b.target = e
	b.position = e.position + Vector3(0.5, 0, 0)
	b.damage = 0.0
	b.freeze = 10.0
	b.poison = 20.0
	b.burn = 20.0
	game.bullets.append(b)
	game.update_bullets()
	check_eq(e.freeze, 10.0, "freeze overwritten with a smaller value")
	check_eq(e.poison_time, 50.0, "shorter poison ignored")
	check_eq(e.burn_time, 50.0, "shorter burn ignored")
	b = SimBullet.new()
	b.id = 100
	b.tower = t
	b.target = e
	b.position = e.position + Vector3(0.5, 0, 0)
	b.poison = 60.0
	b.burn = 70.0
	game.bullets.append(b)
	game.update_bullets()
	check_eq(e.poison_time, 60.0, "longer poison applied")
	check_eq(e.burn_time, 70.0, "longer burn applied")
	check_eq(e.burn_damage, 1.0, "bullet burn does 1 per tick")


func test_single_effect_slot_keeps_first_effect() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	var e := dummy_enemy(ORIGIN + Vector3(5, 0, 0))
	var b := SimBullet.new()
	b.id = 99
	b.tower = t
	b.target = e
	b.position = e.position + Vector3(0.5, 0, 0)
	b.poison = 200.0  # outlives the flame's first shot (23 ticks)
	game.bullets.append(b)
	game.update_bullets()
	check_eq(e.effect_kind, SimGame.EFFECT_POISON, "poison effect attached")
	game.skills.fire_magic = 1
	var flame := game.build_tower(GameData.TOWER_FLAME, e.position + Vector3(1, 0, 0))
	run_until(func(): return e.burn_time > 0.0, 100)
	check_eq(e.effect_kind, SimGame.EFFECT_POISON, "burn keeps the poison effect (_fcreateduration)")
	run_until(func(): return e.poison_time <= 0.0, 300)
	check_eq(e.effect_kind, 0, "effect cleared when the poison ends, burn still running")
	check(e.burn_time > 0.0, "still burning")
	run_until(func(): return e.effect_kind != 0, 100)
	check_eq(e.effect_kind, SimGame.EFFECT_FIRE, "next flame shot attaches the fire effect")
	check(flame.id != 0, "flame alive")


func test_frozen_enemy_moves_slower() -> void:
	game.skills.cold_magic = 1
	var e := game.create_enemy(false, 1)
	var t := game.build_tower(GameData.TOWER_ICEROCK, e.position + Vector3(2, 0, 0))
	run_until(func(): return e.freeze > 0.0, 200)
	check_eq(e.freeze, 15.0, "freeze = cold * 15")
	var p0 := e.position
	run_ticks(1)
	var step := p0.distance_to(e.position)
	check_near(step, e.speed / 15.0 * 2.0, 1e-5, "frozen step speed/freeze*2")
	check_eq(e.freeze, 14.0, "freeze counts down")
	check(t.id != 0, "tower alive")


func test_flame_burns_ground_only_on_road() -> void:
	game.skills.fire_magic = 2
	var t := game.build_tower(GameData.TOWER_FLAME, ORIGIN)
	check(t.place_on_road, "flame must be placed on the road")
	var e := dummy_enemy(ORIGIN + Vector3(3, 0, 0))
	run_until(func(): return e.burn_time > 0.0, 100)
	check_eq(e.burn_time, 2.0 * 55.0, "burn = min(fm,5) * fire")
	check_near(e.burn_damage, 0.3, 1e-6, "burn damage = land damage")
	check_eq(game.bullets.size(), 0, "no bullets")


func test_fire_point_follows_model_frame() -> void:
	var t := game.build_tower(GameData.TOWER_LAND, ORIGIN)
	check_near(t.fire_point().y, 4.366, 0.01, "level 0 fire1 height")
	t.level = 10
	t.animate(SimTower.ANIM_LOOP, t.idle_seq())
	check_near(t.fire_point().y, 6.208, 0.01, "level 10 fire1 height (frame 210)")
	var magic := game.build_tower(GameData.TOWER_MAGIC, ORIGIN + Vector3(10, 0, 0))
	check_near(magic.fire_point().y, 6.562, 0.01, "static fire1 of Magic")
	check_near(magic.fire_point().distance_to(magic.position), Vector3(0.0026, 6.562, 0.2362).length(), 0.01, "yaw keeps the offset length")


func test_too_close_rule() -> void:
	game.build_tower(GameData.TOWER_LAND, ORIGIN)
	check(game.is_too_close_to_tower(ORIGIN + Vector3(5.5, 0, 0)), "5.5 too close")
	check(not game.is_too_close_to_tower(ORIGIN + Vector3(5.7, 0, 0)), "5.7 ok")
