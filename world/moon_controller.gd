# moon_controller.gd
# res://world/moon_controller.gd
#
# Attach to a Node3D child of WorldRoot named "MoonController".
# Drives a secondary DirectionalLight3D (moonlight) and a billboard
# MeshInstance3D (visible moon disc) from TimeService.
#
# SCENE SETUP:
#   MoonController (Node3D, this script)
#   ├── MoonLight    (DirectionalLight3D)
#   └── MoonDisc     (MeshInstance3D — QuadMesh, billboard, unshaded material)
#
# MOON ARC:
#   The moon runs exactly opposite the sun on the X axis.
#   When sun_angle = 0° (dawn horizon), moon_angle = -180° (setting).
#   When sun_angle = -90° (noon), moon_angle = 90° (midnight overhead).
#   moon_angle = sun_angle - 180°   (always opposite)
#
# MOON PHASES:
#   8 phases over a 28-day cycle driven by TimeService.current_day.
#   Phase 0 = new moon (dark), Phase 4 = full moon (bright).
#   Atlas: 8 frames in a row, each frame is 1/8 of the texture width.
#   If you only have a full moon texture, set phase_frame_count = 1.
#
# MOON DISC POSITIONING:
#   The disc is placed at a fixed distance from the camera origin along
#   the moon light direction. It uses BILLBOARD_ENABLED on the material
#   so it always faces the camera, but its world position tracks the
#   light direction so it appears at the right spot in the sky.

class_name MoonController
extends Node3D

# ── Scene refs ────────────────────────────────────────────────────────────────
@export var moon_light: DirectionalLight3D
@export var moon_disc:  MeshInstance3D
@export var sun_light:  DirectionalLight3D   # needed to read current sun angle

# ── Moon light tuning ─────────────────────────────────────────────────────────
@export_group("Moon Light")
@export var moon_max_energy:   float = 0.12
@export var moon_color_full:   Color = Color(0.75, 0.82, 1.00)   # cool blue-white
@export var moon_color_crescent: Color = Color(0.45, 0.52, 0.70) # dimmer, bluer

# ── Moon disc tuning ──────────────────────────────────────────────────────────
@export_group("Moon Disc")
@export var disc_distance:     float = 800.0    # world units from origin
@export var disc_size:         float = 18.0     # world units diameter
@export var phase_frame_count: int   = 8        # frames in phase atlas
@export var phase_cycle_days:  int   = 28       # days per full lunar cycle
@export var moon_texture:      Texture2D        # phase atlas — 8 frames wide

# ── Runtime ───────────────────────────────────────────────────────────────────
var _mat: ShaderMaterial = null

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	_setup_disc()

func _process(_delta: float) -> void:
	if moon_light == null or sun_light == null:
		return
	if TimeService.config == null:
		return

	var sun_angle: float = _get_moon_angle()
	var phase:     float = TimeService.day_phase
	var split:     float = TimeService.config.get("day_night_split")

	_update_moon_light(sun_angle, phase, split)
	_update_moon_disc(sun_angle)

# ════════════════════════════════════════════════════════════════════════════ #
#  Setup
# ════════════════════════════════════════════════════════════════════════════ #

func _setup_disc() -> void:
	if moon_disc == null:
		return

	# Build a simple unshaded billboard material in code if none assigned
	if moon_disc.material_override == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode     = BaseMaterial3D.BILLBOARD_ENABLED
		mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color       = Color.WHITE
		mat.no_depth_test      = true   # always renders on top of sky
		if moon_texture:
			mat.albedo_texture = moon_texture
		moon_disc.material_override = mat
	else:
		_mat = moon_disc.material_override as ShaderMaterial

	# Set quad size
	var quad: QuadMesh = moon_disc.mesh as QuadMesh
	if quad:
		quad.size = Vector2(disc_size, disc_size)

# ════════════════════════════════════════════════════════════════════════════ #
#  Moon light
# ════════════════════════════════════════════════════════════════════════════ #

