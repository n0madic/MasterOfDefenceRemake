## The whole game simulation: what the original kept in `_v*` globals plus the enemy,
## tower and bullet lists. `tick()` is `_fgamelogic` + `UpdateWorld(1)`; nothing here
## touches the scene tree, so it runs headless in tests.
class_name SimGame
extends RefCounted

signal gold_changed(gold: int)
signal lifes_changed(lifes: int)
signal experience_changed(experience: int)
signal skills_changed
signal raid_started(raid_number: int)
signal raid_finished(raid_number: int)
signal enemy_spawned(enemy: SimEnemy)
signal enemy_died(enemy: SimEnemy, killed: bool)
signal enemy_reached_end(enemy: SimEnemy, lost_lifes: int)
signal tower_built(tower: SimTower)
signal tower_upgrade_started(tower: SimTower)
signal tower_upgraded(tower: SimTower)
signal tower_removed(tower: SimTower)
signal bullet_created(bullet: SimBullet)
signal bullet_removed(bullet: SimBullet, exploded: bool)
signal flame_hit(tower: SimTower, enemy: SimEnemy)
signal bomb_dropped(bomb: SimBomb)
signal bomb_exploded(bomb: SimBomb)
signal message(text: String, kind: int, duration_ms: int)
signal sound(name: String, position: Vector3)
signal gold_popup(amount: int, position: Vector3)
signal game_over
signal location_completed

# Message kinds (`_fcreatemessage`): 1 white, 2 red + warning.wav, 3 gold, 4 green.
const MSG_WHITE := 1
const MSG_RED := 2
const MSG_GOLD := 3
const MSG_GREEN := 4

const INGAME_TIME_STEP := 0.01
const RAID_WAIT_TIME := 10.0
const SPAWN_INTERVAL := 0.4
const EXTRA_LIFE_TIME_MIN := 6.0
const EXTRA_LIFE_TIME_MAX := 6.01
const BOSS_RAID_MAX_MONSTERS := 4
const RAID_EXPERIENCE := 20
const CAMPAIGN_INCOME_BASE := 100.0
const ENEMY_SCALE_PER_RAID := 250.0
const BOSS_SCALE := 0.64
const FADE_IN_FRAMES := 3.0
const AIR_BAR_HEIGHT := 3.5
const DEATH_SAVE_MESSAGE_RAIDS := [10, 34, 58]
const PLACE_MARKER_Y := 0.0
const HEALER_RANGE_FACTOR := 10.0
const WORKER_IDS := [32, 33]
const GAMEDEV_WORKER_ID := 34
const TOWER_PREVIEW_COUNT := 2  # hidden Icerock/Flame previews counted in `_vtowersamount`
const FLAME_RANGE_EFFECT := 0.3
const POISON_EFFECT_SIZE := 0.8
const EFFECT_FIRE := 1
const EFFECT_POISON := 2

var data: Node
var rng: Blitz.Random
## When true, known bugs of the original are reproduced (see godot/README.md).
var reproduce_original_bugs := false
var gamedev_mode := false
## Level debugging (`--cheats`): inhabitants never die, gold and experience are never spent.
var cheats := false

# `tthegamet` / globals
var gold := 0:
	set(v):
		gold = v
		gold_changed.emit(gold)
var lifes := 0:
	set(v):
		lifes = v
		lifes_changed.emit(lifes)
var experience := 0:
	set(v):
		experience = v
		experience_changed.emit(experience)
var old_lifes := 0
var extra_lifes := 0
var gold_to_spend := 0
var curlevel := 1
var location := 1
var max_location := 1
var titul := 0
var survival_mode := false
var ingame_time := 0.0
var create_enemies_mode := false
var level_finished := true
var enemies_created := 0
var enemies_amount := 0
var show_units_life := false
var units_life_multiplier := 1.0
var monsters_killed_by_inhabitants := 0
var missed := PackedInt32Array()
var skills := SimSkills.new()
## Mutable prototypes [type][level] (skills multiply them in place).
var protos: Array = []
## Current raids table: campaign uses `data.raids`, survival generates rows lazily.
var survival_raids: Array = []

