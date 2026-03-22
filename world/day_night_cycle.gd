# day_night_cycle.gd
# res://world/day_night_cycle.gd
#
# Drives sun/moon lights and billboard discs from TimeService.
# Attach to any Node child of WorldRoot.
#
# SCENE SETUP:
#   WorldRoot
#   ├── DayNightCycle          (this script)
#   ├── SunLight               (DirectionalLight3D)
#   │   └── MoonLight          (DirectionalLight3D, local rotation X=180)
#   ├── SunDisc                (MeshInstance3D, QuadMesh, billboard material)
#   ├── MoonDisc               (MeshInstance3D, QuadMesh, billboard material)
#   └── WorldEnvironment
#
# Both disc materials need:
#   Shading Mode  = Unshaded
#   Transparency  = Alpha
#   Billboard     = Enabled
#   No Depth Test = true
#   Render Priority = 1

class_name DayNightCycle
extends Node


# ── Sky ───────────────────────────────────────────────────────────────────────
@export_group("Sky")
@export var sky_env:   WorldEnvironment
@export var sky_energy_day:   float = 1.0
@export var sky_energy_night: float = 1.0

@export_subgroup("Day")
@export var sky_top_day:    Color = Color(0.18, 0.45, 0.85)
@export var horizon_day:    Color = Color(0.60, 0.78, 1.00)
@export var ground_day:     Color = Color(0.08, 0.06, 0.04)

@export_subgroup("Dawn")
@export var sky_top_dawn:   Color = Color(0.30, 0.45, 0.70)
@export var horizon_dawn:   Color = Color(0.90, 0.55, 0.30)

@export_subgroup("Dusk")
@export var sky_top_dusk:   Color = Color(0.15, 0.20, 0.55)
@export var horizon_dusk:   Color = Color(0.85, 0.35, 0.15)

@export_subgroup("Night")
@export var sky_top_night:  Color = Color(0.02, 0.02, 0.06)
@export var horizon_night:  Color = Color(0.04, 0.04, 0.10)
@export var ground_night:   Color = Color(0.02, 0.02, 0.02)

# ── Sun ───────────────────────────────────────────────────────────────────────


@export_group("Sun")
@export var sun_light: DirectionalLight3D
@export var sun_disc:  MeshInstance3D
@export var sun_sun_angle:  float = 15.0
@export var sun_max_energy: float = 1.2
@export var sun_disc_distance:  float = 1024
@export var sun_color_day:  Color = Color(1.00, 0.95, 0.85)
@export var sun_color_dawn: Color = Color(1.00, 0.60, 0.30)


# ── Moon ──────────────────────────────────────────────────────────────────────
@export_group("Moon")
@export var moon_light: DirectionalLight3D
@export var moon_disc:  MeshInstance3D
@export var moon_sun_angle:     float = 10.0
@export var moon_min_energy:     float = 0.1
@export var moon_max_energy:     float = 0.33
@export var moon_disc_distance:  float = 1024
@export var moon_color_full:     Color = Color(0.75, 0.82, 1.00)
@export var moon_color_crescent: Color = Color(0.45, 0.52, 0.70)

# ── Runtime ───────────────────────────────────────────────────────────────────
var _sky_material: ProceduralSkyMaterial = null
var _cam: Camera3D = null

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	if sky_env and sky_env.environment and sky_env.environment.sky:
		_sky_material = sky_env.environment.sky.sky_material as ProceduralSkyMaterial
		#if _sky_material:
			## Disable procedural sun disc — we use our own billboard discs
			#_sky_material.sun_angle_max = 0.0
		#else:
			#push_warning("DayNightCycle: sky material is not ProceduralSkyMaterial")

func _process(delta: float) -> void:
	if sun_light == null or TimeService.config == null:
		return

	if _cam == null:
		_cam = get_viewport().get_camera_3d()

	var phase: float = TimeService.day_phase
	var split: float = TimeService.config.get("day_night_split")
	var is_day: bool = TimeService.is_daytime

	_update_sun(phase, split, is_day, delta)
	_update_moon(delta)
	if _sky_material:
		_update_sky(phase, split, is_day)

# ════════════════════════════════════════════════════════════════════════════ #
#  Sun
# ════════════════════════════════════════════════════════════════════════════ #

