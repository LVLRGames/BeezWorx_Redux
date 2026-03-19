# FILE: res://colony/hive/craft_order.gd
# Data structure for a manufacturing task assigned to a hive slot.
class_name CraftOrder
extends RefCounted

var recipe_id: StringName = &""
var target_count: int = 1
var produced_count: int = 0
var is_repeating: bool = false
var crafter_pawn_id: int = 0
var progress: float = 0.0

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> CraftOrder:
	return null