var enemies: Array[SimEnemy] = []
var towers: Array[SimTower] = []
var bullets: Array[SimBullet] = []
var bombs: Array[SimBomb] = []
var balloon: SimBalloon = null
var selected_tower: SimTower = null
var selected_enemy: SimEnemy = null
var _next_id := 1
var tick_count := 0
var is_game_over := false
var path: Dictionary = {}


func _init(game_data: Node, seed_value: int = 0) -> void:
	data = game_data
	rng = Blitz.Random.new(seed_value)
	missed.resize(1000)
	reset_protos()


## `_floadtowerprototipesdata`: fresh copies of the CSV values.
func reset_protos() -> void:
	protos = [null]
	for type_id in range(1, GameData.TOWER_TYPES + 1):
		var levels: Array = []
		for level in GameData.TOWER_LEVELS:
			levels.append(data.proto(type_id, level).duplicate())
		protos.append(levels)


# ---------------------------------------------------------------- game setup

## `_finitbalancedata`: start values for a campaign at difficulty `titul`.
func init_balance(difficulty: int) -> void:
	titul = difficulty
	curlevel = 1
	var start_gold := 200
	var start_lifes := 100
	match titul:
		1:
			start_lifes = 25
		2:
			start_lifes = 1
			start_gold = 500
	gold = start_gold
	lifes = start_lifes
	old_lifes = start_lifes
	skills.reset()
	experience = 0
	extra_lifes = 0
	units_life_multiplier = 1.0
	missed.fill(0)
	monsters_killed_by_inhabitants = 0


func start_campaign(difficulty: int) -> void:
	survival_mode = false
	init_balance(difficulty)
	location = 1
	max_location = 1
	enter_location(1)


## `_finitsurvival`.
func start_survival() -> void:
	survival_mode = true
	init_balance(0)
	experience = SimSurvival.START_EXPERIENCE
	gold = SimSurvival.START_GOLD
	lifes = SimSurvival.START_LIFES
	old_lifes = lifes
	survival_raids = [null]
	location = SimSurvival.LOCATION
	enter_location(SimSurvival.LOCATION)


## Load location L and `_frestartlocation(0)`: clears every object, raid = first of L.
## The balloon is dropped like `_funloadlocation` → `_fdeleteballoon` does, so the next
## `enable_balloon` recreates it at the centre of the new location's rectangle.
func enter_location(L: int) -> void:
	location = L
	path = data.paths[L]
	balloon = null
	restart_location()


## `_frestartlocation(reload_protos)`.
func restart_location(reload_protos: bool = false) -> void:
	deselect_all_towers()
	for t: SimTower in towers.duplicate():
		delete_tower(t)
	for e: SimEnemy in enemies.duplicate():
		delete_enemy(e, false, false)
	for b: SimBullet in bullets.duplicate():
		delete_bullet(b, false)
	bombs.clear()
	curlevel = 1 if survival_mode else data.location_first_raid[location]
	ingame_time = 0.0
	create_enemies_mode = false
	level_finished = true
	enemies_created = 0
	if reload_protos:
		reset_protos()
	units_life_multiplier = 1.0
	is_game_over = false
	if balloon != null:
		balloon.enabled = bool(data.location(location)["balloon"]) and not survival_mode


## `_fnextlocation`: called from the congratulations screen. Returns true when the
## campaign is finished (location 6 done).
func next_location() -> bool:
	if location < GameData.LOCATIONS:
		location += 1
		if location > max_location:
			max_location = location
		if gold > 200:
			gold_to_spend = gold - 100
			extra_lifes += Blitz.idiv(gold_to_spend, 100)
		gold = 200 + location * 20
		if location == 5:
			gold = 250 + location * 20
		experience += location * 10
		return false
	gold_to_spend = gold - 100
	lifes = lifes + Blitz.idiv(gold_to_spend, 100)
	lifes = lifes + extra_lifes
	# `_fcreatehighscoresmenu` converts the same gold once more (only above 200) before
	# the campaign score `lifes` is taken; nothing in between touches gold or lifes.
	if gold > 200:
		gold_to_spend = gold - 100
		lifes = lifes + Blitz.idiv(gold_to_spend, 100)
	return true


