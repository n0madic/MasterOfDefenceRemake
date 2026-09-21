## Settings screen and display manager: the gamma ramp, the 4:3 / wide layout maths, which
## widgets each platform gets and what "ok" writes back into the settings.
extends TestCase

var saved: Dictionary
var saved_file := ""


## `apply()` writes user://settings.json: keep the real file byte for byte.
func setup() -> void:
	saved = SaveManager.settings.duplicate()
	saved_file = FileAccess.get_file_as_string(SaveManager.SETTINGS_PATH) if FileAccess.file_exists(SaveManager.SETTINGS_PATH) else ""


func teardown() -> void:
	SaveManager.settings.clear()
	SaveManager.settings.merge(saved)
	if saved_file != "":
		var f := FileAccess.open(SaveManager.SETTINGS_PATH, FileAccess.WRITE)
		f.store_string(saved_file)
	elif FileAccess.file_exists(SaveManager.SETTINGS_PATH):
		DirAccess.remove_absolute(SaveManager.SETTINGS_PATH)
	DisplayManager.set_gamma(int(saved["GammaIntensity"]))


func test_gamma_exponent_table() -> void:
	for row in [[-100, 0.5], [0, 1.0], [100, 2.0]]:
		check_near(DisplayManager.gamma_exponent(row[0]), row[1], 0.0001, "intensity %d" % row[0])


func test_default_settings_drop_dead_video_options() -> void:
	check(not SaveManager.DEFAULT_SETTINGS.has("ColorDepth"), "ColorDepth removed from the defaults")
	for k in ["Windowed", "VSync", "GammaIntensity", "XRes", "YRes", "WindowX", "WindowY", "WindowMaximized", DisplayManager.WIDE]:
		check(SaveManager.DEFAULT_SETTINGS.has(k), "%s kept" % k)
	check_eq(int(SaveManager.DEFAULT_SETTINGS[DisplayManager.WIDE]), 0, "4:3 letterbox by default")


## The 800x600 box is centred in whatever the expanding canvas grew to, never negative.
func test_box_offset_centres_the_box() -> void:
	for row in [[Vector2(800, 600), Vector2(0, 0)], [Vector2(1066, 600), Vector2(133, 0)], [Vector2(800, 1422), Vector2(0, 411)]]:
		check_eq(DisplayManager.box_offset(row[0]), row[1], "canvas %s" % row[0])


## Wider than 4:3: keep the vertical fov of the original 60-degree horizontal frame; taller:
## keep the horizontal one. At exactly 4:3 both projections are the same frame.
func test_camera_params_keep_the_4_3_frame() -> void:
	var fov_v := 2.0 * rad_to_deg(atan(tan(deg_to_rad(30.0)) * 3.0 / 4.0))
	check_near(fov_v, 46.83, 0.01, "vertical fov of a 60-degree 4:3 frame")
	for row in [[Vector2(1066, 600), Camera3D.KEEP_HEIGHT, fov_v], [Vector2(800, 600), Camera3D.KEEP_HEIGHT, fov_v], [Vector2(800, 1422), Camera3D.KEEP_WIDTH, 60.0]]:
		var params := DisplayManager.camera_params(row[0])
		check_eq(params["keep_aspect"], row[1], "canvas %s: keep_aspect" % row[0])
		check_near(params["fov"], row[2], 0.01, "canvas %s: fov" % row[0])


func test_widgets_per_platform() -> void:
	var table := {
		DisplayManager.PLATFORM_DESKTOP: {"vsync": true, "windowed": true, "caption": GameData.text(19)},
		DisplayManager.PLATFORM_WEB: {"vsync": false, "windowed": true, "caption": OptionsPanel.FULLSCREEN_CAPTION},
		DisplayManager.PLATFORM_MOBILE: {"vsync": false, "windowed": false, "caption": ""},
	}
	for platform in table:
		var want: Dictionary = table[platform]
		var panel := OptionsPanel.new(platform)
		check_eq(panel.vsync != null, want["vsync"], "%s: vsync widget" % platform)
		check_eq(panel.windowed != null, want["windowed"], "%s: mode widget" % platform)
		if panel.windowed != null:
			check_eq((panel.windowed.get_child(0) as BlitzText).text, want["caption"], "%s: mode caption" % platform)
		check(panel.gamma != null and panel.music != null and panel.sound != null and panel.player_name != null, "%s: common widgets" % platform)
		check_eq(panel.wide_radio.size(), 2, "%s: screen mode radios" % platform)
		panel.free()


