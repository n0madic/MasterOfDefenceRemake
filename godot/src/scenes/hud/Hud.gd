## In-game HUD (docs/09, docs/13): the 3D panel `Env.glb` and portrait `faces.glb` are
## attached to the camera exactly like the original; buttons, texts, tooltips, messages,
## the time slider and the skills window are 2D controls in the 800x600 canvas. In the wide
## screen mode every floating group (planks, icons, widgets, messages, tutorial pointers)
## keeps its corner or edge of the window while the box stays centred (see HudLayout).
class_name Hud
extends CanvasLayer

signal build_requested(type: int)
signal upgrade_requested
signal sell_requested
signal menu_requested
signal save_requested
signal load_requested
signal balloon_requested
signal stop_attack_toggled
signal skills_window_toggled(open: bool)
signal skill_operation(id: int, downgrade: bool)
signal skills_ok
signal skills_cancel
signal tutorial_next
signal tutorial_skip_toggled(skip: bool)

const ENV_MODEL := "res://assets/models/Env.glb"
const FACES_MODEL := "res://assets/models/faces.glb"
const TUTORIAL_MODEL := "res://assets/models/tutorial.glb"
const PANEL_OFFSET := Vector3(0, 0, -10)  # Blitz MoveEntity(env, 0, 0, 10)
const WORKER_PORTRAIT_FRAME := 30.99
const COLOR_GOLD := Color(1.0, 203.0 / 255.0, 0.0)
const COLOR_LIFES := Color(110.0 / 255.0, 200.0 / 255.0, 230.0 / 255.0)
const COLOR_EXTRA := Color(180.0 / 255.0, 227.0 / 255.0, 242.0 / 255.0)
const COLOR_EXP := Color(247.0 / 255.0, 232.0 / 255.0, 172.0 / 255.0)
const COLOR_HELP := Color(247.0 / 255.0, 232.0 / 255.0, 171.0 / 255.0)
const COLOR_EXP_TITLE := Color(0.0, 200.0 / 255.0, 120.0 / 255.0)
const COLOR_STORY := Color(0.0, 1.0, 130.0 / 255.0)
const COLOR_FIRE6 := Color(1.0, 207.0 / 255.0, 115.0 / 255.0)
const MSG_COLORS := {1: Color.WHITE, 2: Color.RED, 3: COLOR_GOLD, 4: Color.GREEN}
const MESSAGE_X := 20
const MESSAGE_Y := 510
const MESSAGE_STEP := 16
const MESSAGE_FADE := 0.01
const GOLD_POPUP_RISE := 0.5
const GOLD_POPUP_MS := 100
const TIP_WIDTH := 175.0
const TIP_LINE := 12.8
const TIP_MARGIN := 6.4
const HELP_POS := Vector2(15, 120)
const HELP_WIDTH := 185.0
const SLIDER_RECT := Rect2(400, 500, 190, 20)
const RESET_MARK := Vector2(432 + 8, 477 + 12)
const SLIDER_EDGE := 7
const PROGRESS_RECT := Rect2(648, 512, 152, 32)
const PROGRESS_CORNER := 8
const PROGRESS_EDGE := 8.0
const PROGRESS_TRIM := 3.0
const PROGRESS_PIECE := 64.0
const TOWER_BUTTON_Y := 530
const TOWER_BUTTON_X := [0, 5, 70, 135, 200, 265]
const UPGRADE_SLOTS := [200, 265, 330]  # Icerock / Flame / Balloon, packed left
const SKILL_ROWS := [
	# [id, y button, y text, tip+, tip-, help index]
	[SimSkills.Id.COLD, 105, 113, 61, 96, 0],
	[SimSkills.Id.FIRE, 135, 141, 62, 97, 1],
	[SimSkills.Id.POISON, 165, 172, 63, 98, 2],
	[SimSkills.Id.SPEED, 202, 212, 36, 94, 3],
	[SimSkills.Id.RANGE, 233, 240, 37, 95, 4],
	[SimSkills.Id.DAMAGE, 263, 266, 35, 93, 5],
	[SimSkills.Id.SELL, 293, 295, 34, 92, 6],
	[SimSkills.Id.RESISTANCE, 328, 335, 64, 99, 7],
	[SimSkills.Id.GOLD, 360, 365, 32, 91, 8],
]
const SKILL_PLUS_X := 520
const SKILL_MINUS_X := 550
const SKILL_TEXT_X := 470
const SKILL_BUTTON := Vector2(30, 30)