func current_raid() -> Dictionary:
	if survival_mode:
		while survival_raids.size() <= curlevel:
			survival_raids.append(SimSurvival.make_raid(data, survival_raids.size(), rng))
		return survival_raids[curlevel]
	return data.raid(curlevel)


func last_raid_of_location() -> int:
	if location < GameData.LOCATIONS:
		return data.location_first_raid[location + 1] - 1
	return GameData.CAMPAIGN_RAIDS


func raid_index_in_location() -> int:
	return curlevel - data.location_first_raid[location] + 1


func raids_in_location() -> int:
	return int(data.location(location)["raids"])


# ---------------------------------------------------------------- tick

## `_fgamelogic` (when the skills window is closed) followed by `UpdateWorld(1)`.
func tick() -> void:
	if is_game_over:
		return
	tick_count += 1
	if level_finished:
		handle_levels()
	update_enemies()
	handle_towers()
	handle_balloon()
	update_bullets()
	handle_bombs()
	for t in towers:
		t.update_anim()


## `_fhandlelevels`: raid wait timer and monster spawning.
func handle_levels() -> void:
	ingame_time = Blitz.f32(ingame_time + Blitz.f32(INGAME_TIME_STEP))
	if ingame_time >= RAID_WAIT_TIME:
		ingame_time = 0.0
		create_enemies_mode = true
	if ingame_time >= EXTRA_LIFE_TIME_MIN and ingame_time < EXTRA_LIFE_TIME_MAX and extra_lifes > 0:
		extra_lifes -= 1
		create_enemy(false, worker_id())
	if create_enemies_mode:
		if ingame_time >= SPAWN_INTERVAL:
			var raid := current_raid()
			var monsters: Array = raid["monsters"]
			if enemies_created < monsters.size():
				var boss: bool = monsters.size() < BOSS_RAID_MAX_MONSTERS
				create_enemy(boss, int(monsters[enemies_created]))
				if enemies_created == 0:
					sound.emit("start", Vector3.ZERO)
					raid_started.emit(curlevel)
				enemies_created += 1
				ingame_time = 0.0
			else:
				create_enemies_mode = false
				level_finished = false
				enemies_created = 0


func worker_id() -> int:
	if gamedev_mode:
		return GAMEDEV_WORKER_ID
	return rng.rand(WORKER_IDS[0], WORKER_IDS[1])


## `_fcreateenemy(boss, unitId)`.
func create_enemy(boss: bool, unit_id: int) -> SimEnemy:
	var raid := current_raid()
	var unit: Dictionary = data.unit(unit_id)
	var e := SimEnemy.new()
	e.id = _next_id
	_next_id += 1
	var offset := Blitz.to_godot(Vector3(rng.rnd(-1.0, 1.0), 0.0, rng.rnd(0.0, 1.0)))
	e.path.setup(path, offset)
	e.speed = Blitz.f32(float(raid["speed"]) / 10.0)
	e.max_life = Blitz.f32(units_life_multiplier * float(int(raid["life"])))
	e.armor = int(raid["armor"])
	e.gold = int(raid["gold"])
	e.life = e.max_life
	e.air = bool(unit["air"])
	e.anim_speed = float(unit["anim_speed"])
	e.freeze = 0.0
	e.unit_id = unit_id
	e.boss = boss
	if survival_mode and e.air:
		e.armor = Blitz.round_int(float(e.armor) * SimSurvival.AIR_ARMOR_FACTOR)
	e.healer = int(unit["healer"])
	if e.healer != 0:
		if not boss:
			e.max_life *= 2.0
			e.gold = e.gold << 1
		else:
			e.max_life /= 2.0
			e.gold = Blitz.idiv(e.gold, 10)
		e.life = e.max_life
	e.worker = bool(unit["worker"])
	var s := float(curlevel) / ENEMY_SCALE_PER_RAID
	if boss:
		s = BOSS_SCALE
	if s > BOSS_SCALE:
		s = BOSS_SCALE
	e.scale = s + 1.0
	if e.healer == 0:
		e.md2_speed = e.anim_speed * e.speed - s / 7.5
	else:
		e.md2_speed = e.anim_speed * e.speed - s / 10.0
	if not e.worker:
		enemies_amount += 1
	enemies.append(e)
	enemy_spawned.emit(e)
	return e