func test_screen_mode_radio_round_trip() -> void:
	for start in [0, 1]:
		SaveManager.settings[DisplayManager.WIDE] = start
		var panel := OptionsPanel.new(DisplayManager.PLATFORM_MOBILE)
		check_eq([panel.wide_radio[0].button_pressed, panel.wide_radio[1].button_pressed], [start == 0, start == 1], "WideScreen=%d: exactly one radio pressed" % start)
		panel.free()
	SaveManager.settings[DisplayManager.WIDE] = 0
	SaveManager.settings["Windowed"] = DisplayManager.WINDOWED
	SaveManager.settings["VSync"] = 0
	var panel := OptionsPanel.new(DisplayManager.PLATFORM_DESKTOP)
	panel.wide_radio[1].button_pressed = true
	check(not panel.wide_radio[0].button_pressed, "pressing Wide releases 4:3")
	check(not panel.apply(), "screen mode alone is no video restart")
	check_eq(int(SaveManager.settings[DisplayManager.WIDE]), 1, "Wide stored")
	panel.wide_radio[0].button_pressed = true
	check(not panel.wide_radio[1].button_pressed, "pressing 4:3 releases Wide")
	panel.apply()
	check_eq(int(SaveManager.settings[DisplayManager.WIDE]), 0, "4:3 stored")
	# The name is stored without the blanks a (virtual) keyboard leaves around it.
	var saved_name := str(SaveManager.settings["PlayerName"])
	panel.player_name.text = "  Nomad  "
	panel.apply()
	check_eq(str(SaveManager.settings["PlayerName"]), "Nomad", "name trimmed on apply")
	check_eq(panel.player_name.text, "Nomad", "the box shows the trimmed name")
	SaveManager.settings["PlayerName"] = saved_name
	panel.free()


func test_apply_round_trip_desktop() -> void:
	SaveManager.settings["Windowed"] = DisplayManager.WINDOWED
	SaveManager.settings["VSync"] = 0
	SaveManager.settings["GammaIntensity"] = 0
	var panel := OptionsPanel.new(DisplayManager.PLATFORM_DESKTOP)
	check(not panel.apply(), "no change -> no video restart")
	panel.windowed.button_pressed = false
	panel.vsync.button_pressed = true
	panel.gamma.set_value_no_signal(panel.GAMMA_RANGE + 40.0)
	check(panel.apply(), "windowed / vsync changed -> video restart")
	check_eq(int(SaveManager.settings["Windowed"]), 1, "fullscreen stored")
	check_eq(int(SaveManager.settings["VSync"]), 1, "vsync stored")
	check_eq(int(SaveManager.settings["GammaIntensity"]), 40, "gamma stored")
	panel.free()


## The web toggle follows the live window (never fullscreen headless), not the saved value:
## a saved fullscreen that the browser dropped must be re-requested by a plain "ok".
func test_web_fullscreen_toggle_is_inverted_windowed() -> void:
	SaveManager.settings["Windowed"] = 1
	SaveManager.settings["VSync"] = 1
	var panel := OptionsPanel.new(DisplayManager.PLATFORM_WEB)
	check(not panel.windowed.button_pressed, "browser not fullscreen -> Fullscreen off despite the saved value")
	panel.windowed.button_pressed = true
	check(panel.apply(), "fullscreen requested -> video change")
	check_eq(int(SaveManager.settings["Windowed"]), 1, "Fullscreen on -> Windowed = 1")
	check_eq(int(SaveManager.settings["VSync"]), 1, "vsync untouched without its widget")
	panel.free()


## A Range emits `value_changed` only inside the tree, as in the game.
func test_gamma_slider_previews_live() -> void:
	SaveManager.settings["GammaIntensity"] = 0
	var panel := OptionsPanel.new(DisplayManager.PLATFORM_MOBILE)
	tree.root.add_child(panel)
	panel.gamma.value = panel.GAMMA_RANGE - 25.0
	check_eq(DisplayManager.gamma_intensity, -25, "slider drives the display gamma at once")
	tree.root.remove_child(panel)
	panel.free()


## The wide canvas follows the window aspect between the limits and is letterboxed beyond.
func test_canvas_for_clamps_to_the_aspect_limits() -> void:
	var free := DisplayManager.NO_ASPECT_LIMITS
	check_eq(DisplayManager.canvas_for(Vector2(1600, 900), free), Vector2(1067, 600), "16:9 window -> wider canvas")
	check_eq(DisplayManager.canvas_for(Vector2(900, 1200), free), Vector2(800, 1067), "3:4 window -> taller canvas")
	check_eq(DisplayManager.canvas_for(Vector2(1280, 960), free), Vector2(800, 600), "4:3 window -> the box")
	check_eq(DisplayManager.canvas_for(Vector2(1600, 900), Vector2(0.0, 1.64)), Vector2(984, 600), "capped: bars at the sides")
	check_eq(DisplayManager.canvas_for(Vector2(900, 1200), Vector2(1.2, INF)), Vector2(800, 667), "capped: bars at top and bottom")
	check_eq(DisplayManager.canvas_for(Vector2(1600, 900), Vector2(1.0, 1.0)), Vector2(800, 600), "limits never shrink the box")


