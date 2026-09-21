## Experience skills ("Magic and skills" window), docs/06.
##
## Multipliers are accumulated in float32 like the original: the level caps are
## `upgrader < 1.05f` / `< 1.06f` comparisons, which only give 10 / 12 levels when the
## accumulator drifts exactly like a 32-bit float.
class_name SimSkills
extends RefCounted

enum Id { DAMAGE = 1, SPEED = 2, GOLD = 3, RANGE = 4, SELL = 5, COLD = 6, FIRE = 7, POISON = 8, RESISTANCE = 9, FIRE6 = 10 }
enum Kind { RANGE = 1, SPEED = 2, DAMAGE = 3 }

const PRICES := {
	Id.DAMAGE: 50, Id.SPEED: 80, Id.GOLD: 35, Id.RANGE: 50, Id.SELL: 30,
	Id.COLD: 100, Id.FIRE: 100, Id.POISON: 100, Id.RESISTANCE: 80, Id.FIRE6: 200,
}
const RANGE_MAX := 1.06
const RANGE_INC := 0.005
const SPEED_INC := 0.02
const SPEED_MAX_LEVEL := 5
const DAMAGE_MAX := 1.05
const DAMAGE_INC := 0.005
const GOLD_INC := 0.02
const GOLD_MAX_LEVEL := 20
const SELL_INC := 0.05
const SELL_MAX := 1.0
const SELL_MAX_LEVEL := 5
const MAGIC_MAX_LEVEL := 5

var range_upgrader := 1.0
var range_level := 0
var speed_upgrader := 1.0
var speed_level := 0
var damage_upgrader := 1.0
var damage_level := 0
var gold_rate := 0.6
var gold_level := 0
var sell_rate := 0.75
var sell_level := 0
var cold_magic := 0
var fire_magic := 0
var poison_magic := 0
var ppl_resistance := 0

## Operations since the window was opened: [{id, downgrade}] (`tupgqueryt`).
var query: Array[Dictionary] = []


func reset() -> void:
	range_upgrader = 1.0
	range_level = 0
	speed_upgrader = 1.0
	speed_level = 0
	damage_upgrader = 1.0
	damage_level = 0
	gold_rate = Blitz.f32(0.6)
	gold_level = 0
	sell_rate = 0.75
	sell_level = 0
	cold_magic = 0
	fire_magic = 0
	poison_magic = 0
	ppl_resistance = 0
	query.clear()


## `_fhandlegui`: the fire buttons send id 7 up to level 5 and id 10 (the Magic tower
## ignition, 200 exp) at level 5 / for the downgrade from level 6.
func button_id(id: int, downgrade: bool) -> int:
	if id == Id.FIRE and fire_magic == (MAGIC_MAX_LEVEL + 1 if downgrade else MAGIC_MAX_LEVEL):
		return Id.FIRE6
	return id


## Whether the "+" button of a skill is enabled (`_fhandlegui`).
func can_buy(id: int, experience: int) -> bool:
	if experience < price_of(id):
		return false
	match id:
		Id.DAMAGE: return damage_upgrader < Blitz.f32(DAMAGE_MAX)
		Id.SPEED: return speed_level < SPEED_MAX_LEVEL
		Id.GOLD: return gold_level < GOLD_MAX_LEVEL
		Id.RANGE: return range_upgrader < Blitz.f32(RANGE_MAX)
		Id.SELL: return sell_level < SELL_MAX_LEVEL
		Id.COLD: return cold_magic < MAGIC_MAX_LEVEL
		Id.FIRE: return fire_magic < MAGIC_MAX_LEVEL
		Id.FIRE6: return fire_magic == MAGIC_MAX_LEVEL
		Id.POISON: return poison_magic < MAGIC_MAX_LEVEL
		Id.RESISTANCE: return ppl_resistance < MAGIC_MAX_LEVEL
	return false


func can_downgrade(id: int) -> bool:
	match id:
		Id.DAMAGE: return damage_upgrader > 1.0
		Id.SPEED: return speed_level > 0
		Id.GOLD: return gold_level > 0
		Id.RANGE: return range_upgrader > 1.0
		Id.SELL: return sell_level > 0
		Id.COLD: return cold_magic > 0
		Id.FIRE: return fire_magic >= 1 and fire_magic <= 5
		Id.FIRE6: return fire_magic == 6
		Id.POISON: return poison_magic > 0
		Id.RESISTANCE: return ppl_resistance > 0
	return false


