## UI state rules that live outside the scene tree: tutorial page 8 -> skills window,
## the in-game menu freezing the simulation, and the Eniretu-style tilt of the menu sheet.
extends SimTestCase


func test_tutorial_page8_next_requests_skills_window() -> void:
	var t := Tutorial.new(game)
	var got := {"requested": 0, "pages": []}
	t.skills_window_requested.connect(func(): got["requested"] += 1)
	t.page_changed.connect(func(p): got["pages"].append(p))
	t.start(Tutorial.PAGE_SKILLS)
	check_eq(got["requested"], 0, "window not opened while the page is shown")
	t.next()
	check_eq(got["requested"], 1, "Next on page 8 opens the skills window")
	check_eq(t.state, 0, "tutorial finished")
	check_eq(got["pages"], [Tutorial.PAGE_SKILLS, 0], "page shown then hidden")


## `_fhandleingamemenu` "help" reopens page 10 even after the "don't show" checkbox
## disabled the running tutorial.
func test_help_page_opens_after_tutorial_disabled() -> void:
	game.start_campaign(0)
	var t := Tutorial.new(game)
	var messages := []
	game.message.connect(func(text, _color, _ms): messages.append(text))
	t.start(Tutorial.PAGE_TOWERS)
	t.disable()
	check_eq(t.state, 0, "checkbox closes the running page")
	check_eq(messages.size(), 1, "location 1 warns that the monsters are coming")
	check_eq(game.ingame_time, Tutorial.LOCATION1_EXTRA_WAIT, "5 extra seconds before the raid")
	t.on_tower_placed()
	check_eq(t.is_open(), false, "gameplay events no longer advance the tutorial")
	t.start(Tutorial.PAGE_HELP)
	check_eq(t.is_open(), true, "Help page shows after disable")
	check_eq(t.state, Tutorial.PAGE_HELP, "state is the help page")
	game.ingame_time = 0.0
	t.next()
	check_eq(t.is_open(), false, "Next closes the help page")
	check_eq(messages.size(), 1, "closing Help adds no warning")
	check_eq(game.ingame_time, 0.0, "closing Help adds no wait")


## `_fnexttutorialpage`: Next walks pages 1-7 in order; leaving page 2 by Next hides the
## sheet with the "Your task" message, leaving it by the build button hides it silently.
func test_tutorial_location1_walkthrough() -> void:
	game.start_campaign(0)
	var t := Tutorial.new(game)
	var messages := []
	game.message.connect(func(text, _color, _ms): messages.append(text))
	t.start(Tutorial.PAGE_GOLD)
	t.next()
	check_eq(t.state, Tutorial.PAGE_TOWERS, "gold -> towers")
	t.next()
	check_eq(t.state, Tutorial.PAGE_HIDDEN_BUILD, "Next on towers waits for a build")
	check_eq(t.is_open(), false, "sheet hidden while building")
	check_eq(messages, [game.data.text(56)], "Next reminds the task")
	t.on_tower_placed()
	check_eq(t.state, Tutorial.PAGE_UPGRADE, "placed tower -> upgrade page")
	check_eq(t.is_open(), true, "sheet back")
	t.on_upgrade_pressed()
	check_eq(t.state, Tutorial.PAGE_SELL, "upgrade button steps to sell")
	check_eq(t.is_open(), false, "hidden until the upgrade finishes")
	t.on_upgrade_finished()
	check_eq(t.is_open(), true, "finished upgrade shows sell page")
	t.next()
	check_eq(t.state, Tutorial.PAGE_SPEED, "sell -> speed")
	t.next()
	check_eq(t.state, Tutorial.PAGE_MONSTERS, "speed -> monsters")
	t.next()
	check_eq(t.state, 0, "monsters -> done")
	check_eq(messages.size(), 2, "closing warns about the monsters")

	var t2 := Tutorial.new(game)
	messages.clear()
	t2.start(Tutorial.PAGE_TOWERS)
	t2.on_build_button()
	check_eq(t2.state, Tutorial.PAGE_HIDDEN_BUILD, "build button hides the towers page")
	check_eq(messages, [], "no reminder when the player builds")
	t2.on_tower_placed()
	t2.next()
	check_eq(t2.state, Tutorial.PAGE_SELL, "Next on upgrade page goes to sell")
	check_eq(t2.is_open(), true, "sell page stays visible")


