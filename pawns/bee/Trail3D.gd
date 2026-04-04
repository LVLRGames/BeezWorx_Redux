class_name Trail3D
extends Node

@export var target: Node3D

@export_group("Trail Shape")
@export var size: float = 0.12
@export var sections: int = 24
@export var width_curve: Curve
@export var material: Material
@export var cast_shadow: bool = false
@export var texture_repeat_scale: float = 2.0

@export_group("Sampling")
@export var trail_time_interval: float = 0.025
@export var trail_point_threshold: float = 0.05
@export var min_point_distance: float = 0.03
@export var min_direction_length: float = 0.001

@export_group("Fade")
@export var use_timed_fade: bool = false
@export var fade_interval: float = 0.08

@export_group("Emission")
@export var emit_offset: float = 0.10
@export var flatten_motion_to_ground: bool = true
@export var use_target_velocity_if_available: bool = true
@export var fallback_to_target_basis_when_stationary: bool = true

@export_group("Placement")
@export var attach_to_group_name: StringName = &"trails"

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _points: Array[Dictionary] = []

var _trail_time_left: float = 0.0
var _fade_time_left: float = 0.0

var _last_target_global_position: Vector3 = Vector3.ZERO
var _has_last_position: bool = false
var _last_motion_forward: Vector3 = Vector3.FORWARD

var _frame_motion: Vector3 = Vector3.ZERO
var _frame_speed: float = 0.0
var _frame_forward: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_setup_defaults()
	_create_render_mesh()

	_trail_time_left = trail_time_interval
	_fade_time_left = fade_interval

	if target != null:
		_last_target_global_position = target.global_position
		_has_last_position = true


func _exit_tree() -> void:
	if is_instance_valid(_mesh_instance):
		_mesh_instance.queue_free()


func _process(delta: float) -> void:
	if target == null:
		clear_trail()
		return

	_update_frame_motion(delta)
	update_trail(delta)


func clear_trail() -> void:
	_points.clear()
	_redraw_trail_mesh()


func force_emit_point() -> void:
	_add_point_to_trail()


func remove_oldest_point() -> void:
	if _points.is_empty():
		return
	_points.remove_at(0)
	_redraw_trail_mesh()


func update_trail(delta: float) -> void:
	_trail_time_left -= delta
	_fade_time_left -= delta

	if _frame_speed > trail_point_threshold:
		if _trail_time_left <= 0.0:
			_add_point_to_trail()
			_trail_time_left = trail_time_interval
	else:
		if use_timed_fade:
			if _fade_time_left <= 0.0:
				remove_oldest_point()
				_fade_time_left = fade_interval
		else:
			if not _points.is_empty():
				clear_trail()


func _setup_defaults() -> void:
	if width_curve == null:
		width_curve = Curve.new()
		width_curve.add_point(Vector2(0.0, 1.0))
		width_curve.add_point(Vector2(1.0, 0.0))


func _create_render_mesh() -> void:
	_immediate_mesh = ImmediateMesh.new()

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.material_override = material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.top_level = true

	var parent_node := get_tree().get_first_node_in_group(attach_to_group_name)
	if parent_node != null:
		parent_node.add_child(_mesh_instance)
	else:
		get_tree().current_scene.add_child(_mesh_instance)


func _update_frame_motion(delta: float) -> void:
	_frame_motion = Vector3.ZERO
	_frame_speed = 0.0
	_frame_forward = _last_motion_forward

	if target == null:
		return

	var got_motion := false

	if use_target_velocity_if_available:
		var velocity_value: Variant = target.get("velocity")
		if velocity_value is Vector3:
			_frame_motion = velocity_value
			got_motion = true

	if not got_motion:
		var current_pos := target.global_position

		if not _has_last_position:
			_last_target_global_position = current_pos
			_has_last_position = true
		else:
			_frame_motion = current_pos - _last_target_global_position
			_last_target_global_position = current_pos
			if delta > 0.0:
				_frame_motion /= delta

	if flatten_motion_to_ground:
		_frame_motion.y = 0.0

	_frame_speed = _frame_motion.length()

	if _frame_motion.length_squared() > min_direction_length:
		_frame_forward = _frame_motion.normalized()
		_last_motion_forward = _frame_forward
	elif fallback_to_target_basis_when_stationary:
		var basis_forward := -target.global_basis.z
		if flatten_motion_to_ground:
			basis_forward.y = 0.0
		if basis_forward.length_squared() > 0.000001:
			_frame_forward = basis_forward.normalized()
			_last_motion_forward = _frame_forward


func _get_emit_position() -> Vector3:
	var emit_pos := target.global_position

	if emit_offset != 0.0 and _frame_forward.length_squared() > 0.000001:
		emit_pos -= _frame_forward * emit_offset

	return emit_pos


func _add_point_to_trail() -> void:
	if target == null:
		return

	var emit_pos := _get_emit_position()

	if not _points.is_empty():
		var last_pos: Vector3 = _points[_points.size() - 1]["pos"]
		if last_pos.distance_to(emit_pos) < min_point_distance:
			return

	if _points.size() >= sections:
		_points.remove_at(0)

	_points.append({
		"pos": emit_pos,
		"forward": _frame_forward
	})

	_redraw_trail_mesh()


func _redraw_trail_mesh() -> void:
	_immediate_mesh.clear_surfaces()

	if _points.size() < 2:
		return

	var distances: Array[float] = []
	distances.resize(_points.size())

	var total_length: float = 0.0
	distances[0] = 0.0

	for i in range(1, _points.size()):
		var prev_pos: Vector3 = _points[i - 1]["pos"]
		var curr_pos: Vector3 = _points[i]["pos"]
		total_length += prev_pos.distance_to(curr_pos)
		distances[i] = total_length

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)

	var previous_side: Vector3 = Vector3.ZERO
	var has_previous_side: bool = false

	for i in range(_points.size()):
		var point_data: Dictionary = _points[i]
		var pos: Vector3 = point_data["pos"]
		var forward: Vector3 = point_data["forward"]

		var normalized_index: float = float(i) / float(max(_points.size() - 1, 1))
		var width_factor: float = 1.0
		if width_curve != null:
			width_factor = width_curve.sample_baked(1.0 - normalized_index)

		var half_width: float = size * width_factor * 0.5

		var side: Vector3 = forward.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		else:
			side = side.normalized()

		if has_previous_side and previous_side.dot(side) < 0.0:
			side = -side

		previous_side = side
		has_previous_side = true

		var right: Vector3 = pos + side * half_width
		var left: Vector3 = pos - side * half_width

		var u: float = distances[i] * texture_repeat_scale

		_immediate_mesh.surface_set_uv(Vector2(u, 1.0))
		_immediate_mesh.surface_add_vertex(right)

		_immediate_mesh.surface_set_uv(Vector2(u, 0.0))
		_immediate_mesh.surface_add_vertex(left)

	_immediate_mesh.surface_end()