var game: SimGame
var data: Node
var root: Control
var anchor_roots: Dictionary = {}  # HudLayout anchor -> Control holding the widgets of that corner / edge
var layout := HudLayout.new()
var panel3d: Node3D
var faces: Node3D
var faces_player: AnimationPlayer
var faces_maps: Array[Dictionary] = []
var updates_mesh: Node3D
var tutorial3d: Node3D
var tutorial_player: AnimationPlayer
var buttons: Dictionary = {}
var tower_buttons: Dictionary = {}
var texts: Dictionary = {}
var tooltip: Control
var tooltip_text: BlitzText
var tooltip_frame: NinePatchRect
var slider: HSlider
var slider_knob: TextureRect
var progress_fill: Control
var progress: Control
var info_text: BlitzText
var messages: Array[Dictionary] = []
var messages_node: Control
var gold_popups: Array[Dictionary] = []
var popups_node: Control
var skills_panel: Control
var skill_buttons: Dictionary = {}
var skill_texts: Dictionary = {}
var skills_exp_text: BlitzText
var help_text: BlitzText
var help_frame: NinePatchRect
var tutorial_panel: Control
var tutorial_text: BlitzText
var tutorial_alpha := PackedFloat32Array()
var tutorial_alpha_inc := PackedFloat32Array()
var tutorial_checkbox: TextureButton
var tutorial_skip := false
var show_help := true
var camera: Camera3D
var rng := RandomNumberGenerator.new()
var hovered_tip := ""
## Widgets a tooltip can belong to (and that swallow map clicks), rebuilt when the skills
## window opens or closes.
var tip_candidates: Array = []
var tip_candidates_with_skills := false
var reset_mark: Control
## Widgets without a tooltip that still swallow map clicks (skills ok / cancel, tutorial).
var click_widgets: Array[Control] = []
## False while the in-game menu is shown: the widgets stay drawn but generate no events.
var input_enabled := true
## The tutorial sheet was drawn once this session (see `_warm_panel_models`); its material
## variants are kept so the compiled program outlives this HUD (restart, quick load).
static var _warmed := false
static var _pinned_materials: Array[Material] = []


func _ready() -> void:
	layer = 10
	DisplayManager.register_layer(self)
	root = Control.new()
	root.name = "Root"
	root.size = DisplayManager.BOX  # the box, not the canvas: the layer is centred in wide mode
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	DisplayManager.layout_changed.connect(_apply_layout)
	_build_buttons()
	_build_texts()
	_build_slider()
	_build_progress()
	_build_messages()
	_build_skills_panel()
	_build_tutorial_panel()
	_build_tooltip()


## The clock is followed only while in the tree (see `_exit_tree`).
func _enter_tree() -> void:
	Ticker.frame_ticked.connect(_on_frame_ticked)


## A HUD taken out of the tree (quick load, restart) stops following the clock at once.
func _exit_tree() -> void:
	if Ticker.frame_ticked.is_connected(_on_frame_ticked):
		Ticker.frame_ticked.disconnect(_on_frame_ticked)


## Attach the 3D panel to `cam` and bind the simulation.
func setup(g: SimGame, cam: Camera3D) -> void:
	game = g
	data = g.data
	camera = cam
	if panel3d != null:
		panel3d.queue_free()
	panel3d = Node3D.new()
	panel3d.name = "HudPanel3D"
	cam.add_child(panel3d)
	panel3d.position = PANEL_OFFSET
	var env: Node3D = ModelWarmup.pinned_scene(ENV_MODEL).instantiate()
	panel3d.add_child(env)
	BlitzAnimator.hide_helpers(env)
	layout = HudLayout.new()
	layout.register(env, HudLayout.ENV_RULES, panel3d)
	_order_panel_quads(env)
	updates_mesh = env.find_child("updates", true, false)
	var window_mesh: Node3D = env.find_child("window", true, false)
	if window_mesh != null:
		window_mesh.visible = false
	if updates_mesh != null:
		updates_mesh.visible = false
	faces = ModelWarmup.pinned_scene(FACES_MODEL).instantiate()
	panel3d.add_child(faces)
	BlitzAnimator.hide_helpers(faces)
	layout.register(faces, HudLayout.FACES_RULES, panel3d)
	faces_player = BlitzAnimator.find_player(faces)
	faces_maps = BlitzAnimator.setup_animmaps(faces)
	faces.visible = false
	tutorial3d = ModelWarmup.pinned_scene(TUTORIAL_MODEL).instantiate()
	panel3d.add_child(tutorial3d)
	BlitzAnimator.hide_helpers(tutorial3d)
	layout.register(tutorial3d, HudLayout.TUTORIAL_RULES, panel3d)
	var tutorial_mats := _draw_on_top(tutorial3d)
	tutorial_player = BlitzAnimator.find_player(tutorial3d)
	tutorial3d.visible = false
	game.message.connect(add_message)
	game.gold_popup.connect(add_gold_popup)
	refresh_tower_buttons()
	refresh_all()
	_apply_layout()
	_warm_panel_models(tutorial_mats)


## The tutorial sheet is drawn with its own material variant (`_draw_on_top`) that the
## location's ModelWarmup cannot reproduce: once per session it stays visible for the first
## frame -- under the warm-up's overlay -- so its program compiles now instead of at the
## first tutorial page. (The portrait has plain materials; the warm-up draws it itself.)
## `mats` are pinned: the program lives as long as a material with its variant does.
func _warm_panel_models(mats: Array[Material]) -> void:
	if _warmed or DisplayManager.headless():
		return
	_warmed = true
	_pinned_materials.append_array(mats)
	tutorial3d.visible = true
	_unwarm_panel_models(self)


## Waits on the script, not on the HUD: a quick load can free it while the wait is pending.
static func _unwarm_panel_models(hud: Hud) -> void:
	await RenderingServer.frame_post_draw
	if not is_instance_valid(hud) or hud.game == null:
		return
	hud.tutorial3d.visible = hud.tutorial_panel.visible


# ---------------------------------------------------------------- wide layout