func test_ingame_menu_freezes_simulation() -> void:
	game.start_campaign(0)
	game.enter_location(1)
	GameState.game = game
	GameState.sim_active = true
	GameState.ingame_menu_open = true
	var before := game.tick_count
	for i in 10:
		GameState._on_tick()
	check_eq(game.tick_count, before, "no simulation ticks while the menu is open")
	GameState.ingame_menu_open = false
	GameState._on_tick()
	check_eq(game.tick_count, before + 1, "ticks resume after closing")
	GameState.sim_active = false
	GameState.game = null


func test_ingame_menu_tilt_uses_integer_division() -> void:
	# RotateEntity(menu, -(my - h/2) \ (h/30), (mx - w/2) \ (w/40), 0) on an 800x600 screen.
	var h := 600
	var w := 800
	var pitch := Blitz.idiv(-(599 - (h >> 1)), Blitz.idiv(h, InGameMenu.TILT_PITCH_DIVISIONS))
	var yaw := Blitz.idiv(0 - (w >> 1), Blitz.idiv(w, InGameMenu.TILT_YAW_DIVISIONS))
	check_eq(pitch, -14, "bottom edge: -(299 \\ 20)")
	check_eq(yaw, -20, "left edge: -400 \\ 20")


func test_removal_signals_carry_valid_ids() -> void:
	# Views look up their nodes by id in the handler, so the handle must still be set.
	game.start_campaign(0)
	game.enter_location(1)
	var seen := {"enemy": -1, "bullet": -1}
	game.enemy_died.connect(func(e, _k): seen["enemy"] = e.id)
	game.bullet_removed.connect(func(b, _x): seen["bullet"] = b.id)
	var e := dummy_enemy(Vector3(60, 0, -30), false, 1.0)
	var t := game.build_tower(GameData.TOWER_LAND, Vector3(62, 0, -30))
	run_until(func(): return seen["bullet"] != -1 and seen["enemy"] != -1, 3000)
	check(seen["enemy"] > 0, "enemy_died carries the id")
	check(seen["bullet"] > 0, "bullet_removed carries the id")
	check(t != null, "tower built")


## Score screens: the survival sheet `Send.b3d` keeps restart / to menu, the campaign sheet
## `SendTD.b3d` has no items; the "send" / "don't send" planks exist in the models (they are
## hidden at runtime, the online submission is not ported).
func test_highscore_menu_models_carry_their_items() -> void:
	check_eq(SimpleScreen.highscore_items(false), [], "campaign screen has no items")
	for survival in [true, false]:
		var scene: Node = load(SimpleScreen.highscore_model(survival)).instantiate()
		for n in SimpleScreen.highscore_items(survival):
			check(scene.find_child(n, true, false) != null, "%s in %s" % [n, SimpleScreen.highscore_model(survival)])
		var planks := 0
		for n in SimpleScreen.SEND_PLANKS:
			if scene.find_child(n, true, false) != null:
				planks += 1
		check(planks >= 1, "a send plank to hide in %s" % SimpleScreen.highscore_model(survival))
		scene.free()



## `_fhandlegui`: the same fire "+" button buys levels 1-5 as id 7 and the Magic tower
## ignition (id 10) at level 5; "-" from level 6 removes the ignition first.
func test_fire_button_reaches_level_six() -> void:
	game.start_campaign(0)
	game.enter_location(1)
	game.experience = 100000
	for i in 6:
		var id := game.skills.button_id(SimSkills.Id.FIRE, false)
		check(game.skills.can_buy(id, game.experience), "press %d buys id %d" % [i + 1, id])
		game.skills.operate(game, id, false)
	check_eq(game.skills.fire_magic, 6, "six presses reach the ignition level")
	check_eq(game.skills.button_id(SimSkills.Id.FIRE, true), SimSkills.Id.FIRE6, "downgrade from 6 goes through id 10")
	check(not game.skills.can_buy(game.skills.button_id(SimSkills.Id.FIRE, false), game.experience), "nothing left to buy at 6")


