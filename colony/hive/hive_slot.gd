# FILE: res://colony/hive/hive_slot.gd
# Represents a single functional cell within a hive interior.
class_name HiveSlot
extends RefCounted

enum SlotDesignation {
	GENERAL,
	BED,
	STORAGE,
	CRAFTING,
	NURSERY
}

var slot_index: int = 0
var hive_id: int = 0
var designation: int = SlotDesignation.GENERAL
var locked_item_id: StringName = &""
var assigned_pawn_id: int = 0
var stored_items: Dictionary[StringName, int] = {}
var capacity_units: int = 100
var craft_order: CraftOrder = null
var egg_state: EggState = null
var sleeper_id: int = 0

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> HiveSlot:
	return null
