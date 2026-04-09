# pawn_hopper.gd
# res://pawns/pawn_hopper.gd
#
# Ballistic hop-only locomotion for grasshoppers (and any spring-launched insect).
#
# ── Locomotion model ──────────────────────────────────────────────────────────
#   No walking.  Every move is a hop.
#
#   GROUNDED  — sitting on surface, surface-aligned, waiting for input.
#   AIRBORNE  — ballistic arc after a hop.  Light air-steering only.
#   HOVERING  — wings active; partial gravity cancel; stamina-limited.
#
# ── Input contract ────────────────────────────────────────────────────────────
#   input_dir.xz  (horizontal)  —  hop direction / air-steer / hover-drift.
#   input_dir.y   (vertical up) —  values ≥ hover_input_threshold activate hover.
#
#   Hop cadence is *physics-driven*, not timer-driven.
#   Hold a direction → hops fire automatically on every grounded frame that is
#   not in post-landing recovery.  Arc duration + recovery_time = perceived cadence.
#
#   Hover → small h-input drifts; h-input ≥ hover_hop_threshold fires a hop and
#   exits hover immediately.
#
# ── Required children ─────────────────────────────────────────────────────────
#   GroundRay (RayCast3D)  — long downward (~6 u), spawn floating gate only.
#                            Disabled permanently once terrain is confirmed.
#   LandRay   (RayCast3D)  — short downward (~2 u), always enabled.
#                            Code never hard-depends on it — nil-safe.
#                            Use from animation tree to pre-prep landing pose.
#
# ── Scene pattern ─────────────────────────────────────────────────────────────
#   A concrete species (e.g. Grasshopper) extends PawnHopper, sets exports,
#   and overrides interact / alt_interact / get_pawn_info exactly like Bee does
#   for FlightPawn.

@abstract
class_name PawnHopper
extends PawnBase

# ── Raycasts ──────────────────────────────────────────────────────────────────
@onready var ground_ray: RayCast3D = $GroundRay
@onready var land_ray:   RayCast3D = $LandRay   # optional — nil-safe throughout

# ── Hop ───────────────────────────────────────────────────────────────────────
## Horizontal launch impulse at full hop.
@export var hop_h_force:             float = 85.0
## Vertical launch impulse at full hop.
@export var hop_v_force:             float = 48.0
## Minimum h-input magnitude (XZ) before a hop fires.  Prevents stick-drift hops.
@export var hop_input_threshold:     float = 0.15
## Seconds of squash / settle after landing.  This IS the inter-hop gap.
@export var landing_recovery_time:   float = 0.12
## Seconds of grace before treating "not on floor" as a ledge fall.
@export var coyote_time:             float = 0.08

# ── Gravity & surface ─────────────────────────────────────────────────────────
@export var gravity_force:           float = 98.0
## Surface-normal tracking speed while grounded.
@export var surface_align_rate:      float = 10.0
## Surface-normal snap speed on touchdown — snappier = crispier landing.
@export var surface_align_rate_land: float = 28.0

# ── Air phase ─────────────────────────────────────────────────────────────────
## Small XZ steering acceleration while airborne.
@export var air_control:             float = 14.0
## XZ-only drag in air.  Does NOT damp Y — let gravity shape the arc cleanly.
@export var air_damp_xz:             float = 0.4

# ── Hover ─────────────────────────────────────────────────────────────────────
## input_dir.y must reach this to enter hover.
@export var hover_input_threshold:   float = 0.30
## input_dir.xz must reach this to fire a hop *out of* hover.
## Higher than hop_input_threshold so drifting doesn't accidentally pop you out.
@export var hover_hop_threshold:     float = 0.55
## How fast vertical velocity bleeds to zero during hover (altitude hold).
## Higher = snappier altitude lock.  Lower = floatier / more gradual settle.
@export var hover_y_damp:            float = 8.0
## XZ acceleration while hovering (slower than a hop — wings are busy).
@export var hover_h_accel:           float = 18.0
## XZ drag while hovering.
@export var hover_h_damp:            float = 4.5
## Maximum continuous hover duration in seconds.
@export var hover_max_time:          float = 2.5
## Hover stamina recovered per second while fully grounded (not in recovery).
@export var hover_recharge_rate:     float = 0.55
## Vertical velocity clamp while hovering — keeps hover from drifting too fast.
@export var hover_v_clamp:           float = 8.0
## Horizontal force on the hop fired from hover (no coil = less distance).
@export var hover_hop_h_force:         float = 55.0
## Vertical force on the hop fired from hover (no coil = less height).
@export var hover_hop_v_force:         float = 28.0
## input_dir.y must reach this (negative) to trigger a short hop.
@export var short_hop_input_threshold: float = 0.30
## Horizontal impulse — tuned to stay under half a hex (< 2 u at default gravity).
@export var short_hop_h_force:         float = 48.0
## Vertical impulse.  At default gravity: ~0.245 s hang / ~1.96 u travel.
@export var short_hop_v_force:         float = 28.0

