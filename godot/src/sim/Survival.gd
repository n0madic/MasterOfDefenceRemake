## Survival mode raid generation (`_floaddata` for RaidsData7, docs/08).
class_name SimSurvival
extends RefCounted

const START_GOLD := 250
const START_LIFES := 100
const START_EXPERIENCE := 100
const LOCATION := 2
const MONSTERS_PER_18_RAIDS := 18
const BASE_MONSTERS := 10
const MAX_UNIT_ID := 30
const AIR_ARMOR_FACTOR := 0.8


## Raid `n` of survival: `n \ 18 + 10` monsters of random ids 1..30, stats from the table.
## The original ran off the end of its 200-row table; here the last row's stats repeat.
static func make_raid(data: Node, n: int, rng: Blitz.Random) -> Dictionary:
	var row: Dictionary = data.survival[mini(n, data.survival.size() - 1)]
	var count := Blitz.idiv(n, MONSTERS_PER_18_RAIDS) + BASE_MONSTERS
	var monsters: Array = []
	for i in count:
		monsters.append(rng.rand(1, MAX_UNIT_ID))
	return {
		"raid": n, "monsters": monsters, "boss": false, "location": LOCATION,
		"life": int(row["life"]), "speed": float(row["speed"]), "armor": int(row["armor"]), "gold": int(row["gold"]),
	}
