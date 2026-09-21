## Auto-balance of monster health (`_fhandlebalance`, docs/08).
class_name SimBalance
extends RefCounted

const FLOOR_NORMAL := 0.8
const FLOOR_HERO := 0.95
const FLOOR_LEGEND := 1.0
const CEILING_HERO_FACTOR := 1.1
const CEILING_LEGEND_FACTOR := 1.2
const CLEAN_RAIDS_BONUS := 0.03
const MANY_LIFES := 201
const MANY_LIFES_MULTIPLIER := 1.3
const FEW_LIFES := 20
const FEW_LIFES_MULTIPLIER := 0.7


## `missed` is indexed by raid number (the value written for the raid that just ended is
## stored under the already incremented `curlevel`, exactly like the original).
static func update(m: float, missed: PackedInt32Array, curlevel: int, location: int, titul: int, lifes: int) -> float:
	if missed[curlevel] > 0:
		m = Blitz.f32(m - float(missed[curlevel]) / 100.0)
	if curlevel > 3 and missed[curlevel] == 0 and missed[curlevel - 1] == 0 and missed[curlevel - 2] == 0:
		m = Blitz.f32(m + Blitz.f32(CLEAN_RAIDS_BONUS))
	var ceiling := Blitz.f32(float(location) / 10.0 + 1.0)
	var floor_value := FLOOR_NORMAL
	if titul == 1:
		floor_value = FLOOR_HERO
		ceiling = Blitz.f32(ceiling * Blitz.f32(CEILING_HERO_FACTOR))
	if titul == 2:
		floor_value = FLOOR_LEGEND
		ceiling = Blitz.f32(ceiling * Blitz.f32(CEILING_LEGEND_FACTOR))
	if m > ceiling:
		m = ceiling
	if m < floor_value:
		m = Blitz.f32(floor_value)
	if lifes >= MANY_LIFES:
		m = Blitz.f32(MANY_LIFES_MULTIPLIER)
	elif lifes < FEW_LIFES and titul == 0:
		m = Blitz.f32(FEW_LIFES_MULTIPLIER)
	return m