# ── Visual ────────────────────────────────────────────────────────────────────
@export var face_rate:               float = 20.0
## How fast pitch settles to 0 while grounded / hovering.
@export var level_rate:              float = 14.0
## Rate the body pitches to match vertical velocity arc.
@export var air_pitch_rate:          float = 8.0
## Maximum nose-up angle (degrees) at the apex / ascent.
@export var max_nose_up_deg:         float = 38.0
## Maximum nose-down angle (degrees) on the descent.
@export var max_nose_down_deg:       float = 52.0

# ════════════════════════════════════════════════════════════════════════════ #
#  Internal state
# ════════════════════════════════════════════════════════════════════════════ #

enum HopState { GROUNDED, AIRBORNE, HOVERING }

var _hop_state:      HopState = HopState.GROUNDED
var _terrain_ready:  bool     = false

# Surface
var _surface_normal: Vector3  = Vector3.UP
var _facing_dir:     Vector3  = Vector3.FORWARD

# Grounded sub-state
var _in_recovery:    bool     = false
var _recovery_timer: float    = 0.0
var _coyote_timer:   float    = 0.0

# Hover
var _hover_stamina:  float    = 1.0   # 0..1

# Visual (Euler angles — used only in AIRBORNE / HOVERING)
var _air_pitch:      float    = 0.0
var _yaw:            float    = 0.0

var wants_short_hop:bool = false


# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	super()
	# On save-load respawn, _respawn_colony_pawns() sets pawn_id before add_child(),
	# so PawnBase._ready() wires state before we get here. If state is set, terrain
	# was already confirmed before save — skip the GroundRay spawn gate immediately.
	if pawn_id >= 0 and state != null:
		_terrain_ready     = true
		if ground_ray:
			ground_ray.enabled = false

# ════════════════════════════════════════════════════════════════════════════ #
#  Private helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _project_onto_surface(v: Vector3, n: Vector3) -> Vector3:
	var p: Vector3 = v - n * v.dot(n)
	return p if p.length_squared() >= 0.0001 else Vector3.ZERO


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


# Fires a hop impulse in h_dir (surface-projected, normalised world-space XZ).
# Does NOT call move_and_slide — the calling tick function owns that.
func _fire_hop(h_dir: Vector3, h_force: float = -1.0, v_force: float = -1.0) -> void:
	var hf: float = h_force if h_force >= 0.0 else hop_h_force
	var vf: float = v_force if v_force >= 0.0 else hop_v_force
	velocity   = h_dir * hf
	velocity  += _surface_normal * vf

	_hop_state   = HopState.AIRBORNE
	up_direction = Vector3.UP

	# Snap visual yaw to match launch so the arc looks intentional immediately.
	var flat: Vector3 = Vector3(h_dir.x, 0.0, h_dir.z)
	if flat.length_squared() > 0.001:
		_yaw = atan2(flat.x, flat.z)


# Called the frame we detect is_on_floor() after being AIRBORNE or HOVERING.
func _on_land() -> void:
	_surface_normal = get_floor_normal()
	up_direction    = _surface_normal
	_hop_state      = HopState.GROUNDED
	_in_recovery    = true
	_recovery_timer = landing_recovery_time
	_coyote_timer   = coyote_time
	_air_pitch      = 0.0   # face_direction will lerp this to level

# ════════════════════════════════════════════════════════════════════════════ #
#  PawnBase overrides
# ════════════════════════════════════════════════════════════════════════════ #

