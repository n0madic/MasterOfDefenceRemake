## Main menu (`_floadmenu` / `_fshowmenu`): the `env` world seen through the animated
## camera of `cameraEnv`, the `buttons` sheet and the `playgame` sub-menu in front of it.
class_name MainMenu
extends ScreenBase

signal start_requested(mode: String)  # new / hard / insane / continue / hardcore
## Emitted after "ok" in the settings when windowed / vsync changed.
signal video_changed
signal highscores_requested
signal quit_requested

const ENV_MODEL := "res://assets/models/Menu/env.glb"
const CAMERA_MODEL := "res://assets/models/Menu/cameraEnv.glb"
const BUTTONS_MODEL := "res://assets/models/Menu/buttons.glb"
const PLAYGAME_MODEL := "res://assets/models/Menu/playgame.glb"
const CREDITS_MODEL := "res://assets/models/Menu/credits.glb"
const LOADING_MODEL := "res://assets/models/Menu/loading.glb"
const TITUL_TEXTURE := "res://assets/textures/Menu/Titul%d.png"
const ENV_SPEED := 0.1
const CAMERA_SPEED := 0.25
const OPTIONS_SHOW_FRAME := 16.0
const SUBMENU_SPEED := 0.5
const SUBMENU_SEQ_STRIDE := 8
const SUBMENU_SEQ_FRAMES := 6
const CREDITS_SPEED := 0.3
const LOADING_SPEED := 0.2
const LOADING_END := 9.9
const LOADING_FRAMES := 10.0
const VERSION_TEXT := "Remake based on v1.67e"
# The original drew "v1.67e" left-aligned at (700, 580); keep the right edge of the label
# where it was so the longer remake text does not run off the 800x600 sheet.
const VERSION_RIGHT_EDGE := 700.0 + 7 * (BlitzText.GLYPH - 5.0)
const VERSION_Y := 580.0
# Remake credit shown only while the credits sheet is open, in the free bottom-left strip
# opposite the version label (the baked credits plank has no room for another line).
const REMAKE_CREDIT_TEXT := "Remake by n0madic"
const REMAKE_CREDIT_POS := Vector2(20, 580)
const MAIN_ITEMS := ["start", "hardcore", "settings", "credits", "exit", "highscores", "ok"]
const SUB_ITEMS := ["new", "hard", "insane", "continue"]
const EXIT_LABEL := "Plane10"  # the "Exit" caption mesh of `buttons.b3d`
## The `buttons.b3d` planks that carry the settings widgets at the end of the flight are
## the main-menu button meshes themselves (the `PlaneNN` labels fly off-screen). Planks
## whose widgets are gone (resolution) or platform-gated (VSync) are hidden together with
## the widgets; the colour-depth plank (`fhfh`) carries the Screen 4:3 / Wide radios and
## Windowed shares its plank (`settings`) with Gamma, so both stay.
const PLANK_NODES := {"resolution": "credits", "vsync": "exit"}
## Wide mode, measured on the scene: the sky backdrop (`SkyNew` on the camera) spans an
## aspect of ~1.8 in both the main and the settings view; below 1.25 the sky dome ends at
## the top and the planks parked under the frame ("ok", "credits") show at the bottom.
const ASPECT_LIMITS := Vector2(1.25, 1.8)
## The `grass` polygon of `env.b3d` is cut to the 4:3 frame: in 4:3 the castle and the big
## tree hide where it stops short of the horizon, a wider canvas shows the void at the
## sides. A plain grass plane under everything fills it without touching the original frame.
const GROUND_FILLER_TEXTURE := "res://assets/textures/Menu/grass.jpg"
const GROUND_FILLER_SIZE := 100000.0
const GROUND_FILLER_FAR := 60000.0  # camera far plane: the filler must reach the horizon
const GROUND_FILLER_TILE := 40.0  # world units per texture repeat
const GROUND_FILLER_Y := -8.0  # just under the lowest point of `grass`
const GROUND_FILLER_TINT := Color(1.0, 0.9, 0.6)  # matches the lit ground next to it

var env_scene: Node3D
var env_player: AnimationPlayer
var env_time := 0.0
var env_maps: Array[Dictionary] = []  # the scrolling `flame.jpg` of the green fire
var cam_scene: Node3D
var cam_player: AnimationPlayer
var cam_node: Node3D
var buttons: MenuScene3D
var playgame: MenuScene3D
var credits: MenuScene3D
var loading: MenuScene3D
var state := "main"  # main / settings / credits / loading
## The difficulty sub-menu is open over the main buttons (`_fshowmenu` flag at +0x60).
var sub_open := false
var cam_time := 0.0
var cam_speed := 0.0  # +-CAMERA_SPEED while the fly-through runs, 0 when parked
var cam_length := 0.0
var options: OptionsPanel
var hidden_planks: Array[Node3D] = []
var pending_mode := ""
var remake_credit: BlitzText
var menus_opened := 0
var master_flag := 0


