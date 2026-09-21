## The 3D location: converted scene, camera rig, picking, and views mirroring the
## simulation objects. Everything visual is synced once per rendered frame
## (Ticker.frame_ticked) to the state the simulation reached in that frame's ticks.
class_name LocationView
extends Node3D

signal tower_placed(tower: SimTower)
signal placement_cancelled
signal selection_changed

const DEATH_MODEL := "res://assets/models/Towers/death.glb"
const DEATH2_MODEL := "res://assets/models/Towers/death2.glb"
const BOMB_MODEL := "res://assets/models/Towers/military3.glb"
const HERE_MODEL := "res://assets/models/Towers/here.glb"
const BALLOON_MODEL := "res://assets/models/Towers/Balloon.glb"
const WATER_TEXTURE := "res://assets/textures/Water.jpg"
const BORDER_TEXTURE := "res://assets/textures/border.jpg"
const WATER_FRAME := 64
const WATER_FRAMES := 63  # frames 0..62 are shown
const BORDER_FRAME := 128
const BORDER_FRAMES := 8
const BORDER_STEP := 0.5
const ONE_SHOT_SPEED := 0.2
## `_fupdatedeathanims`: `EntityAlpha (30 - AnimTime) / 10` - the last 10 frames fade out.
const DEATH_FADE_FRAMES := 10.0
const EXPLOSION_SCALE_FACTOR := 0.7
const EXPLOSION_MIN_SCALE := 0.1
const BOMB_BLAST_SCALE := 1.2
const BALLOON_ANIM_SPEED := 0.03
const SHADOW_MODEL := "res://assets/models/Towers/shadow.glb"
const BALLOON_SHADOW_HEIGHT := 0.01
const BALLOON_YAW_MIN_TICKS := 2000.0
const BALLOON_YAW_MAX_TICKS := 5000.0
const HERE_ANIM_SPEED := 0.5
const SCENE_ANIM_SPEED := 1.0
const BIRDPATH_MODEL := "res://assets/models/Location1/birdpath1.glb"
const EAGLE_MODEL := "res://assets/models/Additional/eagle.glb"
const EAGLE_SCREAM_MS := 300000
const DECOR_ANIM_SPEED := 0.1
## Tower types whose texture scroll is driven by the hidden level-0 preview tower
## (`_floadgraphics`: `_fcreatetower(4/5, 0, hidden)`, the first of its type in the list).
const PREVIEW_TOWER_TYPES := [GameData.TOWER_ICEROCK, GameData.TOWER_FLAME]
const EAGLE_FRAMES := 51
const CLOCK_SECOND_STEP := 1.0 / 60.0
const CLOCK_MINUTE_STEP := 1.0 / 3600.0
## Touch: a finger that travels this far (viewport px) pans the map instead of clicking;
## a still finger held this long acts as the right button (balloon, cancel, deselect).
const TOUCH_DRAG_THRESHOLD := 10.0
const TOUCH_LONG_PRESS_MS := 500

var game: SimGame
var data: Node
var location_number := 1
var location_info: Dictionary = {}
var scene_root: Node3D
var scene_player: AnimationPlayer
var scene_time := 0.0
## Idle animation time of the hidden preview towers (loop of sequence 1, 0.1 per tick).
var preview_anim_time := 0.0
var camera_rig: CameraRig
var picker: Picker
var entities: Node3D
var enemy_views: Dictionary = {}  # id -> EnemyView
var tower_views: Dictionary = {}
var bullet_views: Dictionary = {}
var one_shots: Array[OneShotView] = []
var river_anim: UvAtlasAnimator
var border_anim: UvAtlasAnimator
var river_frame := 0
var border_frame := 0.0
var death_mode := 0
var place_marker: PlaceMarkerView = null
var placing_type := 0
## Asked at every click whether the pointer is over the HUD (`Hud.is_mouse_over_gui`).
var gui_hit_test: Callable = Callable()
var balloon_view: Node3D = null
var balloon_player: AnimationPlayer = null
var balloon_time := 0.0
var balloon_rng := RandomNumberGenerator.new()
var balloon_yaw_from := 0.0
var balloon_yaw_to := 0.0
var balloon_yaw_duration := 0
var balloon_yaw_elapsed := 0
var here_marker: Node3D = null
var here_player: AnimationPlayer = null
var here_time := -1.0
var bomb_views: Dictionary = {}
# Decorations (`_fdecoratelocation` / `_fhandledecorates`): clock hands on location 1,
# the eagle circling on location 2.
var clock_hands: Array = []
var clock_hours := 0.0
var clock_minutes := 0.0
var clock_seconds := 0.0
var birdpath: Node3D = null
var birdpath_player: AnimationPlayer = null
var birdpath_time := 0.0
var eagle_mesh: MeshInstance3D = null
var eagle_time := 0.0
var eagle_timer_ms := 0
## Arrival log for the debug overlay: enemy id -> tick when it reached the castle.
var arrivals: Dictionary = {}
var spawn_ticks: Dictionary = {}
# The first finger on the map (see `_unhandled_input` / `_input`).
var touch_active := false
var touch_dragging := false
var touch_start := Vector2.ZERO
var touch_last := Vector2.ZERO
var touch_time_ms := 0


