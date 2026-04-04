class_name PawnFootprinter
extends Node

@export var target: Node3D

@export_group("Stamping")
@export var max_marks: int = 256
@export var step_distance: float = 0.12
@export var lifetime: float = 2.5
@export var emit_offset: float = 0.06
@export var vertical_offset: float = 0.01
@export var material: Material

@export_group("Shape")
@export var mark_size: Vector2 = Vector2(0.18, 0.18)
@export var random_yaw_degrees: float = 10.0
@export var random_scale: float = 0.08

@export_group("Grounding")
@export var use_ground_raycast: bool = true
@export var raycast_height: float = 2.0
@export var raycast_depth: float = 6.0
@export var collision_mask: int = 1
@export var align_to_ground_normal: bool = true
@export var flatten_forward_to_ground: bool = true

@export_group("Motion")
@export var min_speed_to_stamp: float = 0.03
@export var use_target_velocity_if_available: bool = true

@export_group("Placement")
@export var attach_to_group_name: StringName = &"trails"

var _multimesh_instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _quad_mesh: QuadMesh

var _ages: Array[float] = []
var _active: Array[bool] = []
var _write_index: int = 0

var _last_emit_position: Vector3 = Vector3.ZERO
var _has_last_emit_position: bool = false

var _last_target_position: Vector3 = Vector3.ZERO
var _has_last_target_position: bool = false
var _frame_motion: Vector3 = Vector3.ZERO
var _frame_speed: float = 0.0
var _frame_forward: Vector3 = Vector3.FORWARD

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_create_multimesh()

	_ages.resize(max_marks)
	_active.resize(max_marks)

	for i in range(max_marks):
		_ages[i] = 0.0
		_active[i] = false
		_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -10000.0, 0.0)))
		_multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))

	if target != null:
		_last_target_position = target.global_position
		_has_last_target_position = true


func _exit_tree() -> void:
	if is_instance_valid(_multimesh_instance):
		_multimesh_instance.queue_free()


func _process(delta: float) -> void:
	if target == null:
		return

	_update_motion(delta)
	_update_marks(delta)
	_try_emit_mark()


func _create_multimesh() -> void:
	_quad_mesh = QuadMesh.new()
	#_quad_mesh.size = mark_size
	_quad_mesh.size = Vector2.ONE
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.instance_count = max_marks
	_multimesh.visible_instance_count = max_marks
	_multimesh.mesh = _quad_mesh

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.material_override = material
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.top_level = true

	var parent_node := get_tree().get_first_node_in_group(attach_to_group_name)
	if parent_node != null:
		parent_node.add_child(_multimesh_instance)
	else:
		get_tree().current_scene.add_child(_multimesh_instance)


func _update_motion(delta: float) -> void:
	_frame_motion = Vector3.ZERO
	_frame_speed = 0.0

	if use_target_velocity_if_available:
		var velocity_value: Variant = target.get("velocity")
		if velocity_value is Vector3:
			_frame_motion = velocity_value

	if _frame_motion.length_squared() <= 0.000001:
		var current_pos := target.global_position
		if not _has_last_target_position:
			_last_target_position = current_pos
			_has_last_target_position = true
		else:
			_frame_motion = current_pos - _last_target_position
			_last_target_position = current_pos
			if delta > 0.0:
				_frame_motion /= delta

	if flatten_forward_to_ground:
		_frame_motion.y = 0.0

	_frame_speed = _frame_motion.length()

	if _frame_speed > 0.000001:
		_frame_forward = _frame_motion.normalized()
	else:
		var basis_forward := -target.global_basis.z
		if flatten_forward_to_ground:
			basis_forward.y = 0.0
		if basis_forward.length_squared() > 0.000001:
			_frame_forward = basis_forward.normalized()


func _update_marks(delta: float) -> void:
	for i in range(max_marks):
		if not _active[i]:
			continue

		_ages[i] += delta
		var alpha := 1.0 - (_ages[i] / lifetime)

		if alpha <= 0.0:
			_active[i] = false
			_multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
			_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -10000.0, 0.0)))
			continue

		_multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, alpha))


func _try_emit_mark() -> void:
	if _frame_speed < min_speed_to_stamp:
		return

	var desired_pos := target.global_position - _frame_forward * emit_offset

	if not _has_last_emit_position:
		_last_emit_position = desired_pos
		_has_last_emit_position = true
		_emit_mark(desired_pos)
		return

	if desired_pos.distance_to(_last_emit_position) < step_distance:
		return

	_last_emit_position = desired_pos
	_emit_mark(desired_pos)


func _emit_mark(desired_pos: Vector3) -> void:
	var stamp_pos := desired_pos
	var normal := Vector3.UP

	if use_ground_raycast:
		var hit := _sample_ground(desired_pos)
		if hit.has("position"):
			stamp_pos = hit["position"]
			normal = hit["normal"]

	stamp_pos += normal * vertical_offset

	var forward := _frame_forward
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD

	if align_to_ground_normal:
		forward = (forward - normal * forward.dot(normal)).normalized()
		if forward.length_squared() < 0.000001:
			forward = normal.cross(Vector3.RIGHT).normalized()
			if forward.length_squared() < 0.000001:
				forward = Vector3.FORWARD

	var yaw_jitter_rad := deg_to_rad(_rng.randf_range(-random_yaw_degrees, random_yaw_degrees))
	forward = forward.rotated(normal, yaw_jitter_rad).normalized()

	var right := forward.cross(normal).normalized()
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT

	forward = normal.cross(right).normalized()
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD

	# Build a ground-aligned basis first.
	var _basis := Basis(right, normal, forward).orthonormalized()

	# Rotate the quad so its face lies on the XZ-like ground plane instead of standing upright.
	_basis = _basis * Basis(Vector3.RIGHT, deg_to_rad(90.0))

	var scale_jitter := 1.0 + _rng.randf_range(-random_scale, random_scale)
	_basis = _basis.scaled(Vector3(mark_size.x * scale_jitter, 1.0, mark_size.y * scale_jitter))

	var xform := Transform3D(_basis, stamp_pos)

	_multimesh.set_instance_transform(_write_index, xform)
	_multimesh.set_instance_color(_write_index, Color(1.0, 1.0, 1.0, 1.0))

	_ages[_write_index] = 0.0
	_active[_write_index] = true

	_write_index += 1
	if _write_index >= max_marks:
		_write_index = 0


func _sample_ground(world_pos: Vector3) -> Dictionary:
	var space_state := get_viewport().get_world_3d().direct_space_state

	var from := world_pos + Vector3.UP * raycast_height
	var to := world_pos - Vector3.UP * raycast_depth

	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	return space_state.intersect_ray(query)
