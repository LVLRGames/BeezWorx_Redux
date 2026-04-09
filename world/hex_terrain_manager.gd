# hex_terrain_manager.gd
# Thin orchestrator: spawns/despawns HexChunks around the player.
#
# EDITOR / RUNTIME SPLIT
# ───────────────────────
# All scripts in the hex terrain system are #@tool so that editor preview
# works without restriction.  The key rule for editor safety is:
#   • _ready() does nothing in editor mode — chunks are never auto-generated
#     on scene restore, only when Generate is explicitly pressed.
#   • _editor_rebuild() is the single entry point for all editor generation.

#@tool
class_name HexTerrainManager
extends Node3D

# ── Exports ───────────────────────────────────────────────────────────
@export var config: HexTerrainConfig:
	set(v):
		config = v
		if Engine.is_editor_hint() and is_inside_tree() and not _rebuilding:
			_editor_rebuild()

@export var player_path:        NodePath
@export var view_radius_chunks: int   = 4
@export var use_puffy_shading:  bool  = true

# REPLACE WITH:
@export_group("Plant Mesh")
## Single mesh for all resource plants. Quads are reconfigured by the
## vertex shader based on plant variant (Normal/Wild/Lush/Royal).
@export var plant_mesh:     Mesh
@export var plant_material: Material

@export_group("Actions")
#@export_tool_button("Generate") var _btn_gen   : Callable = _editor_rebuild
#@export_tool_button("Clear")    var _btn_clear : Callable = _clear_chunks

# ── Runtime state ─────────────────────────────────────────────────────
@onready var player: Node3D = get_node_or_null(player_path)

var _loaded:      Dictionary[Vector2i, HexChunk] = {}
var _queue:       Array[HexChunk]                = []
var _active_jobs: int  = 0
var _last_chunk:  Vector2i = Vector2i(-999, -999)
var _rebuilding:  bool = false   # re-entrancy guard for config setter
var _finalize_queue: Array[Array] = []  # [[chunk, shape], ...]
var _deferred_free_queue: Array[HexChunk] = []
var _despawn_queue: Array[Vector2i] = []
var _spawn_queue: Array[Vector2i] = []

const MAX_DESPAWNS_PER_FRAME: int = 3
const MAX_SPAWNS_PER_FRAME: int = 2
const MAX_CONCURRENT := 2

# ════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	# Editor: do nothing on scene restore — generate only via button press.
	if Engine.is_editor_hint(): return

	if not config:
		push_error("HexTerrainManager: no HexTerrainConfig assigned.")
		return
	
	HexChunk.plant_mesh     = plant_mesh
	HexChunk.plant_material = plant_material
	
	if HexChunk._lut == null:
		HexChunk._lut = HexMeshLUT.new()
		
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.pawn_possessed.connect(_on_pawn_possessed)
	EventBus.player_pawn_ready.connect(_on_player_pawn_ready)

func _deferred_start() -> void:
	print("_deferred_start fired, player: ", player, " config: ", config)
	_update_chunks()


func _update_chunks() -> void:
	var center := _world_to_chunk(player.global_position if player else Vector3.ZERO)
	#print("_update_chunks center: ", center, " spawn_queue size after: ", _spawn_queue.size())
	var needed: Dictionary[Vector2i, bool] = {}
	var R := view_radius_chunks
	for x in range(-R, R + 1):
		for z in range(-R, R + 1):
			if abs(x) <= R and abs(z) <= R and abs(x + z) <= R:
				needed[center + Vector2i(x, z)] = true
	for coord: Vector2i in _loaded.keys():
		if not needed.has(coord):
			if not _despawn_queue.has(coord):
				_despawn_queue.append(coord)
	for coord: Vector2i in needed.keys():
		if not _loaded.has(coord) and not _spawn_queue.has(coord):
			_spawn_queue.append(coord)
	
	# Sort spawn queue nearest first
	_spawn_queue.sort_custom(_sort_by_distance)

func _sort_by_distance(a: Vector2i, b: Vector2i) -> bool:
	var da: int = absi(a.x - _last_chunk.x) + absi(a.y - _last_chunk.y)
	var db: int = absi(b.x - _last_chunk.x) + absi(b.y - _last_chunk.y)
	return da < db



func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	
	# Finalize one chunk per frame
	if not _finalize_queue.is_empty():
		var entry: Array = _finalize_queue.pop_front()
		if entry[0] == null:
			pass
		elif not is_instance_valid(entry[0]):
			pass
		else:
			var chunk: HexChunk = entry[0]
			var shape: Shape3D = entry[1]
			add_child(chunk)
			chunk.finalize_chunk(shape)
			if not HexWorldState.cell_changed.is_connected(chunk._on_cell_changed):
				HexWorldState.cell_changed.connect(chunk._on_cell_changed)
			HexWorldState.on_chunk_loaded(chunk.chunk_coord, HexChunk.CHUNK_SIZE, chunk._cell_states)
		
	# Spawn a few chunks per frame
	var spawned: int = 0
	while not _spawn_queue.is_empty() and spawned < MAX_SPAWNS_PER_FRAME:
		var coord: Vector2i = _spawn_queue.pop_front()
		if not _loaded.has(coord):
			_spawn(coord)
			spawned += 1
	
	# Despawn a few chunks per frame
	var despawned: int = 0
	while not _despawn_queue.is_empty() and despawned < MAX_DESPAWNS_PER_FRAME:
		var coord: Vector2i = _despawn_queue.pop_front()
		if _loaded.has(coord):
			_despawn(coord)
			despawned += 1
	
	var cc := _world_to_chunk(player.global_position)
	if cc != _last_chunk:
		_last_chunk = cc
		_update_chunks()
	
	var i: int = _deferred_free_queue.size() - 1
	while i >= 0:
		var chunk: HexChunk = _deferred_free_queue[i]
		if not is_instance_valid(chunk) or not chunk.generating:
			_deferred_free_queue.remove_at(i)
			if is_instance_valid(chunk):
				chunk.queue_free()
		i -= 1

