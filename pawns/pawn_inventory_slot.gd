# pawn_inventory_slot.gd
# res://pawns/pawn_inventory_slot.gd
#
# One slot in a pawn's inventory. Holds a single item type up to max_stack.

class_name PawnInventorySlot
extends RefCounted

var item_id: StringName = &""   # empty = vacant
var count:   int        = 0

func is_empty() -> bool:
	return item_id == &"" or count <= 0

func clear() -> void:
	item_id = &""
	count   = 0

func to_dict() -> Dictionary:
	return {"item_id": str(item_id), "count": count}

static func from_dict(d: Dictionary) -> PawnInventorySlot:
	var s := PawnInventorySlot.new()
	s.item_id = StringName(d.get("item_id", ""))
	s.count   = d.get("count", 0)
	return s
