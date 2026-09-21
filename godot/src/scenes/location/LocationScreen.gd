## The in-game screen: LocationView (3D) + Hud + Tutorial + hotkeys (`_fgamelogic`
## key handling, `_fhandlegui`). Owns nothing of the simulation; it forwards intents.
class_name LocationScreen
extends Node

signal menu_requested
signal save_requested(from_button: bool)
signal load_requested

const LocationScene := preload("res://src/scenes/location/Location.tscn")

var game: SimGame
var view: LocationView
var hud: Hud
var tutorial: Tutorial
var debug_overlay: Label = null


func start(g: SimGame, location: int, tutorial_page: int = 0) -> void:
	game = g
	view = LocationScene.instantiate()
	add_child(view)
	view.load_location(game, location)
	hud = Hud.new()
	add_child(hud)
	hud.setup(game, view.camera())
	view.gui_hit_test = hud.is_mouse_over_gui
	tutorial = Tutorial.new(game)
	tutorial.page_changed.connect(_on_tutorial_page)
	tutorial.skills_window_requested.connect(func(): _toggle_skills(true))
	_connect()
	AudioManager.bind(game)
	AudioManager.play_music(game.data.location(location)["music"])
	if tutorial_page > 0:
		tutorial.start(tutorial_page)


func _connect() -> void:
	hud.build_requested.connect(_on_build)
	hud.upgrade_requested.connect(_on_upgrade)
	hud.sell_requested.connect(_on_sell)
	hud.menu_requested.connect(func(): AudioManager.play("click"); menu_requested.emit())
	hud.save_requested.connect(func(): AudioManager.play("click"); save_requested.emit(true))
	hud.load_requested.connect(func(): AudioManager.play("click"); load_requested.emit())
	hud.balloon_requested.connect(func():
		if game.balloon != null:
			view.camera_rig.move_to(game.balloon.position))
	hud.stop_attack_toggled.connect(func():
		if game.selected_tower != null:
			game.selected_tower.stopped = not game.selected_tower.stopped
			hud.refresh_info_panel())
	hud.skills_window_toggled.connect(_toggle_skills)
	hud.skill_operation.connect(_on_skill)
	hud.skills_ok.connect(func(): game.skills.commit(); _toggle_skills(false))
	hud.skills_cancel.connect(func(): game.skills.cancel(game); _toggle_skills(false))
	hud.tutorial_next.connect(func(): AudioManager.play("click"); tutorial.next())
	hud.tutorial_skip_toggled.connect(_on_tutorial_skip_toggled)
	view.tower_placed.connect(func(_t): tutorial.on_tower_placed(); hud.refresh_all())
	view.selection_changed.connect(hud.refresh_info_panel)
	game.tower_upgraded.connect(func(_t): tutorial.on_upgrade_finished(); hud.refresh_info_panel())
	game.location_completed.connect(func(): if view.is_placing(): view.cancel_placing())


func _process(_delta: float) -> void:
	if debug_overlay != null:
		_update_debug()


# ---------------------------------------------------------------- intents

func _on_build(type: int) -> void:
	AudioManager.play("click")
	if type == GameData.TOWER_ICEROCK and game.skills.cold_magic == 0:
		return
	if type == GameData.TOWER_FLAME and game.skills.fire_magic == 0:
		return
	if view.start_placing(type):
		tutorial.on_build_button()


func _on_upgrade() -> void:
	AudioManager.play("click")
	if game.upgrade_selected_tower():
		tutorial.on_upgrade_pressed()
		hud.refresh_info_panel()


func _on_sell() -> void:
	AudioManager.play("click")
	if game.sell_selected_tower():
		tutorial.on_sell()
		hud.refresh_all()


## `_fshowupgradeswindow` / `_fhideupgradeswindow`: pauses the logic and hides enemies.
func _toggle_skills(open: bool) -> void:
	if open and game.location < 2 and not game.survival_mode:
		return
	AudioManager.play("click")
	if view.is_placing():
		view.cancel_placing()
	GameState.skills_window_open = open
	hud.show_skills_window(open)
	view.entities.visible = not open


## `_fshowingamemenu` / `_fhideingamemenu`: enemies hidden, camera frozen, HUD inert.
func set_menu_shown(shown: bool) -> void:
	if view.is_placing():
		view.cancel_placing()
	view.set_enemies_visible(not shown)
	view.camera_rig.scroll_enabled = not shown
	hud.set_input_enabled(not shown)


func _on_skill(id: int, downgrade: bool) -> void:
	id = game.skills.button_id(id, downgrade)
	if downgrade:
		if game.skills.can_downgrade(id):
			game.skills.operate(game, id, true)
			AudioManager.play("click")
	else:
		if game.skills.can_buy(id, game.experience):
			game.skills.operate(game, id, false)
			AudioManager.play("feature")
		elif game.experience < game.skills.price_of(id):
			AudioManager.play("oops2")
	hud.refresh_tower_buttons()
	hud._refresh_skills_panel()


