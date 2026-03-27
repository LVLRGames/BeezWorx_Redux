# hex_world_state.gd
extends Node

signal cell_changed(cell: Vector2i)
signal chunk_loaded(chunk_coord: Vector2i)

enum Stage { SEED, SPROUT, GROWTH, FLOWERING, FRUITING, IDLE, WILT, DEAD }

var _mutex := Mutex.new()

var cfg: HexTerrainConfig = null

var registry: HexDefinitionRegistry = null
var baseline: HexWorldBaseline = null
var delta_store: HexWorldDeltaStore = null
var simulation: HexWorldSimulation = null

var _cell_cache: Dictionary[Vector2i, HexCellState] = {}
var _registered_shader_params: Dictionary[StringName, bool] = {}

const SAVE_PATH := "user://world_deltas.dat"


func initialize(config: HexTerrainConfig) -> void:
	print("HexWorldState.initialize called, seed: ", config.world_seed)

	cfg = config
	cfg.apply_seed()

	registry = HexDefinitionRegistry.new()
	registry.build_from_config(cfg)

	baseline = HexWorldBaseline.new()
	baseline.setup(cfg, registry)

	delta_store = HexWorldDeltaStore.new()

	simulation = HexWorldSimulation.new()
	simulation.setup(cfg, registry, baseline, delta_store)

	_mutex.lock()
	_cell_cache.clear()
	_mutex.unlock()

	load_deltas()
	
	RenderingServer.global_shader_parameter_remove(&"engine_time")
	RenderingServer.global_shader_parameter_add(
		&"engine_time",
		RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
		0.0
	)