## `_fupdateenemies`.
func update_enemies() -> void:
	for e: SimEnemy in enemies.duplicate():
		if e.id == 0:
			continue  # deleted earlier this tick
		if e.healer > 0:
			for other: SimEnemy in enemies:
				if other.id == 0:
					continue
				var d := other.position.distance_to(e.position)
				if d < float(e.healer * 10):
					var heal := float(e.healer) / (d * HEALER_RANGE_FACTOR)
					if heal + other.life < other.max_life:
						other.life += heal
		if e.freeze <= 0.0:
			e.path.advance(e.speed, e.speed * PathFollower.MARKER_FRAMES_PER_SPEED)
		else:
			var step := e.speed / e.freeze * 2.0
			e.path.advance(step, step * PathFollower.MARKER_FRAMES_PER_SPEED)
			e.freeze -= 1.0
		if e.burn_time > 0.0:
			e.life -= e.burn_damage
			e.burn_time -= 1.0
			if e.burn_time <= 0.0:
				e.effect_kind = 0
		if e.poison_time > 0.0:
			e.life -= e.poison_damage
			e.poison_time -= 1.0
			if e.poison_time <= 0.0:
				e.effect_kind = 0
		e.md2_time = fmod(e.md2_time + e.md2_speed, 10.0)
		if not e.reached_end():
			if e.life <= 0.0:
				delete_enemy(e, true, true)
		else:
			var lost := 0
			if not e.worker:
				lost = Blitz.round_int(e.life_percent() / float(skills.ppl_resistance * 3 + 33))
				if e.boss:
					lost *= 5
				if not cheats:
					lifes = maxi(lifes - lost, 0)
				if lost < 1:
					monsters_killed_by_inhabitants += 1
				else:
					sound.emit("kill%d" % rng.rand(1, 4), e.position)
			else:
				lifes += 1
				old_lifes = lifes
			enemy_reached_end.emit(e, lost)
			if lifes < 1:
				is_game_over = true
				game_over.emit()
			delete_enemy(e, false, true)


## `_fdeleteenemy(enemy, killed, checkLevel)`.
func delete_enemy(e: SimEnemy, killed: bool, check_level: bool) -> void:
	if e.id == 0:
		return
	if killed:
		gold += e.gold
		sound.emit("death%d" % rng.rand(1, 4), e.position)
		gold_popup.emit(e.gold, e.position)
	if e.selected:
		e.selected = false
		selected_enemy = null
	for t in towers:
		if t.target == e:
			t.target = null
	for b in bullets:
		if b.target == e:
			b.target = null
	enemies.erase(e)
	# Views look their node up by id, so signal before the handle is invalidated.
	enemy_died.emit(e, killed)
	e.id = 0
	if not e.worker:
		enemies_amount -= 1
		if check_level and enemies_amount == 0:
			next_level()


## `_fnextlevel`.
func next_level() -> void:
	var finished_raid := curlevel
	if not survival_mode:
		match curlevel:
			1: message.emit(data.text(53), MSG_WHITE, 3000)
			3: message.emit(data.text(51), MSG_WHITE, 3000)
			4: message.emit(data.text(52), MSG_WHITE, 3000)
		if curlevel in DEATH_SAVE_MESSAGE_RAIDS:
			message.emit(data.text(50), MSG_WHITE, 3000)
		if curlevel < last_raid_of_location():
			curlevel += 1
		else:
			location_completed.emit()
	else:
		curlevel += 1
	level_finished = true
	ingame_time = 0.0
	var income: int
	if survival_mode:
		income = Blitz.round_int(skills.gold_rate * float(lifes))
	else:
		income = Blitz.round_int(skills.gold_rate * CAMPAIGN_INCOME_BASE)
	gold += income
	message.emit("%s %d %s" % [data.text(46), income, data.text(30)], MSG_GOLD, 3000)
	if lifes < old_lifes:
		missed[curlevel] = old_lifes - lifes
		message.emit("%d %s" % [old_lifes - lifes, data.text(47)], MSG_WHITE, 2000)
		old_lifes = lifes
	if monsters_killed_by_inhabitants > 0:
		message.emit("%d %s" % [monsters_killed_by_inhabitants, data.text(88)], MSG_WHITE, 1500)
		sound.emit("nokills", Vector3.ZERO)
	monsters_killed_by_inhabitants = 0
	if not survival_mode:
		units_life_multiplier = SimBalance.update(units_life_multiplier, missed, curlevel, location, titul, lifes)
	experience += RAID_EXPERIENCE
	enable_all_towers()
	raid_finished.emit(finished_raid)


