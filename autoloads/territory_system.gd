# territory_system.gd
# res://autoloads/territory_system.gd
#
# Autoload. Manages per-cell colony influence, radius projection from hives,
# territory fade after destruction, and plant allegiance queries.
#
# INFLUENCE MODEL (step-valued, per spec):
#   dist <= radius - 2  → 1.0  (core)
#   dist == radius - 1  → 0.6  (border)
#   dist == radius      → 0.3  (fringe)
#   dist > radius       → 0.0  (outside)
#
# NOTE: class_name intentionally omitted — accessed via autoload name TerritorySystem.

extends Node

# ── Tuning constants ──────────────────────────────────────────────────────────
const FADE_DURATION:    float = 120.0   # seconds before destroyed hive fully fades
const EXPANSION_REACH:  int   = 3       # hex cells beyond fringe for new hive placement
const FADE_TICK_RATE:   float = 1.0     # seconds between fade pass

# Step influence values — tunable per spec
const INFLUENCE_CORE:   float = 1.0
const INFLUENCE_BORDER: float = 0.6
const INFLUENCE_FRINGE: float = 0.3

# ── State ─────────────────────────────────────────────────────────────────────
# cell → {colony_id: influence_value}
var _influence: Dictionary = {}

# cell → {hive_id: influence_contributed}
var _cell_contributors: Dictionary = {}

# hive_id → [cells this hive contributes to]
var _hive_cells: Dictionary[int, Array] = {}

# hive_id → FadeRecord
var _active_fades: Dictionary[int, _FadeRecord] = {}

# cell → world_time of last change (for incremental renderer updates)
var _recently_changed: Dictionary[Vector2i, float] = {}

var _fade_timer: float = 0.0

# ── FadeRecord inner data (not a nested class — plain Dictionary wrapper) ─────
class _FadeRecord:
	var hive_id:   int
	var colony_id: int
	var cells:     Array   # Array[Vector2i]
	var timer:     float

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	EventBus.hive_built.connect(_on_hive_built)
	EventBus.hive_destroyed.connect(_on_hive_destroyed)
	EventBus.hive_upgraded.connect(_on_hive_upgraded)

func _process(delta: float) -> void:
	_fade_timer -= delta
	if _fade_timer <= 0.0:
		_fade_timer = FADE_TICK_RATE
		_fade_tick(delta * FADE_TICK_RATE)   # pass elapsed, not frame delta

# ════════════════════════════════════════════════════════════════════════════ #
#  Public query API
# ════════════════════════════════════════════════════════════════════════════ #

func get_influence(cell: Vector2i, colony_id: int) -> float:
	var cell_data: Dictionary = _influence.get(cell, {})
	return cell_data.get(colony_id, 0.0)

func is_in_territory(cell: Vector2i, colony_id: int) -> bool:
	return get_influence(cell, colony_id) > 0.0

func get_controlling_colony(cell: Vector2i) -> int:
	var cell_data: Dictionary = _influence.get(cell, {})
	var best_colony: int    = -1
	var best_influence: float = 0.0
	for cid: int in cell_data:
		var inf: float = cell_data[cid]
		if inf > best_influence or (inf == best_influence and cid < best_colony):
			best_influence = inf
			best_colony    = cid
	return best_colony

func get_all_colonies_at(cell: Vector2i) -> Array[int]:
	var cell_data: Dictionary = _influence.get(cell, {})
	var out: Array[int] = []
	for cid: int in cell_data:
		if cell_data[cid] > 0.0:
			out.append(cid)
	return out

func get_cell_count_for_colony(colony_id: int) -> int:
	var count: int = 0
	for cell: Vector2i in _influence:
		if _influence[cell].get(colony_id, 0.0) > 0.0:
			count += 1
	return count

func get_contested_cell_count(colony_id: int) -> int:
	var count: int = 0
	for cell: Vector2i in _influence:
		if _influence[cell].get(colony_id, 0.0) > 0.0:
			if get_all_colonies_at(cell).size() > 1:
				count += 1
	return count

func is_valid_expansion_cell(cell: Vector2i, colony_id: int) -> bool:
	for neighbor: Vector2i in HexWorldBaseline.hex_disk(cell, EXPANSION_REACH):
		if get_influence(neighbor, colony_id) >= INFLUENCE_FRINGE:
			return true
	return false

func get_render_influence(cell: Vector2i, colony_id: int) -> float:
	return get_influence(cell, colony_id)

func get_all_influence(cell: Vector2i) -> Dictionary:
	return _influence.get(cell, {}).duplicate()