func _ready() -> void:
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	picker = Picker.new()
	picker.name = "Picker"
	add_child(picker)
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)


## The clock is followed only while in the tree (see `_exit_tree`).
func _enter_tree() -> void:
	Ticker.frame_ticked.connect(_on_frame_ticked)


## Load location `L` for `g` (already positioned on that location by the simulation).
func load_location(g: SimGame, L: int) -> void:
	game = g
	data = g.data
	location_number = L
	location_info = data.location(L)
	_clear_views()
	if scene_root != null:
		scene_root.queue_free()
	scene_root = ModelWarmup.pinned_scene(location_info["scene"]).instantiate()
	scene_root.name = "Scene"
	add_child(scene_root)
	move_child(scene_root, 0)
	BlitzAnimator.hide_helpers(scene_root)
	scene_player = BlitzAnimator.find_player(scene_root)
	scene_time = 0.0
	picker.build_zones(scene_root)
	_setup_lights()
	_setup_atlases()
	camera_rig.setup(location_info)
	_setup_decorations()
	_connect_game()
	for t in game.towers:
		_add_tower(t)
	for e in game.enemies:
		_add_enemy(e)
	if bool(location_info["balloon"]) and not game.survival_mode:
		game.enable_balloon()
		_setup_balloon()
	_warmup()


## Load, pin and draw once (off screen) every model the location can spawn that the map
## screen did not warm already (see ModelWarmup). The loading and pinning is over when
## this returns; the drawing runs on its own under the loading sheet.
func _warmup() -> void:
	ModelWarmup.warm(get_tree().root, data, game, location_number)


func _connect_game() -> void:
	if game.enemy_spawned.is_connected(_add_enemy):
		return
	game.enemy_spawned.connect(_add_enemy)
	game.enemy_died.connect(_on_enemy_died)
	game.tower_built.connect(_add_tower)
	game.tower_removed.connect(_on_tower_removed)
	game.bullet_created.connect(_add_bullet)
	game.bullet_removed.connect(_on_bullet_removed)
	game.bomb_dropped.connect(_on_bomb_dropped)
	game.bomb_exploded.connect(_on_bomb_exploded)
	game.enemy_reached_end.connect(_on_enemy_reached_end)


## A view taken out of the tree (quick load, restart) must not mirror the towers that
## `SaveGame.restore` rebuilds for its successor.
func _exit_tree() -> void:
	if Ticker.frame_ticked.is_connected(_on_frame_ticked):
		Ticker.frame_ticked.disconnect(_on_frame_ticked)
	if game == null or not game.enemy_spawned.is_connected(_add_enemy):
		return
	game.enemy_spawned.disconnect(_add_enemy)
	game.enemy_died.disconnect(_on_enemy_died)
	game.tower_built.disconnect(_add_tower)
	game.tower_removed.disconnect(_on_tower_removed)
	game.bullet_created.disconnect(_add_bullet)
	game.bullet_removed.disconnect(_on_bullet_removed)
	game.bomb_dropped.disconnect(_on_bomb_dropped)
	game.bomb_exploded.disconnect(_on_bomb_exploded)
	game.enemy_reached_end.disconnect(_on_enemy_reached_end)