func _get_moon_angle() -> float:
	# Moon runs its own arc during night only
	# Night spans phase split→1.0
	# moon goes from -180° (just set, below west horizon) 
	# through 90° (midnight overhead) to 0° (about to rise east)
	var split: float = TimeService.config.get("day_night_split")
	var phase: float = TimeService.day_phase
	
	var night_t: float
	if not TimeService.is_daytime:
		night_t = (phase - split) / (1.0 - split)
	else:
		# During day: moon is below horizon, park it
		night_t = 0.5   # midnight position, below opposite horizon
	
	night_t = clampf(night_t, 0.0, 1.0)
	# -180°=just set west, 90°=midnight overhead, 0°=about to rise east
	# That's -180 → 90 → 0 — but as a continuous arc: -180 → 0 going through -90
	return lerpf(-180.0, 0.0, night_t)

func _update_moon_light(sun_angle: float, phase: float, split: float) -> void:
	var moon_angle: float = _get_moon_angle()
	moon_light.rotation_degrees = Vector3(moon_angle, -30.0, 0.0)
	
	var moon_rad: float       = deg_to_rad(moon_angle)
	var moon_elevation: float = -sin(moon_rad)
	
	if moon_elevation <= 0.0:
		moon_light.light_energy = 0.0
		return
	
	var phase_t: float      = _get_phase_t()
	var brightness: float   = lerpf(0.02, moon_max_energy, phase_t)
	var horizon_fade: float = clampf(moon_elevation / 0.1, 0.0, 1.0)
	moon_light.light_energy = brightness * horizon_fade
	moon_light.light_color  = moon_color_crescent.lerp(moon_color_full, phase_t)
	
	# Fade out during day
	if TimeService.is_daytime:
		var day_t: float        = phase / split
		var sun_elev: float     = sin(day_t * PI)
		moon_light.light_energy *= clampf(1.0 - sun_elev * 4.0, 0.0, 1.0)



# ════════════════════════════════════════════════════════════════════════════ #
#  Moon disc
# ════════════════════════════════════════════════════════════════════════════ #

func _update_moon_disc(_sun_angle: float) -> void:
	if moon_disc == null or moon_light == null:
		return
	
	# Position relative to camera
	var cam: Camera3D = get_viewport().get_camera_3d()
	var origin: Vector3 = cam.global_position if cam else Vector3.ZERO
	
	# Use the moon light's actual forward direction after rotation is applied
	var light_forward: Vector3 = -moon_light.global_transform.basis.z
	moon_disc.global_position = origin + light_forward * disc_distance
	
	var moon_angle: float     = _get_moon_angle()
	var moon_rad: float       = deg_to_rad(moon_angle)
	var moon_elevation: float = -sin(moon_rad)
	
	var disc_alpha: float = clampf(moon_elevation / 0.05, 0.0, 1.0)
	
	if TimeService.is_daytime:
		var split: float    = TimeService.config.get("day_night_split")
		var day_t: float    = TimeService.day_phase / split
		var sun_elev: float = sin(day_t * PI)
		disc_alpha         *= clampf(1.0 - sun_elev * 5.0, 0.0, 1.0)
	
	var mat: StandardMaterial3D = moon_disc.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(1.0, 1.0, 1.0, disc_alpha)
		if moon_texture and phase_frame_count > 1:
			mat.uv1_scale  = Vector3(1.0 / float(phase_frame_count), 1.0, 1.0)
			mat.uv1_offset = Vector3(float(_get_phase_frame()) / float(phase_frame_count), 0.0, 0.0)

# ════════════════════════════════════════════════════════════════════════════ #
#  Phase helpers
# ════════════════════════════════════════════════════════════════════════════ #

## Returns 0..1 where 0=new moon (dark) and 1=full moon (bright)
func _get_phase_t() -> float:
	var day_in_cycle: int = TimeService.current_day % phase_cycle_days
	# Full moon at day 14 (halfway), new moon at 0 and 28
	return (sin(float(day_in_cycle) / float(phase_cycle_days) * TAU - PI * 0.5) + 1.0) * 0.5

## Returns the atlas frame index 0..phase_frame_count-1
func _get_phase_frame() -> int:
	var t: float = _get_phase_t()
	return int(t * float(phase_frame_count - 1) + 0.5)