## The 4:3 frame on the ground: the top edge 75.8 units ahead, the bottom 11.9, 43.2 wide
## either side at the top (camera 30 up, 45 degrees down, 60 degrees across).
func test_camera_frame_footprint() -> void:
	var f := CameraRig.frame(DisplayManager.BOX)
	check_near(f["far"], 75.8, 0.1, "far edge")
	check_near(f["near"], 11.9, 0.1, "near edge")
	check_near(f["half_w"], 43.2, 0.1, "half width at the far edge")
	var wide := CameraRig.frame(Vector2(1066, 600))
	check_near(wide["far"], f["far"], 0.001, "wider canvas keeps the vertical extent")
	check_near(wide["half_w"], f["half_w"] * 1066.0 / 800.0, 0.01, "half width grows with the aspect")
	var tall := CameraRig.frame(Vector2(800, 800))
	check(tall["far"] > f["far"] and tall["near"] < f["near"], "taller canvas sees further and nearer")
	check(tall["half_w"] > f["half_w"], "and its far edge, being further away, is wider too")


## Location 1 scrolls x 50..70, z -40..0: a 16:9 frame grows 14.4 units either side, more
## than the 20 units of scroll -- the rectangle collapses and the aspect is capped at ~1.64;
## location 2 (100 wide) keeps 71 units of scroll.
func test_scroll_bounds_narrow_with_the_canvas() -> void:
	var l1 := Rect2(50, -40, 20, 40)
	var wide := Vector2(1066, 600)
	var fitted := CameraRig.fit_bounds(l1, wide)
	check_near(fitted.position.x, 60.0, 0.001, "collapsed to the centre")
	check_eq(fitted.size.x, 0.0, "no horizontal scroll left")
	check_near(fitted.position.y, -40.0, 0.001, "z untouched by a wider canvas")
	var l2 := CameraRig.fit_bounds(Rect2(10, -100, 100, 100), wide)
	check_near(l2.position.x, 10.0 + 14.4, 0.05, "left edge moved in by the frame growth")
	check_near(l2.size.x, 100.0 - 2 * 14.4, 0.1, "scroll range narrowed on both sides")
	var limits := CameraRig.aspect_limits_for(l1)
	check_near(limits.y, 4.0 / 3.0 * (1.0 + 10.0 / 43.2), 0.01, "max aspect where the scroll collapses")
	check(limits.x < 4.0 / 3.0 and limits.x > 1.0, "min aspect between 1:1 and 4:3 (the x range collapses first)")
	var at_limit := CameraRig.fit_bounds(l1, DisplayManager.canvas_for(Vector2(1600, 900), limits))
	check(at_limit.size.x >= 0.0 and at_limit.size.x < 0.5, "the capped canvas just fits the scroll range")
	var tall := CameraRig.fit_bounds(l1, DisplayManager.canvas_for(Vector2(600, 1200), limits))
	check(tall.size.x >= 0.0 and tall.size.y >= 0.0 and minf(tall.size.x, tall.size.y) < 0.5, "the capped tall canvas just fits the scroll rectangle")
	check(CameraRig.fit_bounds(l1, DisplayManager.BOX) == l1, "4:3: the data rectangle as is")


## A location's rig hands its limits to the display and releases them on exit, but never
## those of a successor that replaced it (restart, quick load).
func test_camera_rig_owns_the_aspect_limits() -> void:
	var l1 := {"bounds": {"x_min": 50, "x_max": 70, "z_min": -40, "z_max": 0}}
	var l2 := {"bounds": {"x_min": 10, "x_max": 110, "z_min": -100, "z_max": 0}}
	var first := CameraRig.new()
	var second := CameraRig.new()
	tree.root.add_child(first)
	first.setup(l1)
	check_eq(DisplayManager.aspect_limits, CameraRig.aspect_limits_for(first.data_bounds), "limits of location 1 in effect")
	check(first.bounds == first.data_bounds, "headless canvas is 4:3: the data rectangle")
	tree.root.add_child(second)
	second.setup(l2)
	tree.root.remove_child(first)
	check_eq(DisplayManager.aspect_limits, CameraRig.aspect_limits_for(second.data_bounds), "the replaced rig leaves the successor's limits alone")
	tree.root.remove_child(second)
	check_eq(DisplayManager.aspect_limits, DisplayManager.NO_ASPECT_LIMITS, "last rig out releases the limits")
	first.free()
	second.free()