## The web build has no "exit": the plank and its floating caption mesh go together and
## the item stops being pickable, in both sheets that carry the button.
func test_remove_item_hides_plank_and_caption() -> void:
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	for model in [[MainMenu.BUTTONS_MODEL, MainMenu.MAIN_ITEMS, MainMenu.EXIT_LABEL], [InGameMenu.MODEL, InGameMenu.ITEMS, InGameMenu.EXIT_LABEL]]:
		var m := MenuScene3D.new()
		m.load_scene(model[0], cam, model[1])
		var label := m.find_node(model[2])
		check(label != null, "%s carries the caption mesh" % model[0])
		m.remove_item("exit", model[2])
		check(not m.find_node("exit").visible, "%s: plank hidden" % model[0])
		check(label != null and not label.visible, "%s: caption hidden" % model[0])
		m.free()
	cam.queue_free()


## `Animate(playgame, one-shot, -0.5, seq)`: folding the difficulty sub-menu runs its
## own sequence back to the sequence's first frame, never through the earlier variants.
func test_submenu_folds_back_to_its_sequence_start() -> void:
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	var m := MenuScene3D.new()
	m.load_scene(MainMenu.PLAYGAME_MODEL, cam, MainMenu.SUB_ITEMS)
	m.enabled = false  # no picking: only the animation is under test
	var first := float(MainMenu.SUBMENU_SEQ_STRIDE * 2)
	var last := first + MainMenu.SUBMENU_SEQ_FRAMES
	m.animate_range(SimTower.ANIM_ONESHOT, -MainMenu.SUBMENU_SPEED, first, last)
	check_eq(m.anim_time, last, "closing starts at the sequence's last frame")
	var guard := 0
	while m.animating() and guard < 100:
		m.tick(Vector2.ZERO)
		guard += 1
	check_eq(m.anim_time, first, "stops at frame 8 * (seq - 1)")
	m.animate(SimTower.ANIM_ONESHOT, -1.0)
	check_eq(m.anim_time, m.clip_length, "plain animate() spans the whole clip again")
	cam.queue_free()


## `_floadmenu`: loading.b3d is in env.b3d's world and rides with the camera from its
## first flight frame, so its "Loading..." plank ends up in view in front of the camera
## (not 10 units ahead of the camera plus its world offset, which put it off screen).
func test_loading_sheet_keeps_its_world_pose_in_front_of_the_camera() -> void:
	var cam_scene: Node3D = load(MainMenu.CAMERA_MODEL).instantiate()
	tree.root.add_child(cam_scene)
	BlitzAnimator.seek(BlitzAnimator.find_player(cam_scene), 0.0)
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	cam.global_transform = (cam_scene.find_child("Camera01", true, false) as Node3D).global_transform * MainMenu.CAMERA_FIX
	var m := MenuScene3D.new()
	m.load_scene(MainMenu.LOADING_MODEL, cam, [])
	m.enabled = false
	MainMenu.place_loading(m, cam)
	m.seek(MainMenu.LOADING_FRAMES)
	var plank := m.find_node("loading")
	var p := cam.global_transform.affine_inverse() * plank.global_position
	check(p.z < 0.0, "the plank is in front of the camera")
	var half_h := tan(deg_to_rad(cam.fov) / 2.0) * -p.z
	check(absf(p.y) < half_h and absf(p.x) < half_h * 4.0 / 3.0, "the plank is inside the 4:3 view")
	var mat := BlitzAnimator.owned_material(plank as MeshInstance3D, 0) as BaseMaterial3D
	check(mat.no_depth_test, "EntityOrder -6: drawn without the z-buffer")
	check_eq(mat.render_priority, 6, "after the curtain (order -5)")
	cam_scene.queue_free()
	cam.queue_free()


## Detached location screen parts stop listening to the clock at once (quick load,
## restart): a tick between `remove_child` and the deferred free must not reach them.
func test_enemy_info_starts_below_the_time_slider() -> void:
	game.start_campaign(0)
	var hud := Hud.new()
	hud.game = game
	hud.data = game.data
	var e := dummy_enemy(Vector3.ZERO, false, 90.0, 6)
	var text := hud.enemy_info(e)
	check(text.begins_with("\n%s: 90\n" % game.data.text(69)), "an empty first line, then the life")
	e.life = 12345678.0
	check(hud.enemy_info(e).begins_with("\n%s:12345678\n" % game.data.text(69)), "no space before an 8-digit life")
	hud.free()


