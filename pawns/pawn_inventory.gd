# pawn_inventory.gd
# res://pawns/pawn_inventory.gd
#
# Pawn inventory — fixed-size slot array with fast item_id total lookup.
# Owned by PawnState. Capacity set from SpeciesDef at pawn creation.

class_name PawnInventory
extends RefCounted

var capacity: int = 5
var slots:    Array[PawnInventorySlot] = []

# Fast lookup: item_id → total count across all slots
var _totals: Dictionary[StringName, int] = {}
var owner_pawn_id:int = -1
# ════════════════════════════════════════════════════════════════════════════ #
#  Initialisation
# ════════════════════════════════════════════════════════════════════════════ #

func setup(owner_pawn:int, p_capacity: int) -> void:
	owner_pawn_id = owner_pawn
	capacity = p_capacity
	slots.clear()
	_totals.clear()
	for i in capacity:
		slots.append(PawnInventorySlot.new())

# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

## Add count units of item_id. Returns overflow (amount that didn't fit).
func add_item(item_id: StringName, count: int) -> int:
	if count <= 0:
		return 0

	var remaining: int = count

	# Fill existing slots with the same item first
	for slot: PawnInventorySlot in slots:
		if remaining <= 0:
			break
		if slot.item_id != item_id:
			continue
		var space: int = _slot_space(slot, item_id)
		var add: int   = mini(space, remaining)
		slot.count    += add
		remaining     -= add

	# Then fill empty slots
	for slot: PawnInventorySlot in slots:
		if remaining <= 0:
			break
		if not slot.is_empty():
			continue
		var max_stack: int = _get_max_stack(item_id)
		var add: int       = mini(max_stack, remaining)
		slot.item_id = item_id
		slot.count   = add
		remaining   -= add

	var added: int = count - remaining
	if added > 0:
		_totals[item_id] = _totals.get(item_id, 0) + added
		if owner_pawn_id >= 0:
			EventBus.pawn_inventory_changed.emit(owner_pawn_id, item_id)
	return remaining



## Remove count units of item_id. Returns false if insufficient.
func remove_item(item_id: StringName, count: int) -> bool:
	if get_count(item_id) < count:
		return false

	var remaining: int = count
	for slot: PawnInventorySlot in slots:
		if remaining <= 0:
			break
		if slot.item_id != item_id:
			continue
		var take: int = mini(slot.count, remaining)
		slot.count   -= take
		remaining    -= take
		if slot.count <= 0:
			slot.clear()

	_totals[item_id] = maxi(0, _totals.get(item_id, 0) - count)
	if _totals[item_id] == 0:
		_totals.erase(item_id)

	EventBus.pawn_inventory_changed.emit(owner_pawn_id, item_id)  # after removal
	return true

## Total count of item_id across all slots.
func get_count(item_id: StringName) -> int:
	return _totals.get(item_id, 0)

## True if no slot can accept any more items.
func is_full() -> bool:
	for slot: PawnInventorySlot in slots:
		if slot.is_empty():
			return false
		if _slot_space(slot, slot.item_id) > 0:
			return false
	return true

## True if the inventory contains at least one item.
func has_any() -> bool:
	return not _totals.is_empty()

## True if any slot contains item_id.
func has_item(item_id: StringName) -> bool:
	return _totals.get(item_id, 0) > 0

## Returns all item_ids currently carried.
func get_item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _totals:
		if _totals[id] > 0:
			out.append(id)
	return out

## Total carried weight. Affects movement speed when > carry_weight_limit.
## Weight values come from ItemDef.unit_weight — defaulting to 0.1 per unit
## until ItemDef resources are authored and looked up.
func get_carried_weight() -> float:
	var total: float = 0.0
	for item_id: StringName in _totals:
		total += float(_totals[item_id]) * 0.1   # TODO Phase 4: read from ItemDef
	return total

## Remove all items. Returns a dict of what was cleared.
func clear_all() -> Dictionary:
	var snapshot: Dictionary = _totals.duplicate()
	for slot: PawnInventorySlot in slots:
		slot.clear()
	_totals.clear()
	return snapshot

# ════════════════════════════════════════════════════════════════════════════ #
#  Serialisation
# ════════════════════════════════════════════════════════════════════════════ #

func to_dict() -> Dictionary:
	var slot_data: Array = []
	for slot: PawnInventorySlot in slots:
		slot_data.append(slot.to_dict())
	return {
		"capacity": capacity,
		"slots":    slot_data,
	}

static func from_dict(d: Dictionary, owner_id: int = -1) -> PawnInventory:
	var inv := PawnInventory.new()
	inv.owner_pawn_id = owner_id
	inv.capacity = d.get("capacity", 5)
	inv.slots.clear()
	inv._totals.clear()
	for sd: Dictionary in d.get("slots", []):
		var slot: PawnInventorySlot = PawnInventorySlot.from_dict(sd)
		inv.slots.append(slot)
		if not slot.is_empty():
			inv._totals[slot.item_id] = inv._totals.get(slot.item_id, 0) + slot.count
	# Pad to capacity if save had fewer slots
	while inv.slots.size() < inv.capacity:
		inv.slots.append(PawnInventorySlot.new())
	return inv

# ════════════════════════════════════════════════════════════════════════════ #
#  Private helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _slot_space(slot: PawnInventorySlot, item_id: StringName) -> int:
	var max_stack: int = _get_max_stack(item_id)
	return max_stack - slot.count

func _get_max_stack(_item_id: StringName) -> int:
	# TODO Phase 4: look up ItemDef.max_stack from registry
	return 10
