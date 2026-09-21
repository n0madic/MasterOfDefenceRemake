## Settings (Settings.vdd equivalent) and save files (`Saves/*.sav` equivalents as JSON in
## user://saves/). Save/load of the simulation state lives in SaveGame.gd (M5).
extends Node

const SETTINGS_PATH := "user://settings.json"
const SAVES_DIR := "user://saves"
const DEFAULT_SETTINGS := {
	"Windowed": 2, "VSync": 0, "GammaIntensity": 0, "WideScreen": 0,
	"XRes": 800, "YRes": 600, "WindowX": -1, "WindowY": -1, "WindowMaximized": 0,  # last desktop window
	"ShowHelp": 1, "SoundVol": 0.5, "MusicVol": 0.5, "PlayerName": "",
	"TutorialDisable": 0, "GamedevMode": 0, "DeathMode": 0, "CurrentTitul": 0,
	"MenusOpened": 0, "MasterFlag": 0,
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate()


func _ready() -> void:
	load_settings()
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)


func load_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate()
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in parsed:
				settings[k] = parsed[k]
	AudioManager.set_volumes(float(settings["SoundVol"]), float(settings["MusicVol"]))


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(settings, "\t"))


func save_path(role: String) -> String:
	return "%s/%s.json" % [SAVES_DIR, role]


func save_exists(role: String) -> bool:
	return FileAccess.file_exists(save_path(role))


func write_save(role: String, payload: Dictionary) -> bool:
	var f := FileAccess.open(save_path(role), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload))
	return true


func read_save(role: String) -> Dictionary:
	if not save_exists(role):
		return {}
	var f := FileAccess.open(save_path(role), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func delete_save(role: String) -> void:
	if save_exists(role):
		DirAccess.remove_absolute(save_path(role))


# ---------------------------------------------------------------- local high scores

const HIGHSCORES_PATH := "user://highscores.json"
const HIGHSCORES_KEEP := 10


func read_highscores() -> Dictionary:
	var table := {"campaign": [], "survival": []}
	if FileAccess.file_exists(HIGHSCORES_PATH):
		var f := FileAccess.open(HIGHSCORES_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in table:
				if parsed.has(k):
					table[k] = parsed[k]
	return table


## Insert a score into the campaign/survival table (top-10, sorted descending).
func add_highscore(survival: bool, name: String, score: int) -> void:
	var table := read_highscores()
	var key := "survival" if survival else "campaign"
	var rows: Array = table[key]
	name = name.strip_edges()
	rows.append({"name": name if name != "" else "Player", "score": score, "date": Time.get_date_string_from_system()})
	rows.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	table[key] = rows.slice(0, HIGHSCORES_KEEP)
	var f := FileAccess.open(HIGHSCORES_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(table, "\t"))


## `_fclearlocationsaves`: returning to the menu removes Location1..5 and Automatic.
func clear_location_saves() -> void:
	for L in range(1, 6):
		delete_save("Location%d" % L)
	delete_save("Automatic")
