## Entry point and screen state machine:
## Menu -> Map -> Location -> Congratulations -> Map ... -> Final titles -> High scores,
## Game over -> restart location / menu, Survival -> Location 2 -> High scores.
##
## Command line (after `--`): --location=L --seed=N --demo --demo-tower=T --demo-level=N --shot=PATH:FRAMES --debug
## --cheats --open-skills --tutorial-page=N --safe-area=L,T,R,B --hover=x,y --survival --hide=node,…
## --act=F:close --act=F:pivot:X,Z (debug shortcuts straight into a location).
## --cheats: inhabitants never die, gold and experience are never spent; the run is not scored.
extends Node

const SAVE_AUTOMATIC := "Automatic"
const SAVE_QUICK := "Save"
const SAVE_SURVIVAL := "Survival"

var game: SimGame
var current: Node = null
var ingame_menu: InGameMenu = null
var quitting := false
var loading_screen: LoadingScreen = null  # up while a location is being loaded
var back_frame := -1  # process frame of the last handled Back (see `_on_back`)
var overlay: SimpleScreen = null
var shot_path := ""
var shot_frames := 0
var shot_series: PackedInt32Array = []
var frames := 0
var open_skills := false
var tutorial_page_override := 0  # --tutorial-page=N: open the location on that tutorial page
var hover := Vector2(-1, -1)
var hide_nodes: PackedStringArray = []  # debug: location nodes hidden after loading
var hire_message := ""
## Scripted input for screenshots/tests: --act=FRAME:click:X,Y, --act=FRAME:key:KEYNAME or
## --act=FRAME:close (window close button)
var actions: Array[Dictionary] = []


func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false  # Android Back is handled in `_on_back`
	var args := OS.get_cmdline_user_args()
	var L := 0
	var seed_value := 0
	var demo := false
	var demo_tower := GameData.TOWER_LAND
	var demo_level := 0
	var survival := false
	for a in args:
		if a.begins_with("--location="):
			L = int(a.substr("--location=".length()))
		elif a.begins_with("--seed="):
			seed_value = int(a.substr("--seed=".length()))
		elif a.begins_with("--shot="):
			# PATH:FRAME or PATH:FIRST-LAST/STEP (a series; PATH gets the frame number).
			var parts := a.substr("--shot=".length()).split(":")
			shot_path = parts[0]
			var spec := parts[1] if parts.size() > 1 else "120"
			if "-" in spec:
				var step := int(spec.get_slice("/", 1)) if "/" in spec else 1
				var range_spec := spec.get_slice("/", 0)
				for f in range(int(range_spec.get_slice("-", 0)), int(range_spec.get_slice("-", 1)) + 1, maxi(step, 1)):
					shot_series.append(f)
				shot_frames = shot_series[-1]
			else:
				shot_frames = int(spec)
		elif a == "--demo":
			demo = true
		elif a.begins_with("--demo-tower="):  # tower type 1..5 built by --demo (default Land)
			demo = true
			demo_tower = int(a.substr("--demo-tower=".length()))
		elif a.begins_with("--demo-level="):  # upgrade level of the --demo tower (built free of charge)
			demo = true
			demo_level = int(a.substr("--demo-level=".length()))
		elif a == "--debug":
			GameState.debug_mode = true
		elif a == "--cheats":
			GameState.cheats = true
		elif a == "--open-skills":
			open_skills = true
		elif a.begins_with("--tutorial-page="):
			tutorial_page_override = int(a.substr("--tutorial-page=".length()))
		elif a.begins_with("--safe-area="):
			var m := a.substr("--safe-area=".length()).split(",")
			DisplayManager.safe_area_override = Rect2i(int(m[0]), int(m[1]), int(m[2]), int(m[3]))
		elif a == "--survival":
			survival = true
		elif a.begins_with("--act="):
			var f := a.substr("--act=".length()).split(":")
			actions.append({"frame": int(f[0]), "kind": f[1], "arg": f[2] if f.size() > 2 else ""})
		elif a.begins_with("--hover="):
			var xy := a.substr("--hover=".length()).split(",")
			hover = Vector2(float(xy[0]), float(xy[1]))
		elif a.begins_with("--hide="):
			hide_nodes = a.substr("--hide=".length()).split(",")
	DisplayManager.apply(SaveManager.settings)
	if survival:
		_start_survival()
	elif L > 0 or demo:
		game = GameState.new_campaign(0, seed_value)
		if L > 1:
			game.location = L
			game.enter_location(L)
		await _show_location(maxi(L, 1), demo, 0 if demo else _tutorial_page_for(maxi(L, 1)))
		if demo:
			var keys: PackedVector3Array = game.path["pos"]
			var key := _demo_key(keys, game.data.location(maxi(L, 1))["bounds"])
			if demo_tower == GameData.TOWER_FLAME:
				game.skills.fire_magic = 1
			var t := game.build_tower(demo_tower, key + (Vector3.ZERO if demo_tower == GameData.TOWER_FLAME else Vector3(6, 0, 0)), demo_level, demo_level == 0)
			game.select_tower(t)
			(current as LocationScreen).view.camera_rig.jump_to(key + Vector3(0, 0, CameraRig.LOOK_BACK))
			game.ingame_time = SimGame.RAID_WAIT_TIME - 0.01
			game.show_units_life = true
			(current as LocationScreen).hud.refresh_all()
		if open_skills:
			game.location = 2
			(current as LocationScreen)._toggle_skills(true)
	else:
		_show_menu()


