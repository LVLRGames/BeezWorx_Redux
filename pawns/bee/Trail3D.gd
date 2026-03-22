class_name Trail3D
extends Node

@export var size : float = 1.0
@export var segment : float = 1.0
@export var sections : int = 50
@export var curve : Curve = Curve.new()
@export var material := Material.new()
@export var mesh_instance := MeshInstance3D.new()
@export var immediate_mesh := ImmediateMesh.new()
@export var cast_shadow := false;
@export var points = []
@export var trail_time_interval : float = 0.025
@export var trail_point_threshold : float = 0.15
@export var target : Node3D

var trail_time_left : float = trail_time_interval


func _process(delta: float) -> void:
	update_trail(delta)


func clear_mesh():
	immediate_mesh.clear_surfaces()
	mesh_instance.queue_free()
	mesh_instance = MeshInstance3D.new()


func remove_point_from_trail():
	clear_mesh()
	if points.size() > 0:
		points.remove_at(0)
		redraw_trail_mesh()


func add_point_to_trail(pos1: Vector3, _color = Color.WHITE_SMOKE) -> ImmediateMesh:
	clear_mesh()
	if points.size() > sections:
		points.remove_at(0)
	points.append(pos1)
	redraw_trail_mesh()
	return immediate_mesh


func redraw_trail_mesh():
	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = 1 if cast_shadow else 0
	
	if points.size() > 1:
		immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
		for i in range(points.size()-1):
#			var size_scaled = size
			var size_scaled = size * curve.sample((points.size()-i+1.0)/points.size())
			immediate_mesh.surface_set_uv(Vector2(0, 1))
			immediate_mesh.surface_add_vertex(points[i+0] + Vector3.RIGHT * size_scaled)
			immediate_mesh.surface_set_uv(Vector2(0, 0))
			immediate_mesh.surface_add_vertex(points[i+0] + Vector3.LEFT * size_scaled)
			immediate_mesh.surface_set_uv(Vector2(1, 1))
			immediate_mesh.surface_add_vertex(points[i+1] + Vector3.RIGHT * size_scaled)
			immediate_mesh.surface_set_uv(Vector2(1, 0))
			immediate_mesh.surface_add_vertex(points[i+1] + Vector3.LEFT * size_scaled) 
	
		immediate_mesh.surface_end()	
		
	if mesh_instance.get_parent() == null:
#			get_tree().get_root().add_child(mesh_instance)
			get_tree().get_first_node_in_group("trails").add_child(mesh_instance)


func update_trail(delta):
	var linear_velocity :float = target.velocity.length()
	trail_time_left -= delta
	if abs(linear_velocity) > trail_point_threshold:
		if trail_time_left <= 0:
			add_point_to_trail(target.transform.origin)
			trail_time_left = trail_time_interval
			
	if abs(linear_velocity) < trail_point_threshold:
		remove_point_from_trail()