func _update_sun(phase: float, split: float, is_day: bool, delta: float) -> void:
	if is_day:
		_sky_material.sun_angle_max = sun_sun_angle
		var t: float = phase / split
		sun_light.rotation_degrees = Vector3(lerpf(0.0, -180.0, t), -30.0, 0.0)
		sun_light.light_energy     = 1.0
		var edge_t: float          = clampf(sin(t * PI) * 2.0, 0.0, 1.0)
		sun_light.light_color      = sun_color_dawn.lerp(sun_color_day, edge_t)
		sun_disc.mesh.surface_get_material(0).set("albedo_color", sun_light.light_color)
	else:
		# Continue rotating so child MoonLight arcs correctly
		var night_t: float = clampf((phase - split) / (1.0 - split), 0.0, 1.0)
		sun_light.rotation_degrees = Vector3(lerpf(-180.0, -360.0, night_t), -30.0, 0.0)
		sun_light.light_energy     = lerpf(sun_light.light_energy, 0.0, delta * 3.0)

	_update_disc(sun_disc, sun_light, is_day, sun_disc_distance, delta)


# ════════════════════════════════════════════════════════════════════════════ #
#  Moon
# ════════════════════════════════════════════════════════════════════════════ #

func _update_moon(delta: float) -> void:
	if moon_light == null:
		return

	var moon_forward:   Vector3 = -moon_light.global_transform.basis.z
	var moon_elevation: float   = moon_forward.y   # positive = above horizon

	if moon_elevation < 0.0:
		_sky_material.sun_angle_max = moon_sun_angle
		var phase_t:   float = _get_moon_phase_t()
		var horizon_t: float = clampf(moon_elevation / 0.15, 0.0, 1.0)
		moon_light.light_energy = lerpf(moon_min_energy, moon_max_energy, phase_t) 
		moon_light.light_color  = moon_color_crescent.lerp(moon_color_full, phase_t)
		moon_disc.mesh.surface_get_material(0).set("albedo_color", moon_light.light_color)
	else:
		moon_light.light_energy = lerpf(moon_light.light_energy, 0.0, delta * 3.0)

	# Moon disc
	_update_disc(moon_disc, moon_light, moon_elevation < 0.0, moon_disc_distance, delta)


func _get_moon_phase_t() -> float:
	var day_in_cycle: int = TimeService.current_day % 28
	return (sin(float(day_in_cycle) / 28.0 * TAU - PI * 0.5) + 1.0) * 0.5

# ════════════════════════════════════════════════════════════════════════════ #
#  Sky + fog
# ════════════════════════════════════════════════════════════════════════════ #

func _update_sky(phase: float, split: float, is_day: bool) -> void:
	var sky_t:       float = 0.0
	var dawn_dusk_t: float = 0.0
	var is_pre_noon: bool  = true

	if is_day:
		var day_t: float = phase / split
		sky_t       = sin(day_t * PI)
		dawn_dusk_t = clampf((1.0 - sin(day_t * PI)) * 2.5, 0.0, 1.0)
		is_pre_noon = day_t < 0.5

	var top:     Color = sky_top_night.lerp(sky_top_day, sky_t)
	var horizon: Color = horizon_night.lerp(horizon_day, sky_t)
	var ground:  Color = ground_night.lerp(ground_day, sky_t)

	if dawn_dusk_t > 0.0:
		top     = top.lerp(sky_top_dawn if is_pre_noon else sky_top_dusk, dawn_dusk_t)
		horizon = horizon.lerp(horizon_dawn if is_pre_noon else horizon_dusk, dawn_dusk_t)

	var energy: float = lerpf(sky_energy_night, sky_energy_day, sky_t)

	_sky_material.sky_top_color         = top
	_sky_material.sky_horizon_color     = horizon
	_sky_material.ground_horizon_color  = horizon
	_sky_material.ground_bottom_color   = ground
	_sky_material.sky_energy_multiplier = energy

	if sky_env and sky_env.environment:
		sky_env.environment.fog_light_color = horizon


func _update_disc(
	disc: MeshInstance3D,
	light: DirectionalLight3D,
	above_horizon: bool,
	disc_distance:float,
	delta: float
) -> void:
	if disc == null or _cam == null:
		return

	# Position disc along light's forward direction from camera
	var forward: Vector3 = light.global_transform.basis.z
	disc.global_position = _cam.global_position + forward * disc_distance

	# Elevation — Y component of forward vector (positive = above horizon)
	var elevation: float  = forward.y
	var disc_alpha: float = clampf(elevation / 0.08, 0.0, 1.0) if above_horizon \
		else clampf(-elevation / 0.08, 0.0, 1.0)

	var mat: StandardMaterial3D = disc.material_override as StandardMaterial3D
	if mat:
		var c: Color = mat.albedo_color
		c.a = disc_alpha
		mat.albedo_color = c
