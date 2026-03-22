# plant_lifecycle_system.gd
# res://autoloads/plant_lifecycle_system.gd
#
# Autoload. Listens to EventBus.day_changed and runs a lightweight scan
# of all loaded plant cells to handle:
#   - Natural pollination (flowering plants near each other set fruit)
#   - Natural sprouting (fruiting plants spawn sprouts in adjacent empty cells)
#   - Stage change notifications (emits cell_changed for visual refresh)
#
# DESIGN NOTES:
#   This system does NOT tick every frame. It runs once per in-game day,
#   staggered across chunks to spread load. The simulation (hex_world_simulation.gd)
#   already computes plant stages correctly from world_time — this system only
#   needs to detect when a transition has happened and handle side effects
#   (sprouting, death cleanup) that the simulation can't self-report.
#
#   Natural watering: baseline wild plants have wilt_without_water = false.
#   Only player-cultivated plants need manual watering.
#
# NOTE: class_name intentionally omitted — accessed via autoload name.

extends Node

# ── Tuning ────────────────────────────────────────────────────────────────────
## Chance per flowering plant per day that natural pollination occurs
@export var natural_pollination_chance: float = 0.4

## Chance per fruiting plant per day that it spawns a sprout
@export var natural_sprout_chance: float = 0.15

## Max hex distance for natural pollination to occur
@export var natural_pollination_radius: int = 4

## Max hex distance for sprout placement
@export var natural_sprout_radius: int = 3

## How many plants to process per day tick (spread load across days)
@export var plants_per_day_batch: int = 200

# ── State ─────────────────────────────────────────────────────────────────────
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pending_cells: Array[Vector2i] = []
var _last_known_stages: Dictionary[Vector2i, int] = {}

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	_rng.randomize()
	EventBus.day_changed.connect(_on_day_changed)

# ════════════════════════════════════════════════════════════════════════════ #
#  Day tick
# ════════════════════════════════════════════════════════════════════════════ #

func _on_day_changed(_day: int) -> void:
	# Collect all loaded plant cells from HexWorldState cache
	_collect_plant_cells()
	# Process a batch — remainder carries over to next day
	_process_batch()

func _collect_plant_cells() -> void:
	# Pull plant cells from HexWorldState's cell cache (populated by loaded chunks)
	# Only RESOURCE_PLANT cells that are at their origin matter
	var cache: Dictionary = HexWorldState.get_cell_cache()
	for cell: Vector2i in cache:
		var state: HexCellState = cache[cell]
		if not state.occupied:
			continue
		if state.category != HexGridObjectDef.Category.RESOURCE_PLANT:
			continue
		if state.origin != cell:
			continue
		if not _pending_cells.has(cell):
			_pending_cells.append(cell)

func _process_batch() -> void:
	var count: int = mini(plants_per_day_batch, _pending_cells.size())
	var to_process: Array[Vector2i] = []
	for i in count:
		to_process.append(_pending_cells[i])
	_pending_cells = _pending_cells.slice(count)

	for cell: Vector2i in to_process:
		_tick_plant(cell)

func _tick_plant(cell: Vector2i) -> void:
	var state: HexCellState = HexWorldState.get_cell(cell)
	if not state.occupied or state.origin != cell:
		return
	if state.category != HexGridObjectDef.Category.RESOURCE_PLANT:
		return

	var stage: int = state.stage
	var prev_stage: int = _last_known_stages.get(cell, -1)

	# Detect stage change
	if prev_stage != -1 and stage != prev_stage:
		_on_stage_changed(cell, prev_stage, stage, state)

	_last_known_stages[cell] = stage

	# Natural behaviors per stage
	match stage:
		HexWorldState.Stage.FLOWERING:
			_try_natural_pollination(cell, state)
		HexWorldState.Stage.FRUITING:
			_try_natural_sprout(cell, state)
		HexWorldState.Stage.DEAD:
			_on_plant_died(cell, state)

func _on_stage_changed(
	cell: Vector2i,
	prev: int,
	next: int,
	_state: HexCellState
) -> void:
	# Notify chunk to re-render this cell
	HexWorldState.invalidate_cells([cell])
	EventBus.plant_stage_changed.emit(cell, prev, next)

# ════════════════════════════════════════════════════════════════════════════ #
#  Natural pollination
# ════════════════════════════════════════════════════════════════════════════ #

func _try_natural_pollination(cell: Vector2i, state: HexCellState) -> void:
	if not state.has_pollen:
		return
	if _rng.randf() > natural_pollination_chance:
		return

	var neighbors: Array[Vector2i] = _get_cells_in_radius(cell, natural_pollination_radius)
	neighbors.shuffle()

	for neighbor: Vector2i in neighbors:
		if neighbor == cell:
			continue
		var n_state: HexCellState = HexWorldState.get_cell(neighbor)
		if not n_state.occupied:
			continue
		if n_state.category != HexGridObjectDef.Category.RESOURCE_PLANT:
			continue
		if n_state.stage != HexWorldState.Stage.FLOWERING:
			continue
		if not n_state.has_pollen:
			continue
		HexWorldState.apply_pollen(cell, neighbor)
		return

# ════════════════════════════════════════════════════════════════════════════ #
#  Natural sprouting
# ════════════════════════════════════════════════════════════════════════════ #

func _try_natural_sprout(cell: Vector2i, state: HexCellState) -> void:
	if state.definition == null:
		return
	var plant_def: HexPlantDef = state.definition as HexPlantDef
	if plant_def == null:
		return
	var pd: HexPlantData = plant_def.plant_data
	if pd == null:
		return

	var chance: float = pd.sprout_chance if pd.sprout_chance > 0.0 else natural_sprout_chance
	if _rng.randf() > chance:
		return

	var sprout_rad: int = pd.sprout_radius if pd.sprout_radius > 0 else natural_sprout_radius
	var target: Vector2i = HexWorldState.find_sprout_cell(cell, sprout_rad)
	if target == Vector2i(-9999, -9999):
		return

	HexWorldState.spawn_sprout(target, plant_def.id, null, cell, Vector2i(-9999, -9999))
	EventBus.plant_sprouted.emit(target, plant_def.id, cell)


# ════════════════════════════════════════════════════════════════════════════ #
#  Plant death cleanup
# ════════════════════════════════════════════════════════════════════════════ #

func _on_plant_died(cell: Vector2i, _state: HexCellState) -> void:
	_last_known_stages.erase(cell)
	# Clear the delta so the cell returns to baseline on next chunk refresh
	# (baseline may re-generate a new plant here naturally)
	# TODO Phase 5: spawn debris/husk entity, drop seeds as items
	HexWorldState.clear_cell(cell)
	EventBus.plant_died.emit(cell)

# ════════════════════════════════════════════════════════════════════════════ #
#  Helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _get_cells_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq: int in range(-radius, radius + 1):
		for dr: int in range(-radius, radius + 1):
			var cell := Vector2i(center.x + dq, center.y + dr)
			if _hex_distance(center, cell) <= radius:
				out.append(cell)
	return out

static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = b.x - a.x
	var dr: int = b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
