## Owns the running SimGame and drives it from the Ticker. Views subscribe to the game's
## signals; UI reads state through `game`.
extends Node

signal game_changed(game: SimGame)

var game: SimGame = null
## While the skills window is open the simulation does not tick (`_fgamelogic`).
var skills_window_open := false
var tutorial_open := false
## `_vgamelogicupdate = 0` while the in-game menu is shown: the clock keeps ticking (menu
## animation, cursor) but the simulation and the camera do not advance.
var ingame_menu_open := false
var debug_mode := false
## `--cheats`: every game created from now on runs with `SimGame.cheats`.
var cheats := false
## Only the location screen simulates; menus tick the Ticker for their animations but
## must not advance the game (the original hides the game and skips `_fgamelogic`).
var sim_active := false


func _ready() -> void:
	Ticker.tick_callback = Callable(self, "_on_tick")


func new_campaign(difficulty: int, seed_value: int = 0) -> SimGame:
	game = SimGame.new(GameData, seed_value)
	game.start_campaign(difficulty)
	_bind(game)
	game_changed.emit(game)
	return game


func new_survival(seed_value: int = 0) -> SimGame:
	game = SimGame.new(GameData, seed_value)
	game.start_survival()
	_bind(game)
	game_changed.emit(game)
	return game


func _bind(g: SimGame) -> void:
	g.cheats = cheats
	g.game_over.connect(func(): Ticker.paused = true)
	g.location_completed.connect(func(): Ticker.paused = true)


func _on_tick() -> void:
	if game == null or skills_window_open or ingame_menu_open or not sim_active:
		return
	if tutorial_open:
		# `_fhandletutorial` zeroes the spawn timer every tick while the tutorial runs.
		game.ingame_time = 0.0
	game.tick()


func resume() -> void:
	Ticker.paused = false


func pause() -> void:
	Ticker.paused = true
