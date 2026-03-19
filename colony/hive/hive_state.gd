# FILE: res://colony/hive/hive_state.gd
# Persistent state for a single hive instance.
class_name HiveState
extends RefCounted

var hive_id: int = 0
var colony_id: int = 0
var anchor_cell: Vector2i = Vector2i.ZERO
var anchor_type: StringName = &""
var slots: Array[HiveSlot] = []
var slot_count: int = 0
var max_integrity: float = 100.0
var integrity: float = 100.0
var is_destroyed: bool = false
var breach_timer: float = 0.0
var territory_radius: int = 3
var fade_timer: float = 0.0
var applied_upgrades: Array[StringName] = []
var specialisation: StringName = &""
var is_capital: bool = false

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> HiveState:
	return null
