## Mouse picking over the location (`CameraPick` in the original).
##
## Zone meshes (`grass`, `road`, `noparking`, `rocks`) get trimesh collision shapes on
## their own physics layer; enemies and towers register Area3D shapes on two other layers.
class_name Picker
extends Node

const LAYER_ZONES := 1
const LAYER_ENEMIES := 2
const LAYER_TOWERS := 3
const ZONE_NAMES := ["grass", "road", "noparking", "rocks"]
const RAY_LENGTH := 1000.0

var zone_bodies: Dictionary = {}  # StaticBody3D -> zone name


## Build collision for every zone mesh under `scene`. A location may have several nodes
## with the same clean name (Location3 has `grass` and `grass01`; only `grass` counts).
func build_zones(scene: Node) -> void:
	zone_bodies.clear()
	for zone in ZONE_NAMES:
		for node in scene.find_children(zone, "MeshInstance3D", true, false):
			if node.name != zone:
				continue
			var mi := node as MeshInstance3D
			var body := StaticBody3D.new()
			body.name = "Pick_" + zone
			body.collision_layer = 1 << (LAYER_ZONES - 1)
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var faces := mi.mesh.get_faces()
			var concave := ConcavePolygonShape3D.new()
			concave.set_faces(faces)
			shape.shape = concave
			body.add_child(shape)
			mi.add_child(body)
			zone_bodies[body] = zone


## Ray-cast from the camera through `screen_pos`. Returns {} or
## {"zone": name, "position": Vector3} for zone hits, {"enemy": id} / {"tower": id} for entities.
func pick(camera: Camera3D, screen_pos: Vector2, layers: int) -> Dictionary:
	var space := camera.get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, layers)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit["collider"]
	if zone_bodies.has(collider):
		return {"zone": zone_bodies[collider], "position": hit["position"]}
	if collider.has_meta("enemy_id"):
		return {"enemy": int(collider.get_meta("enemy_id")), "position": hit["position"]}
	if collider.has_meta("tower_id"):
		return {"tower": int(collider.get_meta("tower_id")), "position": hit["position"]}
	return {}


static func mask(layers: Array[int]) -> int:
	var m := 0
	for l in layers:
		m |= 1 << (l - 1)
	return m


## Pick sphere/box for an entity, as an Area3D on `layer` carrying `meta_key` = id.
static func make_area(layer: int, meta_key: String, id: int, shape: Shape3D, offset: Vector3 = Vector3.ZERO) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 1 << (layer - 1)
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.set_meta(meta_key, id)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	area.add_child(cs)
	return area
