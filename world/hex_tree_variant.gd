# hex_tree_variant.gd
class_name HexTreeVariant
extends Resource

@export var id: String = ""

@export_group("Rendering")
@export var mesh: Mesh
@export var material: Material

@export_group("Collision")
@export var collision_mesh: ConcavePolygonShape3D

@export_group("Selection")
@export_range(0.0, 100.0, 0.01) var weight: float = 1.0

@export_group("Transform")
@export var scale_range: Vector2 = Vector2(0.95, 1.05)
@export var y_rotation_offset_degrees: float = 0.0

var _cached_collision_shape: Shape3D

func get_collision_shape() -> Shape3D:
	if _cached_collision_shape:
		return _cached_collision_shape

	if collision_mesh:
		_cached_collision_shape = collision_mesh
	elif mesh:
		_cached_collision_shape = mesh.create_trimesh_shape()

	return _cached_collision_shape