## Root of the 2D widgets anchored to a corner / edge (a HudLayout anchor); created on demand.
func _anchor_root(anchor: Vector2) -> Control:
	if anchor == HudLayout.CENTRE:
		return root
	if not anchor_roots.has(anchor):
		var c := Control.new()
		c.name = "Anchor%d%d" % [int(anchor.x) + 1, int(anchor.y) + 1]
		c.size = DisplayManager.BOX
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(c)
		anchor_roots[anchor] = c
	return anchor_roots[anchor]


## Move every anchored group by its share of the box offset, inside the phone's safe area
## (the box itself stays centred).
func _apply_layout() -> void:
	for anchor: Vector2 in anchor_roots:
		(anchor_roots[anchor] as Control).position = DisplayManager.anchor_shift(anchor)
	layout.apply(DisplayManager.ui_offset, DisplayManager.safe_min, DisplayManager.safe_max)


# ---------------------------------------------------------------- construction

## The panel quads are translucent and share one view depth (`reset` over `infopanel`,
## the icons over their frames), so Godot's depth sort flips between frames while the
## camera moves; draw them in file order instead (later nodes on top), which is the
## stable order the original's list gives them. The imported depth pre-pass would still
## z-fight the coplanar quads, so they are drawn as plain alpha without depth writes.
func _order_panel_quads(env: Node3D) -> void:
	var i := 0
	for mi in env.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).get_surface_override_material_count():
			var m := BlitzAnimator.owned_material(mi, s) as BaseMaterial3D
			m.render_priority = i
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		i += 1


## `EntityOrder(tutorial, -400)`: the sheet and its pointers are drawn after the panel and
## without the z-buffer (the pointer feet reach under `infopanel`, which sits nearer the camera).
## Returns the material copies (a shader variant of their own, see `_warm_panel_models`).
func _draw_on_top(model: Node3D) -> Array[Material]:
	var out: Array[Material] = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).get_surface_override_material_count():
			var m := BlitzAnimator.owned_material(mi, s) as BaseMaterial3D
			m.render_priority = RenderingServer.MATERIAL_RENDER_PRIORITY_MAX
			m.no_depth_test = true
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			out.append(m)
	return out


func _button(name: String, style: int, icon: int, pos: Vector2, size: Vector2, tip_index: int, anchor := HudLayout.CENTRE) -> TextureButton:
	var b := GuiAtlas.make_button(style, icon, size)
	b.name = name
	b.position = pos
	b.set_meta("tip", tip_index)
	_anchor_root(anchor).add_child(b)
	buttons[name] = b
	return b


func _build_buttons() -> void:
	var big := Vector2(64, 64)
	for type in range(1, 6):
		var b := _button("tower%d" % type, GuiAtlas.STYLE_BIG, type, Vector2(TOWER_BUTTON_X[type], TOWER_BUTTON_Y), big, 20 + type, HudLayout.BOTTOM_LEFT)
		b.pressed.connect(func(): build_requested.emit(type))
		tower_buttons[type] = b
	var balloon := _button("balloon", GuiAtlas.STYLE_BIG, 8, Vector2(330, TOWER_BUTTON_Y), big, 89, HudLayout.BOTTOM_LEFT)
	balloon.pressed.connect(func(): balloon_requested.emit())
	balloon.visible = false
	_button("upgrade", GuiAtlas.STYLE_BIG, 6, Vector2(664, TOWER_BUTTON_Y), big, 26, HudLayout.BOTTOM_RIGHT).pressed.connect(func(): upgrade_requested.emit())
	_button("sell", GuiAtlas.STYLE_BIG, 7, Vector2(737, TOWER_BUTTON_Y), big, 29, HudLayout.BOTTOM_RIGHT).pressed.connect(func(): sell_requested.emit())
	var small := Vector2(32, 32)
	_button("menu", GuiAtlas.STYLE_SMALL2, 1, Vector2(278, -3), small, 67, HudLayout.TOP_CENTRE).pressed.connect(func(): menu_requested.emit())
	_button("save", GuiAtlas.STYLE_SMALL2, 3, Vector2(310, -3), small, 65, HudLayout.TOP_CENTRE).pressed.connect(func(): save_requested.emit())
	_button("load", GuiAtlas.STYLE_SMALL2, 0, Vector2(450, -3), small, 66, HudLayout.TOP_CENTRE).pressed.connect(func(): load_requested.emit())
	_button("health", GuiAtlas.STYLE_SMALL1, 10, Vector2(483, -3), small, 79, HudLayout.TOP_CENTRE).pressed.connect(func():
		game.show_units_life = not game.show_units_life)
	_button("skills", GuiAtlas.STYLE_SMALL2, 2, Vector2(600, 480), Vector2(35, 35), 68, HudLayout.BOTTOM_CENTRE).pressed.connect(func():
		skills_window_toggled.emit(not skills_panel.visible))
	var stop := _button("stop", GuiAtlas.STYLE_SMALL2, 12, Vector2(590, 520), Vector2(30, 30), 100, HudLayout.BOTTOM_CENTRE)
	stop.pressed.connect(func(): stop_attack_toggled.emit())
	stop.visible = false


func _text(name: String, pos: Vector2, color: Color, anchor := HudLayout.CENTRE, scale_value: float = 1.0, spacing_value: float = 5.0, cx := false, cy := false) -> BlitzText:
	var t := BlitzText.new()
	t.name = name
	t.position = pos
	t.color = color
	t.text_scale = scale_value
	t.spacing = spacing_value
	t.center_x = cx
	t.center_y = cy
	_anchor_root(anchor).add_child(t)
	texts[name] = t
	return t