## The checkbox state is persisted either way; only ticking it ends the running tutorial.
func _on_tutorial_skip_toggled(skip: bool) -> void:
	AudioManager.play("check")
	if skip:
		tutorial.disable()
	SaveManager.settings["TutorialDisable"] = 1 if skip else 0
	SaveManager.save_settings()


## `_fhandletutorial` freezes the raid timer while `tutorialmode` is on, including the
## hidden build/upgrade steps, so the flag follows the state rather than the page.
func _on_tutorial_page(page: int) -> void:
	hud.show_tutorial(page)
	GameState.tutorial_open = tutorial.state > 0


# ---------------------------------------------------------------- hotkeys

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or game == null:
		return
	var key := (event as InputEventKey).keycode
	if GameState.ingame_menu_open:
		return
	if GameState.skills_window_open:
		if key == KEY_F2 or key == KEY_E or key == KEY_ESCAPE:
			_toggle_skills(false)
		return
	match key:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_on_build(key - KEY_1 + 1)
		KEY_U, KEY_R:
			_on_upgrade()
		KEY_TAB:
			var t := game.next_tower()
			if t != null:
				view.camera_rig.move_to(t.position)
				hud.refresh_info_panel()
		KEY_SPACE, KEY_ALT:
			game.show_units_life = not game.show_units_life
		KEY_N:
			Ticker.set_normal_speed()
		KEY_M:
			Ticker.set_fast_speed()
		KEY_F2, KEY_E:
			_toggle_skills(true)
		KEY_ESCAPE, KEY_P, KEY_F10:
			menu_requested.emit()
			# The menu just opened must not see this same key press as "back".
			get_viewport().set_input_as_handled()
		KEY_F5:
			save_requested.emit(false)
		KEY_F9:
			load_requested.emit()
		KEY_F1:
			if GameState.debug_mode and game.level_finished and not game.create_enemies_mode:
				game.ingame_time = SimGame.RAID_WAIT_TIME - 0.01
		KEY_F3:
			if GameState.debug_mode:
				_toggle_debug_overlay()
		KEY_F6:
			if GameState.debug_mode:
				# Debug: finish the location instantly.
				game.curlevel = game.last_raid_of_location()
				game.level_finished = false
				var e := game.create_enemy(false, 1)
				game.delete_enemy(e, true, true)
		KEY_F7:
			if GameState.debug_mode:
				game.lifes = 1
				var e := game.create_enemy(false, 1)
				e.path.time = float(e.path.frames)
				game.update_enemies()
		KEY_F4:
			if GameState.debug_mode:
				game.skills.cold_magic = maxi(game.skills.cold_magic, 1)
				game.skills.fire_magic = maxi(game.skills.fire_magic, 1)
				game.experience += 1000
				game.gold += 1000
				hud.refresh_all()


func _toggle_debug_overlay() -> void:
	if debug_overlay != null:
		debug_overlay.queue_free()
		debug_overlay = null
		return
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	debug_overlay = Label.new()
	debug_overlay.position = Vector2(8, 60)
	debug_overlay.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_overlay.add_theme_constant_override("shadow_offset_x", 1)
	debug_overlay.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(debug_overlay)


func _update_debug() -> void:
	var lines := PackedStringArray()
	lines.append("raid %d tick %d wait %.2f m=%.3f enemies %d towers %d bullets %d slider %d (%d ms) %s" % [
		game.curlevel, game.tick_count, game.ingame_time, game.units_life_multiplier, game.enemies.size(),
		game.towers.size(), game.bullets.size(), Ticker.slider, Ticker.period_ms(), "PAUSED" if Ticker.paused else ""])
	for e in game.enemies:
		lines.append("  #%d unit %d life %.0f/%.0f t=%.2f/%d freeze %.0f" % [e.id, e.unit_id, e.life, e.max_life, e.path.time, e.path.frames, e.freeze])
	var arr: Array = view.arrivals.keys()
	arr.sort()
	for id in arr.slice(maxi(arr.size() - 5, 0)):
		lines.append("  arrived #%d at tick %d (spawned %d, %d ticks)" % [id, view.arrivals[id], view.spawn_ticks.get(id, 0), view.arrivals[id] - view.spawn_ticks.get(id, 0)])
	var rig := view.camera_rig
	lines.append("camera pivot %s pos %s bounds %s fov %.2f keep %d canvas %s" % [
		rig.pivot, rig.camera.position, rig.bounds, rig.camera.fov, rig.camera.keep_aspect, DisplayManager.canvas_size])
	lines.append("F1 start raid  F3 overlay  F4 cheat")
	debug_overlay.text = "\n".join(lines)
