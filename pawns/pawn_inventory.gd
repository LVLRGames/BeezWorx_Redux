# FILE: res://pawns/pawn_inventory.gd
# Manages items carried by a specific pawn.
class_name PawnInventory
extends RefCounted


var capacity: int = 10
var slots: Array[PawnInventorySlot] = []

func add_item(item_id: StringName, count: int) -> int:
	return 0

func remove_item(item_id: StringName, count: int) -> bool:
	return false

func get_count(item_id: StringName) -> int:
	return 0

func is_full() -> bool:
	return false

func get_carried_weight() -> float:
	return 0.0

func get_item_tags() -> Array[StringName]:
	return []

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> PawnInventory:
	return null