# ════════════════════════════════════════════════════════════════════ #
#  Chunk management
# ════════════════════════════════════════════════════════════════════ #
func _spawn(c: Vector2i) -> void:
	#print("spawning chunk: ", c)
	var chunk := HexChunk.new(c, use_puffy_shading)
	chunk.terrain_manager = self
	_loaded[c] = chunk
	if Engine.is_editor_hint():
		add_child(chunk)
		chunk.generate_all_data()
		chunk.finalize_chunk()
		return
	_queue.append(chunk)
	_flush_queue()


func _flush_queue() -> void:
	while _active_jobs < MAX_CONCURRENT and not _queue.is_empty():
		var chunk: HexChunk = _queue.pop_front()
		if not is_instance_valid(chunk): continue
		chunk.generating = true
		_active_jobs += 1
		WorkerThreadPool.add_task(_generate_chunk.bind(chunk))

func _generate_chunk(chunk: HexChunk) -> void:
	if not is_instance_valid(chunk):
		_job_done.call_deferred(null)
		return
	chunk.generate_all_data()
	var shape: Shape3D = chunk.terrain_mesh.create_trimesh_shape() \
		if chunk.terrain_mesh else null
	_job_done.call_deferred(chunk, shape)

func _job_done(chunk: HexChunk, shape: Shape3D = null) -> void:
	_active_jobs -= 1
	if is_instance_valid(chunk):
		chunk.generating = false
		_finalize_queue.append([chunk, shape])
	_flush_queue()


func _despawn(c: Vector2i) -> void:
	if not _loaded.has(c): return
	var chunk: HexChunk = _loaded[c]
	_loaded.erase(c)
	_queue.erase(chunk)
	
	var i: int = _finalize_queue.size() - 1
	while i >= 0:
		if _finalize_queue[i][0] == chunk:
			_finalize_queue.remove_at(i)
		i -= 1
	
	if not Engine.is_editor_hint():
		if HexWorldState.cell_changed.is_connected(chunk._on_cell_changed):
			HexWorldState.cell_changed.disconnect(chunk._on_cell_changed)
		HexWorldState.on_chunk_unloaded(c, HexChunk.CHUNK_SIZE)
	if chunk.generating:
		_deferred_free_queue.append(chunk)
	else:
		chunk.queue_free()

# ════════════════════════════════════════════════════════════════════ #
#  Editor actions
# ════════════════════════════════════════════════════════════════════ #

func _editor_rebuild() -> void:
	if not config: return
	if _rebuilding: return
	_rebuilding = true
	HexChunk.plant_mesh     = plant_mesh
	HexChunk.plant_material = plant_material
	if HexChunk._lut == null:
		HexChunk._lut = HexMeshLUT.new()
	HexWorldState.initialize(config)
	#print("spawn tables: ", HexWorldState._spawn_tables.keys())
	for biome_key in HexWorldState._spawn_tables:
		var entries = HexWorldState._spawn_tables[biome_key]
		print("  ", biome_key, ": ", entries.map(func(d): return d.id))

	#print("plant_sprout_mesh: ", HexChunk.plant_sprout_mesh)
	#print("plant_bush_mesh: ", HexChunk.plant_bush_mesh)
	_clear_chunks()
	_update_chunks()
	_rebuilding = false

func _clear_chunks() -> void:
	for c: Node in get_children():
		if c is HexChunk: c.free()
	_loaded.clear()
	_queue.clear()
	_last_chunk = Vector2i(-999, -999)

# ════════════════════════════════════════════════════════════════════ #
#  Coordinate utilities
# ════════════════════════════════════════════════════════════════════ #

func _world_to_chunk(pos: Vector3) -> Vector2i:
	var q := (HexConsts.SQRT3 / 3.0 * pos.x - 1.0 / 3.0 * pos.z) / HexConsts.HEX_SIZE
	var r := (2.0 / 3.0 * pos.z) / HexConsts.HEX_SIZE
	return Vector2i(
		floori(float(roundi(q)) / HexConsts.CHUNK_SIZE),
		floori(float(roundi(r)) / HexConsts.CHUNK_SIZE))


func get_loaded_chunk(coord: Vector2i) -> HexChunk:
	return _loaded.get(coord)


# ════════════════════════════════════════════════════════════════════ #
#  Event Handlers
# ════════════════════════════════════════════════════════════════════ #

func _on_player_pawn_ready(pawn: Node3D, _slot: int) -> void:
	player = pawn
	_update_chunks()


func _on_game_loaded(_slot_name: String) -> void:
	_update_chunks()   # or whatever your refresh method is called


func _on_pawn_possessed(player_slot: int, pawn_id: int) -> void:
	# Only track player slot 1 (or whichever is your primary viewer)
	if player_slot != 1:
		return
	var node: PawnBase = PawnRegistry.get_pawn(pawn_id)
	if node:
		player = node
		_update_chunks()
