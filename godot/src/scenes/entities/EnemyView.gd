## Visual mirror of a SimEnemy: model (MD2 blend shapes or the healer's B3D), shadow,
## health bar, status effect. Synced once per frame from `sync()`; the effect animation is
## the view's own clock and advances by the frame's `ticks`.
class_name EnemyView
extends Node3D

const HEALTH_MODEL := "res://assets/models/health.glb"
const SHADOW_MODEL := "res://assets/models/Towers/shadow.glb"
## `_vfireexplprototype` is MagicEff.b3d (FireEff.b3d in the game data is an empty stub).
const FIRE_EFFECT := "res://assets/models/Towers/MagicEff.glb"
const POISON_EFFECT := "res://assets/models/Towers/PoisonEff.glb"
const GRADIENT := "res://assets/textures/Monsters/Gradient.bmp"
const MD2_LAST_FRAME := 10
const HEALER_FRAMES := 10
const HEALTH_BAR_HEIGHT := 3.5
const EFFECT_SPEED := 0.2
const FADE_IN_FRAMES := 3.0
const PICK_RADIUS_GROUND := 2.5
const AIR_PICK_BOX := Vector3(3, 3, 3)
const AIR_PICK_OFFSET := Vector3(0, 3, 0)

static var _gradient: Image = null

var enemy: SimEnemy
var model: Node3D
var mesh: MeshInstance3D
var player: AnimationPlayer
var health_bar: Node3D
var health_player: AnimationPlayer
var shadow: Node3D
var effect: Node3D
var effect_player: AnimationPlayer
var effect_time := 0.0
var effect_length := 1.0
var effect_kind := 0
var faded_in := false
## Material copies of the model (shadow included, as `EntityColor` recurses) and the bar.
var model_mats: Array[Material] = []
var health_mats: Array[Material] = []
var health_lost := -1.0
var health_index := -1


func setup(e: SimEnemy, data: Node, shadows: bool) -> void:
	enemy = e
	var unit: Dictionary = data.unit(e.unit_id)
	model = load(unit["model"]).instantiate()
	add_child(model)
	BlitzAnimator.hide_helpers(model)
	mesh = BlitzAnimator.find_mesh(model)
	player = BlitzAnimator.find_player(model)
	model.scale = Vector3.ONE * e.scale
	if e.healer != 0:
		# The healer model is oriented sideways: Blitz turns it 90 degrees every tick.
		model.rotation_degrees.y = -90.0
	if shadows:
		shadow = load(SHADOW_MODEL).instantiate()
		BlitzAnimator.hide_helpers(shadow)
		model.add_child(shadow)
	health_bar = load(HEALTH_MODEL).instantiate()
	BlitzAnimator.hide_helpers(health_bar)
	health_player = BlitzAnimator.find_player(health_bar)
	add_child(health_bar)
	# Blitz parents the bar to the scaled entity: its height and size grow with the enemy.
	health_bar.position = Vector3(0, ((1.0 if e.air else 0.0) + HEALTH_BAR_HEIGHT) * e.scale, 0)
	health_bar.scale = Vector3.ONE * e.scale
	health_bar.visible = false
	model_mats = BlitzAnimator.owned_materials(model)
	health_mats = BlitzAnimator.owned_materials(health_bar)
	var shape: Shape3D
	var offset := Vector3.ZERO
	if e.air:
		var box := BoxShape3D.new()
		box.size = AIR_PICK_BOX
		shape = box
		offset = AIR_PICK_OFFSET
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = PICK_RADIUS_GROUND
		shape = sphere
	add_child(Picker.make_area(Picker.LAYER_ENEMIES, "enemy_id", e.id, shape, offset))
	sync(null, false)


func sync(camera: Camera3D, show_life: bool, ticks := 1) -> void:
	position = enemy.position
	var f := enemy.facing
	if f.length_squared() > 0.0:
		look_at(position + Vector3(f.x, 0.0, f.z).normalized() if absf(f.y) > 0.999 else position + f, Vector3.UP)
	if enemy.healer == 0:
		BlitzAnimator.md2_frame(mesh, enemy.md2_time, 0, MD2_LAST_FRAME)
	else:
		BlitzAnimator.seek(player, fmod(enemy.md2_time, float(HEALER_FRAMES)))
	# Fade in while the path marker is within the first 3 frames.
	var t := enemy.path.time
	if t < FADE_IN_FRAMES:
		var v := Blitz.round_int(255.0 * (t / FADE_IN_FRAMES)) / 255.0
		BlitzAnimator.tint_materials(model_mats, Color(v, v, v))
		faded_in = false
	elif not faded_in:
		BlitzAnimator.tint_materials(model_mats, Color.WHITE)
		faded_in = true
	_sync_health(camera, show_life)
	_sync_effect(ticks)


func _sync_health(camera: Camera3D, show_life: bool) -> void:
	health_bar.visible = show_life
	if not show_life:
		return
	if camera != null:
		health_bar.global_rotation = camera.global_rotation
	var percent := enemy.life_percent()
	var lost := clampf(100.0 - percent, 1.0, 99.0)
	if lost != health_lost:
		health_lost = lost
		BlitzAnimator.seek(health_player, lost)
	var idx := maxi(Blitz.round_int(percent - 1.0), 1)
	if idx != health_index:
		health_index = idx
		BlitzAnimator.tint_materials(health_mats, gradient_color(idx))


static func gradient_color(index: int) -> Color:
	if _gradient == null:
		var tex: Texture2D = load(GRADIENT)
		_gradient = tex.get_image()
	var x := clampi(index, 0, _gradient.get_width() - 1)
	return _gradient.get_pixel(x, 0)


func _sync_effect(ticks: int) -> void:
	if enemy.effect_kind != effect_kind:
		if effect != null:
			effect.queue_free()
			effect = null
		effect_kind = enemy.effect_kind
		if effect_kind != 0:
			effect = load(FIRE_EFFECT if effect_kind == SimGame.EFFECT_FIRE else POISON_EFFECT).instantiate()
			BlitzAnimator.hide_helpers(effect)
			add_child(effect)
			effect.position = Vector3(0, 3, 0) if enemy.air else Vector3.ZERO
			# Blitz parents the effect to the scaled entity, so it grows with the enemy too.
			var s := clampf(enemy.effect_size, 0.2, 0.8) * enemy.scale
			effect.scale = Vector3.ONE * s
			effect_player = BlitzAnimator.find_player(effect)
			effect_time = 0.0
			if effect_player != null:
				effect_length = maxf(effect_player.get_animation(BlitzAnimator.B3D_ANIMATION).length, 1.0)
	if effect != null and effect_player != null:
		effect_time = fmod(effect_time + EFFECT_SPEED * ticks, effect_length)
		BlitzAnimator.seek(effect_player, effect_time)
