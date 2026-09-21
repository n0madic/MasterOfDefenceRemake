## Settings widgets of the main menu (`_fguicreateoptionsbuttons` / `_fhandleoptionsgui` /
## `_fsaveoptions`): Eniretu controls at the original coordinates, shown over the menu
## world once the camera fly-through (`cameraEnv`) has passed frame 16. The resolution
## and colour depth of the original are gone (the render is always 800x600 scaled to the
## window); their planks carry the "Screen" 4:3 / Wide radio group instead. Gamma and the
## screen mode are applied live through DisplayManager. Windowed / VSync exist only where
## the platform lets the game decide them (see DisplayManager).
class_name OptionsPanel
extends Control

const GAMMA_RANGE := 100.0
const FULLSCREEN_CAPTION := "Fullscreen"
const WINDOWED_POS := Vector2(380, 520)
const SCREEN_CAPTION := "Screen"
const WIDE_CAPTIONS := ["4:3", "Wide"]  # index = `WideScreen` value
const SCREEN_LABEL_POS := Vector2(700, 365)
const SCREEN_RADIO_POS := [Vector2(700, 380), Vector2(700, 400)]

var platform: String
var windowed: TextureButton  # desktop: "Windowed mode"; web: "Fullscreen" (inverted); mobile: none
var vsync: TextureButton  # desktop only
var wide_radio: Array[TextureButton] = []  # [0] = 4:3, [1] = Wide
var gamma: Eniretu.AtlasSlider
var music: Eniretu.AtlasSlider
var sound: Eniretu.AtlasSlider
var player_name: Eniretu.TextBox
var settings: Dictionary


func _init(target_platform := DisplayManager.platform()) -> void:
	platform = target_platform
	settings = SaveManager.settings
	size = DisplayManager.BOX  # the box, not the canvas: the layer is centred in wide mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_child(Eniretu.label(SCREEN_LABEL_POS, SCREEN_CAPTION))
	var wide_value := int(settings[DisplayManager.WIDE])
	for i in WIDE_CAPTIONS.size():
		var radio := Eniretu.toggle(SCREEN_RADIO_POS[i], WIDE_CAPTIONS[i], wide_value == i, true)
		radio.toggled.connect(func(on): _on_wide_toggled(i, on))
		wide_radio.append(radio)
		add_child(radio)
	if platform == DisplayManager.PLATFORM_DESKTOP:
		add_child(Eniretu.label(Vector2(360, 440), GameData.text(14)))
		vsync = Eniretu.toggle(Vector2(470, 465), "VSync", int(settings["VSync"]) == 1, false)
		vsync.toggled.connect(func(_on): AudioManager.play("check"))
		add_child(vsync)
	add_child(Eniretu.label(Vector2(360, 542), GameData.text(15)))
	gamma = Eniretu.slider(Rect2(450, 544, 200, 16), 0.0, 2.0 * GAMMA_RANGE, float(int(settings["GammaIntensity"])) + GAMMA_RANGE)
	gamma.value_changed.connect(func(v): DisplayManager.set_gamma(int(v - GAMMA_RANGE)))
	add_child(gamma)
	add_child(Eniretu.label(Vector2(20, 430), GameData.text(16)))
	music = Eniretu.slider(Rect2(20, 460, 280, 16), 0.0, 100.0, float(Blitz.round_int(float(settings["MusicVol"]) * 100.0)))
	music.value_changed.connect(func(v): AudioManager.set_volumes(AudioManager.sound_volume, v / 100.0))
	add_child(music)
	add_child(Eniretu.label(Vector2(50, 505), GameData.text(17)))
	sound = Eniretu.slider(Rect2(50, 530, 240, 16), 0.0, 100.0, float(Blitz.round_int(float(settings["SoundVol"]) * 100.0)))
	sound.value_changed.connect(func(v): AudioManager.set_volumes(v / 100.0, AudioManager.music_volume))
	add_child(sound)
	add_child(Eniretu.label(Vector2(20, 340), GameData.text(18)))
	player_name = Eniretu.textbox(Rect2(20, 360, 280, 30), str(settings["PlayerName"]))
	add_child(player_name)
	match platform:
		DisplayManager.PLATFORM_DESKTOP:
			windowed = Eniretu.toggle(WINDOWED_POS, GameData.text(19), int(settings["Windowed"]) == DisplayManager.WINDOWED, false)
		DisplayManager.PLATFORM_WEB:
			windowed = Eniretu.toggle(WINDOWED_POS, FULLSCREEN_CAPTION, _current_windowed() != DisplayManager.WINDOWED, false)
	if windowed != null:
		windowed.toggled.connect(func(_on): AudioManager.play("check"))
		add_child(windowed)


## Radio group: pressing one releases the other and previews the layout at once (the only
## way off the screen is "ok", which stores it).
func _on_wide_toggled(index: int, on: bool) -> void:
	if not on:
		return
	AudioManager.play("check")
	wide_radio[1 - index].set_pressed_no_signal(false)
	DisplayManager.set_wide(index == 1)


## What the mode toggle is compared against: the saved value on the desktop, the live
## window on the web (a saved fullscreen is not in effect after a reload or Esc).
func _current_windowed() -> int:
	if platform == DisplayManager.PLATFORM_WEB:
		return DisplayManager.windowed_value()
	return int(settings["Windowed"])


## The `Windowed` value the mode toggle stands for (the web toggle reads "Fullscreen").
func _windowed_value() -> int:
	var on := windowed.button_pressed
	if platform == DisplayManager.PLATFORM_WEB:
		on = not on
	return DisplayManager.WINDOWED if on else 1


## `_fsaveoptions` on "ok": store and apply; returns true when the video mode changed.
func apply() -> bool:
	var before := [_current_windowed(), int(settings["VSync"])]
	if windowed != null:
		settings["Windowed"] = _windowed_value()
	if vsync != null:
		settings["VSync"] = 1 if vsync.button_pressed else 0
	settings["GammaIntensity"] = int(gamma.value - GAMMA_RANGE)
	settings[DisplayManager.WIDE] = 1 if wide_radio[1].button_pressed else 0
	settings["MusicVol"] = music.value / 100.0
	settings["SoundVol"] = sound.value / 100.0
	settings["PlayerName"] = player_name.text.strip_edges()
	player_name.text = str(settings["PlayerName"])
	SaveManager.save_settings()
	AudioManager.set_volumes(float(settings["SoundVol"]), float(settings["MusicVol"]))
	var after := [int(settings["Windowed"]), int(settings["VSync"])]
	return before != after