func enable_all_towers() -> void:
	for t in towers:
		t.stopped = false


# ---------------------------------------------------------------- towers

## `_fcreatetower(type, level, hidden=0)` + `_fpositiontower`: a tower placed at `pos`.
## Gold is charged here (`_fdecgold`). Returns null when the player cannot afford it.
func build_tower(type: int, pos: Vector3, level: int = 0, charge: bool = true) -> SimTower:
	var p: Dictionary = protos[type][level]
	if charge and gold < int(p["price"]):
		sound.emit("oops2", Vector3.ZERO)
		return null
	var t := SimTower.new()
	t.id = _next_id
	_next_id += 1
	t.type = type
	t.level = level
	t.apply_proto(p)
	t.fire_keys = data.tower_model(type)["fire1"]
	t.position = pos
	t.yaw_degrees = rng.rnd(0.0, 360.0)
	t.animate(SimTower.ANIM_LOOP, t.idle_seq())
	if charge:
		if not cheats:
			gold -= int(p["price"])
		t.spent += int(p["price"])
	towers.append(t)
	if charge:
		# `_fpositiontower(1, ...)`: only a placed tower plays its sound; towers rebuilt
		# from a save (`_floadgame` -> `_fpositiontower(0, yaw)`) are silent.
		sound.emit("%s_build" % ["", "military", "magic", "plant", "freeze", "fire"][type], pos)
	tower_built.emit(t)
	return t


func tower_price(type: int, level: int = 0) -> int:
	return int(protos[type][level]["price"])


func can_afford_tower(type: int) -> bool:
	return gold >= tower_price(type)


## Placement rule shared by the picker: no other tower closer than 5.6.
func is_too_close_to_tower(pos: Vector3) -> bool:
	for t in towers:
		if not t.hidden and t.position.distance_to(pos) < SimTower.MIN_DISTANCE_BETWEEN_TOWERS:
			return true
	return false


## `_fupgradetower` for the selected tower. Returns true if the upgrade was started.
func upgrade_selected_tower() -> bool:
	var t := selected_tower
	if t == null:
		return false
	if t.level + 1 <= t.max_upgrades and t.anim_seq == t.idle_seq():
		var price := int(protos[t.type][t.level + 1]["price"])
		if gold < price:
			sound.emit("oops2", Vector3.ZERO)
			return false
		t.level += 1
		if not cheats:
			gold -= price
		t.spent += price
		t.upgrade_pending = true
		tower_upgrade_started.emit(t)
		return true
	return false


## `_fselltower` + `_freturngold` + `_fdeletetower` for the selected tower.
func sell_selected_tower() -> bool:
	var t := selected_tower
	if t == null:
		return false
	gold = Blitz.round_int(float(gold) + skills.sell_rate * float(t.spent))
	delete_tower(t)
	return true


func sell_value(t: SimTower) -> int:
	return Blitz.round_int(skills.sell_rate * float(t.spent))


func delete_tower(t: SimTower) -> void:
	if t.selected:
		t.selected = false
		selected_tower = null
	for b: SimBullet in bullets.duplicate():
		if b.tower == t:
			delete_bullet(b, false)
	towers.erase(t)
	tower_removed.emit(t)


## `_fselecttower`: also drops the monster selection.
func select_tower(t: SimTower) -> void:
	deselect_all_towers()
	t.selected = true
	selected_tower = t
	deselect_enemy()


func deselect_all_towers() -> void:
	for t in towers:
		t.selected = false
	selected_tower = null


