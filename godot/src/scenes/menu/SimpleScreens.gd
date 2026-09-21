## Congratulations, game over, final titles and the score screen: one menu sheet
## with a couple of items (`_fcreatecongratulationsmenu`, `_fcreategameovermenu`,
## `_floadfinaltitres`, `_fcreatehighscoresmenu`).
class_name SimpleScreen
extends ScreenBase

signal choice(name: String)

const CONGR_MODEL := "res://assets/models/Menu/congr.glb"
const GAMEOVER_MODEL := "res://assets/models/Menu/gameover.glb"
const END_MODEL := "res://assets/models/Additional/end.glb"
const SEND_MODEL := "res://assets/models/Menu/Send.glb"
const SENDTD_MODEL := "res://assets/models/Menu/SendTD.glb"
## `_fhandlehighscoressendmenu` drew "Your score is: N" (text 74) at (250,260) scale 1.3 in
## gold once the sheet had animated in; the online table is replaced by the two local
## top-10 tables (campaign / survival) laid out inside the sheet's frame, so the score
## line moves to the top of the frame.
const SCORE_POS := Vector2(250, 177)
const SCORE_SCALE := 1.3
const TABLE_Y := 195.0
const TABLE_COLUMNS := {"campaign": 185.0, "survival": 415.0}
const TABLE_TITLES := {"campaign": "Campaign", "survival": "Survival"}
const TABLE_LINE := 13.0
const TABLE_ROWS := 10

var kind := ""
var any_click_closes := false
var score_menu: MenuScene3D
var score_texts: Array[BlitzText] = []


func setup_congratulations() -> void:
	kind = "congr"
	var m := make_menu(CONGR_MODEL, ["cook"])
	m.animate(SimTower.ANIM_ONESHOT, 0.4)
	AudioManager.play("congr")


func setup_game_over() -> void:
	kind = "gameover"
	var m := make_menu(GAMEOVER_MODEL, ["gorestart", "gotomenu"])
	m.animate(SimTower.ANIM_ONESHOT, 0.4)
	AudioManager.play("gameover")


func setup_final_titles() -> void:
	kind = "end"
	var m := make_menu(END_MODEL, [])
	m.animate(SimTower.ANIM_LOOP, 0.03)
	any_click_closes = true


## `_fcreatehighscoresmenu` sheets: survival `Send.b3d`, campaign `SendTD.b3d`. The online
## submission of the original is gone: the score is recorded locally before this screen
## opens, so the "send" / "don't send" planks are hidden and only survival keeps its
## restart / to menu items; the campaign screen closes on any click.
const SEND_PLANKS := ["hs_send", "hs_dont"]

static func highscore_model(survival: bool) -> String:
	return SEND_MODEL if survival else SENDTD_MODEL


static func highscore_items(survival: bool) -> Array:
	return ["hs_restart", "hs_tomenu"] if survival else []


## Score screen: `score` (negative = just browsing from the main menu) over the local
## tables; the survival sheet keeps restart / to menu, re-centred over the hidden send plank.
func setup_highscores(score: int, survival: bool, tables: Dictionary, texts: Node) -> void:
	kind = "highscores"
	score_menu = make_menu(highscore_model(survival), highscore_items(survival))
	for n in SEND_PLANKS:
		var plank := score_menu.find_node(n)
		if plank != null:
			plank.visible = false
	if survival:
		_center_items(score_menu, highscore_items(survival))
	score_menu.animate(SimTower.ANIM_ONESHOT, 0.6)
	any_click_closes = not survival
	if score >= 0:
		score_texts.append(text(SCORE_POS, "%s%d" % [texts.text(74), score], Hud.COLOR_GOLD, SCORE_SCALE))
	for key in TABLE_COLUMNS:
		var x: float = TABLE_COLUMNS[key]
		score_texts.append(text(Vector2(x, TABLE_Y), TABLE_TITLES[key], Hud.COLOR_EXP_TITLE, 0.8, 6.0))
		var rows: Array = tables.get(key, [])
		var y := TABLE_Y + TABLE_LINE
		for i in mini(rows.size(), TABLE_ROWS):
			var row: Dictionary = rows[i]
			score_texts.append(text(Vector2(x, y), "%2d. %s - %d" % [i + 1, row["name"], int(row["score"])], Hud.COLOR_EXP, 0.7, 6.0))
			y += TABLE_LINE
	for t in score_texts:
		t.visible = false


## The planks sit where the model's rest pose leaves them at the end of the fly-in; shift
## the remaining ones so their group is centred where the three used to be.
func _center_items(m: MenuScene3D, names: Array) -> void:
	m.seek(m.anim_length)
	var sum := 0.0
	var count := 0
	for n in names:
		var node := m.find_node(n)
		if node != null:
			sum += node.position.x
			count += 1
	if count == 0:
		return
	var shift := Vector3(-sum / count, 0, 0)
	for n in names:
		m.offset_item(n, shift)


func _tick() -> void:
	if score_menu != null and not score_menu.animating():
		for t in score_texts:
			t.visible = true


func _on_item(name: String) -> void:
	choice.emit(name)


func _unhandled_input(event: InputEvent) -> void:
	if closed:
		return
	if any_click_closes and ((event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed)):
		choice.emit("close")
		return
	super._unhandled_input(event)
