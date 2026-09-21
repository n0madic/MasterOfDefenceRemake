## Tutorial state machine (`_fhandletutorial`, `_fnexttutorialpage`, `_ftutorialstep`,
## `_fdisabletutorial`; docs/09). Pages are Tutorial.txt lines; the HUD shows them.
class_name Tutorial
extends RefCounted

signal page_changed(page: int)
signal finished
## Page 8's "Next" opens the skills window (`_fnexttutorialpage`: `_fshowupgradeswindow`).
signal skills_window_requested

const PAGE_GOLD := 1
const PAGE_TOWERS := 2
const PAGE_HIDDEN_BUILD := 3
const PAGE_UPGRADE := 4
const PAGE_SELL := 5
const PAGE_SPEED := 6
const PAGE_MONSTERS := 7
const PAGE_SKILLS := 8
const PAGE_BALLOON := 9
const PAGE_HELP := 10
const LOCATION1_EXTRA_WAIT := -5.0

var game: SimGame
var state := 0
var visible := false


func _init(g: SimGame) -> void:
	game = g


## `_fhandleingamemenu` "help" sets state 10 unconditionally, so the page opens even
## after "don't show tutorial" was ticked; `TutorialDisable` only filters the
## location's start page (`_tutorial_page_for`).
func start(page: int) -> void:
	if page <= 0:
		return
	state = page
	visible = true
	page_changed.emit(state)


func is_open() -> bool:
	return visible


## Next button (`_fnexttutorialpage(0)`): pages 1-6 advance by one; leaving page 2 hides
## the sheet until a tower is placed and reminds the player of the task.
func next() -> void:
	match state:
		PAGE_TOWERS:
			_hide_for_build()
			game.message.emit(game.data.text(56), SimGame.MSG_WHITE, 2000)
		PAGE_GOLD, PAGE_HIDDEN_BUILD, PAGE_UPGRADE, PAGE_SELL, PAGE_SPEED:
			_show(state + 1)
		PAGE_SKILLS:
			_finish()
			skills_window_requested.emit()
		_:
			_finish()


## `_ftutorialstep(kind, ...)`: gameplay events advance the tutorial.
## `_fbuildtower` passes 1, so no "Your task" message here.
func on_build_button() -> void:
	if state == PAGE_TOWERS:
		_hide_for_build()


func on_tower_placed() -> void:
	if state == PAGE_HIDDEN_BUILD:
		_show(PAGE_UPGRADE)


## `_fhandlegui` upgrade button: step to page 5, then hide until the upgrade finishes.
func on_upgrade_pressed() -> void:
	if state == PAGE_UPGRADE:
		state = PAGE_SELL
		visible = false
		page_changed.emit(0)


## `_fhandletowers`: the finished upgrade shows the sheet again on page 5.
func on_upgrade_finished() -> void:
	if state == PAGE_SELL and not visible:
		visible = true
		page_changed.emit(state)


func on_sell() -> void:
	if state == PAGE_SELL and visible:
		_show(PAGE_SPEED)


func _hide_for_build() -> void:
	state = PAGE_HIDDEN_BUILD
	visible = false
	page_changed.emit(0)


func _show(page: int) -> void:
	state = page
	visible = true
	page_changed.emit(page)


## `_fdisabletutorial`: ending a campaign tutorial page (not Help) on location 1 warns
## that the monsters are coming and gives 5 extra seconds before the first raid.
func _finish() -> void:
	var extra_wait := not game.survival_mode and state < PAGE_HELP and game.location == 1
	visible = false
	state = 0
	page_changed.emit(0)
	if extra_wait:
		game.ingame_time = LOCATION1_EXTRA_WAIT
		game.message.emit(game.data.text(54), SimGame.MSG_WHITE, 3000)
	finished.emit()


## The "don't show" checkbox; gameplay events no longer advance anything because
## `state` is 0 afterwards.
func disable() -> void:
	if visible:
		_finish()
