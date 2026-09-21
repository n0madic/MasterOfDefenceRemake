## Warms up the models of a location before they are needed. Everything is loaded lazily
## at the moment it is spawned (`EnemyView.setup`, `OneShotView.setup`, ...) and the GL
## driver compiles a shader program the first time it is drawn, so a first-of-its-kind
## monster, bullet or explosion used to freeze the game for a moment. Every glb that can
## appear on the location is instead loaded, instantiated and drawn once here -- in a tiny
## off-screen viewport with a world of its own (a directional light like the locations', so
## the same shader variants get compiled) -- then the instances are freed.
##
## The warm-up runs on the map screen, a few models per frame while the story is read,
## so the location itself starts with everything compiled; a location entered without the
## map (survival, "continue", quick load) draws the rest in one go under the loading sheet.
##
## The loaded scenes (and the location's ground texture, which the tower bases blend) and
## the material variants made for them are pinned for the whole session: the resource cache
## holds weak references, so freeing the instances would otherwise release the scenes
## together with their meshes, textures and compiled programs.
class_name ModelWarmup
extends Node

const VIEWPORT_SIZE := Vector2i(16, 16)
const WARM_DISTANCE := 2.0
const WARM_SCALE := 0.01
## Frames an instance is drawn before it is freed (the compile happens in the first).
const WARM_FRAMES := 2
## Instances started per frame on the map screen; 0 = all at once.
const MAP_BATCH := 3
## Any blend of two frames drives the blend-shape path an idle MD2 model never takes.
const MD2_WARM_WEIGHT := 0.5
const FIXED_PATHS: Array[String] = [
	EnemyView.HEALTH_MODEL, EnemyView.SHADOW_MODEL, EnemyView.FIRE_EFFECT, EnemyView.POISON_EFFECT,
	TowerView.RANGE_MODEL, TowerView.SELECTION_MODEL,
	LocationView.DEATH_MODEL, LocationView.DEATH2_MODEL, LocationView.BOMB_MODEL,
	LocationView.HERE_MODEL, LocationView.BALLOON_MODEL, Hud.FACES_MODEL,
]

static var _pinned: Dictionary = {}  # path -> PackedScene / Texture2D
static var _pinned_materials: Array[Material] = []
## The warm-up in progress, if any (one at a time; a new request extends it).
static var _running: ModelWarmup = null

var viewport: SubViewport
var group: Node3D
var data: Node
var location_info: Dictionary
var location_number := 0
var tower_types := {}  # model path -> tower type, for the painted base variant
var queue: Array[String] = []  # paths still to draw
var live: Array = []  # [instance, frames drawn]
var batch := 0


static func is_pinned(path: String) -> bool:
	return _pinned.has(path)


static func is_running() -> bool:
	return _running != null


## `load(path)` that keeps the scene for the session: the location scenes and the HUD
## models go through here, so a restart or the next location does not read them again.
static func pinned_scene(path: String) -> PackedScene:
	if _pinned.has(path):
		return _pinned[path]
	var scene: PackedScene = null
	# A load started on the loader thread (`preload_in_background`) is taken from there.
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		scene = ResourceLoader.load_threaded_get(path)
	if scene == null:
		scene = load(path)
	if scene != null:
		_pinned[path] = scene
	return scene


## Every model that can show up on location `L`: the monsters of its raids (all of them in
## survival) and the workers, the towers with their markers, effects and bullets, and the
## models the location view creates itself. Existing files only, without duplicates.
## Reads the data tables only -- the simulation's RNG must not be touched here.
static func paths_for(data: Node, game: SimGame, location_info: Dictionary, L: int) -> Array[String]:
	var out: Array[String] = []
	var unit_ids := {}
	if game.survival_mode:
		for id in range(1, GameData.UNITS_COUNT + 1):
			unit_ids[id] = true
	else:
		for raid in data.raids:
			if raid != null and int(raid["location"]) == L:
				for id in raid["monsters"]:
					unit_ids[int(id)] = true
		for id in range(SimGame.WORKER_IDS[0], SimGame.WORKER_IDS[1] + 1):
			unit_ids[id] = true
		unit_ids[SimGame.GAMEDEV_WORKER_ID] = true
	for id in unit_ids:
		_add(out, str(data.unit(id)["model"]))
	for type in range(1, GameData.TOWER_TYPES + 1):
		var info: Dictionary = data.tower_model(type)
		for key in ["model", "place_model", "effect_model"]:
			_add(out, str(info[key]))
		for proto in data.tower_protos[type]:
			if proto["bullet_model"] != null:
				_add(out, str(proto["bullet_model"]))
	for path in FIXED_PATHS:
		_add(out, path)
	return out