func _build_texts() -> void:
	_text("gold", Vector2(50, 9), COLOR_GOLD, HudLayout.TOP_LEFT, 1.0, 5.0, true, true)
	_text("lifes", Vector2(760, 40), COLOR_LIFES, HudLayout.TOP_RIGHT, 1.0, 5.0, true, true)
	_text("extra", Vector2(765, 55), COLOR_EXTRA, HudLayout.TOP_RIGHT, 0.9, 4.0)
	_text("exp", Vector2(15, 41), COLOR_EXP, HudLayout.TOP_LEFT, 1.0, 5.0, true, true)
	_text("raid", Vector2(330, 5), Color.WHITE, HudLayout.TOP_CENTRE)
	info_text = _text("info", Vector2(400, 500), Color.WHITE, HudLayout.BOTTOM_CENTRE)


func _build_slider() -> void:
	var track := NinePatchRect.new()
	track.texture = GuiAtlas.slider_track()
	track.position = SLIDER_RECT.position
	track.size = SLIDER_RECT.size
	track.patch_margin_left = SLIDER_EDGE
	track.patch_margin_right = SLIDER_EDGE
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_root(HudLayout.BOTTOM_CENTRE).add_child(track)
	slider = HSlider.new()
	slider.position = SLIDER_RECT.position
	slider.size = SLIDER_RECT.size
	slider.min_value = 0
	slider.max_value = Ticker.SLIDER_MAX
	slider.step = 1
	slider.value = Ticker.slider
	slider.modulate.a = 0.0  # invisible, only handles input; the knob is drawn separately
	slider.value_changed.connect(func(v): Ticker.slider = int(v))
	slider.set_meta("tip", 31)
	_anchor_root(HudLayout.BOTTOM_CENTRE).add_child(slider)
	slider_knob = TextureRect.new()
	slider_knob.texture = GuiAtlas.slider_knob()
	slider_knob.size = Vector2(32, 32)
	slider_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_root(HudLayout.BOTTOM_CENTRE).add_child(slider_knob)
	Ticker.speed_changed.connect(func(_fps): slider.set_value_no_signal(Ticker.slider))
	# `_fhandlegui`: a click within 10 px left/right, 10 px above / 5 px below the projected
	# `reset` marker returns the slider to normal speed.
	var reset := Control.new()
	reset.name = "ResetMark"
	reset.position = RESET_MARK - Vector2(10, 10)
	reset.size = Vector2(20, 15)
	reset.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Ticker.slider = Ticker.DEFAULT_SLIDER)
	_anchor_root(HudLayout.BOTTOM_CENTRE).add_child(reset)
	reset_mark = reset


## `EProgressBar(648, 512, 152x32, 0..100, "")` above the Upgrade button: the frame is a
## 9-slice of the 64x32 block (corner 8, always shown), the fill starts 8 px in and 3 px
## down and is laid out in 64 px wide pieces of the fill strip (`_fedrawwidget` 0x1006).
func _build_progress() -> void:
	progress = Control.new()
	progress.position = PROGRESS_RECT.position
	progress.size = PROGRESS_RECT.size
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_root(HudLayout.BOTTOM_RIGHT).add_child(progress)
	var frame := NinePatchRect.new()
	frame.texture = GuiAtlas.progress_frame()
	frame.size = PROGRESS_RECT.size
	for side in ["left", "right", "top", "bottom"]:
		frame.set("patch_margin_" + side, PROGRESS_CORNER)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_child(frame)
	progress_fill = Control.new()
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_child(progress_fill)
	_set_progress(0.0)


## Fill width `(w - 2*edge) * value / 100` as up to three 64 px pieces of the strip.
func _set_progress(value: float) -> void:
	for c in progress_fill.get_children():
		c.free()
	var remaining := (PROGRESS_RECT.size.x - 2 * PROGRESS_EDGE) * clampf(value, 0.0, 100.0) / 100.0
	var x := PROGRESS_EDGE
	while remaining > 0.0:
		var piece := minf(remaining, PROGRESS_PIECE)
		var tr := TextureRect.new()
		var tex := GuiAtlas.progress_fill()
		tex.region.size.x = piece
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2(x, PROGRESS_TRIM)
		tr.size = Vector2(piece, PROGRESS_RECT.size.y - 2 * PROGRESS_TRIM)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress_fill.add_child(tr)
		x += piece
		remaining -= piece


func _build_messages() -> void:
	messages_node = Control.new()
	messages_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_root(HudLayout.BOTTOM_LEFT).add_child(messages_node)
	popups_node = Control.new()
	popups_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(popups_node)


func _build_tooltip() -> void:
	tooltip = Control.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	tooltip.z_index = 100
	root.add_child(tooltip)
	tooltip_frame = NinePatchRect.new()
	tooltip_frame.texture = GuiAtlas.frame()
	tooltip_frame.patch_margin_left = 6
	tooltip_frame.patch_margin_right = 6
	tooltip_frame.patch_margin_top = 6
	tooltip_frame.patch_margin_bottom = 6
	tooltip_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tooltip_frame)
	tooltip_text = BlitzText.new()
	tooltip_text.text_scale = 0.8
	tooltip_text.spacing = 7.0
	tooltip.add_child(tooltip_text)