## Menu screens own the aspect range like a location's rig: the main menu allows a little
## slack, every other own-camera screen is strictly 4:3, overlays leave it alone.
func test_menu_screens_own_the_aspect_limits() -> void:
	var menu := MainMenu.new()
	tree.root.add_child(menu)
	check_eq(DisplayManager.aspect_limits, MainMenu.ASPECT_LIMITS, "main menu range")
	check(MainMenu.ASPECT_LIMITS.x < 4.0 / 3.0 and MainMenu.ASPECT_LIMITS.y > 4.0 / 3.0, "the range brackets 4:3")
	var scores := SimpleScreen.new()
	tree.root.add_child(scores)
	check_eq(DisplayManager.aspect_limits, ScreenBase.ASPECT_4_3, "a plain screen is strictly 4:3")
	tree.root.remove_child(menu)
	check_eq(DisplayManager.aspect_limits, ScreenBase.ASPECT_4_3, "the replaced menu leaves the successor's range")
	# `Main._switch` closes a screen deferred: its exit runs after the successor's ready,
	# and both may use the same range (titles -> high scores, both 4:3).
	var titles := SimpleScreen.new()
	tree.root.add_child(titles)
	tree.root.remove_child(scores)
	check_eq(DisplayManager.aspect_limits, ScreenBase.ASPECT_4_3, "same range: the late exit of the old screen does not release the new one's")
	tree.root.remove_child(titles)
	check_eq(DisplayManager.aspect_limits, DisplayManager.NO_ASPECT_LIMITS, "the owner's own exit releases")
	var location_like := SimpleScreen.new()
	tree.root.add_child(location_like)
	var overlay := SimpleScreen.new()
	overlay.overlay_camera = location_like.camera
	tree.root.add_child(overlay)
	tree.root.remove_child(overlay)
	check_eq(DisplayManager.aspect_limits, ScreenBase.ASPECT_4_3, "an overlay neither sets nor releases")
	tree.root.remove_child(location_like)
	check_eq(DisplayManager.aspect_limits, DisplayManager.NO_ASPECT_LIMITS, "last screen out releases")
	overlay.free()
	location_like.free()
	scores.free()
	titles.free()
	menu.free()


## A restored window goes back where it was, pulled inside the usable screen area; with no
## saved position (first run) or a window larger than the screen it is centred.
func test_window_position_restored_inside_the_screen() -> void:
	var usable := Rect2i(0, 25, 1920, 1055)  # a menu bar on top
	var size := Vector2i(1280, 960)
	check_eq(DisplayManager.window_position_for(Vector2i(300, 100), size, usable), Vector2i(300, 100), "saved position kept")
	check_eq(DisplayManager.window_position_for(Vector2i(1500, 900), size, usable), Vector2i(640, 120), "off-screen position pulled back")
	check_eq(DisplayManager.window_position_for(Vector2i(-50, 0), size, usable), Vector2i(0, 25), "never above the menu bar")
	check_eq(DisplayManager.window_position_for(DisplayManager.NO_POSITION, size, usable), Vector2i(320, 72), "no saved position -> centred")
	check_eq(DisplayManager.window_position_for(Vector2i(10, 10), Vector2i(2400, 1200), usable), Vector2i(-240, -47), "too large -> centred anyway")


## Safe-area insets come in window pixels; the letterbox bars already cover part of them
## and the rest scales down to canvas pixels. Anchored groups give way on their own side.
func test_safe_area_insets_and_anchor_shift() -> void:
	var wide := DisplayManager.safe_insets_for(Vector2(1600, 900), Vector2(1066.667, 600), Vector2(60, 0), Vector2(0, 45))
	check(wide[0].is_equal_approx(Vector2(40, 0)), "notch on the left: 60 window px = 40 canvas px")
	check(wide[1].is_equal_approx(Vector2(0, 30)), "gesture bar: 45 window px = 30 canvas px")
	var boxed := DisplayManager.safe_insets_for(Vector2(1600, 900), Vector2(800, 600), Vector2(60, 0), Vector2(0, 45))
	check_eq(boxed[0], Vector2.ZERO, "4:3 in a wide window: the bar covers the notch")
	check_eq(boxed[1], Vector2(0, 30), "the gesture bar still eats the bottom")
	var offset := Vector2(133, 0)
	check_eq(DisplayManager.anchor_shift_for(Vector2(-1, 1), offset, Vector2(40, 0), Vector2(0, 30)), Vector2(-93, -30), "bottom-left: in from the notch, up from the bar")
	check_eq(DisplayManager.anchor_shift_for(Vector2(1, -1), offset, Vector2(40, 0), Vector2(0, 30)), Vector2(133, 0), "top-right: nothing in its way")
	check_eq(DisplayManager.anchor_shift_for(Vector2.ZERO, offset, Vector2(40, 0), Vector2(0, 30)), Vector2.ZERO, "centre stays")
	check_eq(DisplayManager.anchor_shift_for(Vector2(-0.5, 0), offset, Vector2(40, 0), Vector2.ZERO), Vector2(-46.5, 0), "a blended strip vertex takes half the way")
