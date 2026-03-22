# world_root.gd
# res://world/world_root.gd
#
# Root script for the main game scene. Responsibilities:
#   - Initialize HexWorldState with the authored HexTerrainConfig
#   - Spawn the player bee pawn and camera rig
#   - Hand the player node reference to HexTerrainManager
#   - Register the player colony via ColonyState
#   - Connect global shader parameters that the terrain/plant shaders need
#
# SCENE TREE EXPECTED:
#   WorldRoot  (Node3D, this script)
#   ├── HexTerrainManager    (res://world/hex_terrain_manager.tscn)
#   ├── DirectionalLight3D
#   ├── WorldEnvironment
#   └── [bee and camera_rig spawned at runtime]
#
# AUTOLOAD ORDER REMINDER:
#   EventBus → HexWorldState → TimeService → HiveSystem →
#   TerritorySystem → ColonyState → JobSystem → PawnRegistry → SaveManager

extends Node3D

# ── Exports ───────────────────────────────────────────────────────────────────
@export var time_config: TimeConfig   # TimeConfig
@export var terrain_config: HexTerrainConfig
@export var terrain_manager_path: NodePath = ^"HexTerrainManager"

@export_group("Spawn")
@export var bee_spawn_position: Vector3 = Vector3(0.0, 2.0, 0.0)

@export_group("Wind shader params")
@export var wind_strength:   float = 0.66
@export var wind_speed:      float = 1.2
@export var wind_scale:      float = 0.52
@export var gust_strength:   float = 0.4
@export var gust_speed:      float = 0.5
@export var shiver_strength: float = 0.03

@export_group("Bending shader params")
@export var bend_radius:   float = 6.66
@export var bend_strength: float = 1.5

@export_group("Bounce shader params")
@export var bounce_duration: float = 0.8
@export var bounce_squash:   float = 0.6
@export var bounce_stretch:  float = 0.6

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var _terrain_manager: HexTerrainManager = get_node(terrain_manager_path)

var _bee: CharacterBody3D = null
var _camera_rig: Node3D   = null

# ── Packed scenes ─────────────────────────────────────────────────────────────
const BEE_SCENE        := preload("res://pawns/bee/bee.tscn")
const CAMERA_RIG_SCENE := preload("res://camera/camera_rig.tscn")

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	if not terrain_config:
		push_error("WorldRoot: no HexTerrainConfig assigned.")
		return
	_init_world()
	_register_global_shader_params()
	_spawn_player()
	_init_colony()
	_place_starter_hive()
	
	# --- TEMP DEBUG ---
	print("_bee: ", _bee)
	print("_camera_rig: ", _camera_rig)
	print("CameraRig.for_player(1): ", CameraRig.for_player(1))
	if _camera_rig:
		print("camera_rig target: ", _camera_rig.target)
	# --- END DEBUG ---
	
	var gb := GrassBender.new()
	add_child(gb)
	gb.name = "GrassBender"
	

func _process(delta: float) -> void:
	_tick_wind_shader(delta)

# ════════════════════════════════════════════════════════════════════════════ #
#  World initialisation
# ════════════════════════════════════════════════════════════════════════════ #

func _init_world() -> void:
	# HexWorldState.initialize() builds registry, baseline, simulation,
	# registers engine_time global shader param, and loads saved deltas.
	HexWorldState.initialize(terrain_config)
	if time_config:
		TimeService.initialize(time_config)
	else:
		# Fallback: use defaults (600s days, 7 days/season)
		TimeService.initialize(null)
	var start_cell: Vector2i = _find_world_start()

	# Find an adjacent non-tree cell for the bee to spawn at
	var spawn_cell: Vector2i = start_cell
	for neighbor: Vector2i in HexWorldBaseline.hex_ring(start_cell, 1):
		var obj_id: String = HexWorldState.baseline.get_baseline_object_id(neighbor)
		if obj_id.is_empty():
			spawn_cell = neighbor
			break

	var w: Vector2 = HexConsts.AXIAL_TO_WORLD(spawn_cell.x, spawn_cell.y)
	bee_spawn_position = Vector3(w.x, 8.0, w.y)

	if not _terrain_manager:
		push_error("WorldRoot: HexTerrainManager node not found at path '%s'" \
			% terrain_manager_path)