func price_of(id: int) -> int:
	return PRICES[id]


func level_of(id: int) -> int:
	match id:
		Id.DAMAGE: return damage_level
		Id.SPEED: return speed_level
		Id.GOLD: return gold_level
		Id.RANGE: return range_level
		Id.SELL: return sell_level
		Id.COLD: return cold_magic
		Id.FIRE, Id.FIRE6: return fire_magic
		Id.POISON: return poison_magic
		Id.RESISTANCE: return ppl_resistance
	return 0


## `_fnewupgade(id, downgrade)`: queue the operation and apply it.
func operate(game: SimGame, id: int, downgrade: bool) -> void:
	query.append({"id": id, "downgrade": downgrade})
	_do(game, id, downgrade, false)


## OK button: forget the queue.
func commit() -> void:
	query.clear()


## Cancel button (`_fcancelqueryupgrades`): undo every queued operation in reverse order.
func cancel(game: SimGame) -> void:
	for i in range(query.size() - 1, -1, -1):
		var op: Dictionary = query[i]
		_do(game, int(op["id"]), not bool(op["downgrade"]), true)
	query.clear()


## `_fdoupgrades(downgrade, cancel)` for one event. Cost is price / (2 - (cancel ^ 1)) on
## purchase and price / (2 - cancel) on downgrade.
func _do(game: SimGame, id: int, downgrade: bool, cancel: bool) -> void:
	var price := 0 if game.cheats else price_of(id)
	var buy_cost := Blitz.idiv(price, 2 - (0 if cancel else 1))
	var refund := Blitz.idiv(price, 2 - (1 if cancel else 0))
	match id:
		Id.DAMAGE:
			if not downgrade:
				damage_upgrader = Blitz.f32(damage_upgrader + Blitz.f32(DAMAGE_INC))
				game.experience -= buy_cost
				damage_level += 1
				apply_upgrade(game, Kind.DAMAGE)
			else:
				apply_downgrade(game, Kind.DAMAGE)
				damage_upgrader = Blitz.f32(damage_upgrader - Blitz.f32(DAMAGE_INC))
				game.experience += refund
				damage_level -= 1
		Id.SPEED:
			if not downgrade:
				speed_upgrader = Blitz.f32(speed_upgrader - Blitz.f32(SPEED_INC))
				game.experience -= buy_cost
				speed_level += 1
				apply_upgrade(game, Kind.SPEED)
			else:
				apply_downgrade(game, Kind.SPEED)
				speed_upgrader = Blitz.f32(speed_upgrader + Blitz.f32(SPEED_INC))
				game.experience += refund
				speed_level -= 1
		Id.GOLD:
			if not downgrade:
				gold_rate = Blitz.f32(gold_rate + Blitz.f32(GOLD_INC))
				game.experience -= buy_cost
				gold_level += 1
			else:
				gold_rate = Blitz.f32(gold_rate - Blitz.f32(GOLD_INC))
				game.experience += refund
				gold_level -= 1
		Id.RANGE:
			if not downgrade:
				range_upgrader = Blitz.f32(range_upgrader + Blitz.f32(RANGE_INC))
				range_level += 1
				game.experience -= buy_cost
				apply_upgrade(game, Kind.RANGE)
			else:
				apply_downgrade(game, Kind.RANGE)
				range_upgrader = Blitz.f32(range_upgrader - Blitz.f32(RANGE_INC))
				range_level -= 1
				game.experience += refund
		Id.SELL:
			if not downgrade:
				sell_rate = minf(Blitz.f32(sell_rate + Blitz.f32(SELL_INC)), SELL_MAX)
				game.experience -= buy_cost
				sell_level += 1
			else:
				sell_rate = minf(Blitz.f32(sell_rate - Blitz.f32(SELL_INC)), SELL_MAX)
				game.experience += refund
				sell_level -= 1
		Id.COLD:
			if not downgrade:
				cold_magic += 1
				game.experience -= buy_cost
			else:
				cold_magic -= 1
				game.experience += refund
		Id.FIRE, Id.FIRE6:
			if not downgrade:
				fire_magic += 1
				game.experience -= buy_cost
			else:
				fire_magic -= 1
				game.experience += refund
		Id.POISON:
			if not downgrade:
				poison_magic += 1
				game.experience -= buy_cost
			else:
				poison_magic -= 1
				game.experience += refund
		Id.RESISTANCE:
			if not downgrade:
				ppl_resistance += 1
				game.experience -= buy_cost
			else:
				ppl_resistance -= 1
				game.experience += refund
	game.skills_changed.emit()


