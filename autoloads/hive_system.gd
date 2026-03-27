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
const DEFAULT_SLOT_COUNT:      int   = 19
const DEFAULT_TERRITORY_RADIUS: int  = 6
const DEFAULT_MAX_INTEGRITY:   float = 100.0
const BREACH_TIMER_DURATION:   float = 30.0   # seconds before destroyed hive is removed
const HIVE_SCENE := preload("res://assets/meshes/hive/hive.tscn")

# ── State ─────────────────────────────────────────────────────────────────────
var _hives:           Dictionary[int, HiveState]    = {}
var _hives_by_cell:   Dictionary[Vector2i, int]     = {}
var _next_hive_id:    int = 0

# ── Visuals ───────────────────────────────────────────────────────────────────
var _visual_parent:   Node3D = null
var _controllers:     Dictionary[int, HiveController] = {}


## Colony inventory aggregate cache — rebuilt on deposit/withdraw
## Key: "%d_%s" % [colony_id, item_id]  Value: total count
var _colony_inventory_cache: Dictionary[String, int] = {}
var _colony_inventory_dirty: Dictionary[int, bool]   = {}   # colony_id → needs rebuild
# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	print("has_save check: ", SaveManager.has_save(SaveManager.AUTOSAVE_SLOT))
	print("save path: ", SaveManager.SAVE_DIR + SaveManager.AUTOSAVE_SLOT + SaveManager.SAVE_EXTENSION)
	print("file exists: ", FileAccess.file_exists(
		SaveManager.SAVE_DIR + SaveManager.AUTOSAVE_SLOT + SaveManager.SAVE_EXTENSION))
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
	_spawn_visual(id, anchor_cell)
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
	for hs: HiveState in get_hives_for_colony(colony_id):
		if hs.is_capital:
			return hs
	# Fallback: first living hive
	var hives: Array[HiveState] = get_hives_for_colony(colony_id)
	for hs: HiveState in hives:
		if not hs.is_destroyed:
			return hs
	return null

func get_all_living_hives() -> Array[HiveState]:
	var out: Array[HiveState] = []
	for hs: HiveState in _hives.values():
		if not hs.is_destroyed:
			out.append(hs)
	return out

func set_queen_bed(hive_id: int, slot_index: int, queen_pawn_id: int) -> void:
	var hs: HiveState = get_hive(hive_id)
	if hs == null:
		return
	var slot: HiveSlot = get_slot(hive_id, slot_index)
	if slot == null:
		return
	slot.designation      = HiveSlot.SlotDesignation.BED
	slot.subtype          = HiveSlot.SlotSubtype.ROYAL
	slot.assigned_pawn_id = queen_pawn_id
 
	# Mark this hive as capital
	_set_capital_hive(hive_id, hs.colony_id)
	emit_slot_changed(hive_id, slot_index)
 

func _set_capital_hive(hive_id: int, colony_id: int) -> void:
	# Clear capital from other hives in this colony
	for hs: HiveState in get_hives_for_colony(colony_id):
		if hs.hive_id != hive_id:
			hs.is_capital = false
	var target: HiveState = get_hive(hive_id)
	if target:
		target.is_capital = true
 




func set_visual_parent(parent: Node3D) -> void:
	_visual_parent = parent

func _spawn_visual(hive_id: int, anchor_cell: Vector2i) -> void:
	print("_spawn_visual called, _visual_parent=", _visual_parent)
	if _visual_parent == null:
		push_warning("HiveSystem: no visual parent")
		return

	if _visual_parent == null:
		push_warning("HiveSystem: no visual parent set — call set_visual_parent() from WorldRoot")
		return
	if HIVE_SCENE == null:
		push_warning("HiveSystem: HIVE_SCENE is null — check res://assets/meshes/hive/hive.tscn")
		return
 
	var instance: Node3D = HIVE_SCENE.instantiate()
	var visual := HiveController.new()
	visual.name = "HiveController_%d" % hive_id
 
	# Attach hive_visual.gd to the instance if it's not already the root script
	# If hive.tscn root already has hive_visual.gd, cast directly
	var hv: HiveController = instance as HiveController
	if hv == null:
		# hive.tscn root is not HiveController — add script as a wrapper parent
		visual.add_child(instance)
		hv = visual
		_visual_parent.add_child(hv)
	else:
		_visual_parent.add_child(hv)
 
	# Get world position of anchor cell
	var w: Vector2 = HexConsts.AXIAL_TO_WORLD(anchor_cell.x, anchor_cell.y)
	# Use terrain height at that cell
	var anchor_world_pos := Vector3(w.x, _get_terrain_height(anchor_cell), w.y)
	hv.setup(hive_id, anchor_world_pos)
	_controllers[hive_id] = hv
 
