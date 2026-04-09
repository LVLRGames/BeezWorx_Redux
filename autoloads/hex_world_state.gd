# hex_world_state.gd
# Autoload. Single source of truth for the physical world layer.
# Colony, job, and pawn systems read from here; they never write terrain directly.
#
# SLOT SYSTEM (plant system overhaul):
#   All deltas are keyed by Vector3i(q, r, slot) where slot = 0-5.
#   Cache is also Vector3i-keyed.
#   get_cell / get_cell_ref are kept as compat wrappers (queries slot 0).
#   New API: get_slot / get_slot_ref / get_cell_occupants.

extends Node

signal cell_changed(cell: Vector2i)
signal chunk_loaded(chunk_coord: Vector2i)

enum Stage { SEED, SPROUT, GROWTH, FLOWERING, FRUITING, IDLE, WILT, DEAD }

var _mutex := Mutex.new()

var cfg:         HexTerrainConfig     = null
var registry:    HexDefinitionRegistry = null
var baseline:    HexWorldBaseline     = null
var delta_store: HexWorldDeltaStore   = null
var simulation:  HexWorldSimulation   = null

## Slot-keyed cell cache: Vector3i(q, r, slot) → HexCellState
var _cell_cache: Dictionary[Vector3i, HexCellState] = {}
var _registered_shader_params: Dictionary[StringName, bool] = {}

const SAVE_PATH := "user://world_deltas.dat"

# ════════════════════════════════════════════════════════════════════ #
#  Init
# ════════════════════════════════════════════════════════════════════ #

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

func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set(
		&"engine_time",
		float(Time.get_ticks_usec()) / 1000000.0
	)

# ════════════════════════════════════════════════════════════════════ #
#  Read API — slot-aware
# ════════════════════════════════════════════════════════════════════ #

