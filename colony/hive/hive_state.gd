# hive_state.gd
# res://colony/hive/hive_state.gd
# Persistent state for a single hive instance.

class_name HiveState
extends RefCounted

var hive_name:       String          = ""
var hive_id:         int             = 0
var colony_id:       int             = 0
var anchor_cell:     Vector2i        = Vector2i.ZERO
var anchor_type:     StringName      = &""
var slots:           Array[HiveSlot] = []
var slot_count:      int             = 0
var max_integrity:   float           = 100.0
var integrity:       float           = 100.0
var is_destroyed:    bool            = false
var breach_timer:    float           = 0.0
var territory_radius: int            = 6
var fade_timer:      float           = 0.0
var applied_upgrades: Array[StringName] = []
var specialisation:  StringName      = &""
var is_capital:      bool            = false

func to_dict() -> Dictionary:
	var slots_data: Array = []
	for slot: HiveSlot in slots:
		slots_data.append(slot.to_dict())
	return {
		"hive_name":        hive_name,
		"hive_id":          hive_id,
		"colony_id":        colony_id,
		"anchor_cell_x":    anchor_cell.x,
		"anchor_cell_y":    anchor_cell.y,
		"anchor_type":      str(anchor_type),
		"slot_count":       slot_count,
		"max_integrity":    max_integrity,
		"integrity":        integrity,
		"is_destroyed":     is_destroyed,
		"territory_radius": territory_radius,
		"applied_upgrades": applied_upgrades.map(func(s): return str(s)),
		"specialisation":   str(specialisation),
		"is_capital":       is_capital,
		"slots":            slots_data,
		"schema_version":   1,
	}

static func from_dict(d: Dictionary) -> HiveState:
	var hs := HiveState.new()
	hs.hive_name        = d.get("hive_name",        "")
	hs.hive_id          = d.get("hive_id",          0)
	hs.colony_id        = d.get("colony_id",        0)
	hs.anchor_cell      = Vector2i(
		d.get("anchor_cell_x", 0),
		d.get("anchor_cell_y", 0)
	)
	hs.anchor_type      = StringName(d.get("anchor_type", ""))
	hs.slot_count       = d.get("slot_count",       0)
	hs.max_integrity    = d.get("max_integrity",    100.0)
	hs.integrity        = d.get("integrity",        100.0)
	hs.is_destroyed     = d.get("is_destroyed",     false)
	hs.territory_radius = d.get("territory_radius", 6)
	hs.specialisation   = StringName(d.get("specialisation", ""))
	hs.is_capital       = d.get("is_capital",       false)

	var upgrades: Array = d.get("applied_upgrades", [])
	for u in upgrades:
		hs.applied_upgrades.append(StringName(u))

	var slots_data: Array = d.get("slots", [])
	hs.slots.clear()
	for sd: Dictionary in slots_data:
		hs.slots.append(HiveSlot.from_dict(sd))
	# Pad to slot_count if save had fewer slots
	while hs.slots.size() < hs.slot_count:
		var pad := HiveSlot.new()
		pad.slot_index = hs.slots.size()
		pad.hive_id    = hs.hive_id
		hs.slots.append(pad)

	return hs