static func _add(out: Array[String], path: String) -> void:
	if path != "" and not out.has(path) and ResourceLoader.exists(path):
		out.append(path)


## Warm location `L` for `game`: load and pin what is not pinned yet (synchronously, so a
## spawn right after finds its scene) and draw the new models off screen, `per_frame` at a
## time (0 = all in the next frame). The node lives under `parent` until the last model
## was drawn; a warm-up already running takes the new paths over. Nothing is drawn in
## headless mode.
static func warm(parent: Node, data: Node, game: SimGame, L: int, per_frame := 0) -> void:
	var location_info: Dictionary = data.location(L)
	var ground: String = location_info["ground_texture"]
	if not _pinned.has(ground) and ResourceLoader.exists(ground):
		_pinned[ground] = load(ground)
	# The HUD models are only pinned: the panel is redrawn with variants of its own
	# (`Hud._order_panel_quads`, `_draw_on_top`) on the location's first frame anyway.
	pinned_scene(Hud.ENV_MODEL)
	pinned_scene(Hud.TUTORIAL_MODEL)
	var fresh: Array[String] = []
	for path in [str(location_info["scene"])] + paths_for(data, game, location_info, L):
		if not _pinned.has(path) and pinned_scene(path) != null:
			fresh.append(path)
	if fresh.is_empty() or DisplayManager.headless():
		return
	if _running == null:
		_running = ModelWarmup.new()
		_running.name = "Warmup"
		_running._setup(data, location_info, L)
		parent.add_child(_running)
	_running.queue.append_array(fresh)
	_running.batch = per_frame


## Everything `warm` loads for location `L`.
static func all_paths(data: Node, game: SimGame, L: int) -> Array[String]:
	var location_info: Dictionary = data.location(L)
	var paths := paths_for(data, game, location_info, L)
	paths.append(str(location_info["scene"]))
	paths.append(Hud.ENV_MODEL)
	paths.append(Hud.TUTORIAL_MODEL)
	return paths


## Start reading the resources of location `L` on a loader thread (where the platform has
## threads -- not the web build); `background_done` tells when `warm` can take them over
## without waiting. Returns false when nothing was started.
static func preload_in_background(data: Node, game: SimGame, L: int) -> bool:
	if not OS.has_feature("threads"):
		return false
	var started := false
	for path in all_paths(data, game, L):
		if not _pinned.has(path) and ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path)
			started = true
	return started


## Pin up to `n` of location `L`'s resources that are not pinned yet, skipping the ones the
## loader thread is still reading; true once everything is pinned. Called every tick by the
## map screen, so the reading (without threads) and the pinning come in small slices.
static func pin_some(data: Node, game: SimGame, L: int, n: int) -> bool:
	var left := 0
	for path in all_paths(data, game, L):
		if _pinned.has(path):
			continue
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			left += 1
			continue
		if n > 0:
			pinned_scene(path)
			n -= 1
		else:
			left += 1
	return left == 0


## A world like the locations' (`LocationView._setup_lights`: colour background, one
## directional light without shadows) in a viewport nobody looks at.
func _setup(d: Node, info: Dictionary, L: int) -> void:
	data = d
	location_info = info
	location_number = L
	for type in range(1, GameData.TOWER_TYPES + 1):
		tower_types[str(data.tower_model(type)["model"])] = type
	viewport = SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment = e
	viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 30, 0)
	light.shadow_enabled = false
	viewport.add_child(light)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	group = Node3D.new()
	group.position = Vector3(0, 0, -WARM_DISTANCE)
	group.scale = Vector3.ONE * WARM_SCALE
	camera.add_child(group)


func _process(_delta: float) -> void:
	# Instances that had their frames go; then the next batch comes in.
	for i in range(live.size() - 1, -1, -1):
		live[i][1] += 1
		if live[i][1] > WARM_FRAMES:
			(live[i][0] as Node).queue_free()
			live.remove_at(i)
	var n := queue.size() if batch <= 0 else mini(batch, queue.size())
	for i in n:
		_start(queue.pop_front())
	if queue.is_empty() and live.is_empty():
		_running = null
		queue_free()


func _start(path: String) -> void:
	var scene: PackedScene = _pinned.get(path)
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	BlitzAnimator.hide_helpers(inst)
	group.add_child(inst)
	if tower_types.has(path):
		_pinned_materials.append_array(TowerView.paint_base(inst, tower_types[path], location_info, location_number))
	var mesh := BlitzAnimator.find_mesh(inst)
	if mesh != null and mesh.get_blend_shape_count() > 0:
		mesh.set_blend_shape_value(0, MD2_WARM_WEIGHT)
	live.append([inst, 0])


func _exit_tree() -> void:
	if _running == self:
		_running = null
