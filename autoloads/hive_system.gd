# hive_system.gd
# res://autoloads/hive_system.gd
#
# Autoload. Owns all HiveState objects and the hive slot grid.
# Exposes inventory queries, sleep slot reservation, damage, and upgrades.
#
# BOUNDARY CONTRACT:
#   HiveSystem writes HiveAnchorOccupant into HexWorldState cells.
#   HiveSystem reads HexWorldState only for tree detection (finding valid anchors).
#   All cross-system events go through EventBus.
#   TerritorySystem listens to hive_built / hive_destroyed to manage influence.
#
# NOTE: class_name intentionally omitted — accessed via autoload name HiveSystem.

extends Node

# ── Constants ─────────────────────────────────────────────────────────────────
const DEFAULT_SLOT_COUNT:      int   = 16
const DEFAULT_TERRITORY_RADIUS: int  = 6
const DEFAULT_MAX_INTEGRITY:   float = 100.0
const BREACH_TIMER_DURATION:   float = 30.0   # seconds before destroyed hive is removed

# ── State ─────────────────────────────────────────────────────────────────────
var _hives:           Dictionary[int, HiveState]    = {}
var _hives_by_cell:   Dictionary[Vector2i, int]     = {}
var _next_hive_id:    int = 0

# Inventory cache: colony_id → {item_id → total_count}
# Dirty flag per colony triggers recount on next query.
var _colony_inventory_cache: Dictionary[int, Dictionary] = {}
var _colony_inventory_dirty: Dictionary[int, bool]       = {}

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	EventBus.hive_destroyed.connect(_on_hive_destroyed)

# ════════════════════════════════════════════════════════════════════════════ #
#  Hive registration
# ════════════════════════════════════════════════════════════════════════════ #

## Register a new hive at anchor_cell for colony_id.
## Returns the new hive_id. Emits EventBus.hive_built.
## builder_pawn_id = -1 for the starter hive (no builder).
func register_hive(
	anchor_cell: Vector2i,
	colony_id: int,
	builder_pawn_id: int = -1,
	is_capital: bool = false,
	slot_count: int = DEFAULT_SLOT_COUNT,
	territory_radius: int = DEFAULT_TERRITORY_RADIUS
) -> int:
	var id: int = _next_hive_id
	_next_hive_id += 1

	var hs := HiveState.new()
	hs.hive_id          = id
	hs.colony_id        = colony_id
	hs.anchor_cell      = anchor_cell
	hs.anchor_type      = &"tree"
	hs.slot_count       = slot_count
	hs.max_integrity    = DEFAULT_MAX_INTEGRITY
	hs.integrity        = DEFAULT_MAX_INTEGRITY
	hs.is_destroyed     = false
	hs.territory_radius = territory_radius
	hs.is_capital       = is_capital

	# Initialise slot grid
	hs.slots.resize(slot_count)
	for i: int in slot_count:
		var slot := HiveSlot.new()
		slot.slot_index = i
		slot.hive_id    = id
		hs.slots[i]     = slot

	_hives[id]                    = hs
	_hives_by_cell[anchor_cell]   = id
	_colony_inventory_dirty[colony_id] = true

	# Mark cell as occupied by this hive in the world layer
	var occupant := HiveAnchorOccupant.new()
	occupant.hive_id   = id
	occupant.colony_id = colony_id
	occupant.placed_at = TimeService.world_time
	HexWorldState.set_occupant_data(anchor_cell, occupant)

	EventBus.hive_built.emit(id, anchor_cell, colony_id)
	return id

func get_hive(hive_id: int) -> HiveState:
	return _hives.get(hive_id, null)

func get_hive_at_cell(cell: Vector2i) -> HiveState:
	var id: int = _hives_by_cell.get(cell, -1)
	return _hives.get(id, null) if id >= 0 else null

func get_hives_for_colony(colony_id: int) -> Array[HiveState]:
	var out: Array[HiveState] = []
	for hs: HiveState in _hives.values():
		if hs.colony_id == colony_id and not hs.is_destroyed:
			out.append(hs)
	return out