func get_cell(
	cell: Vector2i,
	world_time: float = -1.0,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	if world_time < 0.0:
		world_time = TimeService.world_time

	var state: HexCellState = get_cell_ref(cell, world_time, gen_cache)
	return state.duplicate_state()

func get_cell_ref(
	cell: Vector2i,
	world_time: float = -1.0,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	if world_time < 0.0:
		world_time = TimeService.world_time

	_mutex.lock()
	if _cell_cache.has(cell):
		var cached: HexCellState = _cell_cache[cell]
		_mutex.unlock()
		return cached
	_mutex.unlock()

	var state: HexCellState = simulation.get_cell(cell, world_time, gen_cache)

	_mutex.lock()
	if not _cell_cache.has(cell):
		_cell_cache[cell] = state
	_mutex.unlock()

	return state

func get_cell_cache() -> Dictionary:
	return _cell_cache

func get_baseline_cell(cell: Vector2i, world_time: float = -1.0) -> HexCellState:
	if world_time < 0.0:
		world_time = TimeService.world_time
	return baseline.get_baseline_cell(cell, world_time)

func set_cell(cell: Vector2i, object_id: String, overrides: Dictionary = {}) -> void:
	if registry == null or not registry.definitions.has(object_id):
		push_error("HexWorldState: unknown id '%s'" % object_id)
		return

	var delta := HexCellDelta.new()
	delta.delta_type = HexCellDelta.DeltaType.PLANTED
	delta.object_id = object_id
	delta.timestamp = TimeService.world_time

	if overrides.has("stage_override"):
		delta.stage_override = overrides["stage_override"]
	if overrides.has("last_watered"):
		delta.last_watered = overrides["last_watered"]
	if overrides.has("hybrid_genes"):
		delta.hybrid_genes = overrides["hybrid_genes"]
	if overrides.has("parent_a_cell"):
		delta.parent_a_cell = overrides["parent_a_cell"]
	if overrides.has("parent_b_cell"):
		delta.parent_b_cell = overrides["parent_b_cell"]
	if overrides.has("fruit_cycles_done"):
		delta.fruit_cycles_done = overrides["fruit_cycles_done"]

	_write_delta(cell, delta)

func clear_cell(cell: Vector2i) -> void:
	var origin: Vector2i = delta_store.get_origin_for_cell(cell)

	var delta := HexCellDelta.new()
	delta.delta_type = HexCellDelta.DeltaType.CLEARED
	delta.timestamp = TimeService.world_time

	_write_delta(origin, delta)
	

func mutate_cell(cell: Vector2i, overrides: Dictionary) -> void:
	var state: HexCellState = get_cell_ref(cell)
	if not state.occupied:
		return


	var ex: HexCellDelta = delta_store.get_delta(state.origin)
	var delta: HexCellDelta = ex.duplicate() if ex else HexCellDelta.new()

	delta.delta_type = HexCellDelta.DeltaType.STATE_MUTATED
	delta.timestamp = TimeService.world_time

	if overrides.has("stage_override"):
		delta.stage_override = overrides["stage_override"]
	if overrides.has("last_watered"):
		delta.last_watered = overrides["last_watered"]
	if overrides.has("pollen_source_id"):
		delta.pollen_source_id = overrides["pollen_source_id"]
	if overrides.has("fruit_cycles_done"):
		delta.fruit_cycles_done = overrides["fruit_cycles_done"]
	if overrides.has("pollen_remaining"):
		delta.pollen_remaining = overrides["pollen_remaining"]
	if overrides.has("nectar_remaining"):
		delta.nectar_remaining = overrides["nectar_remaining"]
	if overrides.has("pollinated_by"):
		delta.pollinated_by = overrides["pollinated_by"]

	_write_delta(state.origin, delta)

func has_delta(cell: Vector2i) -> bool:
	return delta_store != null and delta_store.has_delta(cell)

func get_delta(cell: Vector2i) -> HexCellDelta:
	if delta_store == null:
		return null
	return delta_store.get_delta(cell)

func place_object(cell: Vector2i, object_id: String) -> void:
	set_cell(cell, object_id)

func water_plant(cell: Vector2i) -> void:
	var state: HexCellState = get_cell_ref(cell)
	if not state.occupied:
		return
	if not (state.definition is HexPlantDef):
		return

	var overrides: Dictionary = {
		"last_watered": TimeService.world_time
	}

	if state.stage == Stage.WILT:
		overrides["stage_override"] = Stage.GROWTH

	mutate_cell(state.origin, overrides)

func consume_pollen(cell: Vector2i, amount: float) -> void:
	var state: HexCellState = get_cell_ref(cell)
	if not state.occupied:
		return
	if not (state.definition is HexPlantDef):
		return

	var remaining: float = maxf(state.pollen_amount - amount, 0.0)
	mutate_cell(state.origin, {"pollen_remaining": remaining})


func consume_nectar(cell: Vector2i, amount: float) -> void:
	var state: HexCellState = get_cell_ref(cell)
	if not state.occupied:
		return
	if not (state.definition is HexPlantDef):
		return

	var remaining: float = maxf(state.nectar_amount - amount, 0.0)
	var overrides: Dictionary = {"nectar_remaining": remaining}

	if remaining <= 0.0:
		overrides["stage_override"] = Stage.IDLE

	mutate_cell(state.origin, overrides)


func apply_pollen(source_cell: Vector2i, target_cell: Vector2i) -> void:
	var target_state: HexCellState = get_cell_ref(target_cell)
	if not target_state.occupied:
		return
	if not (target_state.definition is HexPlantDef):
		return

	mutate_cell(target_state.origin, {"pollinated_by": source_cell})

func set_plant_stage(cell: Vector2i, stage: int) -> void:
	var state: HexCellState = get_cell_ref(cell)
	if not state.occupied:
		return
	if not (state.definition is HexPlantDef):
		return

	mutate_cell(state.origin, {"stage_override": stage})

func get_fresh_stage(cell: Vector2i) -> int:
	var delta: HexCellDelta = delta_store.get_delta(cell)
	if delta and delta.stage_override >= 0:
		return delta.stage_override

	var state: HexCellState = get_cell_ref(cell)
	if not state.occupied:
		return -1
	if not (state.definition is HexPlantDef):
		return -1

	return state.stage

func attempt_cross_sprout(ca: Vector2i, cb: Vector2i, ga: HexPlantGenes, gb: HexPlantGenes) -> void:
	if ga.species_group != gb.species_group:
		return

	var a_state: HexCellState = get_cell_ref(ca)
	var b_state: HexCellState = get_cell_ref(cb)
	if not a_state.occupied or not b_state.occupied:
		return

	var key: String = HexDefinitionRegistry.canonical_key(a_state.object_id, b_state.object_id)
	var target_cell: Vector2i = _find_sprout_cell(cb, gb.pollen_radius)

	if target_cell == Vector2i(-9999, -9999):
		return

	if registry.authored_crosses.has(key):
		var authored: HexPlantDef = registry.authored_crosses[key]
		_spawn_sprout(target_cell, authored.id, null, ca, cb)
	else:
		_spawn_sprout(target_cell, "wild_plant", HexPlantGenes.blend(ga, gb), ca, cb)


func spawn_sprout(cell: Vector2i, object_id: String, genes: HexPlantGenes, 
		parent_a: Vector2i, parent_b: Vector2i) -> void:
	_spawn_sprout(cell, object_id, genes, parent_a, parent_b)

func find_sprout_cell(origin: Vector2i, radius: int) -> Vector2i:
	return _find_sprout_cell(origin, radius)


func _find_sprout_cell(origin: Vector2i, radius: int) -> Vector2i:
	for r: int in range(1, radius + 1):
		var ring: Array[Vector2i] = HexWorldBaseline.hex_ring(origin, r)
		ring.shuffle()

		for c: Vector2i in ring:
			if cfg.get_cell_biome(c.x, c.y) == "ocean":
				continue
			if not get_cell_ref(c).occupied:
				return c

	return Vector2i(-9999, -9999)

func _spawn_sprout(
	cell: Vector2i,
	object_id: String,
	genes: HexPlantGenes,
	parent_a: Vector2i,
	parent_b: Vector2i
) -> void:
	var delta := HexCellDelta.new()
	delta.delta_type = HexCellDelta.DeltaType.SPROUT_SPAWNED
	delta.object_id = object_id
	delta.timestamp = TimeService.world_time
	delta.hybrid_genes = genes
	delta.parent_a_cell = parent_a
	delta.parent_b_cell = parent_b

	_write_delta(cell, delta)

func on_chunk_loaded(
	chunk_coord: Vector2i,
	chunk_size: int,
	cached_states: Dictionary[Vector2i, HexCellState] = {}
) -> void:
	var cells_to_invalidate: Array[Vector2i] = []

	for dq: int in chunk_size:
		for dr: int in chunk_size:
			cells_to_invalidate.append(Vector2i(
				chunk_coord.x * chunk_size + dq,
				chunk_coord.y * chunk_size + dr
			))
	invalidate_cells(cells_to_invalidate)

	for dq: int in chunk_size:
		for dr: int in chunk_size:
			var cell := Vector2i(
				chunk_coord.x * chunk_size + dq,
				chunk_coord.y * chunk_size + dr
			)

			var state: HexCellState = cached_states[cell] if cached_states.has(cell) else get_cell_ref(cell)

			if state.occupied and state.origin == cell:
				var def: HexGridObjectDef = state.definition
				if def:
					delta_store.set_occupancy(cell, def.footprint)
	
	chunk_loaded.emit(chunk_coord)


func on_chunk_unloaded(chunk_coord: Vector2i, chunk_size: int) -> void:
	var cells_to_invalidate: Array[Vector2i] = []

	for dq: int in chunk_size:
		for dr: int in chunk_size:
			cells_to_invalidate.append(Vector2i(
				chunk_coord.x * chunk_size + dq,
				chunk_coord.y * chunk_size + dr
			))

	invalidate_cells(cells_to_invalidate)
	delta_store.clear_occupancy_in_chunk(chunk_coord, chunk_size)

func invalidate_cell(cell: Vector2i) -> void:
	_mutex.lock()
	_cell_cache.erase(cell)
	_mutex.unlock()

func invalidate_cells(cells: Array[Vector2i]) -> void:
	_mutex.lock()
	for cell: Vector2i in cells:
		_cell_cache.erase(cell)
	_mutex.unlock()

func clear_cache() -> void:
	_mutex.lock()
	_cell_cache.clear()
	_mutex.unlock()

func set_occupant_data(cell: Vector2i, occupant: CellOccupantData) -> void:
	# Ensure the cell has a cached state to write into.
	# get_cell_ref() populates the cache if empty.
	var state: HexCellState = get_cell_ref(cell)
	state.occupant_data = occupant
 
	# Update category so chunk rendering can route correctly.
	if occupant != null:
		state.category = occupant.category
	# Note: we do NOT emit cell_changed here — occupant_data changes are
	# colony-layer mutations, not world-layer mutations. Colony systems
	# that need to notify rendering do so via EventBus directly.

func clear_occupant_data(cell: Vector2i) -> void:
	_mutex.lock()
	if _cell_cache.has(cell):
		_cell_cache[cell].occupant_data = null
		# Restore category from definition if present
		var state: HexCellState = _cell_cache[cell]
		if state.definition != null:
			state.category = state.definition.category
		else:
			state.category = -1
	_mutex.unlock()

func save_deltas() -> void:
	if delta_store == null:
		return
	if not delta_store.save(SAVE_PATH):
		push_error("HexWorldState: failed to save deltas to '%s'" % SAVE_PATH)

func load_deltas() -> void:
	if delta_store == null:
		return
	if not delta_store.load(SAVE_PATH):
		push_error("HexWorldState: failed to load deltas from '%s'" % SAVE_PATH)

func _write_delta(cell: Vector2i, delta: HexCellDelta) -> void:
	delta_store.set_delta(cell, delta)
	invalidate_cell(cell)
	cell_changed.emit(cell)


func save_state() -> Dictionary:
	save_deltas()
	return {}   # HexWorldState saves its own file separately

func load_state(_data: Dictionary) -> void:
	load_deltas()