## `_fhandleenemyselection`: the picked monster becomes every tower's target (an inhabitant
## is selected but never targeted); the tower selection is dropped.
func select_enemy(e: SimEnemy) -> void:
	if not e.worker:
		for t in towers:
			t.target = e
	deselect_enemy()
	e.selected = true
	selected_enemy = e
	deselect_all_towers()


func deselect_enemy() -> void:
	if selected_enemy != null:
		selected_enemy.selected = false
	selected_enemy = null


## Tab: next visible tower after the selected one (`_fswitchtonexttower`).
func next_tower() -> SimTower:
	if towers.size() + TOWER_PREVIEW_COUNT <= 3:
		return null
	var idx := towers.find(selected_tower) if selected_tower != null else -1
	var t: SimTower = towers[(idx + 1) % towers.size()]
	select_tower(t)
	return t


## `_fhandletowers` (simulation part; picking lives in the view).
func handle_towers() -> void:
	var candidate: SimEnemy = null
	for t in towers:
		t.timer += SimTower.TIMER_STEP_MS
		if t.anim_seq == t.upgrade_seq() and not t.animating():
			t.animate(SimTower.ANIM_LOOP, t.idle_seq())
			message.emit(data.text(57), MSG_WHITE, 1500)
			finish_tower_upgrade(t)
			sound.emit("update", t.position)
		if t.upgrade_pending and Blitz.round_int(t.anim_time) == SimTower.SEQ_FRAMES:
			t.animate(SimTower.ANIM_ONESHOT, t.upgrade_seq())
			t.upgrade_pending = false
		if not t.stopped:
			candidate = null
			if t.target_method == 1:
				var best := 100.0
				for e: SimEnemy in enemies:
					if e.worker or not t.can_hit(e):
						continue
					var d := t.position.distance_to(e.position)
					if d < t.range:
						if e.selected:
							candidate = e
							break
						if d < best:
							candidate = e
							best = d
			elif t.target_method == 2:
				if t.target == null or t.position.distance_to(t.target.position) >= t.range:
					for i in range(enemies.size() - 1, -1, -1):
						var e: SimEnemy = enemies[i]
						if t.position.distance_to(e.position) < t.range and not e.worker and t.can_hit(e):
							candidate = e
							break
				else:
					candidate = t.target
		if candidate != null:
			if shoot(t, candidate):
				t.target = candidate
			else:
				t.target = null


## `_ffinishtowerupgrade`: parameters of the new level become active.
func finish_tower_upgrade(t: SimTower) -> void:
	t.apply_proto(protos[t.type][t.level])
	tower_upgraded.emit(t)


## `_fcreateduration`: an enemy carries one visual effect; a burn or poison applied while
## another effect is still attached keeps the old one (both timers clear the slot).
func start_effect(e: SimEnemy, kind: int, size: float) -> void:
	if e.effect_kind != 0:
		return
	e.effect_kind = kind
	e.effect_size = size


## `_fshoot(tower, enemy)`: returns false when the tower cannot attack this enemy.
func shoot(t: SimTower, e: SimEnemy) -> bool:
	if e.air and t.air_damage == 0.0:
		return false
	if not e.air and t.land_damage == 0.0:
		return false
	if t.stopped:
		return false
	if t.timer > t.rate_of_fire:
		if t.type == GameData.TOWER_FLAME:
			var fm := mini(skills.fire_magic, 5)
			e.burn_time = float(fm) * t.fire
			start_effect(e, EFFECT_FIRE, float(t.level + 1) * FLAME_RANGE_EFFECT)
			e.burn_damage = t.land_damage
			t.timer = 0
			flame_hit.emit(t, e)
			return true
		var b := SimBullet.new()
		b.id = _next_id
		_next_id += 1
		b.position = t.fire_point()
		b.direction = (e.position - b.position).normalized()
		b.target = e
		b.speed = SimTower.BULLET_SPEED
		if e.air:
			b.damage = t.air_damage
			if skills.fire_magic == 6 and t.type == GameData.TOWER_MAGIC:
				b.burn = b.damage * 5.0
		else:
			b.damage = t.land_damage
		b.freeze = float(skills.cold_magic) * t.freeze
		b.poison = float(t.poison_coof * skills.poison_magic)
		t.timer = 0
		b.tower = t
		b.model = t.bullet_model
		bullets.append(b)
		match t.type:
			GameData.TOWER_LAND:
				sound.emit("exp1", t.position)
			GameData.TOWER_MAGIC, GameData.TOWER_ICEROCK:
				sound.emit("exp2", t.position)
		bullet_created.emit(b)
	return true


