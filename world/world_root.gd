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

var _bee: PawnBase = null
var _camera_rig: Node3D   = null
var _is_reloading: bool = false


# ── Packed scenes ─────────────────────────────────────────────────────────────
const BEE_SCENE        := preload("res://pawns/bee/bee.tscn")
const ANT_SCENE := preload("res://pawns/ant/ant.tscn")
const GRASSHOPPER_SCENE := preload("uid://ch6oki808pp3q")
const CAMERA_RIG_SCENE := preload("res://camera/camera_rig.tscn")

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	if not terrain_config:
		push_error("WorldRoot: no HexTerrainConfig assigned.")
		return
 
	_register_global_shader_params()
 
	# Always initialize world substrate — terrain is procedural and not saved
	_init_world()
 
	var gb := GrassBender.new()
	add_child(gb)
	gb.name = "GrassBender"
 
	var most_recent: String = SaveManager.get_most_recent_slot()
	if not most_recent.is_empty():
		_load_world_from_slot(most_recent)
	else:
		_init_new_world()


func _process(delta: float) -> void:
	_tick_wind_shader(delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("p1_save_game"):
		SaveManager.save_game(SaveManager.AUTOSAVE_SLOT)
	if event.is_action_pressed("p1_load_game") and not _is_reloading:
		_is_reloading = true
		get_tree().reload_current_scene()
		
	if event.is_action_pressed("ui_accept"):   # Enter key by default
		_debug_damage_possessed_pawn()

func _debug_damage_possessed_pawn() -> void:
	var pawn: PawnBase = PossessionManager.get_possessed_pawn(1)
	if pawn == null or pawn.state == null:
		return
	pawn.state.health   = maxf(pawn.state.health - 10.0, 0.0)
	pawn.state.fatigue  = minf(pawn.state.fatigue + 0.1, 1.0)
	EventBus.pawn_hit.emit(-1, pawn.pawn_id, 10.0, [])
	print("debug damage: pawn=%s health=%.1f fatigue=%.2f" % [
		pawn.state.pawn_name, pawn.state.health, pawn.state.fatigue
	])


# ════════════════════════════════════════════════════════════════════════════ #
#  World initialisation
# ════════════════════════════════════════════════════════════════════════════ #
func _init_new_world() -> void:
	_spawn_player()
	_init_colony()
	_place_starter_hive()
	_spawn_ant()
	_spawn_grasshopper()
	if _bee:
		_bee.refresh_name_tag()


func _init_world() -> void:
	# HexWorldState.initialize() builds registry, baseline, simulation,
	# registers engine_time global shader param, and loads saved deltas.
	HexWorldState.initialize(terrain_config)
	HiveSystem.set_visual_parent(self)

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


func _load_world() -> void:
	SaveManager.load_game(SaveManager.get_most_recent_slot())
	_respawn_player_from_save()
	print("calling _respawn_colony_pawns")
	_respawn_colony_pawns()


func _load_world_from_slot(slot_name: String) -> void:
	SaveManager.load_game(slot_name)
	_respawn_player_from_save()
	print("load_world_from_slots]  calling _respawn_colony_pawns")
	_respawn_colony_pawns()

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

	# Connect BEFORE add_child — _ready() fires synchronously during add_child
	EventBus.pawn_registered.connect(_on_player_pawn_registered)

	add_child(_bee)
	add_child(_camera_rig)

	if _terrain_manager:
		_terrain_manager.player = _bee

	_bee.global_position = bee_spawn_position
	_bee.add_to_group("grass_bender")

	EventBus.player_pawn_ready.emit(_bee, 1)


func _respawn_player_from_save() -> void:
	var queen_id: int = ColonyState.get_queen_id(0)
	if queen_id < 0:
		push_warning("WorldRoot: no queen found in save — starting new world")
		_init_new_world()
		return

	var state: PawnState = PawnRegistry.get_state(queen_id)
	if state == null:
		push_warning("WorldRoot: queen state missing from PawnRegistry — starting new world")
		_init_new_world()
		return

	_camera_rig = CAMERA_RIG_SCENE.instantiate() as Node3D
	if _camera_rig:
		add_child(_camera_rig)

	_bee = BEE_SCENE.instantiate() as CharacterBody3D
	if not _bee:
		push_error("WorldRoot: failed to instantiate bee scene on load")
		return

	_bee.pawn_id = queen_id
	# DO NOT connect pawn_registered — bee won't emit it on load path
	add_child(_bee)   # _ready() fires here — PawnBase wires loaded state

	_bee.global_position = state.last_world_pos
	print(state.last_world_pos)
	_bee.add_to_group("grass_bender")

	if _terrain_manager:
		_terrain_manager.player = _bee

	if state.inventory != null:
		_bee.state = state

	_bee.refresh_name_tag()

	# _ready() has fired — possess directly, no signal needed
	PossessionManager.request_possess(1, queen_id)

	EventBus.player_pawn_ready.emit(_bee, 1)
 

func _respawn_colony_pawns() -> void:
	var queen_id: int = ColonyState.get_queen_id(0)
	for pawn_id: int in PawnRegistry.get_pawns_for_colony(0):
		if pawn_id == queen_id:
			continue
		var state: PawnState = PawnRegistry.get_state(pawn_id)
		if state == null or not state.is_alive:
			continue
		if state.scene_path.is_empty():
			push_warning("_respawn_colony_pawns: no scene_path for pawn %d" % pawn_id)
			continue
		var scene: PackedScene = load(state.scene_path) as PackedScene
		if scene == null:
			continue
		var node: CharacterBody3D = scene.instantiate() as CharacterBody3D
		if node == null:
			continue
		node.pawn_id = pawn_id
		add_child(node)
		node.global_position = state.last_world_pos
		var pb: PawnBase = node as PawnBase
		if pb:
			pb.refresh_name_tag()


func _get_pawn_scene(species_id: StringName) -> PackedScene:
	match species_id:
		&"red_ant":   return ANT_SCENE
		&"bee":   return BEE_SCENE
		&"grasshopper":   return GRASSHOPPER_SCENE
		_:        return null


func _spawn_ant() -> void:
	var ant: CharacterBody3D = ANT_SCENE.instantiate() as CharacterBody3D
	if ant == null:
		return
	add_child(ant)
	# Spawn near the bee
	ant.global_position = bee_spawn_position + Vector3(2.0, 0.0, 2.0)
	# Refresh name tag after registration
	var ant_pawn: PawnBase = ant as PawnBase
	if ant_pawn:
		ant_pawn.refresh_name_tag()
	# Add to player colony
	if ant.state:
		ant.state.colony_id = 0


func _spawn_grasshopper() -> void:
	var grasshopper: CharacterBody3D = GRASSHOPPER_SCENE.instantiate() as CharacterBody3D
	if grasshopper == null:
		return
	add_child(grasshopper)
	# Spawn near the bee
	grasshopper.global_position = bee_spawn_position + Vector3(-2.0, 0.0, -2.0)
	# Refresh name tag after registration
	var grasshopper_pawn: PawnBase = grasshopper as PawnBase
	if grasshopper_pawn:
		grasshopper_pawn.refresh_name_tag()
	# Add to player colony
	if grasshopper.state:
		grasshopper.state.colony_id = 0


func _on_player_pawn_registered(pawn_id: int, _colony_id: int) -> void:
	print("_on_player_pawn_registered: pawn_id=", pawn_id, " _bee=", _bee)
	var node: PawnBase = PawnRegistry.get_pawn(pawn_id)
	print("node=", node, " matches _bee=", node == _bee)
	if node != _bee:
		return
	EventBus.pawn_registered.disconnect(_on_player_pawn_registered)
	print("calling request_possess(1, ", pawn_id, ")")
	PossessionManager.request_possess(1, pawn_id)





# ════════════════════════════════════════════════════════════════════════════ #
#  Colony init
# ════════════════════════════════════════════════════════════════════════════ #

func _init_colony() -> void:
	if ColonyState.get_player_colony() == null:
		var colony_id: int = ColonyState.create_colony()
		assert(colony_id == 0)
	# Set the bee as queen once it has a valid pawn_id
	# (called after _spawn_player() so pawn is registered)
	if _bee and _bee.pawn_id >= 0:
		ColonyState.set_queen(0, _bee.pawn_id)



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

	var hive_id: int = HiveSystem.register_hive(hive_cell, 0, -1, true, 19, 6)

	var queen_id: int = ColonyState.get_queen_id(0)
	if queen_id >= 0:
		HiveSystem.set_queen_bed(hive_id, 0, queen_id)

	print("WorldRoot: starter hive %d placed at %s (colony 0)" % [hive_id, hive_cell])

## Search hex rings outward from origin for the nearest TREE category cell.
## Returns Vector2i(-9999, -9999) if none found within max_radius.
func _find_nearest_tree_cell(origin: Vector2i, max_radius: int) -> Vector2i:
	# Remove the biome check block entirely — it was using (0,0) as origin
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
