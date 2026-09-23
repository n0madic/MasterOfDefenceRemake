## In-game pause menu (`Menu/ingame.b3d`, `_fcreateingamemenu` / `_fshowingamemenu` /
## `_fhandleingamemenu`): the sheet with back / restart / help / to menu / exit is parented
## to the location camera 10 units ahead, tilts with the mouse, and carries the 3D volume
## sliders `music.b3d` / `sound.b3d` (children of `themusic` / `thesound`) whose knob is
## the animation frame `99.99 - volume * 100`.
class_name InGameMenu
extends Node

signal choice(name: String)

const MODEL := "res://assets/models/Menu/ingame.glb"
const MUSIC_MODEL := "res://assets/models/Menu/music.glb"
const SOUND_MODEL := "res://assets/models/Menu/sound.glb"
const ITEMS := ["back", "restart", "tomenu", "exit", "help"]
const EXIT_LABEL := "Plane10"  # the "Exit" caption mesh of `ingame.b3d`
const OPEN_SPEED := 0.4
## `RotateEntity(menu, -(my - h/2) / (h/30), (mx - w/2) / (w/40), 0)` with integer maths.
const TILT_PITCH_DIVISIONS := 30
const TILT_YAW_DIVISIONS := 40
const SLIDER_FRAMES := 100
const SLIDER_TOP := 99.99


## One `music.b3d` / `sound.b3d`: a 100-frame animation moving the knob along the track.
class VolumeSlider:
	var scene: Node3D
	var player: AnimationPlayer
	var knob: Node3D
	var back_name: String
	var time := 0.0

	func _init(model: String, holder: Node3D, knob_name: String, back: String) -> void:
		scene = load(model).instantiate()
		holder.add_child(scene)
		BlitzAnimator.hide_helpers(scene)
		player = BlitzAnimator.find_player(scene)
		knob = scene.find_child(knob_name, true, false)
		back_name = back

	func set_volume(v: float) -> void:
		seek(SLIDER_TOP - v * SLIDER_FRAMES)

	func volume() -> float:
		return 1.0 - time / SLIDER_FRAMES

	func seek(t: float) -> void:
		time = t
		BlitzAnimator.seek(player, t)

	## `_fcalcposfordragger`: the frame (0..99) whose knob projects closest to the mouse.
	func nearest_frame(camera: Camera3D, mouse: Vector2) -> float:
		var best := 0.0
		var best_dist := INF
		for t in SLIDER_FRAMES:
			BlitzAnimator.seek(player, float(t))
			var p := knob.global_position
			if camera.is_position_behind(p):
				continue
			var d := camera.unproject_position(p).distance_to(mouse)
			if d < best_dist:
				best_dist = d
				best = float(t)
		return best


var menu: MenuScene3D
var camera: Camera3D
var music: VolumeSlider
var sound: VolumeSlider
var dragging := ""  # "" / music back name / sound back name
var saved_fps := Ticker.NORMAL_FPS
var closed := false


func open(cam: Camera3D) -> void:
	camera = cam
	menu = MenuScene3D.new()
	menu.load_scene(MODEL, cam, ITEMS)
	menu.item_clicked.connect(_on_item)
	# In a browser tab "exit" means closing the tab: the button goes.
	if DisplayManager.platform() == DisplayManager.PLATFORM_WEB:
		menu.remove_item("exit", EXIT_LABEL)
	menu.animate(SimTower.ANIM_ONESHOT, OPEN_SPEED)
	music = VolumeSlider.new(MUSIC_MODEL, menu.find_node("themusic"), "music", "musicback")
	sound = VolumeSlider.new(SOUND_MODEL, menu.find_node("thesound"), "sound", "soundback")
	menu.register_item(music.back_name, music.scene.find_child(music.back_name, true, false), true)
	menu.register_item(sound.back_name, sound.scene.find_child(sound.back_name, true, false), true)
	music.set_volume(AudioManager.music_volume)
	sound.set_volume(AudioManager.sound_volume)
	# `_fshowingamemenu` runs the menu at 60 fps whatever the time slider says.
	saved_fps = Ticker.fps()
	Ticker.set_fps(Ticker.NORMAL_FPS)
	Ticker.ticked.connect(_on_ticked)


func _on_item(name: String) -> void:
	if name == "back":
		_save()
	choice.emit(name)


func _save() -> void:
	SaveManager.settings["SoundVol"] = AudioManager.sound_volume
	SaveManager.settings["MusicVol"] = AudioManager.music_volume
	SaveManager.save_settings()


func _on_ticked() -> void:
	if closed or menu == null:
		return
	var mouse := get_viewport().get_mouse_position()
	_handle_sliders(mouse)
	if dragging == "":
		menu.tick(mouse)
	else:
		menu.tick(Vector2(-1000, -1000))
	_tilt(mouse)


## Mouse held: a pick on a slider back starts / continues dragging its knob.
func _handle_sliders(mouse: Vector2) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		dragging = ""
		return
	var hit := menu.pick(mouse)
	if hit == music.back_name or (hit == "" and dragging == music.back_name):
		dragging = music.back_name
		music.seek(music.nearest_frame(camera, mouse))
		AudioManager.set_volumes(AudioManager.sound_volume, music.volume())
	elif hit == sound.back_name or (hit == "" and dragging == sound.back_name):
		dragging = sound.back_name
		sound.seek(sound.nearest_frame(camera, mouse))
		AudioManager.set_volumes(sound.volume(), AudioManager.music_volume)


## The sheet follows the cursor: Blitz pitch/yaw in whole degrees; under the z-mirror the
## pitch flips sign and the yaw keeps it (geom.h `pitchMatrix`/`yawMatrix`).
func _tilt(mouse: Vector2) -> void:
	# Box coordinates, clamped: in wide mode the cursor can sit in the margins, where the
	# original tilt limits would be exceeded.
	var m := (mouse - DisplayManager.ui_offset).clamp(Vector2.ZERO, DisplayManager.BOX - Vector2.ONE)
	var w := int(DisplayManager.BOX.x)
	var h := int(DisplayManager.BOX.y)
	var pitch := Blitz.idiv(-(int(m.y) - (h >> 1)), Blitz.idiv(h, TILT_PITCH_DIVISIONS))
	var yaw := Blitz.idiv(int(m.x) - (w >> 1), Blitz.idiv(w, TILT_YAW_DIVISIONS))
	menu.rotation_degrees = Vector3(-pitch, yaw, 0)


func _unhandled_input(event: InputEvent) -> void:
	if closed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if dragging == "":
			menu.click(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P or event.keycode == KEY_F10):
		_on_item("back")
		get_viewport().set_input_as_handled()


func close() -> void:
	closed = true
	if Ticker.ticked.is_connected(_on_ticked):
		Ticker.ticked.disconnect(_on_ticked)
	Ticker.set_fps(saved_fps)
	if menu != null:
		menu.queue_free()
	queue_free()
