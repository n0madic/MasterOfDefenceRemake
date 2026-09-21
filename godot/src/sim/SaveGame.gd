## Save/load of the simulation (`_fsavegame` / `_floadgame`, docs/02): the same fields as
## the original `tthegamet` record plus the tower list, stored as JSON. Loading rebuilds
## towers through `build_tower` (no charge), recomputes `spent` as the sum of level prices
## and re-applies the skill multipliers from their levels.
class_name SaveGame
extends RefCounted

const VERSION := 1


static func serialize(g: SimGame) -> Dictionary:
	var towers: Array = []
	for t in g.towers:
		if t.hidden:
			continue
		towers.append({"type": t.type, "level": t.level, "x": t.position.x, "y": t.position.y, "z": t.position.z,
					   "yaw": t.yaw_degrees, "stopped": t.stopped})
	var s := g.skills
	return {
		"version": VERSION,
		"survival": g.survival_mode,
		"titul": g.titul,
		"gold": g.gold, "lifes": g.lifes, "curlevel": g.curlevel, "location": g.location,
		"range_upgrader": s.range_upgrader, "speed_upgrader": s.speed_upgrader, "damage_upgrader": s.damage_upgrader,
		"gold_rate": s.gold_rate, "sell_rate": s.sell_rate,
		"enemies_created": g.enemies_created, "ingame_time": g.ingame_time, "show_units_life": g.show_units_life,
		"create_enemies_mode": g.create_enemies_mode, "level_finished": g.level_finished,
		"range_level": s.range_level, "speed_level": s.speed_level, "damage_level": s.damage_level,
		"gold_level": s.gold_level, "sell_level": s.sell_level,
		"cold_magic": s.cold_magic, "fire_magic": s.fire_magic, "poison_magic": s.poison_magic,
		"ppl_resistance": s.ppl_resistance, "experience": g.experience, "max_location": g.max_location,
		"old_lifes": g.old_lifes,
		"balloon": [g.balloon.position.x, g.balloon.position.y, g.balloon.position.z] if g.balloon != null else null,
		"extra_lifes": g.extra_lifes,
		"units_life_multiplier": g.units_life_multiplier,
		"missed": Array(g.missed),
		"towers": towers,
	}


## Restore `g` from `d`. Enemies/bullets are dropped (the original saves between raids).
static func restore(g: SimGame, d: Dictionary) -> void:
	g.survival_mode = bool(d.get("survival", false))
	g.titul = int(d.get("titul", 0))
	g.location = int(d["location"])
	g.enter_location(g.location)
	g.reset_protos()
	g.gold = int(d["gold"])
	g.lifes = int(d["lifes"])
	g.curlevel = int(d["curlevel"])
	var s := g.skills
	s.reset()
	s.range_level = int(d["range_level"])
	s.speed_level = int(d["speed_level"])
	s.damage_level = int(d["damage_level"])
	s.gold_level = int(d["gold_level"])
	s.sell_level = int(d["sell_level"])
	s.cold_magic = int(d["cold_magic"])
	s.fire_magic = int(d["fire_magic"])
	s.poison_magic = int(d["poison_magic"])
	s.ppl_resistance = int(d["ppl_resistance"])
	s.range_upgrader = Blitz.f32(float(d["range_upgrader"]))
	s.speed_upgrader = Blitz.f32(float(d["speed_upgrader"]))
	s.damage_upgrader = Blitz.f32(float(d["damage_upgrader"]))
	s.gold_rate = Blitz.f32(float(d["gold_rate"]))
	s.sell_rate = Blitz.f32(float(d["sell_rate"]))
	g.enemies_created = int(d.get("enemies_created", 0))
	g.ingame_time = Blitz.f32(float(d.get("ingame_time", 0.0)))
	g.show_units_life = bool(d.get("show_units_life", false))
	g.create_enemies_mode = bool(d.get("create_enemies_mode", false))
	g.level_finished = bool(d.get("level_finished", true))
	g.experience = int(d["experience"])
	g.max_location = int(d.get("max_location", g.location))
	g.old_lifes = int(d.get("old_lifes", g.lifes))
	g.extra_lifes = int(d.get("extra_lifes", 0))
	g.units_life_multiplier = Blitz.f32(float(d.get("units_life_multiplier", 1.0)))
	if d.has("missed"):
		var m: Array = d["missed"]
		for i in mini(m.size(), g.missed.size()):
			g.missed[i] = int(m[i])
	if d.get("balloon") != null and bool(g.data.location(g.location)["balloon"]) and not g.survival_mode:
		g.enable_balloon()
		var b: Array = d["balloon"]
		g.balloon.position = Vector3(b[0], b[1], b[2])
	for entry in d.get("towers", []):
		var t := g.build_tower(int(entry["type"]), Vector3(entry["x"], entry["y"], entry["z"]), int(entry["level"]), false)
		t.yaw_degrees = float(entry.get("yaw", t.yaw_degrees))
		t.stopped = bool(entry.get("stopped", false))
		t.spent = 0
		for lv in range(0, t.level + 1):
			t.spent += int(g.data.proto(t.type, lv)["price"])
	# `_fupgradetowerbuildingskills(k, 1)` for the three multiplier skills.
	s.reapply_from_levels(g, SimSkills.Kind.RANGE)
	s.reapply_from_levels(g, SimSkills.Kind.SPEED)
	s.reapply_from_levels(g, SimSkills.Kind.DAMAGE)