func _build_skills_panel() -> void:
	skills_panel = Control.new()
	skills_panel.name = "Skills"
	skills_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	skills_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skills_panel.visible = false
	root.add_child(skills_panel)
	skills_exp_text = BlitzText.new()
	skills_exp_text.position = Vector2(240, 62)
	skills_exp_text.color = COLOR_EXP_TITLE
	skills_panel.add_child(skills_exp_text)
	for row in SKILL_ROWS:
		var id: int = row[0]
		var plus := GuiAtlas.make_button(GuiAtlas.STYLE_SMALL1, 1, SKILL_BUTTON)
		plus.position = Vector2(SKILL_PLUS_X, row[1])
		plus.set_meta("skill", id)
		plus.set_meta("downgrade", false)
		plus.set_meta("skill_help", row[5])
		plus.pressed.connect(func(): skill_operation.emit(id, false))
		skills_panel.add_child(plus)
		var minus := GuiAtlas.make_button(GuiAtlas.STYLE_SMALL2, 11, SKILL_BUTTON)
		minus.position = Vector2(SKILL_MINUS_X, row[1])
		minus.set_meta("skill", id)
		minus.set_meta("downgrade", true)
		minus.set_meta("skill_help", row[5])
		minus.pressed.connect(func(): skill_operation.emit(id, true))
		skills_panel.add_child(minus)
		skill_buttons[id] = {"plus": plus, "minus": minus, "row": row}
		var t := BlitzText.new()
		t.position = Vector2(SKILL_TEXT_X, row[2])
		t.text_scale = 0.8
		t.color = COLOR_HELP
		skills_panel.add_child(t)
		skill_texts[id] = t
	var ok := GuiAtlas.make_button(GuiAtlas.STYLE_SMALL1, 2, Vector2(35, 35))
	ok.position = Vector2(530, 405)
	ok.pressed.connect(func(): skills_ok.emit())
	click_widgets.append(ok)
	skills_panel.add_child(ok)
	var cancel := GuiAtlas.make_button(GuiAtlas.STYLE_SMALL2, 4, Vector2(35, 35))
	cancel.position = Vector2(335, 402)
	cancel.pressed.connect(func(): skills_cancel.emit())
	click_widgets.append(cancel)
	skills_panel.add_child(cancel)
	help_frame = NinePatchRect.new()
	help_frame.texture = GuiAtlas.frame()
	help_frame.patch_margin_left = 6
	help_frame.patch_margin_right = 6
	help_frame.patch_margin_top = 6
	help_frame.patch_margin_bottom = 6
	help_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_frame.visible = false
	skills_panel.add_child(help_frame)
	help_text = BlitzText.new()
	help_text.text_scale = 0.8
	help_text.spacing = 7.0
	help_text.color = COLOR_HELP
	help_text.visible = false
	skills_panel.add_child(help_text)


func _build_tutorial_panel() -> void:
	tutorial_panel = Control.new()
	tutorial_panel.name = "Tutorial"
	tutorial_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_panel.visible = false
	root.add_child(tutorial_panel)
	tutorial_text = BlitzText.new()
	tutorial_text.position = Vector2(100, 105)
	tutorial_text.spacing = 4.5
	tutorial_text.color = COLOR_STORY
	tutorial_panel.add_child(tutorial_text)
	var next := GuiAtlas.make_button(GuiAtlas.STYLE_SMALL1, 9, Vector2(32, 32))
	next.position = Vector2(665, 345)
	next.pressed.connect(func(): tutorial_next.emit())
	click_widgets.append(next)
	tutorial_panel.add_child(next)
	tutorial_checkbox = TextureButton.new()
	tutorial_checkbox.toggle_mode = true
	tutorial_checkbox.texture_normal = GuiAtlas.checkbox(0, false)
	tutorial_checkbox.texture_pressed = GuiAtlas.checkbox(0, true)
	tutorial_checkbox.ignore_texture_size = true
	tutorial_checkbox.stretch_mode = TextureButton.STRETCH_SCALE
	tutorial_checkbox.size = Vector2(20, 20)
	tutorial_checkbox.position = Vector2(100, 345)
	tutorial_checkbox.toggled.connect(func(on): tutorial_skip = on; tutorial_skip_toggled.emit(on))
	click_widgets.append(tutorial_checkbox)
	tutorial_panel.add_child(tutorial_checkbox)
	var skip_label := BlitzText.new()
	skip_label.position = Vector2(122, 347)
	skip_label.text_scale = 0.8
	skip_label.color = COLOR_STORY
	skip_label.name = "SkipLabel"
	tutorial_panel.add_child(skip_label)


# ---------------------------------------------------------------- state -> widgets

## `_fupdateupgradebuttons`: Icerock/Flame/Balloon occupy the free slots from the left.
func refresh_tower_buttons() -> void:
	var slots := UPGRADE_SLOTS.duplicate()
	var order := [
		[tower_buttons[GameData.TOWER_ICEROCK], game.skills.cold_magic > 0],
		[tower_buttons[GameData.TOWER_FLAME], game.skills.fire_magic > 0],
		[buttons["balloon"], game.balloon != null and game.balloon.enabled],
	]
	for entry in order:
		var b: TextureButton = entry[0]
		b.visible = entry[1]
		if entry[1]:
			b.position.x = slots.pop_front()
	buttons["save"].visible = game.titul != 2 and game.level_finished and not game.create_enemies_mode
	buttons["load"].visible = game.titul != 2


