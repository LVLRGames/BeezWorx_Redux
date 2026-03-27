# hive_slot.gd
# res://colony/hive/hive_slot.gd
# One slot in a hive's interior grid.

class_name HiveSlot
extends RefCounted

enum SlotDesignation {
	LOCKED   = 0,
	GENERAL  = 1,
	BED      = 2,
	STORAGE  = 3,
	CRAFTING = 4,
	NURSERY  = 5,
}

# Atlas subtype rows per designation
enum SlotSubtype {
	DEFAULT  = 0,
	VARIANT1 = 1,
	VARIANT2 = 2,
	ROYAL    = 3,
}

var slot_index:       int         = 0
var hive_id:          int         = -1
var designation:      int         = SlotDesignation.GENERAL
var subtype:          int         = SlotSubtype.DEFAULT
var stored_items:     Dictionary  = {}   # StringName → int
var capacity_units:   int         = 10
var locked_item_id:   StringName  = &""  # storage filter OR crafting recipe id
var sleeper_id:       int         = -1   # pawn_id of sleeping pawn
var assigned_pawn_id: int         = -1   # permanently assigned pawn (BED)
var craft_order:      Resource    = null  # CraftOrder — Phase 5
var egg_state:        Resource    = null  # EggState — Phase 9

func to_dict() -> Dictionary:
	var items: Dictionary = {}
	for k in stored_items:
		items[str(k)] = stored_items[k]
	return {
		"slot_index":       slot_index,
		"hive_id":          hive_id,
		"designation":      designation,
		"subtype":          subtype,
		"stored_items":     items,
		"capacity_units":   capacity_units,
		"locked_item_id":   str(locked_item_id),
		"sleeper_id":       sleeper_id,
		"assigned_pawn_id": assigned_pawn_id,
	}

static func from_dict(d: Dictionary) -> HiveSlot:
	var s := HiveSlot.new()
	s.slot_index       = d.get("slot_index",       0)
	s.hive_id          = d.get("hive_id",          -1)
	s.designation      = d.get("designation",      SlotDesignation.GENERAL)
	s.subtype          = d.get("subtype",           SlotSubtype.DEFAULT)
	s.capacity_units   = d.get("capacity_units",   10)
	s.locked_item_id   = StringName(d.get("locked_item_id", ""))
	s.sleeper_id       = d.get("sleeper_id",       -1)
	s.assigned_pawn_id = d.get("assigned_pawn_id", -1)
	var items: Dictionary = d.get("stored_items", {})
	for k in items:
		s.stored_items[StringName(k)] = items[k]
	return s
