## Visual mirror of a SimBullet.
class_name BulletView
extends Node3D

var bullet: SimBullet
var model: Node3D


func setup(b: SimBullet) -> void:
	bullet = b
	if b.model != "" and ResourceLoader.exists(b.model):
		model = load(b.model).instantiate()
		BlitzAnimator.hide_helpers(model)
		add_child(model)
	sync()


func sync() -> void:
	position = bullet.position
	var d := bullet.direction
	if d.length_squared() > 0.0 and absf(d.normalized().dot(Vector3.UP)) < 0.999:
		look_at(position + d, Vector3.UP)