func _register_global_shader_params() -> void:
	# Add all params once. global_shader_parameter_add errors if called twice
	# so we track which ones we've registered this session.
	_add_shader_param(&"wind_strength",   RenderingServer.GLOBAL_VAR_TYPE_FLOAT, wind_strength)
	_add_shader_param(&"wind_speed",      RenderingServer.GLOBAL_VAR_TYPE_FLOAT, wind_speed)
	_add_shader_param(&"wind_scale",      RenderingServer.GLOBAL_VAR_TYPE_FLOAT, wind_scale)
	_add_shader_param(&"gust_strength",   RenderingServer.GLOBAL_VAR_TYPE_FLOAT, gust_strength)
	_add_shader_param(&"gust_speed",      RenderingServer.GLOBAL_VAR_TYPE_FLOAT, gust_speed)
	_add_shader_param(&"shiver_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, shiver_strength)
	_add_shader_param(&"bend_radius",     RenderingServer.GLOBAL_VAR_TYPE_FLOAT, bend_radius)
	_add_shader_param(&"bend_strength",   RenderingServer.GLOBAL_VAR_TYPE_FLOAT, bend_strength)
	_add_shader_param(&"bender_count",    RenderingServer.GLOBAL_VAR_TYPE_INT,   0)
	_add_shader_param(&"bounce_duration", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, bounce_duration)
	_add_shader_param(&"bounce_squash",   RenderingServer.GLOBAL_VAR_TYPE_FLOAT, bounce_squash)
	_add_shader_param(&"bounce_stretch",  RenderingServer.GLOBAL_VAR_TYPE_FLOAT, bounce_stretch)




func _add_shader_param(param_name: StringName, type: int, value: Variant) -> void:
	# global_shader_parameter_add is safe to call at runtime.
	# It will print an error if the param already exists from a previous run
	# in the same editor session — suppress by erasing first on re-init.
	RenderingServer.global_shader_parameter_remove(param_name)
	RenderingServer.global_shader_parameter_add(param_name, type, value)


static func _set_global_param(name: StringName, value: Variant) -> void:
	if RenderingServer.global_shader_parameter_get(name) == null:
		var type: int = _infer_global_param_type(value)
		RenderingServer.global_shader_parameter_add(name, type, value)
	else:
		RenderingServer.global_shader_parameter_set(name, value)

static func _infer_global_param_type(value: Variant) -> int:
	match typeof(value):
		TYPE_FLOAT:  return RenderingServer.GLOBAL_VAR_TYPE_FLOAT
		TYPE_INT:    return RenderingServer.GLOBAL_VAR_TYPE_INT
		TYPE_VECTOR2: return RenderingServer.GLOBAL_VAR_TYPE_VEC2
		TYPE_VECTOR3: return RenderingServer.GLOBAL_VAR_TYPE_VEC3
		TYPE_COLOR:   return RenderingServer.GLOBAL_VAR_TYPE_COLOR
		TYPE_OBJECT:
			if value is Texture2D:
				return RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D
		_:
			return RenderingServer.GLOBAL_VAR_TYPE_FLOAT
	return RenderingServer.GLOBAL_VAR_TYPE_FLOAT

# ════════════════════════════════════════════════════════════════════════════ #
#  Player spawn
# ════════════════════════════════════════════════════════════════════════════ #

func _spawn_player() -> void:
	_bee = BEE_SCENE.instantiate() as CharacterBody3D
	if not _bee:
		push_error("WorldRoot: failed to instantiate bee scene")
		return

	_camera_rig = CAMERA_RIG_SCENE.instantiate() as Node3D
	if not _camera_rig:
		push_error("WorldRoot: failed to instantiate camera_rig scene")
		return

	add_child(_bee)
	add_child(_camera_rig)
	
	if _terrain_manager:
		_terrain_manager.player = _bee
	
	_bee.global_position = bee_spawn_position
	_bee.pawn_id = 0
	_bee.add_to_group("pawns")
	_bee.add_to_group("grass_bender")

	PossessionManager.request_possess(1, 0)

	# Signal that player pawn is in the tree and ready
	EventBus.player_pawn_ready.emit(_bee, 1)

# ════════════════════════════════════════════════════════════════════════════ #
#  Colony init
# ════════════════════════════════════════════════════════════════════════════ #

func _init_colony() -> void:
	# Create player colony (id 0) if it doesn't exist yet.
	# SaveManager will populate this from save data on subsequent loads.
	if ColonyState.get_player_colony() == null:
		var colony_id: int = ColonyState.create_colony()
		assert(colony_id == 0, "Player colony must always be id 0")


func _place_starter_hive() -> void:
	if not HiveSystem.get_hives_for_colony(0).is_empty():
		return

	var anchor_cell: Vector2i = HexConsts.WORLD_TO_AXIAL(
		bee_spawn_position.x,
		bee_spawn_position.z
	)

	# The hive anchors at the tree cell — spawn_position is the adjacent
	# empty cell, so step back to the tree
	var hive_cell: Vector2i = _find_nearest_tree_cell(anchor_cell, 3)
	if hive_cell == Vector2i(-9999, -9999):
		hive_cell = anchor_cell

	var hive_id: int = HiveSystem.register_hive(hive_cell, 0, -1, true, 16, 6)

	var queen_id: int = ColonyState.get_queen_id(0)
	if queen_id >= 0:
		HiveSystem.set_queen_bed(hive_id, 0, queen_id)

	print("WorldRoot: starter hive %d placed at %s (colony 0)" % [hive_id, hive_cell])

## Search hex rings outward from origin for the nearest TREE category cell.
## Returns Vector2i(-9999, -9999) if none found within max_radius.
func _find_nearest_tree_cell(origin: Vector2i, max_radius: int) -> Vector2i:
	var biome = HexWorldState.cfg.get_cell_biome(0, 0)
	for r in range(1, 13):
		for cell in HexWorldBaseline.hex_ring(Vector2i(0,0), r):
			var b = HexWorldState.cfg.get_cell_biome(cell.x, cell.y)
			if b != biome:
				print("first different biome at ring %d: %s = %s" % [r, cell, b])
				return Vector2i.ZERO
				
	var found_categories: Dictionary = {}
	for r: int in range(0, max_radius + 1):
		var ring: Array = HexWorldBaseline.hex_ring(origin, r) if r > 0 \
			else [origin]
		for cell: Vector2i in ring:
			var state: HexCellState = HexWorldState.get_cell(cell)
			if state.occupied:
				found_categories[state.category] = \
					found_categories.get(state.category, 0) + 1
			if state.occupied and state.category == HexGridObjectDef.Category.TREE:
				return cell
	print("_find_nearest_tree: categories found in radius %d: %s" % [max_radius, found_categories])
	return Vector2i(-9999, -9999)

func _find_world_start() -> Vector2i:
	# Biomes that can contain valid hive anchor trees
	var good_biomes: Array[StringName] = [
		&"deciduous", &"grassland", &"savanna", &"beach"
	]
	for r in range(0, 120):
		for cell: Vector2i in HexWorldBaseline.hex_ring(Vector2i(0, 0), r):
			var biome: StringName = HexWorldState.cfg.get_cell_biome(cell.x, cell.y)
			if not good_biomes.has(biome):
				continue
			var obj_id: String = HexWorldState.baseline.get_baseline_object_id(cell)
			if obj_id.is_empty():
				continue
			var def: HexGridObjectDef = HexWorldState.registry.get_definition(obj_id)
			if def != null and def.category == HexGridObjectDef.Category.TREE:
				return cell
	return Vector2i(0, 0)


# ════════════════════════════════════════════════════════════════════════════ #
#  Per-frame shader updates
# ════════════════════════════════════════════════════════════════════════════ #

func _tick_wind_shader(_delta: float) -> void:
	# engine_time is already ticked by HexWorldState._process().
	# Wind params are static — only update if you add runtime wind changes.
	pass