## `_fupdatebullets`.
func update_bullets() -> void:
	for b: SimBullet in bullets.duplicate():
		if b.id == 0:
			continue
		if b.position.distance_to(b.tower.position) > b.tower.range:
			delete_bullet(b, true)
			continue
		if b.target != null:
			var e := b.target
			var aim := e.aim_point()
			var delta := aim - b.position
			if delta.length() > 0.0:
				b.direction = delta.normalized()
			if b.position.distance_to(aim) < 1.0:
				if float(e.armor) < b.damage:
					e.life -= b.damage - float(e.armor)
				if b.freeze > 0.0:
					e.freeze = b.freeze
				if b.poison > 0.0 and e.poison_time < b.poison:
					e.poison_time = b.poison
					start_effect(e, EFFECT_POISON, POISON_EFFECT_SIZE)
					e.poison_damage = b.tower.poison_damage
				if b.burn > 0.0 and e.burn_time < b.burn:
					e.burn_time = b.burn
					start_effect(e, EFFECT_FIRE, float(b.tower.level + 1) * FLAME_RANGE_EFFECT)
					e.burn_damage = 1.0
				delete_bullet(b, true)
				continue
		b.position += b.direction * b.speed


func delete_bullet(b: SimBullet, exploded: bool) -> void:
	if b.id == 0:
		return
	bullets.erase(b)
	bullet_removed.emit(b, exploded)
	b.id = 0


# ---------------------------------------------------------------- balloon and bombs

func enable_balloon() -> void:
	if balloon == null:
		balloon = SimBalloon.new()
		var loc: Dictionary = data.location(location)
		var bounds: Dictionary = loc["bounds"]
		balloon.position = Vector3(
			(float(bounds["x_min"]) + float(bounds["x_max"])) / 2.0,
			SimBalloon.HEIGHT,
			(float(bounds["z_min"]) + float(bounds["z_max"])) / 2.0)
	balloon.enabled = true


## `_fhandleballoons`: bombs drop when an enemy is near and the timer allows it.
func handle_balloon() -> void:
	if balloon == null or not balloon.enabled:
		return
	balloon.update(self)
	balloon.timer += 1
	if balloon.timer > SimBalloon.BOMB_INTERVAL_TICKS:
		for e: SimEnemy in enemies:
			if not e.worker and e.position.distance_to(balloon.position) < SimBalloon.BOMB_TRIGGER_DISTANCE:
				var bomb := SimBomb.new()
				bomb.id = _next_id
				_next_id += 1
				bomb.position = balloon.position + Vector3(0, 1, 0)
				bomb.damage = SimBomb.DAMAGE
				bomb.freeze = float(SimBomb.FREEZE_PER_COLD * skills.cold_magic)
				bombs.append(bomb)
				balloon.timer = 0
				bomb_dropped.emit(bomb)
				break


## `_fhandlebombs`.
func handle_bombs() -> void:
	for bomb: SimBomb in bombs.duplicate():
		bomb.position.y -= SimBomb.FALL_SPEED
		if bomb.position.y <= 0.0:
			for e: SimEnemy in enemies.duplicate():
				if e.position.distance_to(bomb.position) < SimBomb.RADIUS:
					e.life -= bomb.damage
					e.freeze = bomb.freeze
			sound.emit("exp1", bomb.position)
			bombs.erase(bomb)
			bomb_exploded.emit(bomb)


# ---------------------------------------------------------------- helpers for views

func find_enemy(id: int) -> SimEnemy:
	for e in enemies:
		if e.id == id:
			return e
	return null


func find_tower(id: int) -> SimTower:
	for t in towers:
		if t.id == id:
			return t
	return null
