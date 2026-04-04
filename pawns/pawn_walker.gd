# pawn_walker.gd
# res://pawns/pawn_walker.gd
#
# Surface-aligned walking for ground pawns (ants, beetles, bears, badgers).
# Renamed from GroundPawn. Logic is identical to the old project.
#
# Requires four RayCast3D children:
#   GroundRay  — long downward cast, used as floating gate on spawn
#   ClimbRay   — forward cast, detects walls
#   FloorRay   — short downward cast, confirms floor underfoot
#   AngleRay   — forward-down cast, detects upcoming ledge drops

@abstract
class_name PawnWalker
extends PawnBase

# ── Raycasts ──────────────────────────────────────────────────────────────────
@onready var ground_ray: RayCast3D = $GroundRay
@onready var climb_ray:  RayCast3D = $ClimbRay
@onready var floor_ray:  RayCast3D = $FloorRay
@onready var angle_ray:  RayCast3D = $AngleRay

# ── Movement tuning ───────────────────────────────────────────────────────────
@export var max_speed:              float = 60.0
@export var accel:                  float = 60.0
@export var linear_damp:            float = 3.5
@export var face_rate:              float = 20.0
@export var level_rate:             float = 16.0
@export var moving_speed_threshold: float = 0.15
@export var surface_align_rate:     float = 8.0
@export var gravity_force:          float = 98.0

# ── Runtime state ─────────────────────────────────────────────────────────────
var _terrain_generated: bool    = false
var _surface_normal:    Vector3 = Vector3.UP
var _facing_dir:        Vector3 = Vector3.FORWARD
var _pitch:             float   = 0.0
var _yaw:               float   = 0.0

# ════════════════════════════════════════════════════════════════════════════ #
#  Private helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _resolve_surface_normal() -> Vector3:
	if climb_ray and climb_ray.is_colliding():
		return climb_ray.get_collision_normal()
	if angle_ray and angle_ray.is_colliding():
		return angle_ray.get_collision_normal()
	return _surface_normal

func _project_onto_surface(v: Vector3, surface_up: Vector3) -> Vector3:
	var projected: Vector3 = v - surface_up * v.dot(surface_up)
	if projected.length_squared() < 0.0001:
		return Vector3.ZERO
	return projected

func _build_basis(surface_up: Vector3, facing: Vector3) -> Basis:
	var right: Vector3 = surface_up.cross(facing)
	if right.length_squared() < 0.001:
		var alt: Vector3 = Vector3.FORWARD \
			if abs(surface_up.dot(Vector3.FORWARD)) < 0.9 \
			else Vector3.RIGHT
		right = surface_up.cross(alt)
	right = right.normalized()
	var fwd: Vector3 = right.cross(surface_up).normalized()
	return Basis(right, surface_up, fwd)

# ════════════════════════════════════════════════════════════════════════════ #
#  PawnBase overrides
# ════════════════════════════════════════════════════════════════════════════ #

func move_in_plane(input_dir: Vector3, delta: float) -> void:
	# Floating gate — wait for terrain collision on first spawn
	if not _terrain_generated:
		if ground_ray and ground_ray.is_colliding():
			_terrain_generated = true
			ground_ray.enabled = false
		else:
			return

	var target_normal: Vector3 = _resolve_surface_normal().normalized()
	var t: float = 1.0 - pow(0.0001, delta * surface_align_rate)
	_surface_normal = _surface_normal.lerp(target_normal, t).normalized()
	_surface_normal = _surface_normal / _surface_normal.length()
	up_direction    = _surface_normal

	var a: Vector3 = input_dir
	if a.length() > 1.0:
		a = a.normalized()

	a = a - _surface_normal * a.dot(_surface_normal)

	if _surface_normal.dot(Vector3.UP) < 0.5 and a.length_squared() > 0.0001:
		var axis: Vector3 = Vector3(_surface_normal.x, 0.0, _surface_normal.z).normalized()
		if axis.length_squared() > 0.5:
			a = a.rotated(axis, deg_to_rad(-90.0))

	velocity += a * accel * delta
	velocity += _surface_normal * -gravity_force * delta

	if linear_damp > 0.0:
		velocity *= maxf(0.0, 1.0 - linear_damp * delta)

	var spd: float = velocity.length()
	if spd > max_speed:
		velocity *= max_speed / spd

	move_and_slide()


func face_direction(input_dir: Vector3, delta: float, gfx: Node3D = null) -> void:
	if not _terrain_generated:
		return

	var spd: float = velocity.length()

	if spd > moving_speed_threshold:
		var planar_vel: Vector3 = _project_onto_surface(velocity, _surface_normal)
		if planar_vel.length_squared() > 0.0001:
			var t: float = 1.0 - pow(0.0001, delta * face_rate)
			_facing_dir = _facing_dir.slerp(planar_vel.normalized(), t).normalized()
	else:
		var reprojected: Vector3 = _project_onto_surface(_facing_dir, _surface_normal)
		if reprojected.length_squared() > 0.0001:
			var t: float = 1.0 - pow(0.0001, delta * level_rate)
			_facing_dir = _facing_dir.slerp(reprojected.normalized(), t).normalized()

	var on_plane: Vector3 = _project_onto_surface(_facing_dir, _surface_normal)
	if on_plane.length_squared() < 0.0001:
		on_plane = _project_onto_surface(Vector3.UP, _surface_normal)
		if on_plane.length_squared() < 0.0001:
			on_plane = _project_onto_surface(Vector3.FORWARD, _surface_normal)
		if on_plane.length_squared() < 0.0001:
			return
	_facing_dir = on_plane.normalized()

	var new_basis: Basis = _build_basis(_surface_normal, _facing_dir)
	if gfx:
		gfx.global_transform.basis = new_basis
	else:
		global_transform.basis = new_basis


func distance_to_ground() -> float:
	var ss   := get_world_3d().direct_space_state
	var prqp := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 100.0,
		0xFFFFFFFF,
		[get_rid()]
	)
	var result: Dictionary = ss.intersect_ray(prqp)
	if result.has("position"):
		return global_position.distance_to(result["position"])
	return 0.0