func _on_enemy_reached_end(e: SimEnemy, _lost: int) -> void:
	arrivals[e.id] = game.tick_count


func _setup_lights() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	var cc: Array = location_info["clear_color"]
	e.background_color = Color(cc[0] / 255.0, cc[1] / 255.0, cc[2] / 255.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# B3D Extensions store RGB in the node position; the converter mirrored its z.
	var ambient: Node3D = scene_root.find_child("B3DEXT_AMBIENT", true, false)
	var a := Vector3(0.5, 0.5, 0.5)
	if ambient != null:
		a = Blitz.to_godot(ambient.position)
	e.ambient_light_color = Color(a.x, a.y, a.z)
	e.ambient_light_energy = 1.0
	env.environment = e
	scene_root.add_child(env)
	var dirlight: Node3D = scene_root.find_child("B3DEXT_DIRLIGHT", true, false)
	var light := DirectionalLight3D.new()
	if dirlight != null and dirlight.get_parent() is Node3D:
		# `_fext_initlight`: CreateLight(parent) + TurnEntity 90,0,0 — the light shines along
		# the parent's local -Y, like the B3D Extensions camera (see MainMenu.CAMERA_FIX).
		var holder := dirlight.get_parent() as Node3D
		holder.add_child(light)
		light.transform = MainMenu.CAMERA_FIX
		var c := Blitz.to_godot(dirlight.position)
		light.light_color = Color(c.x, c.y, c.z)
	else:
		scene_root.add_child(light)
		light.rotation_degrees = Vector3(-60, 30, 0)
	light.shadow_enabled = false


func _setup_atlases() -> void:
	river_anim = _atlas_for("river", WATER_TEXTURE, WATER_FRAME, WATER_FRAME)
	border_anim = _atlas_for("border", BORDER_TEXTURE, BORDER_FRAME, BORDER_FRAME)


func _atlas_for(node_name: String, texture_path: String, fw: int, fh: int) -> UvAtlasAnimator:
	# Location5's `border` has a single vertex and no faces, so it imports as a plain Node3D.
	var mi := scene_root.find_child(node_name, true, false) as MeshInstance3D
	if mi == null or not ResourceLoader.exists(texture_path):
		return null
	var m := mi.get_active_material(0)
	if not BlitzAnimator._is_blitz_material(m):
		return null
	var own := m.duplicate() as Material
	mi.set_surface_override_material(0, own)
	return UvAtlasAnimator.new(own, load(texture_path), fw, fh)


func _setup_balloon() -> void:
	if balloon_view != null:
		return
	balloon_view = load(BALLOON_MODEL).instantiate()
	BlitzAnimator.hide_helpers(balloon_view)
	entities.add_child(balloon_view)
	balloon_player = BlitzAnimator.find_player(balloon_view)
	if bool(location_info["shadows"]):
		# `_fcreateballoon`: a copy of shadow.b3d parented to the balloon at ground level.
		var shadow: Node3D = load(SHADOW_MODEL).instantiate()
		BlitzAnimator.hide_helpers(shadow)
		balloon_view.add_child(shadow)
		shadow.position = Vector3(0, -SimBalloon.HEIGHT + BALLOON_SHADOW_HEIGHT, 0)
		shadow.name = "BalloonShadow"
	balloon_rng.randomize()
	here_marker = load(HERE_MODEL).instantiate()
	BlitzAnimator.hide_helpers(here_marker)
	entities.add_child(here_marker)
	here_marker.visible = false
	here_player = BlitzAnimator.find_player(here_marker)


func _setup_decorations() -> void:
	clock_hands.clear()
	birdpath = null
	eagle_mesh = null
	match str(location_info.get("decoration", "")):
		"clock":
			var now := Time.get_time_dict_from_system()
			clock_hours = float(now["hour"] % 12)
			clock_minutes = float(now["minute"])
			clock_seconds = float(now["second"])
			# `_fdecoratelocation`: little_arrow = hours, big_arrow = minutes.
			for n in ["little_arrow", "big_arrow", "second_arrow"]:
				clock_hands.append(scene_root.find_child(n, true, false))
		"eagle":
			if not ResourceLoader.exists(BIRDPATH_MODEL) or not ResourceLoader.exists(EAGLE_MODEL):
				return
			birdpath = load(BIRDPATH_MODEL).instantiate()
			BlitzAnimator.hide_helpers(birdpath)
			scene_root.add_child(birdpath)
			birdpath_player = BlitzAnimator.find_player(birdpath)
			var piv: Node3D = birdpath.find_child("piv", true, false)
			if piv == null:
				return
			var eagle: Node3D = load(EAGLE_MODEL).instantiate()
			piv.add_child(eagle)
			eagle.rotation_degrees.y = 180.0
			eagle_mesh = BlitzAnimator.find_mesh(eagle)
			eagle_timer_ms = Time.get_ticks_msec()


func _tick_decorations(ticks: int) -> void:
	if not clock_hands.is_empty():
		clock_seconds += CLOCK_SECOND_STEP * ticks
		clock_minutes += CLOCK_MINUTE_STEP * ticks
		if clock_seconds >= 60.0:
			clock_seconds -= 60.0
		if clock_minutes >= 60.0:
			clock_minutes -= 60.0
			clock_hours = fmod(clock_hours + 1.0, 12.0)
		var angles := [-clock_hours * 30.0, -clock_minutes * 6.0, -clock_seconds * 6.0]
		for i in clock_hands.size():
			var hand: Node3D = clock_hands[i]
			if hand != null:
				# Blitz RotateEntity(0, 0, roll): roll keeps its sign in Godot (geom.h
				# rollMatrix), so -h*30 turns the hands clockwise as seen from the camera.
				hand.rotation_degrees = Vector3(0, 0, angles[i])
	if birdpath_player != null:
		var length := birdpath_player.get_animation(BlitzAnimator.B3D_ANIMATION).length
		birdpath_time = fmod(birdpath_time + DECOR_ANIM_SPEED * ticks, maxf(length, 1.0))
		BlitzAnimator.seek(birdpath_player, birdpath_time)
		eagle_time = fmod(eagle_time + DECOR_ANIM_SPEED * ticks, float(EAGLE_FRAMES - 1))
		BlitzAnimator.md2_frame(eagle_mesh, eagle_time, 0, EAGLE_FRAMES - 1)
		if Time.get_ticks_msec() > eagle_timer_ms + EAGLE_SCREAM_MS:
			game.sound.emit("eagle", Vector3.ZERO)  # file missing in the original distribution
			eagle_timer_ms = Time.get_ticks_msec()


# ---------------------------------------------------------------- views

func _clear_views() -> void:
	for v in enemy_views.values():
		v.queue_free()
	for v in tower_views.values():
		v.queue_free()
	for v in bullet_views.values():
		v.queue_free()
	for v in bomb_views.values():
		v.queue_free()
	for o in one_shots:
		o.queue_free()
	enemy_views.clear()
	tower_views.clear()
	bullet_views.clear()
	bomb_views.clear()
	one_shots.clear()
	arrivals.clear()
	spawn_ticks.clear()


func _add_enemy(e: SimEnemy) -> void:
	var v := EnemyView.new()
	entities.add_child(v)
	v.setup(e, data, bool(location_info["shadows"]))
	enemy_views[e.id] = v
	spawn_ticks[e.id] = game.tick_count


func _on_enemy_died(e: SimEnemy, killed: bool) -> void:
	var v: EnemyView = enemy_views.get(e.id)
	if v == null:
		return
	enemy_views.erase(e.id)
	if killed:
		# The view may lag the simulation by the ticks of this frame: take the sim position.
		_one_shot(DEATH2_MODEL if death_mode == 1 else DEATH_MODEL, e.position, 1.0, ONE_SHOT_SPEED, DEATH_FADE_FRAMES)
	v.queue_free()
	selection_changed.emit()


func _add_tower(t: SimTower) -> void:
	var v := TowerView.new()
	entities.add_child(v)
	v.setup(t, data, location_info, location_number)
	tower_views[t.id] = v


func _on_tower_removed(t: SimTower) -> void:
	var v: TowerView = tower_views.get(t.id)
	if v != null:
		tower_views.erase(t.id)
		v.queue_free()
	selection_changed.emit()


func _add_bullet(b: SimBullet) -> void:
	var v := BulletView.new()
	entities.add_child(v)
	v.setup(b)
	bullet_views[b.id] = v


func _on_bullet_removed(b: SimBullet, exploded: bool) -> void:
	var v: BulletView = bullet_views.get(b.id)
	if v == null:
		return
	bullet_views.erase(b.id)
	if exploded and b.tower != null and b.tower.type != GameData.TOWER_FLAME:
		var s := maxf(EXPLOSION_MIN_SCALE, float(b.tower.level) / float(maxi(b.tower.max_upgrades, 1)) * EXPLOSION_SCALE_FACTOR)
		_one_shot(data.tower_model(b.tower.type)["effect_model"], b.position, s, ONE_SHOT_SPEED)
	v.queue_free()


func _on_bomb_dropped(bomb: SimBomb) -> void:
	var v := Node3D.new()
	var model: Node3D = load(BOMB_MODEL).instantiate()
	BlitzAnimator.hide_helpers(model)
	v.add_child(model)
	entities.add_child(v)
	v.position = bomb.position
	bomb_views[bomb.id] = v


func _on_bomb_exploded(bomb: SimBomb) -> void:
	var v: Node3D = bomb_views.get(bomb.id)
	if v != null:
		bomb_views.erase(bomb.id)
		v.queue_free()
	_one_shot(data.tower_model(GameData.TOWER_LAND)["effect_model"], bomb.position, BOMB_BLAST_SCALE, ONE_SHOT_SPEED)


func _one_shot(model_path: String, at: Vector3, uniform_scale: float, speed: float, fade_frames := 0.0) -> void:
	if not ResourceLoader.exists(model_path):
		return
	var o := OneShotView.new()
	entities.add_child(o)
	o.setup(model_path, at, uniform_scale, speed, fade_frames)
	one_shots.append(o)


# ---------------------------------------------------------------- per frame

## `ticks` logic ticks ran since the last frame: every view is synced once to the current
## simulation state; the view's own animation clocks advance by `ticks` steps.
func _on_frame_ticked(ticks: int) -> void:
	if game == null or scene_root == null:
		return
	var mouse := get_viewport().get_mouse_position()
	camera_rig.tick(mouse, get_viewport().get_visible_rect().size, ticks)
	var cam := camera_rig.camera
	for v in enemy_views.values():
		v.sync(cam, game.show_units_life, ticks)
	preview_anim_time = fmod(preview_anim_time + SimTower.ANIM_SPEED * ticks, float(SimTower.SEQ_FRAMES))
	var uv_driver := {}  # type -> frame of the first tower of that type (`_fupdateextanims`)
	for t in PREVIEW_TOWER_TYPES:
		uv_driver[t] = preview_anim_time
	for t in game.towers:
		if not uv_driver.has(t.type):
			uv_driver[t.type] = t.model_frame()
	for v in tower_views.values():
		v.sync(uv_driver.get(v.tower.type, -1.0), ticks)
	for v in bullet_views.values():
		v.sync()
	if not bomb_views.is_empty():
		var bombs := {}  # id -> SimBomb
		for b in game.bombs:
			bombs[b.id] = b
		for id in bomb_views:
			if bombs.has(id):
				bomb_views[id].position = bombs[id].position
	for i in range(one_shots.size() - 1, -1, -1):
		var o := one_shots[i]
		if o.tick(ticks):
			one_shots.remove_at(i)
			o.queue_free()
	_tick_location_animation(ticks)
	_tick_decorations(ticks)
	_tick_balloon(ticks)
	_tick_placement(mouse)


## `_fupdatelocation` + `Animate(scene, 1, 1, 0)`: river/border atlases and scene keys.
func _tick_location_animation(ticks: int) -> void:
	if river_anim != null:
		river_frame = (river_frame + ticks) % WATER_FRAMES
		river_anim.set_frame(river_frame)
	if border_anim != null:
		border_frame = fmod(border_frame + BORDER_STEP * ticks, float(BORDER_FRAMES))
		border_anim.set_frame(int(floorf(border_frame)))
	if scene_player != null:
		var length := scene_player.get_animation(BlitzAnimator.B3D_ANIMATION).length
		if length > 0.0:
			scene_time = fmod(scene_time + SCENE_ANIM_SPEED * ticks, length)
			BlitzAnimator.seek(scene_player, scene_time)


## `_fhandleballoons`: when no rotation tween runs, start a new one — yaw += Rnd(-360, 360)
## over Round(Rnd(2000, 5000)) ticks with the cosine easing of `_fflux_rotate` (decorative;
## uses an own RNG so the simulation stream is untouched). Stepped `ticks` times so the
## tween boundaries (and the RNG draws) fall on the same ticks whatever the frame rate.
func _tick_balloon_yaw(ticks: int) -> void:
	var yaw := balloon_view.rotation_degrees.y
	for i in ticks:
		if balloon_yaw_elapsed >= balloon_yaw_duration:
			balloon_yaw_from = balloon_yaw_to
			balloon_yaw_to = balloon_yaw_from + balloon_rng.randf_range(-360.0, 360.0)
			balloon_yaw_duration = Blitz.round_int(balloon_rng.randf_range(BALLOON_YAW_MIN_TICKS, BALLOON_YAW_MAX_TICKS))
			balloon_yaw_elapsed = 0
		balloon_yaw_elapsed += 1
		var t := float(balloon_yaw_elapsed) / float(balloon_yaw_duration)
		var eased := (1.0 - cos(clampf(t, 0.0, 1.0) * PI)) / 2.0
		yaw = lerpf(balloon_yaw_from, balloon_yaw_to, eased)
	balloon_view.rotation_degrees.y = yaw


func _tick_balloon(ticks: int) -> void:
	if balloon_view == null or game.balloon == null:
		return
	balloon_view.visible = game.balloon.enabled
	balloon_view.position = game.balloon.position
	_tick_balloon_yaw(ticks)
	if balloon_player != null:
		var length := balloon_player.get_animation(BlitzAnimator.B3D_ANIMATION).length
		balloon_time = fmod(balloon_time + BALLOON_ANIM_SPEED * ticks, maxf(length, 1.0))
		BlitzAnimator.seek(balloon_player, balloon_time)
	if here_marker != null and here_time >= 0.0:
		var length := here_player.get_animation(BlitzAnimator.B3D_ANIMATION).length if here_player else 0.0
		here_time += HERE_ANIM_SPEED * ticks
		if here_time >= length:
			here_time = -1.0
			here_marker.visible = false
		else:
			BlitzAnimator.seek(here_player, here_time)


# ---------------------------------------------------------------- placement & selection

## `_fbuildtower`: enter placement mode for tower `type` (returns false when unaffordable).
func start_placing(type: int) -> bool:
	if placing_type != 0:
		cancel_placing()
	if not game.can_afford_tower(type):
		game.sound.emit("oops2", Vector3.ZERO)
		return false
	placing_type = type
	place_marker = PlaceMarkerView.new()
	entities.add_child(place_marker)
	place_marker.setup(data.tower_model(type)["place_model"], float(game.protos[type][0]["range"]))
	place_marker.visible = false
	return true


func cancel_placing() -> void:
	if place_marker != null:
		place_marker.queue_free()
		place_marker = null
	placing_type = 0
	placement_cancelled.emit()


func is_placing() -> bool:
	return placing_type != 0


## `_fplacetower`: marker follows the cursor; zone rules + distance rule decide the colour.
func _tick_placement(mouse: Vector2) -> void:
	if placing_type == 0 or place_marker == null:
		return
	var hit := picker.pick(camera_rig.camera, mouse, Picker.mask([Picker.LAYER_ZONES]))
	if hit.is_empty():
		place_marker.visible = false
		place_marker.set_allowed(false)
		return
	var p: Vector3 = hit["position"]
	place_marker.visible = true
	place_marker.position = Vector3(p.x, SimGame.PLACE_MARKER_Y, p.z)
	place_marker.set_allowed(can_place_at(hit["zone"], place_marker.position))


func can_place_at(zone: String, pos: Vector3) -> bool:
	var proto: Dictionary = game.protos[placing_type][0]
	var on_road := bool(proto["place_on_road"])
	var zone_ok := false
	if zone == "grass":
		zone_ok = not on_road
	elif zone == "road":
		zone_ok = on_road
	if not zone_ok:
		return false
	return not game.is_too_close_to_tower(pos)


func _unhandled_input(event: InputEvent) -> void:
	if game == null or GameState.ingame_menu_open:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return  # a touch, handled below as one
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_left_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_right_click(mb.position)
	elif event is InputEventScreenTouch and event.pressed and event.index == 0:
		camera_rig.edge_scroll_enabled = false
		touch_active = true
		touch_dragging = false
		touch_start = event.position
		touch_last = event.position
		touch_time_ms = Time.get_ticks_msec()
	elif event is InputEventScreenDrag and event.index == 0 and touch_active:
		_touch_drag(event.position)


## Touch: a tap clicks, a held finger right-clicks, a moving finger drags the map so the
## ground under it follows. The release is taken here, before the GUI: a finger lifted over
## a HUD widget would never reach `_unhandled_input` and leave the touch armed.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == 0 and touch_active:
		touch_active = false
		if touch_dragging or game == null or GameState.ingame_menu_open:
			return
		if Time.get_ticks_msec() - touch_time_ms >= TOUCH_LONG_PRESS_MS:
			_right_click(event.position)
		else:
			_left_click(event.position)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		camera_rig.edge_scroll_enabled = true


func _touch_drag(pos: Vector2) -> void:
	if not touch_dragging:
		if pos.distance_to(touch_start) < TOUCH_DRAG_THRESHOLD:
			return
		touch_dragging = true
	camera_rig.pan(camera_rig.ground_point(touch_last) - camera_rig.ground_point(pos))
	touch_last = pos


func _left_click(pos: Vector2) -> void:
	if gui_hit_test.is_valid() and gui_hit_test.call():
		return
	if placing_type != 0:
		_tick_placement(pos)  # a tap lands before the frame that moves the marker under it
		if place_marker != null and place_marker.visible and place_marker.can_place:
			var t := game.build_tower(placing_type, place_marker.position)
			if t != null:
				cancel_placing()
				game.select_tower(t)
				tower_placed.emit(t)
				selection_changed.emit()
		return
	var hit := picker.pick(camera_rig.camera, pos, Picker.mask([Picker.LAYER_TOWERS]))
	if hit.has("tower"):
		var t := game.find_tower(int(hit["tower"]))
		if t != null and not t.selected:
			game.select_tower(t)
			selection_changed.emit()
		return
	hit = picker.pick(camera_rig.camera, pos, Picker.mask([Picker.LAYER_ENEMIES]))
	if hit.has("enemy"):
		var e := game.find_enemy(int(hit["enemy"]))
		if e != null:
			game.select_enemy(e)
			selection_changed.emit()


func _right_click(pos: Vector2) -> void:
	if placing_type != 0:
		cancel_placing()
		return
	if game.balloon != null and game.balloon.enabled:
		var hit := picker.pick(camera_rig.camera, pos, Picker.mask([Picker.LAYER_ZONES]))
		if hit.has("zone") and hit["zone"] == "road":
			var p: Vector3 = hit["position"]
			game.balloon.move_to(p)
			if here_marker != null:
				here_marker.position = p + Vector3(0, 0.01, 0)
				here_marker.visible = true
				here_time = 0.0
		else:
			game.message.emit(data.text(77), SimGame.MSG_WHITE, 1500)
	game.deselect_all_towers()
	game.deselect_enemy()
	selection_changed.emit()


func camera() -> Camera3D:
	return camera_rig.camera


## `_fhideallenemies` / `_fshowallenemies`.
func set_enemies_visible(on: bool) -> void:
	for v in enemy_views.values():
		(v as Node3D).visible = on
