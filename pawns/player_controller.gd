extends Controller
class_name PlayerController

@export var player_index: int = 1

@export var vertical_when_stationary: bool = false
@export var stationary_threshold: float = 0.15

var accel_dir := Vector3.ZERO



func physics_tick(delta: float) -> void:
	if pawn == null:
		return

	# Only drive input if we are the multiplayer authority (or singleplayer)
	if pawn.multiplayer.has_multiplayer_peer() and !pawn.is_multiplayer_authority():
		return

	var px := "p%d_" % player_index

	if Input.is_action_just_pressed(px+"prev_pawn") or Input.is_action_just_pressed(px+"next_pawn"):
		var next_pawn = pawn.get_tree().get_nodes_in_group("pawns").pick_random()
		print(next_pawn)
		PossessionManager._local_possess(next_pawn, player_index)
		return
	
	
	var move2 := Input.get_vector(px+"move_left", px+"move_right", px+"move_forward", px+"move_back")
	
	var cam := CameraRig.for_player(player_index).get_current_camera()
	if cam:
		var f := cam.global_transform.basis.z
		f.y = 0.0
		f = f.normalized()

		var r := cam.global_transform.basis.x
		r.y = 0.0
		r = r.normalized()

		accel_dir = (r * move2.x) + (f * move2.y)
	else:
		accel_dir = Vector3(move2.x, 0.0, move2.y)

	# Vertical accel from look axis (works nicely with "camera pitch only when not moving").
	var look_y := Input.get_axis(px+"move_down", px+"move_up")
	
	var speed := 0.0
	if pawn is CharacterBody3D:
		speed = (pawn as CharacterBody3D).velocity.length()

	var _wants_motion := (move2.length() > 0.05) or (speed > stationary_threshold)

	#if vertical_when_stationary or wants_motion:
	accel_dir.y += look_y
	#else:
		#accel_dir.y = 0.0

	# NOTE: face_direction now uses velocity (FlightPawn), but we still pass input_dir for roll.
	pawn.face_direction(accel_dir, delta, pawn.get_node("GFX") if pawn.has_node("GFX") else null)
	pawn.move_in_plane(accel_dir, delta)
	
	if Input.is_action_just_pressed(px+"action"):
		pawn.interact()
	
	if Input.is_action_just_pressed(px+"alt_action"):
		pawn.alt_interact()

















#