func refresh_all() -> void:
	if game == null:
		return
	texts["gold"].text = str(game.gold)
	texts["lifes"].text = str(game.lifes)
	texts["extra"].text = "+%d" % game.extra_lifes if game.extra_lifes > 0 else ""
	texts["exp"].text = str(game.experience)
	if game.survival_mode:
		texts["raid"].text = "%s: %d" % [data.text(48), game.curlevel]
	else:
		texts["raid"].text = "%s: %d/%d" % [data.text(48), game.raid_index_in_location(), game.raids_in_location()]
	refresh_info_panel()
	refresh_tower_buttons()
	_refresh_skills_panel()


## `_ftowerinfo` / `_fshowenemyinfoondisplay`.
func refresh_info_panel() -> void:
	var t := game.selected_tower
	var e := game.selected_enemy
	buttons["stop"].visible = false
	if t != null:
		info_text.text = tower_info(t.type, t.level)
		faces.visible = false
		buttons["stop"].visible = t.freeze * game.skills.cold_magic > 0
		buttons["stop"].set_meta("tip", 101 if t.stopped else 100)
	elif e != null:
		# `_fshowenemyinfoondisplay`: texts 72 / 73 are the whole "Type: ground" / "Type: air" line.
		info_text.text = "%s: %d\n%s: %d\n%s: %d\n%s" % [
			data.text(69), Blitz.round_int(e.life), data.text(70), e.armor, data.text(71), int(e.speed * 100.0),
			data.text(73 if e.air else 72)]
		faces.visible = true
		var frame := WORKER_PORTRAIT_FRAME if e.worker else float(e.unit_id - 1)
		BlitzAnimator.seek(faces_player, frame)
		BlitzAnimator.update_animmaps(faces_maps)
	else:
		info_text.text = ""
		faces.visible = false


## `_ftowerinfo(type, level, showCost)`: text of the tower panel and tooltips, built from
## the (skill-scaled) prototypes. `level < 0` = build tooltip (cost of level 0, no range).
func tower_info(type: int, level: int, show_cost: bool = false) -> String:
	const GOLD := "<colR=255><colG=203><colB=000>"
	const WHITE := "<colR=255><colG=255><colB=255>"
	const GREEN := "<colR=000><colG=200><colB=120>"
	var s := ""
	var full := true
	if show_cost:
		s += "\n%s%s:%d%s" % [GOLD, data.text(33), int(game.protos[type][level]["price"]), WHITE]
	if level < 0:
		level = 0
		s += "\n%sCost:%d%s" % [GOLD, int(game.protos[type][0]["price"]), WHITE]
		full = false
	var p: Dictionary = game.protos[type][level]
	s += "\n%s%s[%d/%d]:%s" % [GREEN, data.text(1 + type), level, int(p["max_upgrades"]), WHITE]
	var land := float(p["land_damage"])
	var land_text: String
	if land <= 0.0 or land >= 1.0:
		land_text = str(Blitz.round_int(land))
	else:
		land_text = str(land).left(4)
	if land > 0.0:
		s += "\n%s - %s" % [data.text(7), land_text]
	var air := float(p["air_damage"])
	if air > 0.0:
		s += "\n%s - %d" % [data.text(8), Blitz.round_int(air)]
	if full:
		s += "\n%s - %d" % [data.text(9), Blitz.round_int(float(p["range"]))]
	if type != GameData.TOWER_FLAME:
		s += "\n%s - %d" % [data.text(10), (1000 - int(p["rate_of_fire_ms"])) / 10]
	if full:
		var fz := int(p["freeze"]) * game.skills.cold_magic
		if fz > 0:
			s += "\n<colR=110><colG=200><colB=230>%s - %d%s" % [data.text(11), fz, WHITE]
	var fm := mini(game.skills.fire_magic, 5)
	if int(p["fire"]) * fm > 0:
		s += "\n<colR=255><colG=110><colB=080>%s - %d%s" % [data.text(12), Blitz.round_int(float(fm) * land * float(int(p["fire"]))) / 10, WHITE]
	if game.skills.fire_magic == 6 and type == GameData.TOWER_MAGIC:
		s += "\n<colR=255><colG=110><colB=080>%s - %d%s" % [data.text(12), Blitz.round_int(air * 0.5), WHITE]
	if int(p["poison_coof"]) * game.skills.poison_magic > 0:
		s += "\n<colR=000><colG=255><colB=000>%s - %d%s" % [data.text(49), Blitz.round_int(float(game.skills.poison_magic) * float(p["poison_damage"]) * float(int(p["poison_coof"]))) / 10, WHITE]
	return s


func _refresh_skills_panel() -> void:
	if not skills_panel.visible:
		return
	skills_exp_text.text = "%s: %d" % [data.text(82), game.experience]
	for id in skill_buttons:
		var entry: Dictionary = skill_buttons[id]
		var level := game.skills.level_of(id)
		if id == SimSkills.Id.FIRE:
			level = game.skills.fire_magic
		(entry["minus"] as TextureButton).visible = game.skills.can_downgrade(id) and id != SimSkills.Id.DAMAGE
		var plus: TextureButton = entry["plus"]
		plus.modulate = COLOR_FIRE6 if id == SimSkills.Id.FIRE and game.skills.fire_magic == 5 else Color.WHITE
		skill_texts[id].text = str(level)


