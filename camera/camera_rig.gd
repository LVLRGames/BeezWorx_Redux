extends Node3D
class_name CameraRig

@onready var cam: Camera3D = %Camera3D
@onready var pivot: Node3D = $Pivot
@onready var spring_arm_3d: SpringArm3D = $Pivot/SpringArm3D

@export var player_index: int = 1
@export var target: Node3D

@export var min_distance := 2.0
@export var max_distance := 20.0
@export var distance := 10.0
@export var follow_speed := 10.0
@export var look_at_target:bool = false
@export var look_speed := 4.0

@export var joystick_x_sensitivity := 5.0
@export var joystick_y_sensitivity := 2.5
@export var yaw_speed := 0.012
@export var pitch_speed := 0.012
@export var min_pitch := deg_to_rad(-80)
@export var max_pitch := deg_to_rad(10)
@export var pitch_lock_speed_threshold: float = 0.15
static var _registry := {}
var _yaw := 0.0
var _pitch := deg_to_rad(-20)
var _last_target_pos: Vector3 = Vector3.ZERO

static func for_player(idx: int) -> CameraRig:
	return _registry.get(idx, null)

func _ready() -> void:
	_registry[player_index] = self
	if cam:
		cam.rotation = Vector3.ZERO
	spring_arm_3d.position = Vector3.ZERO
	spring_arm_3d.rotation = Vector3.ZERO
	spring_arm_3d.spring_length = distance

	# Listen for player pawn becoming available
	EventBus.player_pawn_ready.connect(_on_player_pawn_ready)

func set_target(node: Node3D) -> void:
	target = node
	if target:
		_last_target_pos = target.global_position

func get_current_camera() -> Camera3D:
	return cam

func _target_speed(dt: float) -> float:
	if target == null:
		return 0.0

	if target is CharacterBody3D:
		return (target as CharacterBody3D).velocity.length()

	var p := target.global_position
	var v := (p - _last_target_pos) / maxf(dt, 0.0001)
	return v.length()

func _can_pitch(_dt: float) -> bool:
	return true
	#return _target_speed(dt) < pitch_lock_speed_threshold\
	#or Input.is_action_pressed("p%s_orbit" % [player_index])

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= e.relative.x * yaw_speed

		# Pitch only if not moving
		if _can_pitch(1.0 / 60.0): # mouse event doesn't include dt; this is fine as a gate
			_pitch -= e.relative.y * pitch_speed
			_pitch = clamp(_pitch, min_pitch, max_pitch)

func _process(dt: float) -> void:
	if not target: 
		return
	
	if target:
		global_position = lerp(global_position,target.global_position, dt * follow_speed)

	var px := "p%d_" % player_index
	var look := Input.get_vector(px+"look_left", px+"look_right", px+"look_down", px+"look_up")

	# Yaw always
	_yaw -= look.x * yaw_speed * joystick_x_sensitivity

	# Pitch only when target isn't moving
	if _can_pitch(dt):
		_pitch -= look.y * pitch_speed * joystick_y_sensitivity
		_pitch = clamp(_pitch, min_pitch, max_pitch)

	if Input.is_action_pressed(px+"zoom_in"):
		distance = clampf(distance - 0.25, min_distance, max_distance)
	elif Input.is_action_pressed(px+"zoom_out"):
		distance = clampf(distance + 0.25, min_distance, max_distance)

	#prints(spring_arm_3d.spring_length, distance)
	rotation.y = _yaw
	pivot.rotation.x = _pitch
	spring_arm_3d.spring_length = distance

	

	if look_at_target and target:
		var target_pos := target.global_position
	
		# Smoothly look at the target to compensate for positional lag
		var desired := cam.global_transform.looking_at(target_pos, Vector3.UP)
		var t := 1.0 - pow(0.0001, dt * look_speed)
		cam.global_transform = cam.global_transform.interpolate_with(desired, t)
		
	_last_target_pos = target.global_position


func _on_player_pawn_ready(pawn: Node3D, slot: int) -> void:
	if slot != player_index:
		return
	set_target(pawn)