func get_capital_hive(colony_id: int) -> HiveState:
	for hs: HiveState in _hives.values():
		if hs.colony_id == colony_id and hs.is_capital and not hs.is_destroyed:
			return hs
	# Fallback: return first living hive if no capital flagged
	for hs: HiveState in _hives.values():
		if hs.colony_id == colony_id and not hs.is_destroyed:
			return hs
	return null

func get_all_living_hives() -> Array[HiveState]:
	var out: Array[HiveState] = []
	for hs: HiveState in _hives.values():
		if not hs.is_destroyed:
			out.append(hs)
	return out

func set_queen_bed(hive_id: int, slot_index: int, queen_pawn_id: int) -> void:
	var slot: HiveSlot = get_slot(hive_id, slot_index)
	if slot == null:
		return
	slot.designation   = HiveSlot.SlotDesignation.BED
	slot.sleeper_id    = queen_pawn_id
	slot.assigned_pawn_id = queen_pawn_id
	emit_slot_changed(hive_id, slot_index)

# ════════════════════════════════════════════════════════════════════════════ #
#  Inventory
# ════════════════════════════════════════════════════════════════════════════ #

func get_colony_inventory_count(colony_id: int, item_id: StringName) -> int:
	if _colony_inventory_dirty.get(colony_id, true):
		_recount_colony_inventory(colony_id)
	var cache: Dictionary = _colony_inventory_cache.get(colony_id, {})
	return cache.get(item_id, 0)

func find_nearest_hive_with_item(
	colony_id: int,
	item_id: StringName,
	min_count: int,
	near_cell: Vector2i
) -> HiveState:
	var best: HiveState = null
	var best_dist: int  = 999999
	for hs: HiveState in get_hives_for_colony(colony_id):
		if _hive_item_count(hs, item_id) >= min_count:
			var dist: int = _hex_distance(hs.anchor_cell, near_cell)
			if dist < best_dist:
				best_dist = dist
				best       = hs
	return best

func find_nearest_hive_with_storage(
	colony_id: int,
	item_id: StringName,
	near_cell: Vector2i
) -> HiveState:
	var best: HiveState = null
	var best_dist: int  = 999999
	for hs: HiveState in get_hives_for_colony(colony_id):
		for slot: HiveSlot in hs.slots:
			if slot.designation != HiveSlot.SlotDesignation.STORAGE:
				continue
			if slot.locked_item_id != &"" and slot.locked_item_id != item_id:
				continue
			var used: int = _slot_total_items(slot)
			if used < slot.capacity_units:
				var dist: int = _hex_distance(hs.anchor_cell, near_cell)
				if dist < best_dist:
					best_dist = dist
					best       = hs
				break
	return best

func withdraw_item(hive_id: int, item_id: StringName, count: int) -> int:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null:
		return 0
	var remaining: int = count
	for slot: HiveSlot in hs.slots:
		if remaining <= 0:
			break
		if not slot.stored_items.has(item_id):
			continue
		var available: int = slot.stored_items[item_id]
		var take: int = mini(available, remaining)
		slot.stored_items[item_id] -= take
		if slot.stored_items[item_id] <= 0:
			slot.stored_items.erase(item_id)
		remaining -= take
	var withdrawn: int = count - remaining
	if withdrawn > 0:
		_colony_inventory_dirty[hs.colony_id] = true
	return withdrawn

func deposit_item(hive_id: int, item_id: StringName, count: int) -> int:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null:
		return count  # nothing deposited
	var remaining: int = count
	for slot: HiveSlot in hs.slots:
		if remaining <= 0:
			break
		if slot.designation != HiveSlot.SlotDesignation.STORAGE \
				and slot.designation != HiveSlot.SlotDesignation.GENERAL:
			continue
		if slot.locked_item_id != &"" and slot.locked_item_id != item_id:
			continue
		var used: int   = _slot_total_items(slot)
		var space: int  = slot.capacity_units - used
		if space <= 0:
			continue
		var put: int = mini(space, remaining)
		slot.stored_items[item_id] = slot.stored_items.get(item_id, 0) + put
		remaining -= put
	var deposited: int = count - remaining
	if deposited > 0:
		_colony_inventory_dirty[hs.colony_id] = true
	return remaining   # overflow that could not be deposited