func _get_terrain_height(cell: Vector2i) -> float:
	# Query the world state for terrain height at this cell
	# Falls back to 0 if cell not loaded yet
	var state: HexCellState = HexWorldState.get_cell(cell)
	if state == null:
		return 0.0
	# HexCellState doesn't store height directly — use the baseline noise
	# Same approach as HexChunk._hc() but we only need one cell
	if HexWorldState.cfg == null:
		return 0.0
	return HexWorldState.cfg.get_height(cell.x, cell.y)

func get_controller(hive_id: int) -> HiveController:
	return _controllers.get(hive_id, null)

# ════════════════════════════════════════════════════════════════════════════ #
#  Inventory
# ════════════════════════════════════════════════════════════════════════════ #

## Total count of item_id across all hives owned by colony_id.
func get_colony_inventory_count(colony_id: int, item_id: StringName) -> int:
	_rebuild_cache_if_dirty(colony_id)
	return _colony_inventory_cache.get("%d_%s" % [colony_id, item_id], 0)

## Find the nearest hive to near_cell that has at least min_count of item_id.
## Returns null if none found.
func find_nearest_hive_with_item(
	colony_id: int,
	item_id: StringName,
	min_count: int,
	near_cell: Vector2i
) -> HiveState:
	var best: HiveState = null
	var best_dist: int  = 999999
 
	for hs: HiveState in get_hives_for_colony(colony_id):
		if hs.is_destroyed:
			continue
		var total: int = 0
		for slot: HiveSlot in hs.slots:
			total += slot.stored_items.get(item_id, 0)
		if total < min_count:
			continue
		var dist: int = _hex_dist(hs.anchor_cell, near_cell)
		if dist < best_dist:
			best_dist = dist
			best      = hs
 
	return best

## Find the nearest hive to near_cell with available storage space for item_id.
func find_nearest_hive_with_storage(
	colony_id: int,
	item_id: StringName,
	near_cell: Vector2i
) -> HiveState:
	var best: HiveState = null
	var best_dist: int  = 999999
 
	for hs: HiveState in get_hives_for_colony(colony_id):
		if hs.is_destroyed:
			continue
		for slot: HiveSlot in hs.slots:
			if not _slot_accepts(slot, item_id):
				continue
			if _slot_total(slot) < slot.capacity_units:
				var dist: int = _hex_dist(hs.anchor_cell, near_cell)
				if dist < best_dist:
					best_dist = dist
					best      = hs
				break   # found a valid slot in this hive, no need to check more
 
	return best


## Withdraw count units of item_id from hive_id.
## Returns how many were actually withdrawn (may be less than count if insufficient).
func withdraw_item(hive_id: int, item_id: StringName, count: int) -> int:
	var hs: HiveState = get_hive(hive_id)
	if hs == null or count <= 0:
		return 0
 
	var withdrawn: int = 0
	var remaining: int = count
 
	for slot: HiveSlot in hs.slots:
		if remaining <= 0:
			break
		var available: int = slot.stored_items.get(item_id, 0)
		if available <= 0:
			continue
		var take: int = mini(available, remaining)
		slot.stored_items[item_id] = available - take
		if slot.stored_items[item_id] <= 0:
			slot.stored_items.erase(item_id)
		withdrawn  += take
		remaining  -= take
		emit_slot_changed(hive_id, slot.slot_index)
 
	if withdrawn > 0:
		_mark_colony_inventory_dirty(hs.colony_id)
 
	return withdrawn



## Deposit count units of item_id into any available slot in hive_id.
## Returns overflow (units that didn't fit).
func deposit_item(hive_id: int, item_id: StringName, count: int) -> int:
	var hs: HiveState = get_hive(hive_id)
	if hs == null or count <= 0:
		return count
 
	var remaining: int = count
 
	# Prefer storage slots locked to this item, then general slots
	for slot: HiveSlot in hs.slots:
		if remaining <= 0:
			break
		if not _slot_accepts(slot, item_id):
			continue
		var space: int  = slot.capacity_units - _slot_total(slot)
		if space <= 0:
			continue
		var add: int    = mini(space, remaining)
		slot.stored_items[item_id] = slot.stored_items.get(item_id, 0) + add
		remaining -= add
		emit_slot_changed(hive_id, slot.slot_index)
 
	if remaining < count:
		_mark_colony_inventory_dirty(hs.colony_id)
 
	return remaining   # overflow

# ════════════════════════════════════════════════════════════════════════════ #
#  Sleep slots
# ════════════════════════════════════════════════════════════════════════════ #