## Demo camera anchor: the path key inside the camera bounds closest to their centre
## (the paths start outside the playable rectangle), so the demo view matches the
## location's normal start view.
func _demo_key(keys: PackedVector3Array, bounds: Dictionary) -> Vector3:
	var rect := Rect2(float(bounds["x_min"]), float(bounds["z_min"]),
		float(bounds["x_max"]) - float(bounds["x_min"]), float(bounds["z_max"]) - float(bounds["z_min"])).grow(-10.0)
	var centre := rect.get_center()
	var best := keys[3]
	var best_dist := INF
	for i in range(3, keys.size()):
		var p := Vector2(keys[i].x, keys[i].z)
		if rect.has_point(p) and p.distance_to(centre) < best_dist:
			best_dist = p.distance_to(centre)
			best = keys[i]
	return best


func _process(_delta: float) -> void:
	frames += 1
	if hover.x >= 0 and frames == 5:
		Input.warp_mouse(hover)
	for act in actions:
		if int(act["frame"]) == frames:
			_perform(act)
	if shot_path != "" and (frames == shot_frames or frames in shot_series):
		var path := shot_path
		if not shot_series.is_empty():
			path = shot_path.get_basename() + "_%04d." % frames + shot_path.get_extension()
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		if frames == shot_frames:
			quit()


## Stops the audio and lets the mixer release its playbacks before the tree is freed;
## the window close button goes through here too (`auto_accept_quit` is off).
func quit() -> void:
	if quitting:
		return
	quitting = true
	DisplayManager.remember_window(SaveManager.settings)
	SaveManager.save_settings()
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


## Android Back: in a location it pauses (opens the in-game menu) and resumes, closing the
## skills window first like Escape does; in the main menu it quits the game. One press
## reaches the tree twice on Android (4.7), so a repeat within the frame is dropped.
func _on_back() -> void:
	var frame := Engine.get_process_frames()
	if frame == back_frame:
		return
	back_frame = frame
	if current is LocationScreen:
		if overlay != null:
			return  # the game-over / congratulations sheet takes its own choice
		if ingame_menu != null:
			_on_ingame_choice("back")
		elif GameState.skills_window_open:
			(current as LocationScreen)._toggle_skills(false)
		else:
			_open_ingame_menu()
	elif current is MainMenu:
		quit()


func _perform(act: Dictionary) -> void:
	match act["kind"]:
		"click":
			var xy: PackedStringArray = str(act["arg"]).split(",")
			var pos := Vector2(float(xy[0]), float(xy[1]))
			Input.warp_mouse(pos)
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = pos
				ev.global_position = pos
				Input.parse_input_event(ev)
		"key":
			for pressed in [true, false]:
				var ev := InputEventKey.new()
				ev.keycode = OS.find_keycode_from_string(str(act["arg"]))
				ev.pressed = pressed
				Input.parse_input_event(ev)
		"pivot":  # --act=F:pivot:X,Z -- scroll the location camera towards (X, Z), clamped to the bounds
			var xz := str(act["arg"]).split(",")
			if current is LocationScreen:
				(current as LocationScreen).view.camera_rig.move_to(Vector3(float(xz[0]), 0.0, float(xz[1]) - CameraRig.LOOK_BACK))
		"close":
			# The window close button (leak hunting: exit from any state).
			_notification(NOTIFICATION_WM_CLOSE_REQUEST)


