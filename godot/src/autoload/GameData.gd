## Static game tables exported by tools/game_data.py (res://data/*.json, tools/build_assets.py).
##
## Registered as the `GameData` autoload, but also instantiable directly for headless
## tests: `var data := GameDataScript.new(); data.load_all()`.
extends Node

const DATA_DIR := "res://data"

const TOWER_LAND := 1
const TOWER_MAGIC := 2
const TOWER_PLANT := 3
const TOWER_ICEROCK := 4
const TOWER_FLAME := 5
const TOWER_TYPES := 5
const TOWER_LEVELS := 11
const TOWER_KEYS := {1: "land", 2: "magic", 3: "plant", 4: "freeze", 5: "fire"}

const UNITS_COUNT := 34
const CAMPAIGN_RAIDS := 180
const SURVIVAL_RAIDS := 200
const LOCATIONS := 6

## units[id] for id 1..34 (index 0 unused).
var units: Array = []
## tower_protos[type][level] -> Dictionary (immutable base values from Tower<t>.csv).
var tower_protos: Array = []
## tower_models[type] -> {model, place_model, effect_model, anim_frames, fire1}.
var tower_models: Array = []
## raids[n] for n 1..180 (index 0 unused): {monsters, boss, location, life, speed, armor, gold}.
var raids: Array = []
## survival[n] for n 1..200: {monsters_count, life, speed, armor, gold}.
var survival: Array = []
## location_first_raid[L] for L 1..6.
var location_first_raid: Array = []
## locations[L] for L 1..6.
var locations: Array = []
## paths[L] -> {"frames": int, "pos": PackedVector3Array, "rot": Array[Quaternion]}.
var paths: Array = []
var texts: Dictionary = {}
var hud_layout: Dictionary = {}
var loaded := false


func _ready() -> void:
	if not loaded:
		load_all()


func load_all(dir: String = DATA_DIR) -> void:
	var u: Array = _read_json(dir + "/units.json")
	units = [null]
	units.append_array(u)

	var t: Dictionary = _read_json(dir + "/towers.json")
	tower_protos = [null]
	tower_models = [null]
	for type_id in range(1, TOWER_TYPES + 1):
		var entry: Dictionary = t[TOWER_KEYS[type_id]]
		var levels: Array = entry["levels"]
		for lv in levels:
			lv["max_upgrades"] = entry["max_upgrades"]
			lv["type_id"] = type_id
		tower_protos.append(levels)
		var fire1: Dictionary = entry["fire1"]
		var fire_keys := PackedVector3Array()
		if fire1.has("keys"):
			for k in fire1["keys"]:
				fire_keys.append(Vector3(k[0], k[1], k[2]))
		else:
			var k: Array = fire1["static"]
			fire_keys.append(Vector3(k[0], k[1], k[2]))
		tower_models.append({
			"model": entry["model"], "place_model": entry["place_model"], "effect_model": entry["effect_model"],
			"anim_frames": int(entry["anim_frames"]), "fire1": fire_keys,
		})

	var r: Dictionary = _read_json(dir + "/raids.json")
	raids = [null]
	raids.append_array(r["campaign"])
	survival = [null]
	survival.append_array(r["survival"])
	location_first_raid = [0]
	for L in range(1, LOCATIONS + 1):
		location_first_raid.append(int(r["location_first_raid"][str(L)]))

	var locs: Dictionary = _read_json(dir + "/locations.json")
	locations = [null]
	for L in range(1, LOCATIONS + 1):
		locations.append(locs[str(L)])

	var p: Dictionary = _read_json(dir + "/paths.json")
	paths = [null]
	for L in range(1, LOCATIONS + 1):
		var entry: Dictionary = p[str(L)]
		var pos := PackedVector3Array()
		var rot: Array[Quaternion] = []
		for k in entry["keys"]:
			var v: Array = k["pos"]
			pos.append(Vector3(v[0], v[1], v[2]))
			if k.has("rot_wxyz"):
				var q: Array = k["rot_wxyz"]
				rot.append(Quaternion(q[1], q[2], q[3], q[0]))
		paths.append({"frames": int(entry["anim_frames"]), "pos": pos, "rot": rot})

	texts = _read_json(dir + "/texts.json")
	hud_layout = _read_json(dir + "/hud_layout.json")
	loaded = true


## gametext[k] = line k+1 of Texts.txt.
func text(k: int) -> String:
	var arr: Array = texts["texts"]
	return arr[k] if k < arr.size() else ""


func help(k: int) -> String:
	return texts["helps"][k]


func storyline(location: int) -> String:
	return texts["storyline"][location - 1]


func tutorial_page(page: int) -> String:
	return texts["tutorial"][page]


func unit(id: int) -> Dictionary:
	return units[id]


func proto(type_id: int, level: int) -> Dictionary:
	return tower_protos[type_id][level]


func tower_model(type_id: int) -> Dictionary:
	return tower_models[type_id]


func raid(n: int) -> Dictionary:
	return raids[n]


func location(L: int) -> Dictionary:
	return locations[L]


func last_raid_of_location(L: int) -> int:
	return int(locations[L]["last_raid"])


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open " + path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("invalid JSON in " + path)
	return parsed