# ════════════════════════════════════════════════════════════════════════════ #
#  Sleep slots
# ════════════════════════════════════════════════════════════════════════════ #

func find_sleep_slot(pawn_id: int, colony_id: int, near_cell: Vector2i) -> Dictionary:
	# Returns {hive_id, slot_index} or {} if none found
	var best_hive: HiveState = null
	var best_slot_idx: int   = -1
	var best_dist: int       = 999999

	for hs: HiveState in get_hives_for_colony(colony_id):
		var dist: int = _hex_distance(hs.anchor_cell, near_cell)
		if dist >= best_dist:
			continue
		for i: int in hs.slots.size():
			var slot: HiveSlot = hs.slots[i]
			if slot.designation != HiveSlot.SlotDesignation.BED:
				continue
			if slot.sleeper_id != -1 and slot.sleeper_id != pawn_id:
				continue
			best_hive     = hs
			best_slot_idx = i
			best_dist     = dist
			break

	if best_hive == null:
		return {}
	return {"hive_id": best_hive.hive_id, "slot_index": best_slot_idx}

func reserve_sleep_slot(hive_id: int, slot_index: int, pawn_id: int) -> void:
	var slot: HiveSlot = get_slot(hive_id, slot_index)
	if slot == null:
		return
	slot.sleeper_id = pawn_id
	emit_slot_changed(hive_id, slot_index)

func release_sleep_slot(hive_id: int, slot_index: int, pawn_id: int) -> void:
	var slot: HiveSlot = get_slot(hive_id, slot_index)
	if slot == null or slot.sleeper_id != pawn_id:
		return
	slot.sleeper_id = -1
	emit_slot_changed(hive_id, slot_index)

# ════════════════════════════════════════════════════════════════════════════ #
#  Damage and repair
# ════════════════════════════════════════════════════════════════════════════ #

func apply_damage(hive_id: int, amount: float, attacker_id: int) -> void:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null or hs.is_destroyed:
		return

	hs.integrity = maxf(hs.integrity - amount, 0.0)
	EventBus.hive_integrity_changed.emit(hive_id, hs.integrity)

	if hs.integrity <= 0.0:
		_begin_destroy(hive_id, attacker_id)

func repair_hive(hive_id: int, amount: float, _repairer_pawn_id: int) -> void:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null or hs.is_destroyed:
		return
	hs.integrity = minf(hs.integrity + amount, hs.max_integrity)
	EventBus.hive_integrity_changed.emit(hive_id, hs.integrity)