func _switch(node: Node) -> void:
	_close_current()
	current = node
	add_child(node)
	GameState.sim_active = node is LocationScreen


## Takes the current screen out of the tree at once (its view disconnects from the game),
## so a state restored right after is mirrored only by the next screen.
func _close_current() -> void:
	_close_ingame_menu()
	if overlay != null:
		overlay.close()
		overlay = null
	if current != null:
		if current is MainMenu:
			AudioManager.stop_loops()  # the main menu's own ambience (the campfire embers)
		if current.has_method("close"):
			current.close()
		else:
			remove_child(current)
			current.queue_free()
		current = null


# ---------------------------------------------------------------- menu

func _show_menu() -> void:
	GameState.pause()
	GameState.skills_window_open = false
	GameState.tutorial_open = false
	var menu := MainMenu.new()
	menu.start_requested.connect(_on_menu_start)
	# The "ok" click reaches here synchronously: the browser sees a user gesture.
	menu.video_changed.connect(func(): DisplayManager.apply(SaveManager.settings, true))
	menu.highscores_requested.connect(func(): _show_highscores(-1, false))
	menu.quit_requested.connect(quit)
	_switch(menu)
	_hide_debug_nodes(menu.env_scene)


## `--hide=node,…`: hide named nodes of the loaded scene (location or menu `env`).
func _hide_debug_nodes(root: Node) -> void:
	for n in hide_nodes:
		var node := root.find_child(n, true, false)
		if node != null:
			node.visible = false


func _on_menu_start(mode: String) -> void:
	match mode:
		"new":
			_start_campaign(0)
		"hard":
			_start_campaign(1)
		"insane":
			_start_campaign(2)
		"continue":
			_continue_campaign()
		"hardcore":
			_start_survival()


func _start_campaign(difficulty: int) -> void:
	SaveManager.settings["CurrentTitul"] = difficulty
	SaveManager.save_settings()
	game = GameState.new_campaign(difficulty)
	hire_message = ""
	_show_map()


func _continue_campaign() -> void:
	var payload := SaveManager.read_save(SAVE_AUTOMATIC)
	if payload.is_empty():
		_show_menu()
		return
	game = GameState.new_campaign(int(payload.get("titul", 0)))
	SaveGame.restore(game, payload)
	await _show_location(game.location, false)


func _start_survival() -> void:
	game = GameState.new_survival()
	await _show_location(SimSurvival.LOCATION, false)


# ---------------------------------------------------------------- map / location

## Enters `game.location` (clears towers, resets `curlevel`) and snapshots the save right
## away, so quitting from the map screen without pressing "Continue" never loses a
## completed location: the save used to be written only on "Continue" (`_on_map_continue`),
## leaving the disk with nothing newer than the last raid of the location just finished.
func _show_map() -> void:
	game.enter_location(game.location)
	var payload := SaveGame.serialize(game)
	SaveManager.write_save("Location%d" % game.location, payload)
	SaveManager.write_save(SAVE_AUTOMATIC, payload)
	GameState.pause()
	var map := MapScreen.new()
	_switch(map)
	map.setup(game, hire_message)
	map.continue_requested.connect(_on_map_continue)


## `_fhandlemapmenu` "continue": the location was already entered and saved by `_show_map`,
## so this only loads the screen and starts the tutorial.
func _on_map_continue() -> void:
	var L := game.location
	await _show_location(L, false, _tutorial_page_for(L))
	if hire_message != "":
		game.message.emit(hire_message, SimGame.MSG_WHITE, 5000)


func _tutorial_page_for(L: int) -> int:
	if tutorial_page_override > 0:
		return tutorial_page_override
	if int(SaveManager.settings["TutorialDisable"]) != 0:
		return 0
	return int(game.data.location(L)["tutorial_page"])