func test_location_view_and_hud_leave_the_ticker_on_exit() -> void:
	var view := LocationView.new()
	var hud := Hud.new()
	tree.root.add_child(view)
	tree.root.add_child(hud)
	check(Ticker.frame_ticked.is_connected(view._on_frame_ticked), "view follows the clock while in the tree")
	check(Ticker.frame_ticked.is_connected(hud._on_frame_ticked), "hud follows the clock while in the tree")
	tree.root.remove_child(view)
	tree.root.remove_child(hud)
	check(not Ticker.frame_ticked.is_connected(view._on_frame_ticked), "view disconnected on exit")
	check(not Ticker.frame_ticked.is_connected(hud._on_frame_ticked), "hud disconnected on exit")
	view.free()
	hud.free()


## Wide mode: every group keeps its corner / edge -- the posts part, the plain planks
## stretch between a post and the centred info panel, the tutorial pointer keeps its drops
## rigid and stretches only the line to the sheet; the 4:3 layout leaves the model as is.
func test_hud_groups_follow_their_anchors() -> void:
	game.start_campaign(0)
	game.enter_location(1)
	var cam := Camera3D.new()
	var hud := Hud.new()
	tree.root.add_child(cam)
	tree.root.add_child(hud)
	hud.setup(game, cam)
	var rest := {}  # MeshInstance3D -> [min x, max x, units per pixel]
	var by_name := {}  # first mesh of that name (Env.glb and tutorial.glb both have "gold")
	for e in hud.layout.entries:
		rest[e["mi"]] = _mesh_x_range(e["mi"]) + [e["upp"]]
		if not by_name.has(e["mi"].name):
			by_name[e["mi"].name] = e["mi"]
	var rule_count := HudLayout.ENV_RULES.size() + HudLayout.FACES_RULES.size() + HudLayout.TUTORIAL_RULES.size()
	check_eq(hud.layout.entries.size(), rule_count, "every rule found its mesh")
	for e in hud.layout.entries:
		# Every quad of the panel hangs 7 units in front of the camera (z 3.0 +- 0.04 of -10).
		check_near(e["upp"], HudLayout.units_per_pixel(7.0), 0.01 * HudLayout.units_per_pixel(7.0), "%s: depth" % e["mi"].name)
	var offset := Vector2(133, 40)
	DisplayManager.ui_offset = offset
	hud._apply_layout()
	check_eq(hud.anchor_roots[HudLayout.BOTTOM_LEFT].position, Vector2(-133, 40), "tower buttons at the bottom-left corner")
	check_eq(hud.anchor_roots[HudLayout.TOP_RIGHT].position, Vector2(133, -40), "inhabitants at the top-right corner")
	check_eq(hud.anchor_roots[HudLayout.BOTTOM_CENTRE].position, Vector2(0, 40), "slider centred at the bottom")
	var tol := 0.001
	var posts: MeshInstance3D = by_name["Plane10"]
	var post_x := _mesh_x_range(posts)
	check_near(post_x[0], rest[posts][0] - offset.x * rest[posts][2], tol, "left post at the left edge")
	check_near(post_x[1], rest[posts][1] + offset.x * rest[posts][2], tol, "right post at the right edge")
	var leftside: MeshInstance3D = by_name["leftside"]
	var left := _mesh_x_range(leftside)
	check_near(left[0], rest[leftside][0] - offset.x * rest[leftside][2], tol, "left plank starts at the post")
	check_near(left[1], rest[leftside][1], tol, "left plank still ends at the info panel")
	var rightside: MeshInstance3D = by_name["rightside"]
	var right := _mesh_x_range(rightside)
	check_near(right[0], rest[rightside][0], tol, "right plank still starts at the info panel")
	check_near(right[1], rest[rightside][1] + offset.x * rest[rightside][2], tol, "right plank ends at the right post")
	var info := _mesh_x_range(by_name["infopanel"])
	check_near(info[0], rest[by_name["infopanel"]][0], tol, "info panel stays centred")
	var create: MeshInstance3D = by_name["create"]
	var create_rest: Array = rest[create]
	var xs := _mesh_x_range(create)
	check_near(xs[0], create_rest[0] - offset.x * create_rest[2], tol, "pointer drops moved with the tower buttons")
	check_near(xs[1], create_rest[1], tol, "pointer end at the sheet stayed")
	var arrays := create.mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var drop_span := [INF, -INF]
	for i in verts.size():
		if uvs[i].x <= 0.25:
			drop_span[0] = minf(drop_span[0], verts[i].x)
			drop_span[1] = maxf(drop_span[1], verts[i].x)
	check_near(drop_span[1] - drop_span[0], (0.25 - 0.015213) / (0.373068 - 0.015213) * (create_rest[1] - create_rest[0]), 0.01, "the rigid part of the pointer kept its width")
	# A phone notch on the left and a gesture bar below: the corner groups give way.
	DisplayManager.safe_min = Vector2(40, 0)
	DisplayManager.safe_max = Vector2(0, 30)
	hud._apply_layout()
	check_eq(hud.anchor_roots[HudLayout.BOTTOM_LEFT].position, Vector2(-133 + 40, 40 - 30), "tower buttons inside the safe area")
	check_eq(hud.anchor_roots[HudLayout.TOP_RIGHT].position, Vector2(133, -40), "top-right untouched")
	check_near(_mesh_x_range(posts)[0], rest[posts][0] - (offset.x - 40) * rest[posts][2], tol, "left post inside the notch")
	DisplayManager.safe_min = Vector2.ZERO
	DisplayManager.safe_max = Vector2.ZERO
	# Page 4 (frame 3) shows the upgrade pointer and parks the others below the frame.
	hud.show_tutorial(Tutorial.PAGE_UPGRADE)
	check(by_name["upgrade"].visible, "upgrade pointer shown on its page")
	check(not create.visible, "parked create pointer hidden (it would show in a tall canvas)")
	check(not by_name["speed"].visible, "parked speed pointer hidden")
	hud.show_tutorial(Tutorial.PAGE_TOWERS)
	check(create.visible and not by_name["upgrade"].visible, "page 2 swaps the pointers back")
	hud.show_tutorial(0)
	DisplayManager.ui_offset = Vector2.ZERO
	hud._apply_layout()
	for mi in rest:
		var now := _mesh_x_range(mi)
		check_near(now[0], rest[mi][0], tol, "4:3: %s min x at rest" % mi.name)
		check_near(now[1], rest[mi][1], tol, "4:3: %s max x at rest" % mi.name)
	tree.root.remove_child(hud)
	tree.root.remove_child(cam)
	hud.free()
	cam.free()