func move_in_plane(input_dir: Vector3, delta: float) -> void:
	# ── Spawn floating gate ───────────────────────────────────────────────────
	if not _terrain_ready:
		if ground_ray and ground_ray.is_colliding():
			_terrain_ready     = true
			ground_ray.enabled = false
			_coyote_timer      = coyote_time
		else:
			return

	# ── Global timer tick ────────────────────────────────────────────────────
	if _in_recovery:
		_recovery_timer -= delta
		if _recovery_timer <= 0.0:
			_in_recovery = false

	# Recharge hover stamina only while fully settled on the ground.
	if _hop_state == HopState.GROUNDED and not _in_recovery:
		_hover_stamina = minf(_hover_stamina + hover_recharge_rate * delta, 1.0)

	# ── State dispatch ───────────────────────────────────────────────────────
	match _hop_state:
		HopState.GROUNDED:  _tick_grounded(input_dir, delta)
		HopState.AIRBORNE:  _tick_airborne(input_dir, delta)
		HopState.HOVERING:  _tick_hovering(input_dir, delta)


# ── Grounded tick ─────────────────────────────────────────────────────────────
func _tick_grounded(input_dir: Vector3, delta: float) -> void:
	# Surface tracking —  use the fast rate during the post-land squash window.
	var align_rate: float = surface_align_rate_land if _in_recovery else surface_align_rate
	if is_on_floor():
		_coyote_timer = coyote_time
		var t: float = 1.0 - pow(0.0001, delta * align_rate)
		# Normalize get_floor_normal() input — ramp terrain can return slightly
		# off-unit vectors that cause Basis.set_axis_angle() to assert.
		var floor_n: Vector3 = get_floor_normal()
		if floor_n.length_squared() > 0.0001:
			floor_n = floor_n.normalized()
		_surface_normal = _surface_normal.slerp(floor_n, t).normalized()
	else:
		_coyote_timer -= delta
		if _coyote_timer <= 0.0:
			# Walked off a ledge — enter freefall, next airborne tick handles it.
			_hop_state   = HopState.AIRBORNE
			up_direction = Vector3.UP
			# Apply this frame's gravity before bailing out.
			velocity.y -= gravity_force * delta
			move_and_slide()
			return

	# Always assign a precisely unit-length vector — Godot's CharacterBody3D
	# asserts normalization internally when building the surface basis.
	up_direction = _surface_normal.normalized()

	# Stick to surface.  Strong friction kills any residual momentum.
	velocity     *= maxf(0.0, 1.0 - 22.0 * delta)
	velocity     += _surface_normal * -gravity_force * delta
	move_and_slide()

	if _in_recovery:
		return   # no input accepted during squash/settle

	# ── Hover entry ──────────────────────────────────────────────────────────
	if input_dir.y >= hover_input_threshold and _hover_stamina > 0.0:
		_hop_state   = HopState.HOVERING
		up_direction = Vector3.UP
		velocity.y   = 0.0   # instant altitude lock on activation
		return

	# ── Short hop (direction + move_down) ───────────────────────────────────
	# Requires an active horizontal direction — move_down alone does nothing.
	# move_down + direction = shortened hop.  move_up + direction = hover (above).
	var h: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
	wants_short_hop = input_dir.y <= -short_hop_input_threshold
	if wants_short_hop and h.length() >= hop_input_threshold:
		var sh_dir: Vector3 = _project_onto_surface(h.normalized(), _surface_normal)
		if sh_dir.length_squared() < 0.001:
			sh_dir = _project_onto_surface(Vector3.FORWARD, _surface_normal)
		if sh_dir.length_squared() > 0.001:
			_fire_hop(sh_dir.normalized(), short_hop_h_force, short_hop_v_force)
		return

	# ── Normal hop entry ─────────────────────────────────────────────────────
	if h.length() >= hop_input_threshold:
		var h_dir: Vector3 = _project_onto_surface(h.normalized(), _surface_normal)
		if h_dir.length_squared() < 0.001:
			# Degenerate case (e.g. pure vertical surface) — fall back to forward.
			h_dir = _project_onto_surface(Vector3.FORWARD, _surface_normal)
		if h_dir.length_squared() > 0.001:
			_fire_hop(h_dir.normalized())
			# move_and_slide already happened above; hop velocity applies next frame.
			# This is intentional: one-frame lag is imperceptible at 60 Hz and keeps
			# move_and_slide to exactly one call per tick.