## `_fupgradetowerbuildingskills(kind, 0)`: multiply all prototypes and built towers by the
## current upgrader.
func apply_upgrade(game: SimGame, kind: int) -> void:
	for type_id in range(1, GameData.TOWER_TYPES + 1):
		for level in GameData.TOWER_LEVELS:
			var p: Dictionary = game.protos[type_id][level]
			_scale_proto(p, kind, false)
	for t in game.towers:
		_scale_tower(t, kind, false)


## `_fdowngradetowerbuildingskills(kind, 0)`: divide by the current upgrader.
func apply_downgrade(game: SimGame, kind: int) -> void:
	for type_id in range(1, GameData.TOWER_TYPES + 1):
		for level in GameData.TOWER_LEVELS:
			_scale_proto(game.protos[type_id][level], kind, true)
	for t in game.towers:
		_scale_tower(t, kind, true)


## `_fupgradetowerbuildingskills(kind, 1)` after loading a save: rebuild multipliers from
## the levels. Prototypes get the cumulative product; built towers get the same, unless
## `reproduce_original_bugs` is set, in which case attack speed of built towers is scaled
## `level` times by the final upgrader (original bug, docs/06).
func reapply_from_levels(game: SimGame, kind: int) -> void:
	var level := 0
	match kind:
		Kind.RANGE: level = range_level
		Kind.SPEED: level = speed_level
		Kind.DAMAGE: level = damage_level
	for type_id in range(1, GameData.TOWER_TYPES + 1):
		for lv in GameData.TOWER_LEVELS:
			var p: Dictionary = game.protos[type_id][lv]
			var m := 1.0
			for k in range(1, level + 1):
				m = _step(m, kind)
				_scale_proto_by(p, kind, m)
	for t in game.towers:
		var m := 1.0
		for k in range(1, level + 1):
			m = _step(m, kind)
			if kind == Kind.SPEED and game.reproduce_original_bugs:
				_scale_tower_by(t, kind, speed_upgrader)
			else:
				_scale_tower_by(t, kind, m)


func _step(m: float, kind: int) -> float:
	match kind:
		Kind.RANGE: return Blitz.f32(m + Blitz.f32(RANGE_INC))
		Kind.SPEED: return Blitz.f32(m - Blitz.f32(SPEED_INC))
		Kind.DAMAGE: return Blitz.f32(m + Blitz.f32(DAMAGE_INC))
	return m


func _upgrader(kind: int) -> float:
	match kind:
		Kind.RANGE: return range_upgrader
		Kind.SPEED: return speed_upgrader
		Kind.DAMAGE: return damage_upgrader
	return 1.0


func _scale_proto(p: Dictionary, kind: int, divide: bool) -> void:
	_scale_proto_by(p, kind, _upgrader(kind), divide)


func _scale_proto_by(p: Dictionary, kind: int, m: float, divide: bool = false) -> void:
	match kind:
		Kind.RANGE:
			p["range"] = _mul(float(p["range"]), m, divide)
		Kind.SPEED:
			p["rate_of_fire_ms"] = Blitz.round_int(_mul(float(p["rate_of_fire_ms"]), m, divide))
		Kind.DAMAGE:
			p["land_damage"] = _mul(float(p["land_damage"]), m, divide)
			p["air_damage"] = _mul(float(p["air_damage"]), m, divide)


func _scale_tower(t: SimTower, kind: int, divide: bool) -> void:
	_scale_tower_by(t, kind, _upgrader(kind), divide)


func _scale_tower_by(t: SimTower, kind: int, m: float, divide: bool = false) -> void:
	match kind:
		Kind.RANGE:
			t.range = _mul(t.range, m, divide)
		Kind.SPEED:
			t.rate_of_fire = Blitz.round_int(_mul(float(t.rate_of_fire), m, divide))
		Kind.DAMAGE:
			t.land_damage = _mul(t.land_damage, m, divide)
			t.air_damage = _mul(t.air_damage, m, divide)


static func _mul(x: float, m: float, divide: bool) -> float:
	return Blitz.f32(x / m) if divide else Blitz.f32(x * m)