## A two-line message takes two slots: the next message stacks above it, not over its
## second line.
func test_hud_messages_stack_by_line_count() -> void:
	game.start_campaign(0)
	game.enter_location(1)
	var cam := Camera3D.new()
	var hud := Hud.new()
	tree.root.add_child(cam)
	tree.root.add_child(hud)
	hud.setup(game, cam)
	hud.add_message("Well done!\nKeep it going!", SimGame.MSG_WHITE, 5000)
	hud.add_message("You have received 60 gold.", SimGame.MSG_GOLD, 5000)
	hud.add_message("15 of your inhabitants were killed", SimGame.MSG_WHITE, 5000)
	hud._update_messages(1)
	var ys := []
	for m in hud.messages:  # newest first
		ys.append(m["node"].position.y)
	check_eq(ys[0], float(Hud.MESSAGE_Y), "newest message on the bottom slot")
	check_eq(ys[1], float(Hud.MESSAGE_Y - Hud.MESSAGE_STEP), "one-line message one slot up")
	check_eq(ys[2], float(Hud.MESSAGE_Y - 3 * Hud.MESSAGE_STEP), "two-line message starts two slots up")
	tree.root.remove_child(hud)
	tree.root.remove_child(cam)
	hud.free()
	cam.free()


## [min, max] of the mesh's vertex x in the model's space (the node's x plus local x).
func _mesh_x_range(mi: MeshInstance3D) -> Array:
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	for v in verts:
		var w := mi.transform * v
		lo = minf(lo, w.x)
		hi = maxf(hi, w.x)
	return [lo, hi]