# ── Airborne tick ─────────────────────────────────────────────────────────────
func _tick_airborne(input_dir: Vector3, delta: float) -> void:
	# Hover catch — player held up-input before/during the arc.
	if input_dir.y >= hover_input_threshold and _hover_stamina > 0.0:
		_hop_state   = HopState.HOVERING
		up_direction = Vector3.UP
		velocity.y   = 0.0   # instant altitude lock on activation
		# Fall through — XZ movement and move_and_slide still run this frame.

	# Gravity — always applied even on hover-entry frame so the blend feels natural.
	velocity.y -= gravity_force * delta

	# Light XZ air-steering.
	var h: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
	if h.length() > 1.0:
		h = h.normalized()
	velocity += h * air_control * delta

	# XZ drag only — Y is shaped by gravity alone.
	velocity.x *= maxf(0.0, 1.0 - air_damp_xz * delta)
	velocity.z *= maxf(0.0, 1.0 - air_damp_xz * delta)

	move_and_slide()

	if is_on_floor():
		_on_land()


# ── Hover tick ────────────────────────────────────────────────────────────────
func _tick_hovering(input_dir: Vector3, delta: float) -> void:
	# Drain stamina.
	_hover_stamina -= delta / hover_max_time
	if _hover_stamina <= 0.0:
		_hover_stamina = 0.0
		_hop_state     = HopState.AIRBORNE   # wings gave out — now falling
		up_direction   = Vector3.UP

	# Wing release — player dropped the up-input.
	if input_dir.y < hover_input_threshold:
		_hop_state   = HopState.AIRBORNE
		up_direction = Vector3.UP

	# ── Directional hop from hover ────────────────────────────────────────────
	# Only when still in HOVERING (guards against the release cases above).
	#if _hop_state == HopState.HOVERING:
		#var h: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
		#if h.length() >= hover_hop_threshold:
			## Pop out of hover into a directional hop.
			## Use world-UP as launch surface (no coil, so vertical is reduced).
			#_surface_normal = Vector3.UP
			#_fire_hop(h.normalized(), hover_hop_h_force, hover_hop_v_force)
			## State is now AIRBORNE.  Fall through to shared physics below.

	# ── Hover physics (only if still hovering after all checks above) ─────────
	if _hop_state == HopState.HOVERING:
		# Altitude hold: lerp vertical velocity toward 0.
		# Works for any entry velocity — upward arc, freefall, or ground liftoff.
		# hover_y_damp controls how quickly the altitude locks in.
		var t_y: float = 1.0 - pow(0.0001, delta * hover_y_damp)
		velocity.y     = lerp(velocity.y, 0.0, t_y)

		# Horizontal drift.
		var h_steer: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
		if h_steer.length() > 1.0:
			h_steer = h_steer.normalized()
		velocity   += h_steer * hover_h_accel * delta
		velocity.x *= maxf(0.0, 1.0 - hover_h_damp * delta)
		velocity.z *= maxf(0.0, 1.0 - hover_h_damp * delta)
	else:
		# We transitioned to AIRBORNE this frame (wing-out / release / hop).
		# Apply normal gravity for the remainder of this tick.
		velocity.y -= gravity_force * delta
		velocity.x *= maxf(0.0, 1.0 - air_damp_xz * delta)
		velocity.z *= maxf(0.0, 1.0 - air_damp_xz * delta)

	move_and_slide()

	if is_on_floor():
		_on_land()


# ════════════════════════════════════════════════════════════════════════════ #
#  face_direction
# ════════════════════════════════════════════════════════════════════════════ #

func face_direction(input_dir: Vector3, delta: float, gfx: Node3D = null) -> void:
	if not _terrain_ready:
		return
	match _hop_state:
		HopState.GROUNDED:  _face_grounded(input_dir, delta, gfx)
		HopState.AIRBORNE:  _face_airborne(delta, gfx)
		HopState.HOVERING:  _face_hovering(input_dir, delta, gfx)