## Only the map's "continue" (`_fhandlemapmenu`) starts a tutorial page; survival,
## "continue game" and restarts enter the location silently. The loading sheet goes up
## first and reaches the screen before the load stalls the frame (a coroutine: callers
## that continue with the location `await` it; headless runs it straight through).
func _show_location(L: int, demo: bool, tutorial_page: int = 0) -> void:
	if loading_screen != null:
		return  # a location is on its way already
	# A restart / quick load can replace a screen with a tutorial page or the skills
	# window open; the new screen starts with neither, so the flags must not survive.
	GameState.skills_window_open = false
	GameState.tutorial_open = false
	GameState.sim_active = false
	_close_current()
	loading_screen = LoadingScreen.new()
	add_child(loading_screen)
	if not DisplayManager.headless():
		await get_tree().process_frame  # the frame that carries the sheet is drawn in between
	var screen := LocationScreen.new()
	_switch(screen)
	screen.start(game, L, tutorial_page)
	_hide_debug_nodes(screen.view.scene_root)
	screen.menu_requested.connect(_open_ingame_menu)
	screen.save_requested.connect(_quick_save)
	screen.load_requested.connect(_quick_load)
	if not game.location_completed.is_connected(_on_location_completed):
		game.location_completed.connect(_on_location_completed)
		game.game_over.connect(_on_game_over)
		game.raid_finished.connect(_on_raid_finished)
	GameState.resume()
	loading_screen.finish()
	loading_screen = null


func _on_raid_finished(_n: int) -> void:
	# Autosave after a repulsed raid when nothing is alive (campaign only). The last monster
	# of a raid can take the last life in the same tick (`game_over` arrives first): the
	# original still wrote `Automatic.sav` there, which "Continue" then loaded with no lives.
	if game.is_game_over:
		return
	if not game.survival_mode and not game.create_enemies_mode and game.enemies_amount == 0:
		SaveManager.write_save(SAVE_AUTOMATIC, SaveGame.serialize(game))


func _on_location_completed() -> void:
	# The last monster of the last raid can take the last life in the same tick: the
	# original stops the game logic at the game-over sheet, so the congratulations never
	# appear (the signals arrive game_over first).
	if overlay != null:
		return
	var screen := _overlay_screen()
	screen.setup_congratulations()
	screen.choice.connect(func(_n): _after_congratulations())


func _after_congratulations() -> void:
	var gold_before := game.gold
	var extra_before := game.extra_lifes
	var finished := game.next_location()
	if finished:
		_finish_campaign()
		return
	var employed := game.extra_lifes - extra_before
	hire_message = ""
	if employed > 0:
		hire_message = "%s %d %s %d %s" % [game.data.text(83), gold_before - 100, game.data.text(84), employed, game.data.text(85)]
	# `_show_map` enters the new location (clears old towers/curlevel) and autosaves
	# immediately, so the completed location is never lost if the player quits from the map.
	_show_map()


## `_floadfinaltitres`: titles, then difficulty unlocks, then the score screen.
func _finish_campaign() -> void:
	var s: Dictionary = SaveManager.settings
	var titul := game.titul
	if titul < 2:
		s["CurrentTitul"] = titul + 1
	s["MenusOpened"] = maxi(int(s["MenusOpened"]), titul + 1)
	if titul == 2:
		s["MasterFlag"] = 1
	SaveManager.save_settings()
	SaveManager.clear_location_saves()
	var screen := SimpleScreen.new()
	_switch(screen)
	screen.setup_final_titles()
	screen.choice.connect(func(_n): _show_highscores(game.lifes, false))


func _on_game_over() -> void:
	if overlay != null:
		return
	if game.survival_mode:
		_show_highscores(game.curlevel, true)
		return
	var screen := _overlay_screen()
	screen.setup_game_over()
	screen.choice.connect(_on_game_over_choice)


## `_fcreategameovermenu` / `_fcreatecongratulationsmenu`: the sheet hangs on the location
## camera over the frozen location (`_vgamelogicupdate = 0`, enemies stay visible); the
## location is unloaded only by the choice made on it.
func _overlay_screen() -> SimpleScreen:
	var loc := current as LocationScreen
	var screen := SimpleScreen.new()
	screen.overlay_camera = loc.view.camera_rig.camera
	GameState.ingame_menu_open = true
	loc.view.camera_rig.scroll_enabled = false
	loc.hud.set_input_enabled(false)
	overlay = screen
	add_child(screen)
	return screen


func _on_game_over_choice(name: String) -> void:
	match name:
		"gorestart":
			_restart_location()
		"gotomenu":
			SaveManager.clear_location_saves()
			_show_menu()


