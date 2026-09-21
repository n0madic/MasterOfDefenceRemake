## Emulation of Blitz3D runtime numerics (conventions C1/C4 of the remake plan).
##
## This is a static helper class, not an autoload: sim code and headless tests use it
## without a scene tree.
class_name Blitz


## Blitz `Round`: x87 `fistp` with default rounding mode = round-half-to-even.
static func round_int(x: float) -> int:
	var f := floorf(x)
	var diff := x - f
	if diff < 0.5:
		return int(f)
	if diff > 0.5:
		return int(f) + 1
	# Exactly halfway: pick the even neighbour.
	var fi := int(f)
	return fi if (fi & 1) == 0 else fi + 1


## Blitz integer division `\`: truncation toward zero.
static func idiv(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return q if (a < 0) == (b < 0) else -q


## Blitz `Mod` for floats keeps the sign of the dividend, like C fmod.
static func fmod_blitz(a: float, b: float) -> float:
	return fmod(a, b)


## Round to single precision. Blitz keeps all floats as 32-bit; accumulators that gate
## events (ingametime, tower AnimTime, freeze) drift differently in float64.
static func f32(x: float) -> float:
	var arr := PackedFloat32Array([x])
	return arr[0]


## Blitz left-handed coordinates -> Godot right-handed: (x, y, z) -> (x, y, -z).
static func to_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, -v.z)


## Blitz quaternion (w, x, y, z) -> Godot: (w, x, y, -z) as Quaternion(x, y, z, w).
## Blitz applies the inverse of the textbook rotation for a file quaternion (see
## tools/blitzconv.py), hence conj + z-mirror.
static func quat_to_godot(w: float, x: float, y: float, z: float) -> Quaternion:
	return Quaternion(x, y, -z, w)


## Seedable random source with Blitz `Rand`/`Rnd` semantics.
class Random:
	extends RefCounted
	var rng := RandomNumberGenerator.new()

	func _init(seed_value: int = 0) -> void:
		if seed_value != 0:
			rng.seed = seed_value
		else:
			rng.randomize()

	## Blitz `Rand(a, b)`: inclusive integer range.
	func rand(a: int, b: int) -> int:
		return rng.randi_range(a, b)

	## Blitz `Rnd(a, b)`: float in [a, b).
	func rnd(a: float, b: float) -> float:
		return rng.randf_range(a, b)