func _ready() -> void:
	aspect_limits = ASPECT_LIMITS
	super._ready()
	menus_opened = int(SaveManager.settings["MenusOpened"])
	master_flag = int(SaveManager.settings["MasterFlag"])
	env_scene = load(ENV_MODEL).instantiate()
	world.add_child(env_scene)
	BlitzAnimator.hide_helpers(env_scene)
	world.add_child(_ground_filler())
	camera.far = GROUND_FILLER_FAR
	env_player = BlitzAnimator.find_player(env_scene)
	env_maps = BlitzAnimator.setup_animmaps(env_scene)
	cam_scene = load(CAMERA_MODEL).instantiate()
	world.add_child(cam_scene)
	BlitzAnimator.hide_helpers(cam_scene)
	cam_player = BlitzAnimator.find_player(cam_scene)
	cam_node = cam_scene.find_child("Camera01", true, false)
	cam_length = cam_player.get_animation(BlitzAnimator.B3D_ANIMATION).length if cam_player != null else 0.0
	BlitzAnimator.seek(cam_player, 0.0)
	_align_camera()
	buttons = make_menu(BUTTONS_MODEL, MAIN_ITEMS)
	playgame = make_menu(PLAYGAME_MODEL, SUB_ITEMS)
	playgame.scene.visible = false
	playgame.enabled = false
	credits = make_menu(CREDITS_MODEL, ["ok"])
	credits.scene.visible = false
	credits.enabled = false
	loading = make_menu(LOADING_MODEL, [])
	loading.scene.visible = false
	_setup_titul()
	buttons.set_item_visible("ok", false)
	options = OptionsPanel.new()
	canvas.add_child(options)
	var planks := ["resolution"] + (["vsync"] if options.vsync == null else [])
	# In a browser tab "exit" means closing the tab: the button goes for good. Its mesh is
	# also the VSync plank, so it is dropped from the widget-driven planks above.
	if DisplayManager.platform() == DisplayManager.PLATFORM_WEB:
		planks.erase("vsync")
		buttons.remove_item("exit", EXIT_LABEL)
	for key in planks:
		var plank := buttons.find_node(PLANK_NODES[key])
		if plank != null:
			hidden_planks.append(plank)
	for demo_item in ["buynow", "buynow1"]:
		var n := buttons.find_node(demo_item)
		if n != null:
			n.visible = false
	_update_sub_items()
	var version := text(Vector2.ZERO, VERSION_TEXT, Hud.COLOR_EXP)
	version.position = Vector2(VERSION_RIGHT_EDGE - version.text_width() - version.advance(), VERSION_Y)
	remake_credit = text(REMAKE_CREDIT_POS, REMAKE_CREDIT_TEXT, Hud.COLOR_EXP_TITLE)
	remake_credit.visible = false
	AudioManager.stop_loops()
	AudioManager.play_loop("tlen")
	AudioManager.play_music("res://assets/audio/menu.ogg")


func _setup_titul() -> void:
	var titul: MeshInstance3D = buttons.find_node("titul")
	if titul == null:
		return
	var n := menus_opened + master_flag
	if n < 1:
		titul.visible = false
		return
	var path := TITUL_TEXTURE % n
	if ResourceLoader.exists(path):
		var m := titul.get_active_material(0)
		if m is StandardMaterial3D:
			var own := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			own.albedo_texture = load(path)
			titul.set_surface_override_material(0, own)


func _update_sub_items() -> void:
	playgame.set_item_visible("hard", menus_opened >= 1)
	playgame.set_item_visible("insane", menus_opened >= 2)
	playgame.set_item_visible("continue", SaveManager.save_exists("Automatic"))


## B3D Extensions cameras look along the local -Y of the exported `Camera01` node with
## local +Z (Blitz) as up; in Godot the node's +Y/-Z carry those axes, so the camera
## basis is (x, y, z) = (x, -z, y) of the node.
const CAMERA_FIX := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO)


func _align_camera() -> void:
	if cam_node != null:
		camera.global_transform = cam_node.global_transform * CAMERA_FIX


