## Falling balloon bomb (`tbombt`, docs/07).
class_name SimBomb
extends RefCounted

const DAMAGE := 350.0
const FREEZE_PER_COLD := 30
const FALL_SPEED := 0.2
const RADIUS := 7.0

var id := 0
var position := Vector3.ZERO
var damage := DAMAGE
var freeze := 0.0