## `_fshowmenu` state 1: "start" unfolds the difficulty sheet once; any other main button
## folds it and acts, so the main menu never gets stuck under the sub-menu.
func test_main_buttons_fold_the_open_submenu() -> void:
	var menu := MainMenu.new()
	tree.root.add_child(menu)
	menu._on_item("start")
	check(menu.sub_open, "Play game opens the sub-menu")
	check(menu.playgame.animating() and menu.playgame.anim_speed > 0.0, "sheet flies in")
	menu._on_item("start")
	check(menu.sub_open, "a second Play game is ignored while open")
	menu._on_item("settings")
	check(not menu.sub_open, "Settings folds the sub-menu")
	check(menu.playgame.anim_speed < 0.0, "sheet flies back")
	check_eq(menu.state, "settings", "and opens the settings")
	menu._on_item("ok")
	check_eq(menu.state, "main", "back to the main menu")
	menu._on_item("start")
	menu._on_item("new")
	check(not menu.sub_open and menu.state == "loading", "a difficulty pick starts loading")
	check(menu.playgame.anim_speed > 0.0, "the sheet is not folded under the loading screen")
	menu.close()


## A tutorial page or the skills window open at restart / quick load must not freeze the
## next location (`GameState.tutorial_open` zeroes the spawn timer every tick).
func test_location_switch_resets_pause_flags() -> void:
	var main: Node = load("res://src/scenes/Main.gd").new()
	tree.root.add_child(main)
	main.game = GameState.new_campaign(0, 1)
	GameState.tutorial_open = true
	GameState.skills_window_open = true
	main._show_location(1, false, 0)
	check(not GameState.tutorial_open, "tutorial flag reset on entering a location")
	check(not GameState.skills_window_open, "skills window flag reset on entering a location")
	main._close_current()
	GameState.pause()
	GameState.sim_active = false
	GameState.game = null
	main.free()


## Touch panning moves the pivot and the camera together and stops at the scroll bounds;
## the ground point under a viewport position lies on y = 0 in front of the camera.
func test_camera_rig_pan_keeps_pivot_in_bounds() -> void:
	var rig := CameraRig.new()
	tree.root.add_child(rig)
	rig.setup(data.location(1))
	var pivot := rig.pivot
	var cam := rig.camera.position
	rig.pan(Vector3(3.0, 0.0, -2.0))
	check(rig.pivot.is_equal_approx(pivot + Vector3(3.0, 0.0, -2.0)), "pivot moved by the delta")
	check(rig.camera.position.is_equal_approx(cam + Vector3(3.0, 0.0, -2.0)), "camera moved with the pivot")
	rig.pan(Vector3(1000.0, 0.0, 1000.0))
	check_eq(rig.pivot.x, rig.bounds.end.x, "pivot clamped at the right edge")
	check_eq(rig.pivot.z, rig.bounds.end.y, "pivot clamped at the near edge")
	check(rig.camera.position.is_equal_approx(rig.pivot), "camera followed only the applied delta")
	var ground := rig.ground_point(DisplayManager.BOX / 2.0)
	check(is_zero_approx(ground.y), "ground point on y = 0")
	check(ground.z < rig.pivot.z, "the screen centre is ahead of the camera (looking down at 45 degrees)")
	tree.root.remove_child(rig)
	rig.free()


## Android Back (`NOTIFICATION_WM_GO_BACK_REQUEST`): in a location it opens the in-game
## menu, closes it again, and closes the skills window first; the main menu quits (not
## exercised here).
func test_back_request_toggles_the_ingame_menu() -> void:
	var main: Node = load("res://src/scenes/Main.gd").new()
	tree.root.add_child(main)
	main.game = GameState.new_campaign(0, 1)
	main.game.enter_location(2)  # the skills window exists from location 2 on
	main._show_location(2, false, 0)
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)  # Android delivers it twice
	check(main.ingame_menu != null, "Back opens the in-game menu (once per frame)")
	check(GameState.ingame_menu_open, "flag set")
	main.back_frame = -1  # next frame
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(main.ingame_menu == null, "Back closes it again")
	check(not GameState.ingame_menu_open, "flag cleared")
	main.current._toggle_skills(true)
	main.back_frame = -1
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not GameState.skills_window_open, "Back closes the skills window")
	check(main.ingame_menu == null, "...without opening the menu")
	main._close_current()
	GameState.pause()
	GameState.sim_active = false
	GameState.game = null
	main.free()
