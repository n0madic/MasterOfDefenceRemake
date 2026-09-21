extends SceneTree
func _initialize() -> void:
	load("res://tests/_probe_inner.gd").new().run(root)
	quit()