## Find an available bed slot for pawn_id near near_cell.
## Returns { hive_id, slot_index } or {} if none found.
func find_sleep_slot(pawn_id: int, colony_id: int, near_cell: Vector2i) -> Dictionary:
	var hives: Array[HiveState] = get_hives_for_colony(colony_id)
	# Sort by distance
	hives.sort_custom(func(a, b):
		return _hex_dist(a.anchor_cell, near_cell) < _hex_dist(b.anchor_cell, near_cell)
	)
 
	for hs: HiveState in hives:
		if hs.is_destroyed:
			continue
		for slot: HiveSlot in hs.slots:
			if slot.designation != HiveSlot.SlotDesignation.BED \
					and slot.designation != HiveSlot.SlotDesignation.GENERAL:
				continue
			if slot.sleeper_id >= 0:
				continue   # occupied
			if slot.assigned_pawn_id >= 0 and slot.assigned_pawn_id != pawn_id:
				continue   # assigned to someone else
			return { "hive_id": hs.hive_id, "slot_index": slot.slot_index }
 
	return {}
 
func reserve_sleep_slot(hive_id: int, slot_index: int, pawn_id: int) -> void:
	var slot: HiveSlot = get_slot(hive_id, slot_index)
	if slot == null:
		return
	slot.sleeper_id = pawn_id
	emit_slot_changed(hive_id, slot_index)
 
func release_sleep_slot(hive_id: int, slot_index: int, pawn_id: int) -> void:
	var slot: HiveSlot = get_slot(hive_id, slot_index)
	if slot == null:
		return
	if slot.sleeper_id == pawn_id:
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
	
	var visual: HiveController = _controllers.get(hive_id)
	if visual:
		visual.set_integrity(hs.integrity, hs.max_integrity)

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
	var visual: HiveController = _controllers.get(hive_id)
	if visual:
		visual.show_destroyed()
		_controllers.erase(hive_id)


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
	var hs: HiveState = get_hive(hive_id)
	if hs == null or slot_index < 0 or slot_index >= hs.slots.size():
		return null
	return hs.slots[slot_index]
 
func get_slots_by_designation(hive_id: int, designation: int) -> Array[HiveSlot]:
	var hs: HiveState = get_hive(hive_id)
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
	print("HiveSystem.load_state: hive count=", data.get("hives", []).size())
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
	
	# Respawn visuals for all living hives
	for hive_id_key: int in _hives:
		var hs: HiveState = _hives[hive_id_key]
		if not hs.is_destroyed:
			_spawn_visual(hive_id_key, hs.anchor_cell)


# ════════════════════════════════════════════════════════════════════════════ #
#  Private helpers
# ════════════════════════════════════════════════════════════════════════════ #


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


func _mark_colony_inventory_dirty(colony_id: int) -> void:
	_colony_inventory_dirty[colony_id] = true
 
func _rebuild_cache_if_dirty(colony_id: int) -> void:
	if not _colony_inventory_dirty.get(colony_id, true):
		return

	# Collect keys to remove first, then erase
	var prefix: String = "%d_" % colony_id
	var to_erase: Array[String] = []
	for key: String in _colony_inventory_cache:
		if key.begins_with(prefix):
			to_erase.append(key)
	for key: String in to_erase:
		_colony_inventory_cache.erase(key)

	# Rebuild from all hives
	for hs: HiveState in get_hives_for_colony(colony_id):
		if hs.is_destroyed:
			continue
		for slot: HiveSlot in hs.slots:
			for item_id: StringName in slot.stored_items:
				var cache_key: String = "%d_%s" % [colony_id, item_id]
				_colony_inventory_cache[cache_key] = \
					_colony_inventory_cache.get(cache_key, 0) + slot.stored_items[item_id]

	_colony_inventory_dirty[colony_id] = false
 
func _slot_accepts(slot: HiveSlot, item_id: StringName) -> bool:
	match slot.designation:
		HiveSlot.SlotDesignation.BED:
			return false
		HiveSlot.SlotDesignation.STORAGE:
			if slot.locked_item_id != &"":
				return item_id == slot.locked_item_id
			return true
		HiveSlot.SlotDesignation.GENERAL, \
		HiveSlot.SlotDesignation.CRAFTING, \
		HiveSlot.SlotDesignation.NURSERY:
			return SlotDepositRules.can_deposit(item_id, slot)
	return false
 
func _slot_total(slot: HiveSlot) -> int:
	var total: int = 0
	for v in slot.stored_items.values():
		total += v
	return total
 
static func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var dq: int = b.x - a.x
	var dr: int = b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