# ---------------------------------------------------------------- windows

func show_skills_window(open: bool) -> void:
	skills_panel.visible = open
	if updates_mesh != null:
		updates_mesh.visible = open
	if open:
		_refresh_skills_panel()


func show_tutorial(page: int) -> void:
	if page <= 0:
		tutorial_panel.visible = false
		tutorial3d.visible = false
		return
	tutorial_panel.visible = true
	tutorial3d.visible = true
	# `_fnexttutorialpage` calls `_fsettutorialpage(old_state)`: frame = page - 1 (frame 0
	# also shows the gold/people pointers, frame 2 parks the window off-screen while the
	# player builds). Pages 8-10 are set directly and never seek: the sheet stays as is.
	BlitzAnimator.seek(tutorial_player, float(page - 1) if page <= Tutorial.PAGE_MONSTERS else 1.0)
	layout.cull_parked(tutorial3d)
	tutorial_text.text = data.tutorial_page(page)
	# `_fshowtutorial`: the "skip" checkbox exists only on location 1 and pages below 10.
	var skip_visible := game != null and game.location == 1 and page < Tutorial.PAGE_HELP
	tutorial_checkbox.visible = skip_visible
	var skip_label := tutorial_panel.get_node("SkipLabel") as BlitzText
	skip_label.visible = skip_visible
	skip_label.text = data.text(81)
	var n := tutorial_text.letter_count()
	tutorial_alpha.resize(n)
	tutorial_alpha_inc.resize(n)
	for i in n:
		tutorial_alpha[i] = 0.0
		tutorial_alpha_inc[i] = rng.randf_range(0.01, 0.03)
	tutorial_text.letter_alpha = tutorial_alpha


func is_tutorial_visible() -> bool:
	return tutorial_panel.visible


# ---------------------------------------------------------------- messages

func add_message(text: String, kind: int, duration_ms: int) -> void:
	var t := BlitzText.new()
	t.text = text
	t.text_scale = 0.9
	t.spacing = 7.0
	t.color = MSG_COLORS.get(kind, Color.WHITE)
	messages_node.add_child(t)
	messages.push_front({"node": t, "lines": text.count("\n") + 1, "alpha": 1.0, "end": Time.get_ticks_msec() + duration_ms})
	if kind == SimGame.MSG_RED:
		game.sound.emit("warning", Vector3.ZERO)


func add_gold_popup(amount: int, world_pos: Vector3) -> void:
	var t := BlitzText.new()
	t.text = "+%d" % amount
	t.text_scale = 0.9
	t.color = COLOR_GOLD
	popups_node.add_child(t)
	gold_popups.append({"node": t, "pos": world_pos, "rise": 0.0, "alpha": 1.0, "end": Time.get_ticks_msec() + GOLD_POPUP_MS})


## Newest message at the bottom, older ones stacked above; a multi-line message takes a
## slot per line (the original stepped 16 px per message and let long ones overlap).
## Fading and rising are per tick: `ticks` of them passed since the last frame.
func _update_messages(ticks: int) -> void:
	var now := Time.get_ticks_msec()
	var y := MESSAGE_Y
	for m in messages.duplicate():
		if now >= m["end"]:
			m["alpha"] -= MESSAGE_FADE * ticks
		var node: BlitzText = m["node"]
		y -= (int(m["lines"]) - 1) * MESSAGE_STEP
		node.position = Vector2(MESSAGE_X, y)
		node.color.a = maxf(m["alpha"], 0.0)
		if m["alpha"] <= 0.0:
			messages.erase(m)
			node.queue_free()
		y -= MESSAGE_STEP
	for p in gold_popups.duplicate():
		p["rise"] += GOLD_POPUP_RISE * ticks
		if now >= p["end"]:
			p["alpha"] -= MESSAGE_FADE * ticks
		var node: BlitzText = p["node"]
		if camera != null and not camera.is_position_behind(p["pos"]):
			var screen := camera.unproject_position(p["pos"]) - offset  # canvas -> box coordinates
			node.position = Vector2(screen.x, screen.y - p["rise"])
			node.visible = true
		else:
			node.visible = false
		node.color.a = maxf(p["alpha"], 0.0)
		if p["alpha"] <= 0.0:
			gold_popups.erase(p)
			node.queue_free()


# ---------------------------------------------------------------- per frame

## `ticks` logic ticks ran since the last frame: the widgets mirror the simulation once.
func _on_frame_ticked(ticks: int) -> void:
	if game == null:
		return
	refresh_all()
	_update_messages(ticks)
	_update_slider_knob()
	_update_progress()
	_update_tutorial_reveal(ticks)


func _update_slider_knob() -> void:
	var frac := float(Ticker.slider) / float(Ticker.SLIDER_MAX)
	var x := SLIDER_RECT.position.x + SLIDER_EDGE + frac * (SLIDER_RECT.size.x - 2 * SLIDER_EDGE) - 16
	slider_knob.position = Vector2(x, SLIDER_RECT.position.y - 6)


## `_fhandletowers`: value = 10 * AnimTime of the selected tower's upgrade sequence, else 0;
## the Upgrade button is blocked while the animation runs.
func _update_progress() -> void:
	var t := game.selected_tower
	var upgrading := t != null and t.is_upgrading()
	_set_progress(t.anim_time * 10.0 if upgrading else 0.0)
	buttons["upgrade"].disabled = upgrading


