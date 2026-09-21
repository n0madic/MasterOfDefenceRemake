## Projectile state (`tbullett`, docs/10).
class_name SimBullet
extends RefCounted

var id := 0
var position := Vector3.ZERO
var direction := Vector3.FORWARD
var target: SimEnemy = null
var speed := SimTower.BULLET_SPEED
var damage := 0.0
var freeze := 0.0
var burn := 0.0
var poison := 0.0
var tower: SimTower = null
var model := ""