func _face_grounded(input_dir: Vector3, delta: float, gfx: Node3D) -> void:
	# While grounded, drive _facing_dir from horizontal input rather than velocity
	# (velocity is near-zero; input is the only meaningful signal here).
	var h: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
	if h.length() >= hop_input_threshold:
		var h_on_plane: Vector3 = _project_onto_surface(h.normalized(), _surface_normal)
		if h_on_plane.length_squared() > 0.0001:
			var t: float = 1.0 - pow(0.0001, delta * face_rate)
			_facing_dir = _facing_dir.slerp(h_on_plane.normalized(), t).normalized()
	else:
		# No input — reproject _facing_dir onto the current surface plane (handles
		# slope transitions so the bug doesn't tilt off the surface visually).
		var rp: Vector3 = _project_onto_surface(_facing_dir, _surface_normal)
		if rp.length_squared() > 0.0001:
			var t: float = 1.0 - pow(0.0001, delta * level_rate)
			_facing_dir = _facing_dir.slerp(rp.normalized(), t).normalized()

	# Level out the air pitch accumulated during the arc.
	_air_pitch = lerp_angle(_air_pitch, 0.0, 1.0 - pow(0.0001, delta * level_rate * 2.0))

	var on_plane: Vector3 = _project_onto_surface(_facing_dir, _surface_normal)
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


func _face_airborne(delta: float, gfx: Node3D) -> void:
	var spd: float = velocity.length()

	# Yaw — tracks horizontal velocity.
	var flat: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() > 0.001 and spd > 0.5:
		var t_yaw: float = 1.0 - pow(0.0001, delta * face_rate)
		_yaw = lerp_angle(_yaw, atan2(flat.x, flat.z), t_yaw)

	# Pitch — maps vertical velocity component to nose angle.
	# Ascending  → nose up.   Descending → nose down.
	var v_norm: float    = clamp(velocity.y / maxf(spd, 0.001), -1.0, 1.0)
	var target_pitch: float = \
		-deg_to_rad(max_nose_up_deg)   * maxf(v_norm,  0.0) + \
		 deg_to_rad(max_nose_down_deg) * maxf(-v_norm, 0.0)

	var t_pitch: float = 1.0 - pow(0.0001, delta * air_pitch_rate)
	_air_pitch = lerp_angle(_air_pitch, target_pitch, t_pitch)

	var air_basis: Basis = Basis.from_euler(Vector3(_air_pitch, _yaw, 0.0))
	if gfx:
		gfx.global_transform.basis = air_basis
	else:
		global_transform.basis = air_basis


func _face_hovering(input_dir: Vector3, delta: float, gfx: Node3D) -> void:
	# Level out and face horizontal input (or maintain last direction if drifting).
	var h: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
	if h.length() > hop_input_threshold:
		var t: float = 1.0 - pow(0.0001, delta * face_rate)
		_facing_dir = _facing_dir.slerp(h.normalized(), t).normalized()

	_air_pitch = lerp_angle(_air_pitch, 0.0, 1.0 - pow(0.0001, delta * level_rate))

	# Hover orientation uses world-UP (flat basis, not surface-aligned).
	var hover_basis: Basis = _build_basis(Vector3.UP, _facing_dir)
	if gfx:
		gfx.global_transform.basis = hover_basis
	else:
		global_transform.basis = hover_basis


# ════════════════════════════════════════════════════════════════════════════ #
#  Utility
# ════════════════════════════════════════════════════════════════════════════ #

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


# ── Read-only accessors — for AI, animation trees, HUD ───────────────────────
## True during the post-landing squash window.  Useful for landing animation.
func in_recovery()   -> bool:      return _in_recovery
func is_grounded()   -> bool:      return _hop_state == HopState.GROUNDED
func is_airborne()   -> bool:      return _hop_state == HopState.AIRBORNE
func is_hovering()   -> bool:      return _hop_state == HopState.HOVERING
## 0..1 remaining hover stamina.  Useful for a wing-buzz VFX intensity driver.
func hover_stamina() -> float:     return _hover_stamina
func get_hop_state() -> HopState:  return _hop_state
## True when LandRay is colliding — ground is within ~2 units.  Pre-warn animation.
func near_ground()   -> bool:      return land_ray != null and land_ray.is_colliding()