func _tick() -> void:
	if env_player != null:
		env_time = fposmod(env_time + ENV_SPEED, env_player.get_animation(BlitzAnimator.B3D_ANIMATION).length)
		BlitzAnimator.seek(env_player, env_time)
		BlitzAnimator.update_animmaps(env_maps)
	_tick_camera_flight()
	_align_camera()
	# `_fguioptionsbuttonsvisible`: the widgets appear once the flight passes frame 16.
	options.visible = state == "settings" and cam_time >= OPTIONS_SHOW_FRAME
	for plank in hidden_planks:
		plank.visible = not options.visible
	if state == "loading" and loading.anim_time > LOADING_END:
		state = "done"
		start_requested.emit(pending_mode)


## `Animate(cameraEnv, one-shot, +-0.25)`: the flight into the settings and back.
func _tick_camera_flight() -> void:
	if cam_speed == 0.0 or cam_player == null:
		return
	cam_time = clampf(cam_time + cam_speed, 0.0, cam_length)
	if cam_time == 0.0 or cam_time == cam_length:
		cam_speed = 0.0
	BlitzAnimator.seek(cam_player, cam_time)


func _ground_filler() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_FILLER_SIZE, GROUND_FILLER_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(GROUND_FILLER_TEXTURE)
	mat.albedo_color = GROUND_FILLER_TINT
	mat.uv1_scale = Vector3(GROUND_FILLER_SIZE / GROUND_FILLER_TILE, GROUND_FILLER_SIZE / GROUND_FILLER_TILE, 1.0)
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "GroundFiller"
	mi.mesh = plane
	mi.position.y = GROUND_FILLER_Y
	return mi


func _on_item(name: String) -> void:
	match state:
		"main":
			# `_fshowmenu` state 1: any other main button folds the open sub-menu first;
			# a difficulty pick leaves the sheet where it is under the loading screen.
			if name != "start" and name not in SUB_ITEMS:
				_close_sub()
			match name:
				"start":
					_open_sub()
				"new", "hard", "insane", "continue":
					_start(name)
				"hardcore":
					_start("hardcore")
				"settings":
					_open_settings()
				"credits":
					state = "credits"
					credits.scene.visible = true
					credits.enabled = true
					buttons.enabled = false
					remake_credit.visible = true
					credits.animate(SimTower.ANIM_ONESHOT, CREDITS_SPEED)
				"highscores":
					highscores_requested.emit()
				"exit":
					quit_requested.emit()
		"settings":
			if name == "ok":
				_close_settings()
		"credits":
			if name == "ok":
				state = "main"
				credits.enabled = false
				credits.scene.visible = false
				remake_credit.visible = false
				buttons.enabled = true


## `Animate(playgame, one-shot, +-0.5, MenusOpened + 1)`: sequence `seq` of `playgame.b3d`
## is frames 8 * (seq - 1) .. 8 * (seq - 1) + 6; closing runs it back to its first frame.
func _sub_range() -> Array:
	var first := SUBMENU_SEQ_STRIDE * menus_opened
	return [float(first), float(first + SUBMENU_SEQ_FRAMES)]


func _open_sub() -> void:
	if sub_open:
		return
	sub_open = true
	playgame.scene.visible = true
	playgame.enabled = true
	var r := _sub_range()
	playgame.animate_range(SimTower.ANIM_ONESHOT, SUBMENU_SPEED, r[0], r[1])


func _close_sub() -> void:
	if not sub_open:
		return
	sub_open = false
	playgame.enabled = false
	var r := _sub_range()
	playgame.animate_range(SimTower.ANIM_ONESHOT, -SUBMENU_SPEED, r[0], r[1])


## "settings": the buttons sheet flies away with the camera; only "ok" stays pickable.
func _open_settings() -> void:
	state = "settings"
	cam_speed = CAMERA_SPEED
	buttons.animate(SimTower.ANIM_ONESHOT, CAMERA_SPEED)
	buttons.set_item_visible("ok", true)
	for item in MAIN_ITEMS:
		if item != "ok":
			buttons.set_item_enabled(item, false)


func _close_settings() -> void:
	state = "main"
	cam_speed = -CAMERA_SPEED
	buttons.animate(SimTower.ANIM_ONESHOT, -CAMERA_SPEED)
	buttons.set_item_visible("ok", false)
	for item in MAIN_ITEMS:
		if item != "ok":
			buttons.set_item_enabled(item, true)
	if options.apply():
		video_changed.emit()


func _start(mode: String) -> void:
	pending_mode = mode
	state = "loading"
	sub_open = false
	buttons.enabled = false
	playgame.enabled = false
	loading.scene.visible = true
	loading.animate_range(SimTower.ANIM_ONESHOT, LOADING_SPEED, 0.0, LOADING_FRAMES)