## Returns a deep copy of the occupant at the given slot.
func get_slot(
	cell: Vector2i,
	slot: int,
	world_time: float = -1.0,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	return get_slot_ref(cell, slot, world_time, gen_cache).duplicate_state()


## Returns the cached (live) state for a slot. Do not mutate the returned object.
func get_slot_ref(
	cell: Vector2i,
	slot: int,
	world_time: float = -1.0,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	if world_time < 0.0:
		world_time = TimeService.world_time

	var sk := Vector3i(cell.x, cell.y, slot)

	_mutex.lock()
	if _cell_cache.has(sk):
		var cached: HexCellState = _cell_cache[sk]
		_mutex.unlock()
		return cached
	_mutex.unlock()

	var state: HexCellState = simulation.get_slot(sk, world_time, gen_cache)

	_mutex.lock()
	if not _cell_cache.has(sk):
		_cell_cache[sk] = state
	_mutex.unlock()

	return state


## Returns all 6 slot states for a cell.
## Empty slots have state.occupied = false. Array always has length 6.
func get_cell_occupants(
	cell: Vector2i,
	world_time: float = -1.0,
	gen_cache: HexChunkGenCache = null
) -> Array[HexCellState]:
	var result: Array[HexCellState] = []
	for s: int in 6:
		result.append(get_slot(cell, s, world_time, gen_cache))
	return result


# ── Legacy compat: queries slot 0 ────────────────────────────────────

func get_cell(
	cell: Vector2i,
	world_time: float = -1.0,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	return get_slot(cell, 0, world_time, gen_cache)


func get_cell_ref(
	cell: Vector2i,
	world_time: float = -1.0,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	return get_slot_ref(cell, 0, world_time, gen_cache)


func get_cell_cache() -> Dictionary:
	return _cell_cache


func get_baseline_cell(cell: Vector2i, world_time: float = -1.0) -> HexCellState:
	if world_time < 0.0:
		world_time = TimeService.world_time
	return baseline.get_baseline_cell(cell, world_time)

# ════════════════════════════════════════════════════════════════════ #
#  Write API
# ════════════════════════════════════════════════════════════════════ #

## Place an object at the given cell (slot 0) and register occupancy.
func set_cell(cell: Vector2i, object_id: String, overrides: Dictionary = {}) -> void:
	set_slot(cell, 0, object_id, overrides)


## Place an object at a specific slot.
func set_slot(cell: Vector2i, slot: int, object_id: String, overrides: Dictionary = {}) -> void:
	if registry == null or not registry.definitions.has(object_id):
		push_error("HexWorldState: unknown id '%s'" % object_id)
		return

	var def: HexGridObjectDef = registry.get_definition(object_id)

	var delta          := HexCellDelta.new()
	delta.delta_type    = HexCellDelta.DeltaType.PLANTED
	delta.object_id     = object_id
	delta.timestamp     = TimeService.world_time

	if overrides.has("stage_override"):      delta.stage_override    = overrides["stage_override"]
	if overrides.has("last_watered"):        delta.last_watered      = overrides["last_watered"]
	if overrides.has("hybrid_genes"):        delta.hybrid_genes      = overrides["hybrid_genes"]
	if overrides.has("parent_a_cell"):       delta.parent_a_cell     = overrides["parent_a_cell"]
	if overrides.has("parent_b_cell"):       delta.parent_b_cell     = overrides["parent_b_cell"]
	if overrides.has("fruit_cycles_done"):   delta.fruit_cycles_done = overrides["fruit_cycles_done"]

	var sk := Vector3i(cell.x, cell.y, slot)
	_write_delta(sk, delta)

	# Register occupancy for multi-slot / multi-cell objects.
	if def != null:
		delta_store.set_occupancy(sk, def.footprint, def.slots_occupied)


## Clear a specific slot.
func clear_slot(cell: Vector2i, slot: int) -> void:
	var sk     := Vector3i(cell.x, cell.y, slot)
	var anchor := delta_store.get_anchor_for_slot(sk)

	var delta          := HexCellDelta.new()
	delta.delta_type    = HexCellDelta.DeltaType.CLEARED
	delta.timestamp     = TimeService.world_time

	_write_delta(anchor, delta)


## Legacy compat: clears slot 0 (and its anchor if redirected).
func clear_cell(cell: Vector2i) -> void:
	clear_slot(cell, 0)


## Mutate state on a specific slot.
func mutate_slot(cell: Vector2i, slot: int, overrides: Dictionary) -> void:
	var sk    := Vector3i(cell.x, cell.y, slot)
	var state := get_slot_ref(cell, slot)
	if not state.occupied:
		return

	var anchor    := delta_store.get_anchor_for_slot(sk)
	var ex: HexCellDelta = delta_store.get_delta(anchor)
	var delta: HexCellDelta = ex.duplicate() if ex else HexCellDelta.new()

	# Preserve object_id for baseline plants. Without this, the next query
	# calls get_baseline_object_id() which returns slot 0's def, not the
	# grass at this slot — the plant loses identity and appears to vanish.
	if delta.object_id.is_empty() and not state.object_id.is_empty():
		delta.object_id = state.object_id

	delta.delta_type = HexCellDelta.DeltaType.STATE_MUTATED
	delta.timestamp  = TimeService.world_time

	if overrides.has("stage_override"):      delta.stage_override    = overrides["stage_override"]
	if overrides.has("last_watered"):        delta.last_watered      = overrides["last_watered"]
	if overrides.has("pollen_source_id"):    delta.pollen_source_id  = overrides["pollen_source_id"]
	if overrides.has("fruit_cycles_done"):   delta.fruit_cycles_done = overrides["fruit_cycles_done"]
	if overrides.has("pollen_remaining"):    delta.pollen_remaining  = overrides["pollen_remaining"]
	if overrides.has("nectar_remaining"):    delta.nectar_remaining  = overrides["nectar_remaining"]
	if overrides.has("pollinated_by"):       delta.pollinated_by     = overrides["pollinated_by"]
	if overrides.has("health_remaining"):    delta.health_remaining  = overrides["health_remaining"]
	if overrides.has("wetness_override"):    delta.wetness_override  = overrides["wetness_override"]
	if overrides.has("toxicity_override"):   delta.toxicity_override = overrides["toxicity_override"]
	if overrides.has("plant_variant"):       delta.plant_variant     = overrides["plant_variant"]

	_write_delta(anchor, delta)


## Legacy compat: mutates slot 0.
func mutate_cell(cell: Vector2i, overrides: Dictionary) -> void:
	mutate_slot(cell, 0, overrides)

# ════════════════════════════════════════════════════════════════════ #
#  damage_plant
# ════════════════════════════════════════════════════════════════════ #

## Apply damage to the plant at (cell, slot).
## Returns actual damage dealt. 0.0 if the slot is not a damageable plant.
## On kill: clears the slot, rolls seed_respawn_chance, stubs item gem drop.
func damage_plant(
	cell:          Vector2i,
	slot:          int,
	raw_damage:    float,
	pawn_id:       int        = -1,
	drop_override: StringName = &""
) -> float:
	var state := get_slot_ref(cell, slot)
	if not state.is_damageable_plant():
		return 0.0

	var plant_def := state.definition as HexPlantDef
	var effective: float = raw_damage / maxf(plant_def.toughness, 0.001)
	var current: float   = state.get_health()
	var new_hp: float    = current - effective

	if new_hp <= 0.0:
		_kill_plant(cell, slot, state, pawn_id, drop_override)
		return effective

	# Silent — health change has no visual; bounce applied directly to the MM.
	mutate_slot(cell, slot, {"health_remaining": new_hp})
	_trigger_bounce_on_chunk(cell, slot)
	return effective


func _kill_plant(
	cell:          Vector2i,
	slot:          int,
	state:         HexCellState,
	pawn_id:       int,
	drop_override: StringName
) -> void:
	var plant_def := state.definition as HexPlantDef
	var pd: HexPlantData = plant_def.plant_data if plant_def else null

	# Seed respawn roll — plant replaces itself with a sprout if it seeded at least once.
	if pd and pd.seed_respawn_chance > 0.0 and state.fruit_cycles_done > 0:
		if randf() < pd.seed_respawn_chance:
			_spawn_sprout(cell, slot, plant_def.id, null,
				cell, cell)   # self-seed: both parents = self
			return

	# Clear the slot.
	clear_slot(cell, slot)

	# Item gem drop stub. Resolved drop id: ability override → def default.
	var item_id: StringName = drop_override \
		if not drop_override.is_empty() \
		else plant_def.drop_item_id
	var count: int = plant_def.drop_count

	var chance: float = plant_def.drop_chance if plant_def else 1.0
	if not item_id.is_empty() and count > 0 and randf() < chance:
		_try_spawn_gem(cell, item_id, count)

	# Notify other systems.
	if EventBus.has_signal("plant_killed"):
		EventBus.plant_killed.emit(cell, pawn_id)


func _try_spawn_gem(cell: Vector2i, item_id: StringName, count: int) -> void:
	var world_xz: Vector2 = HexConsts.AXIAL_TO_WORLD(cell.x, cell.y)
	var terrain_y: float = 0.0
	if cfg != null:
		terrain_y = snappedf(cfg.get_height(world_xz.x, world_xz.y), HexConsts.HEIGHT_STEP)
	var world_pos := Vector3(world_xz.x, terrain_y, world_xz.y)

	var mgr: Node = get_tree().get_first_node_in_group("item_gem_manager")
	if mgr and mgr.has_method("spawn_gem"):
		for _i: int in count:
			mgr.spawn_gem(item_id, world_pos)
	else:
		print("[HexWorldState] plant killed at %s — gem drop pending ItemGemManager (item: %s × %d)" \
			% [cell, item_id, count])

# ════════════════════════════════════════════════════════════════════ #
#  Convenience plant helpers
# ════════════════════════════════════════════════════════════════════ #

func water_plant(cell: Vector2i) -> void:
	var state := get_cell_ref(cell)
	if not state.occupied or not (state.definition is HexPlantDef):
		return
	var overrides: Dictionary = {"last_watered": TimeService.world_time}
	if state.stage == Stage.WILT:
		overrides["stage_override"] = Stage.GROWTH
	mutate_slot(cell, state.slot_index if state.slot_index >= 0 else 0, overrides)


func consume_pollen(cell: Vector2i, amount: float) -> void:
	var state := get_cell_ref(cell)
	if not state.occupied or not (state.definition is HexPlantDef):
		return
	var remaining: float = maxf(state.pollen_amount - amount, 0.0)
	mutate_slot(cell, state.slot_index if state.slot_index >= 0 else 0,
		{"pollen_remaining": remaining})


func consume_nectar(cell: Vector2i, amount: float) -> void:
	var state := get_cell_ref(cell)
	if not state.occupied or not (state.definition is HexPlantDef):
		return
	var remaining: float = maxf(state.nectar_amount - amount, 0.0)
	var overrides: Dictionary = {"nectar_remaining": remaining}
	if remaining <= 0.0:
		overrides["stage_override"] = Stage.IDLE
	mutate_slot(cell, state.slot_index if state.slot_index >= 0 else 0, overrides)


func apply_pollen(source_cell: Vector2i, target_cell: Vector2i) -> void:
	var ts := get_cell_ref(target_cell)
	if not ts.occupied or not (ts.definition is HexPlantDef):
		return
	mutate_slot(target_cell, ts.slot_index if ts.slot_index >= 0 else 0,
		{"pollinated_by": source_cell})


func set_plant_stage(cell: Vector2i, stage: int) -> void:
	var state := get_cell_ref(cell)
	if not state.occupied or not (state.definition is HexPlantDef):
		return
	mutate_slot(cell, state.slot_index if state.slot_index >= 0 else 0,
		{"stage_override": stage})


func get_fresh_stage(cell: Vector2i) -> int:
	var sk    := Vector3i(cell.x, cell.y, 0)
	var delta := delta_store.get_delta(sk)
	if delta and delta.stage_override >= 0:
		return delta.stage_override
	var state := get_cell_ref(cell)
	if not state.occupied or not (state.definition is HexPlantDef):
		return -1
	return state.stage


func place_object(cell: Vector2i, object_id: String) -> void:
	set_cell(cell, object_id)

# ════════════════════════════════════════════════════════════════════ #
#  Hybridization / sprout system
# ════════════════════════════════════════════════════════════════════ #

func attempt_cross_sprout(ca: Vector2i, cb: Vector2i,
		ga: HexPlantGenes, gb: HexPlantGenes) -> void:
	# Pollen species isolation check.
	var a_state := get_cell_ref(ca)
	var b_state := get_cell_ref(cb)
	if not a_state.occupied or not b_state.occupied:
		return

	if a_state.definition is HexPlantDef and b_state.definition is HexPlantDef:
		var a_def := a_state.definition as HexPlantDef
		var b_def := b_state.definition as HexPlantDef
		if (not a_def.can_hybridize_across_species or not b_def.can_hybridize_across_species) \
				and a_def.pollen_species_tag != b_def.pollen_species_tag:
			return   # isolated — cannot cross

	if ga.species_group != gb.species_group:
		return

	var target: Vector3i = _find_sprout_slot(cb, gb.pollen_radius)
	if target == Vector3i(-9999, -9999, -1):
		return

	var target_cell := Vector2i(target.x, target.y)
	var key: String = HexDefinitionRegistry.canonical_key(a_state.object_id, b_state.object_id)
	if registry.authored_crosses.has(key):
		var authored: HexPlantDef = registry.authored_crosses[key]
		_spawn_sprout(target_cell, target.z, authored.id, null, ca, cb)
	else:
		_spawn_sprout(target_cell, target.z, "wild_plant",
			HexPlantGenes.blend(ga, gb), ca, cb)


## Public wrappers for external callers.
func spawn_sprout(cell: Vector2i, slot: int, object_id: String,
		genes: HexPlantGenes, parent_a: Vector2i, parent_b: Vector2i) -> void:
	_spawn_sprout(cell, slot, object_id, genes, parent_a, parent_b)


func find_sprout_slot(origin: Vector2i, radius: int) -> Vector3i:
	return _find_sprout_slot(origin, radius)


## Legacy compat — returns cell only (slot 0).
func find_sprout_cell(origin: Vector2i, radius: int) -> Vector2i:
	var sk := _find_sprout_slot(origin, radius)
	if sk == Vector3i(-9999, -9999, -1):
		return Vector2i(-9999, -9999)
	return Vector2i(sk.x, sk.y)


func _find_sprout_slot(origin: Vector2i, radius: int) -> Vector3i:
	var wt: float = TimeService.world_time
	# Same cell first — find any free slot.
	for s: int in range(6):
		if not get_slot_ref(origin, s, wt).occupied:
			return Vector3i(origin.x, origin.y, s)
	# Adjacent cells.
	for r: int in range(1, radius + 1):
		var ring: Array[Vector2i] = HexWorldBaseline.hex_ring(origin, r)
		ring.shuffle()
		for c: Vector2i in ring:
			if cfg.get_cell_biome(c.x, c.y) == "ocean":
				continue
			for s: int in range(6):
				if not get_slot_ref(c, s, wt).occupied:
					return Vector3i(c.x, c.y, s)
	return Vector3i(-9999, -9999, -1)


func _spawn_sprout(
	cell: Vector2i, slot: int,
	object_id: String, genes: HexPlantGenes,
	parent_a: Vector2i, parent_b: Vector2i
) -> void:
	var delta          := HexCellDelta.new()
	delta.delta_type    = HexCellDelta.DeltaType.SPROUT_SPAWNED
	delta.object_id     = object_id
	delta.timestamp     = TimeService.world_time
	delta.hybrid_genes  = genes
	delta.parent_a_cell = parent_a
	delta.parent_b_cell = parent_b
	_write_delta(Vector3i(cell.x, cell.y, slot), delta)

# ════════════════════════════════════════════════════════════════════ #
#  Colony-layer occupant data (colony writes only — world reads nothing)
# ════════════════════════════════════════════════════════════════════ #

func set_occupant_data(cell: Vector2i, occupant: CellOccupantData) -> void:
	var state := get_slot_ref(cell, 0)
	state.occupant_data = occupant
	if occupant != null:
		state.category = occupant.category

func clear_occupant_data(cell: Vector2i) -> void:
	var sk := Vector3i(cell.x, cell.y, 0)
	_mutex.lock()
	if _cell_cache.has(sk):
		var state: HexCellState = _cell_cache[sk]
		state.occupant_data = null
		state.category = state.definition.category if state.definition != null else -1
	_mutex.unlock()

# ════════════════════════════════════════════════════════════════════ #
#  Delta helpers
# ════════════════════════════════════════════════════════════════════ #

func has_delta(cell: Vector2i) -> bool:
	return delta_store != null \
		and delta_store.has_delta(Vector3i(cell.x, cell.y, 0))

func get_delta(cell: Vector2i) -> HexCellDelta:
	if delta_store == null:
		return null
	return delta_store.get_delta(Vector3i(cell.x, cell.y, 0))

# ════════════════════════════════════════════════════════════════════ #
#  Chunk events
# ════════════════════════════════════════════════════════════════════ #

func on_chunk_loaded(
	chunk_coord: Vector2i,
	chunk_size: int,
	cached_states: Dictionary[Vector3i, HexCellState] = {}
) -> void:
	_invalidate_chunk(chunk_coord, chunk_size)

	for dq: int in chunk_size:
		for dr: int in chunk_size:
			var cell := Vector2i(
				chunk_coord.x * chunk_size + dq,
				chunk_coord.y * chunk_size + dr
			)
			# Check slot 0 for the primary occupant (stub — multi-slot baseline later).
			var sk0 := Vector3i(cell.x, cell.y, 0)
			var state: HexCellState = cached_states[sk0] \
				if cached_states.has(sk0) \
				else get_slot_ref(cell, 0)

			if state.occupied and state.origin == cell:
				var def: HexGridObjectDef = state.definition
				if def:
					var anchor := Vector3i(cell.x, cell.y, 0)
					delta_store.set_occupancy(anchor, def.footprint, def.slots_occupied)

	chunk_loaded.emit(chunk_coord)


func on_chunk_unloaded(chunk_coord: Vector2i, chunk_size: int) -> void:
	_invalidate_chunk(chunk_coord, chunk_size)
	delta_store.clear_occupancy_in_chunk(chunk_coord, chunk_size)


func _invalidate_chunk(chunk_coord: Vector2i, chunk_size: int) -> void:
	_mutex.lock()
	for dq: int in chunk_size:
		for dr: int in chunk_size:
			var q: int = chunk_coord.x * chunk_size + dq
			var r: int = chunk_coord.y * chunk_size + dr
			for s: int in range(6):
				_cell_cache.erase(Vector3i(q, r, s))
	_mutex.unlock()

# ════════════════════════════════════════════════════════════════════ #
#  Cache invalidation
# ════════════════════════════════════════════════════════════════════ #

## Invalidates all 6 slots of the given cell.
func invalidate_cell(cell: Vector2i) -> void:
	_mutex.lock()
	for s: int in range(6):
		_cell_cache.erase(Vector3i(cell.x, cell.y, s))
	_mutex.unlock()


func invalidate_cells(cells: Array[Vector2i]) -> void:
	_mutex.lock()
	for cell: Vector2i in cells:
		for s: int in range(6):
			_cell_cache.erase(Vector3i(cell.x, cell.y, s))
	_mutex.unlock()


func clear_cache() -> void:
	_mutex.lock()
	_cell_cache.clear()
	_mutex.unlock()

# ════════════════════════════════════════════════════════════════════ #
#  Internal write
# ════════════════════════════════════════════════════════════════════ #

func _write_delta(slot_key: Vector3i, delta: HexCellDelta) -> void:
	delta_store.set_delta(slot_key, delta)
	# Invalidate this slot and any occupancy-linked slots in the same cell.
	_mutex.lock()
	for s: int in range(6):
		_cell_cache.erase(Vector3i(slot_key.x, slot_key.y, s))
	_mutex.unlock()
	cell_changed.emit(Vector2i(slot_key.x, slot_key.y))

# ════════════════════════════════════════════════════════════════════ #
#  Save / load
# ════════════════════════════════════════════════════════════════════ #

func has_slot_delta(slot_key: Vector3i) -> bool:
	return delta_store.get_delta(slot_key) != null

func _trigger_bounce_on_chunk(cell: Vector2i, slot: int) -> void:
	var sk := Vector3i(cell.x, cell.y, slot)
	for chunk: Node in get_tree().get_nodes_in_group("hex_chunks"):
		if chunk.has_method("trigger_plant_bounce_slot"):
			chunk.trigger_plant_bounce_slot(sk)

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

func save_state() -> Dictionary:
	save_deltas()
	return {}

func load_state(_data: Dictionary) -> void:
	load_deltas()