## `_frestartlocation` + load of `Location<L>` (the snapshot taken on entering it).
func _restart_location() -> void:
	var L := game.location
	_close_current()
	game.restart_location()
	var payload := SaveManager.read_save("Location%d" % L)
	if not payload.is_empty():
		SaveGame.restore(game, payload)
	game.units_life_multiplier = 1.0
	await _show_location(L, false, 0)


## Records the score locally (the original asked whether to submit it online) and shows
## the tables; `score < 0` only browses them. After survival the sheet hangs on the
## location camera like the game-over sheet (`_fcreatehighscoresmenu`: `_vgamelogicupdate = 0`).
func _show_highscores(score: int, survival: bool) -> void:
	if score >= 0 and not GameState.cheats:
		SaveManager.add_highscore(survival, str(SaveManager.settings["PlayerName"]), score)
	var screen: SimpleScreen
	if survival and current is LocationScreen:
		screen = _overlay_screen()
	else:
		screen = SimpleScreen.new()
		_switch(screen)
	screen.setup_highscores(score, survival, SaveManager.read_highscores(), GameData)
	screen.choice.connect(func(name): _on_highscores_choice(name))


func _on_highscores_choice(name: String) -> void:
	if name == "hs_restart":
		_start_survival()
	else:
		_show_menu()


# ---------------------------------------------------------------- in-game menu & saves

func _open_ingame_menu() -> void:
	if ingame_menu != null or not (current is LocationScreen):
		return
	var screen := current as LocationScreen
	GameState.ingame_menu_open = true
	screen.set_menu_shown(true)
	ingame_menu = InGameMenu.new()
	add_child(ingame_menu)
	ingame_menu.open(screen.view.camera())
	ingame_menu.choice.connect(_on_ingame_choice)


func _close_ingame_menu() -> void:
	if ingame_menu != null:
		ingame_menu.close()
		ingame_menu = null
	GameState.ingame_menu_open = false
	if current is LocationScreen:
		(current as LocationScreen).set_menu_shown(false)


func _on_ingame_choice(name: String) -> void:
	match name:
		"back":
			_close_ingame_menu()
		"restart":
			if game.survival_mode:
				_start_survival()
			else:
				_restart_location()
		"tomenu":
			# `_fhandleingamemenu`: survival ends at the highscores screen (`_fcreatehighscoresmenu`),
			# the campaign autosaves between raids and returns to the main menu.
			if game.survival_mode:
				_close_ingame_menu()
				_show_highscores(game.curlevel, true)
			else:
				# Only the autosave: `_fclearlocationsaves` runs on the game-over "to menu"
				# and after the final titles, so "continue" stays available here.
				if not game.create_enemies_mode and game.enemies_amount == 0:
					SaveManager.write_save(SAVE_AUTOMATIC, SaveGame.serialize(game))
				_show_menu()
		"exit":
			if not game.survival_mode and game.enemies_amount == 0:
				SaveManager.write_save(SAVE_AUTOMATIC, SaveGame.serialize(game))
			quit()
		"help":
			_close_ingame_menu()
			(current as LocationScreen).tutorial.start(Tutorial.PAGE_HELP)


## Save button (`_fhandlegui`, shown only between raids by `_fhandlelevels`) and F5
## (`_fmainloop`: campaign only, difficulties 0-1, no enemies alive). A survival save
## taken mid-raid would restore `level_finished = false` with no enemies and never start
## another raid, so the button's rule guards both paths.
func _quick_save(from_button: bool) -> void:
	if game.titul == 2 or not game.level_finished or game.create_enemies_mode:
		return
	if game.survival_mode:
		if not from_button:
			return
		SaveManager.write_save(SAVE_SURVIVAL, SaveGame.serialize(game))
	else:
		if game.enemies_amount > 0:
			return
		SaveManager.write_save(SAVE_QUICK, SaveGame.serialize(game))
	game.message.emit(game.data.text(58), SimGame.MSG_WHITE, 1500)


func _quick_load() -> void:
	var role := SAVE_SURVIVAL if game.survival_mode else SAVE_QUICK
	if game.titul == 2 and not game.survival_mode:
		return
	var payload := SaveManager.read_save(role)
	if payload.is_empty():
		return
	_close_current()
	game.restart_location()
	SaveGame.restore(game, payload)
	await _show_location(game.location, false, 0)
	game.message.emit(game.data.text(59), SimGame.MSG_WHITE, 1500)