func get_changed_cells_since(world_time: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in _recently_changed:
		if _recently_changed[cell] >= world_time:
			out.append(cell)
	return out

# ── Plant allegiance ──────────────────────────────────────────────────────────

enum PlantAllegiance { ALLIED, NEUTRAL, HOSTILE, FERAL }

func get_plant_allegiance(cell: Vector2i, plant_colony_id: int) -> int:
	var influence: float = get_influence(cell, plant_colony_id)
	if influence <= 0.0:
		return PlantAllegiance.FERAL

	var controller: int = get_controlling_colony(cell)
	if controller == plant_colony_id:
		if influence >= INFLUENCE_BORDER:
			return PlantAllegiance.ALLIED
		else:
			return PlantAllegiance.NEUTRAL   # fringe: uncertain
	else:
		return PlantAllegiance.HOSTILE

# ════════════════════════════════════════════════════════════════════════════ #
#  Radius projection
# ════════════════════════════════════════════════════════════════════════════ #

func expand_hive_radius(hive_id: int, new_radius: int) -> void:
	var hs: HiveState = HiveSystem.get_hive(hive_id)
	if hs == null:
		return
	hs.territory_radius = new_radius
	# Clear old contribution, re-project with new radius
	_clear_hive_contributions(hive_id)
	_project_hive_influence(hive_id)

func _project_hive_influence(hive_id: int) -> void:
	var hs: HiveState = HiveSystem.get_hive(hive_id)
	if hs == null:
		return

	var radius:    int = hs.territory_radius
	var colony_id: int = hs.colony_id
	var new_cells: Array[Vector2i] = []

	for cell: Vector2i in HexWorldBaseline.hex_disk(hs.anchor_cell, radius):
		var dist:      int   = _hex_distance(hs.anchor_cell, cell)
		var influence: float = _influence_at_distance(dist, radius)
		if influence <= 0.0:
			continue

		var old_influence: float = get_influence(cell, colony_id)
		_set_influence(cell, colony_id, influence, hive_id)

		if get_influence(cell, colony_id) > old_influence:
			new_cells.append(cell)

	if not new_cells.is_empty():
		EventBus.territory_expanded.emit(colony_id, new_cells)

func _clear_hive_contributions(hive_id: int) -> void:
	var cells: Array = _hive_cells.get(hive_id, [])
	for cell: Vector2i in cells:
		var contrib: Dictionary = _cell_contributors.get(cell, {})
		contrib.erase(hive_id)
	_hive_cells.erase(hive_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  Territory fade
# ════════════════════════════════════════════════════════════════════════════ #

func _register_fade(hive_id: int, colony_id: int, cells: Array) -> void:
	var rec        := _FadeRecord.new()
	rec.hive_id    = hive_id
	rec.colony_id  = colony_id
	rec.cells      = cells.duplicate()
	rec.timer      = FADE_DURATION
	_active_fades[hive_id] = rec

func _fade_tick(_elapsed: float) -> void:
	var completed: Array[int] = []
	for hive_id: int in _active_fades:
		var rec: _FadeRecord = _active_fades[hive_id]
		rec.timer -= FADE_TICK_RATE

		# Partial visual fade at 50% and 75% through timer
		var progress: float = 1.0 - (rec.timer / FADE_DURATION)
		_update_fade_visuals(rec, progress)

		if rec.timer <= 0.0:
			_apply_fade(rec)
			completed.append(hive_id)

	for hive_id: int in completed:
		_active_fades.erase(hive_id)

func _update_fade_visuals(rec: _FadeRecord, progress: float) -> void:
	# At 50%: fringe cells lose influence
	# At 75%: border cells lose influence
	# At 100%: _apply_fade handles remainder
	if progress < 0.5 or progress >= 1.0:
		return

	var threshold: float = 0.0
	if progress >= 0.75:
		threshold = INFLUENCE_BORDER
	elif progress >= 0.5:
		threshold = INFLUENCE_FRINGE

	var faded: Array[Vector2i] = []
	for cell: Vector2i in rec.cells:
		var contrib: Dictionary = _cell_contributors.get(cell, {})
		var hive_inf: float     = contrib.get(rec.hive_id, 0.0)
		if hive_inf > threshold:
			continue
		# Only fade if this hive was the sole contributor at this level
		var other_max: float = 0.0
		for other_id: int in contrib:
			if other_id == rec.hive_id:
				continue
			var other_hs: HiveState = HiveSystem.get_hive(other_id)
			if other_hs and other_hs.colony_id == rec.colony_id:
				other_max = maxf(other_max, contrib[other_id])
		if other_max < hive_inf:
			_set_raw_influence(cell, rec.colony_id, other_max)
			faded.append(cell)

	if not faded.is_empty():
		EventBus.territory_faded.emit(rec.colony_id, faded)

func _apply_fade(rec: _FadeRecord) -> void:
	var faded_cells: Array[Vector2i] = []

	for cell: Vector2i in rec.cells:
		var contrib: Dictionary = _cell_contributors.get(cell, {})
		contrib.erase(rec.hive_id)

		# Recompute influence from remaining contributors for this colony
		var new_influence: float = 0.0
		for other_hive_id: int in contrib:
			var other_hs: HiveState = HiveSystem.get_hive(other_hive_id)
			if other_hs and other_hs.colony_id == rec.colony_id:
				new_influence = maxf(new_influence, contrib[other_hive_id])

		var old_influence: float = get_influence(cell, rec.colony_id)
		_set_raw_influence(cell, rec.colony_id, new_influence)

		if new_influence < old_influence:
			faded_cells.append(cell)

	_hive_cells.erase(rec.hive_id)

	if not faded_cells.is_empty():
		EventBus.territory_faded.emit(rec.colony_id, faded_cells)

# ════════════════════════════════════════════════════════════════════════════ #
#  EventBus listeners
# ════════════════════════════════════════════════════════════════════════════ #

func _on_hive_built(hive_id: int, anchor_cell: Vector2i, colony_id: int) -> void:
	_project_hive_influence(hive_id)
	print("Territory projected for hive %d at %s, cell count: %d" % [
		hive_id, anchor_cell, get_cell_count_for_colony(colony_id)])

func _on_hive_destroyed(hive_id: int, _anchor_cell: Vector2i, colony_id: int) -> void:
	var cells: Array = _hive_cells.get(hive_id, [])
	_register_fade(hive_id, colony_id, cells)

func _on_hive_upgraded(hive_id: int, upgrade_type_id: StringName) -> void:
	if upgrade_type_id == &"TERRITORY_BEACON":
		var hs: HiveState = HiveSystem.get_hive(hive_id)
		if hs:
			expand_hive_radius(hive_id, hs.territory_radius)

# ════════════════════════════════════════════════════════════════════════════ #
#  Save / Load
# ════════════════════════════════════════════════════════════════════════════ #

func save_state() -> Dictionary:
	var fades: Array = []
	for hive_id: int in _active_fades:
		var rec: _FadeRecord = _active_fades[hive_id]
		fades.append({
			"hive_id":   rec.hive_id,
			"colony_id": rec.colony_id,
			"timer":     rec.timer,
		})
	return {"active_fades": fades, "schema_version": 1}

func load_state(data: Dictionary) -> void:
	_recompute_from_hives()
	for f: Dictionary in data.get("active_fades", []):
		var hive_id: int = f["hive_id"]
		if not _hive_cells.has(hive_id):
			continue
		var rec        := _FadeRecord.new()
		rec.hive_id    = hive_id
		rec.colony_id  = f["colony_id"]
		rec.cells      = _hive_cells[hive_id].duplicate()
		rec.timer      = f["timer"]
		_active_fades[hive_id] = rec

func _recompute_from_hives() -> void:
	_influence.clear()
	_cell_contributors.clear()
	_hive_cells.clear()
	_recently_changed.clear()
	for hs: HiveState in HiveSystem.get_all_living_hives():
		_project_hive_influence(hs.hive_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  Private helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _influence_at_distance(dist: int, radius: int) -> float:
	if dist <= radius - 2:   return INFLUENCE_CORE
	elif dist == radius - 1: return INFLUENCE_BORDER
	elif dist == radius:     return INFLUENCE_FRINGE
	else:                    return 0.0

func _set_influence(cell: Vector2i, colony_id: int, influence: float, hive_id: int) -> void:
	# Only set if higher than current for this colony (union-of-radii rule)
	var cell_data: Dictionary = _influence.get(cell, {})
	var current: float = cell_data.get(colony_id, 0.0)
	if influence <= current:
		return

	cell_data[colony_id] = influence
	_influence[cell]     = cell_data

	# Track contributor
	var contrib: Dictionary = _cell_contributors.get(cell, {})
	contrib[hive_id]        = influence
	_cell_contributors[cell] = contrib

	# Track reverse (hive → cells)
	if not _hive_cells.has(hive_id):
		_hive_cells[hive_id] = []
	if not _hive_cells[hive_id].has(cell):
		_hive_cells[hive_id].append(cell)

	_recently_changed[cell] = TimeService.world_time

func _set_raw_influence(cell: Vector2i, colony_id: int, influence: float) -> void:
	var cell_data: Dictionary = _influence.get(cell, {})
	if influence <= 0.0:
		cell_data.erase(colony_id)
	else:
		cell_data[colony_id] = influence
	if cell_data.is_empty():
		_influence.erase(cell)
	else:
		_influence[cell] = cell_data
	_recently_changed[cell] = TimeService.world_time

static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = b.x - a.x
	var dr: int = b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
