# pawn_flyer.gd
# res://pawns/pawn_flyer.gd
#
# Flying movement for pawns (bees, hornets, butterflies, birds).
# Full 3D movement, no gravity, pitch/yaw/roll visual orientation.
# Renamed from FlightPawn. Logic is identical to the old project.
#
# Altitude clamping and bird predator zone are Phase 3 additions.

@abstract
class_name PawnFlyer
extends PawnBase

# ── Flight tuning ─────────────────────────────────────────────────────────────
@export var max_speed:              float = 60.0
@export var accel:                  float = 60.0
@export var linear_damp:            float = 3.5
@export var vertical_accel_scale:   float = 0.8

@export var face_rate:              float = 20.0
@export var roll_rate:              float = 12.0
@export var max_roll_deg:           float = 35.0
@export var level_rate:             float = 16.0

@export var moving_speed_threshold: float = 0.15

# ── TODO Phase 3 — altitude constraints ──────────────────────────────────────
# @export var min_altitude:       float = 0.3    # cannot go underground
# @export var soft_max_altitude:  float = 40.0   # bird predator zone above this
# @export var hard_max_altitude:  float = 120.0

# ── Runtime state ─────────────────────────────────────────────────────────────
var _pitch: float = 0.0
var _yaw:   float = 0.0
var _roll:  float = 0.0

# ════════════════════════════════════════════════════════════════════════════ #
#  PawnBase overrides
# ════════════════════════════════════════════════════════════════════════════ #

func move_in_plane(input_dir: Vector3, delta: float) -> void:
	var a := input_dir
	if a.length() > 1.0:
		a = a.normalized()

	a.y *= vertical_accel_scale
	velocity += a * accel * delta

	if linear_damp > 0.0:
		velocity *= maxf(0.0, 1.0 - linear_damp * delta)

	var spd: float = velocity.length()
	if spd > max_speed:
		velocity *= max_speed / spd

	move_and_slide()


func face_direction(input_dir: Vector3, delta: float, gfx: Node3D = null) -> void:
	var spd: float = velocity.length()
	
	
	if spd > moving_speed_threshold:
		var v: Vector3 = velocity / spd

		var target_yaw:   float = atan2(v.x, v.z)
		var target_pitch: float = -asin(clampf(v.y, -1.0, 1.0))

		# Roll into turns based on lateral input in local space
		var yaw_basis := Basis(Vector3.UP, _yaw)
		var local_in: Vector3 = yaw_basis.inverse() * input_dir
		var lateral: float = clampf(-local_in.x, -1.0, 1.0)
		var target_roll: float = deg_to_rad(max_roll_deg) * signf(lateral) * pow(absf(lateral), 0.5)



		var t_face: float = 1.0 - pow(0.0001, delta * face_rate)
		var t_roll: float = 1.0 - pow(0.0001, delta * roll_rate)

		_pitch = lerp_angle(_pitch, target_pitch, t_face)
		_yaw   = lerp_angle(_yaw,   target_yaw,   t_face)
		_roll  = lerp_angle(_roll,  target_roll,  t_roll)
	else:
		var t_lvl: float = 1.0 - pow(0.0001, delta * level_rate)
		_pitch = lerp_angle(_pitch, 0.0, t_lvl)
		_roll  = lerp_angle(_roll,  0.0, t_lvl)

	var rot := Vector3(_pitch, _yaw, _roll)
	if gfx:
		gfx.rotation = rot
	else:
		rotation = rot


func distance_to_ground() -> float:
	var ss   := get_world_3d().direct_space_state
	var prqp := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0.0, -100.0, 0.0),
		1,
		[get_rid()]
	)
	var result: Dictionary = ss.intersect_ray(prqp)
	if result.has("position"):
		return global_position.distance_to(result["position"])
	return 0.0