func _begin_destroy(hive_id: int, _attacker_id: int) -> void:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null:
		return
	hs.is_destroyed  = true
	hs.breach_timer  = BREACH_TIMER_DURATION

	HexWorldState.clear_occupant_data(hs.anchor_cell)
	_hives_by_cell.erase(hs.anchor_cell)
	_colony_inventory_dirty[hs.colony_id] = true

	EventBus.hive_destroyed.emit(hive_id, hs.anchor_cell, hs.colony_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  Upgrades
# ════════════════════════════════════════════════════════════════════════════ #

func apply_upgrade(hive_id: int, upgrade_type_id: StringName) -> void:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null:
		return
	if hs.applied_upgrades.has(upgrade_type_id):
		return
	hs.applied_upgrades.append(upgrade_type_id)

	# Handle territory beacon upgrade
	if upgrade_type_id == &"TERRITORY_BEACON":
		hs.territory_radius += 2
		TerritorySystem.expand_hive_radius(hive_id, hs.territory_radius)

	EventBus.hive_upgraded.emit(hive_id, upgrade_type_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  Slot queries
# ════════════════════════════════════════════════════════════════════════════ #

func get_slot(hive_id: int, slot_index: int) -> HiveSlot:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null or slot_index < 0 or slot_index >= hs.slots.size():
		return null
	return hs.slots[slot_index]

func get_slots_by_designation(hive_id: int, designation: int) -> Array[HiveSlot]:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null:
		return []
	var out: Array[HiveSlot] = []
	for slot: HiveSlot in hs.slots:
		if slot.designation == designation:
			out.append(slot)
	return out

func get_all_craft_orders(hive_id: int) -> Array[CraftOrder]:
	var hs: HiveState = _hives.get(hive_id)
	if hs == null:
		return []
	var out: Array[CraftOrder] = []
	for slot: HiveSlot in hs.slots:
		if slot.craft_order != null:
			out.append(slot.craft_order)
	return out

func get_nursery_eggs(colony_id: int) -> Array[Dictionary]:
	# Returns [{hive_id, slot_index, egg_state}]
	var out: Array[Dictionary] = []
	for hs: HiveState in get_hives_for_colony(colony_id):
		for i: int in hs.slots.size():
			var slot: HiveSlot = hs.slots[i]
			if slot.designation == HiveSlot.SlotDesignation.NURSERY \
					and slot.egg_state != null:
				out.append({
					"hive_id":    hs.hive_id,
					"slot_index": i,
					"egg_state":  slot.egg_state,
				})
	return out

func emit_slot_changed(hive_id: int, slot_index: int) -> void:
	EventBus.hive_slot_changed.emit(hive_id, slot_index)

# ════════════════════════════════════════════════════════════════════════════ #
#  EventBus listeners
# ════════════════════════════════════════════════════════════════════════════ #

func _on_hive_destroyed(_hive_id: int, _anchor_cell: Vector2i, _colony_id: int) -> void:
	# TerritorySystem handles fade. HiveSystem just cleans up sleeping pawns.
	# TODO Phase 3: release sleep slot reservations for pawns sleeping in this hive
	pass

# ════════════════════════════════════════════════════════════════════════════ #
#  Save / Load
# ════════════════════════════════════════════════════════════════════════════ #

func save_state() -> Dictionary:
	var hives_data: Array = []
	for hs: HiveState in _hives.values():
		hives_data.append(hs.to_dict())
	return {
		"hives":        hives_data,
		"next_hive_id": _next_hive_id,
		"schema_version": 1,
	}

func load_state(data: Dictionary) -> void:
	_hives.clear()
	_hives_by_cell.clear()
	_colony_inventory_cache.clear()
	_colony_inventory_dirty.clear()
	_next_hive_id = data.get("next_hive_id", 0)

	for d: Dictionary in data.get("hives", []):
		var hs: HiveState = HiveState.from_dict(d)
		_hives[hs.hive_id] = hs
		if not hs.is_destroyed:
			_hives_by_cell[hs.anchor_cell] = hs.hive_id
			_colony_inventory_dirty[hs.colony_id] = true
			# Re-populate occupant data
			var occupant := HiveAnchorOccupant.new()
			occupant.hive_id   = hs.hive_id
			occupant.colony_id = hs.colony_id
			#occupant.placed_at = TimeService.world_time
			HexWorldState.set_occupant_data(hs.anchor_cell, occupant)

# ════════════════════════════════════════════════════════════════════════════ #
#  Private helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _recount_colony_inventory(colony_id: int) -> void:
	var totals: Dictionary = {}
	for hs: HiveState in get_hives_for_colony(colony_id):
		for slot: HiveSlot in hs.slots:
			for item_id: StringName in slot.stored_items:
				totals[item_id] = totals.get(item_id, 0) + slot.stored_items[item_id]
	_colony_inventory_cache[colony_id] = totals
	_colony_inventory_dirty[colony_id] = false

func _hive_item_count(hs: HiveState, item_id: StringName) -> int:
	var total: int = 0
	for slot: HiveSlot in hs.slots:
		total += slot.stored_items.get(item_id, 0)
	return total

func _slot_total_items(slot: HiveSlot) -> int:
	var total: int = 0
	for item_id: StringName in slot.stored_items:
		total += slot.stored_items[item_id]
	return total

static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = b.x - a.x
	var dr: int = b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
