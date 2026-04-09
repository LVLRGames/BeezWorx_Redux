# plant_lifecycle_system.gd
# res://autoloads/plant_lifecycle_system.gd
#
# Autoload. Listens to EventBus.day_changed and runs a lightweight scan
# of all loaded plant cells to handle:
#   - Natural pollination (flowering plants near each other set fruit)
#   - Natural sprouting (fruiting plants spawn sprouts in adjacent empty slots)
#   - Stage change notifications (emits events for visual refresh)
#
# SLOT SYSTEM MIGRATION:
#   Cache is now Dictionary[Vector3i, HexCellState]. Pending and stage tracking
#   use Vector3i slot keys. spawn_sprout and find_sprout_slot use the new API.
#   Category check migrated from RESOURCE_PLANT to category == PLANT +
#   plant_subcategory in [RESOURCE, GRASS].

extends Node

@export var natural_pollination_chance: float = 0.4
@export var natural_sprout_chance:      float = 0.15
@export var natural_pollination_radius: int   = 4
@export var natural_sprout_radius:      int   = 3
@export var plants_per_day_batch:       int   = 200

var _rng: RandomNumberGenerator             = RandomNumberGenerator.new()
var _pending_slots: Dictionary[Vector3i, bool] = {}
var _last_known_stages: Dictionary[Vector3i, int] = {}

func _ready() -> void:
	_rng.randomize()
	EventBus.day_changed.connect(_on_day_changed)

func _on_day_changed(_day: int) -> void:
	_collect_plant_slots()
	_process_batch()

# ── Collection ──────────────────────────────────────────────────────────────

func _collect_plant_slots() -> void:
	# Cache keys are now Vector3i(q, r, slot).
	var cache: Dictionary = HexWorldState.get_cell_cache()
	for sk: Vector3i in cache:
		var state: HexCellState = cache[sk]
		if not state.occupied:
			continue
		if state.category != HexGridObjectDef.Category.PLANT:
			continue
		# Process RESOURCE and GRASS subcategories only (not trees, active defense).
		if state.plant_subcategory != HexPlantDef.PlantSubcategory.RESOURCE \
				and state.plant_subcategory != HexPlantDef.PlantSubcategory.GRASS:
			continue
		var cell := Vector2i(sk.x, sk.y)
		if state.origin != cell:
			continue   # satellite — origin handles it
		_pending_slots[sk] = true

# ── Batch processing ────────────────────────────────────────────────────────

func _process_batch() -> void:
	var all_keys: Array = _pending_slots.keys()
	var count: int = mini(plants_per_day_batch, all_keys.size())
	for i: int in count:
		var sk: Vector3i = all_keys[i]
		_pending_slots.erase(sk)
	var to_process: Array = all_keys.slice(0, count)
	for sk: Vector3i in to_process:
		_tick_plant(sk)

func _tick_plant(sk: Vector3i) -> void:
	var cell  := Vector2i(sk.x, sk.y)
	var slot: int = sk.z
	var state: HexCellState = HexWorldState.get_slot(cell, slot)
	if not state.occupied or state.origin != cell:
		return
	if state.category != HexGridObjectDef.Category.PLANT:
		return

	var stage: int      = state.stage
	var prev_stage: int = _last_known_stages.get(sk, -1)

	if prev_stage != -1 and stage != prev_stage:
		_on_stage_changed(cell, prev_stage, stage, state)

	_last_known_stages[sk] = stage

	match stage:
		HexWorldState.Stage.FLOWERING:
			_try_natural_pollination(cell, slot, state)
		HexWorldState.Stage.FRUITING:
			_try_natural_sprout(cell, slot, state)
		HexWorldState.Stage.DEAD:
			_on_plant_died(cell, slot, state)

# ── Stage change ────────────────────────────────────────────────────────────

func _on_stage_changed(
	cell: Vector2i,
	prev: int,
	next: int,
	_state: HexCellState
) -> void:
	HexWorldState.invalidate_cells([cell])
	EventBus.plant_stage_changed.emit(cell, prev, next)

# ── Natural pollination ─────────────────────────────────────────────────────

func _try_natural_pollination(cell: Vector2i, _slot: int, state: HexCellState) -> void:
	if not state.has_pollen:
		return
	if _rng.randf() > natural_pollination_chance:
		return

	# Same-cell neighbors first, then radius search (spec §12 spreading priority).
	var same_cell_occupants: Array[HexCellState] = HexWorldState.get_cell_occupants(cell)
	for n_state: HexCellState in same_cell_occupants:
		if not n_state.occupied or n_state.stage != HexWorldState.Stage.FLOWERING:
			continue
		if n_state.origin != cell or not n_state.has_pollen:
			continue
		if n_state.slot_index == _slot:
			continue
		HexWorldState.apply_pollen(cell, cell)
		return

	# Adjacent cells.
	var neighbors: Array[Vector2i] = _get_cells_in_radius(cell, natural_pollination_radius)
	neighbors.shuffle()
	for neighbor: Vector2i in neighbors:
		if neighbor == cell:
			continue
		var n_state: HexCellState = HexWorldState.get_cell(neighbor)
		if not n_state.occupied:
			continue
		if n_state.category != HexGridObjectDef.Category.PLANT:
			continue
		if n_state.stage != HexWorldState.Stage.FLOWERING or not n_state.has_pollen:
			continue
		HexWorldState.apply_pollen(cell, neighbor)
		return

# ── Natural sprouting ───────────────────────────────────────────────────────

func _try_natural_sprout(cell: Vector2i, _slot: int, state: HexCellState) -> void:
	if state.definition == null:
		return
	var plant_def: HexPlantDef = state.definition as HexPlantDef
	if plant_def == null:
		return
	var pd: HexPlantData = plant_def.plant_data
	if pd == null:
		return

	var chance: float   = pd.sprout_chance if pd.sprout_chance > 0.0 else natural_sprout_chance
	if _rng.randf() > chance:
		return

	var sprout_rad: int = pd.sprout_radius if pd.sprout_radius > 0 else natural_sprout_radius
	# find_sprout_slot returns Vector3i; -1 sentinel = no slot found.
	var target_sk: Vector3i = HexWorldState.find_sprout_slot(cell, sprout_rad)
	if target_sk == Vector3i(-9999, -9999, -1):
		return

	var target_cell := Vector2i(target_sk.x, target_sk.y)
	HexWorldState.spawn_sprout(
		target_cell, target_sk.z,
		plant_def.id, null,
		cell, Vector2i(-9999, -9999)
	)
	EventBus.plant_sprouted.emit(target_cell, plant_def.id, cell)

# ── Plant death ─────────────────────────────────────────────────────────────

func _on_plant_died(cell: Vector2i, slot: int, _state: HexCellState) -> void:
	_last_known_stages.erase(Vector3i(cell.x, cell.y, slot))
	HexWorldState.clear_slot(cell, slot)
	EventBus.plant_died.emit(cell)

# ── Helpers ─────────────────────────────────────────────────────────────────

func _get_cells_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq: int in range(-radius, radius + 1):
		for dr: int in range(-radius, radius + 1):
			var c := Vector2i(center.x + dq, center.y + dr)
			if _hex_distance(center, c) <= radius:
				out.append(c)
	return out

static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = b.x - a.x
	var dr: int = b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