func _update_tutorial_reveal(ticks: int) -> void:
	if not tutorial_panel.visible:
		return
	var changed := false
	for i in tutorial_alpha.size():
		if tutorial_alpha[i] < 1.0:
			tutorial_alpha[i] = minf(tutorial_alpha[i] + tutorial_alpha_inc[i] * ticks, 1.0)
			changed = true
	if changed:
		tutorial_text.letter_alpha = tutorial_alpha


func _process(_delta: float) -> void:
	_update_tooltip()


# ---------------------------------------------------------------- tooltips

## `_fcreatetip`: tooltip of the hovered widget, composed from Texts.txt indices.
func _update_tooltip() -> void:
	if game == null or not input_enabled:
		tooltip.visible = false
		return
	var mouse := root.get_local_mouse_position()
	var hovered: Control = null
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		hovered = _widget_at(root.get_global_mouse_position())
		if hovered == reset_mark:
			hovered = null
	if hovered == null:
		tooltip.visible = false
		_show_help("")
		return
	# `_fcreatetip` also queues the skill's Helps.txt line for `_fdrawhelps`.
	_show_help(data.help(int(hovered.get_meta("skill_help"))) if hovered.has_meta("skill_help") else "")
	var tip := _tip_for(hovered)
	if tip == "":
		tooltip.visible = false
		return
	tooltip_text.text = tip
	var lines := tip.count("\n") + 1
	var th := lines * TIP_LINE
	var viewport_w := root.size.x
	var x := mouse.x - 16.0 - maxf(0.0, 170.0 - (viewport_w - mouse.x))
	var y := mouse.y - th
	tooltip.position = Vector2(x, y)
	tooltip_frame.position = Vector2(0, -TIP_MARGIN)
	tooltip_frame.size = Vector2(TIP_WIDTH, th + 2 * TIP_MARGIN)
	tooltip_text.position = Vector2.ZERO
	tooltip.visible = true


## `_fdrawhelps`: the help line in a 185 px block at (15, 120) when ShowHelp is on.
func _show_help(text: String) -> void:
	var on := text != "" and int(SaveManager.settings["ShowHelp"]) == 1
	help_frame.visible = on
	help_text.visible = on
	if not on:
		return
	help_text.text = text
	var th := (text.count("\n") + 1) * TIP_LINE
	help_frame.position = Vector2(HELP_POS.x, HELP_POS.y - TIP_MARGIN)
	help_frame.size = Vector2(HELP_WIDTH, th + 2 * TIP_MARGIN)
	help_text.position = HELP_POS


func _tip_for(c: Control) -> String:
	if c.has_meta("skill"):
		var id: int = c.get_meta("skill")
		var downgrade: bool = c.get_meta("downgrade")
		var row: Array = skill_buttons[id]["row"]
		if downgrade:
			return "%s\n<colR=247><colG=232><colB=172>%s: %d %s" % [data.text(row[4]), data.text(90), game.skills.price_of(id) / 2, data.text(60)]
		if not game.skills.can_buy(id, 1000000):
			return data.text(78)
		var price := game.skills.price_of(id)
		if id == SimSkills.Id.FIRE and game.skills.fire_magic == 5:
			return "%s\n<colR=247><colG=232><colB=172>%s: %d %s" % [data.text(87), data.text(33), game.skills.price_of(SimSkills.Id.FIRE6), data.text(60)]
		return "%s\n<colR=247><colG=232><colB=172>%s: %d %s" % [data.text(row[3]), data.text(33), price, data.text(60)]
	var k: int = c.get_meta("tip", -1)
	if k < 0:
		return ""
	var name := c.name
	if name.begins_with("tower"):
		var type := int(name.substr(5))
		return data.text(k) + tower_info(type, -1)
	match name:
		"upgrade":
			var t := game.selected_tower
			if t == null:
				return data.text(26) + data.text(76)
			if t.is_upgrading():
				return ""
			if t.level >= t.max_upgrades:
				return data.text(27)
			return data.text(26) + tower_info(t.type, t.level + 1, true)
		"sell":
			var t := game.selected_tower
			if t == null:
				return data.text(28)
			return "%s\n<colR=255><colG=203><colB=000>%d %s" % [data.text(29), game.sell_value(t), data.text(30)]
		"health":
			return data.text(80 if game.show_units_life else 79)
	return data.text(k)


## The interactive widget under `global_pos` (canvas coordinates), if any.
func _widget_at(global_pos: Vector2) -> Control:
	if tip_candidates.is_empty() or tip_candidates_with_skills != skills_panel.visible:
		tip_candidates_with_skills = skills_panel.visible
		tip_candidates = buttons.values() + [slider, reset_mark]
		if skills_panel.visible:
			for entry in skill_buttons.values():
				tip_candidates.append(entry["plus"])
				tip_candidates.append(entry["minus"])
	for c in tip_candidates + click_widgets:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(global_pos):
			return c
	return null


## Whether the pointer (the mouse, or the last touch) is over a widget or the skills window
## is open: a click there is not a click on the location. A hit test at the time of asking
## rather than enter / exit tracking, which touch emulation does not drive.
func is_mouse_over_gui() -> bool:
	return skills_panel.visible or _widget_at(root.get_global_mouse_position()) != null


func set_input_enabled(on: bool) -> void:
	input_enabled = on
	root.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
