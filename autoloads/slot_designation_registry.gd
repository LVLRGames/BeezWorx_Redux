# slot_designation_registry.gd
# res://autoloads/slot_designation_registry.gd
#
# Autoload. Loads all SlotDesignationDef .tres files at startup.
# Access via SlotDesignationRegistry.get_def(designation_id)
#
# AUTHORING:
#   Create these .tres files in res://defs/hive/designations/:
#     0_locked.tres    — designation_id=0, is_locked=true
#     1_general.tres   — designation_id=1
#     2_bed.tres       — designation_id=2
#     3_storage.tres   — designation_id=3
#     4_crafting.tres  — designation_id=4
#     5_nursery.tres   — designation_id=5

extends Node

# Preloaded defs — update paths when you create the .tres files
const _DEF_PATHS: Array[String] = [
	"res://defs/hive/designations/0_locked.tres",
	"res://defs/hive/designations/1_general.tres",
	"res://defs/hive/designations/2_bed.tres",
	"res://defs/hive/designations/3_storage.tres",
	"res://defs/hive/designations/4_crafting.tres",
	"res://defs/hive/designations/5_nursery.tres",
]

var _defs: Dictionary[int, SlotDesignationDef] = {}
var _fallback: SlotDesignationDef = null

func _ready() -> void:
	_fallback = _make_fallback()
	for path: String in _DEF_PATHS:
		if not ResourceLoader.exists(path):
			push_warning("SlotDesignationRegistry: missing def at '%s'" % path)
			continue
		var def: SlotDesignationDef = load(path) as SlotDesignationDef
		if def == null:
			push_warning("SlotDesignationRegistry: failed to load '%s'" % path)
			continue
		_defs[def.designation_id] = def

func get_def(designation_id: int) -> SlotDesignationDef:
	return _defs.get(designation_id, _fallback)

func get_all() -> Array[SlotDesignationDef]:
	var out: Array[SlotDesignationDef] = []
	for id: int in _defs:
		out.append(_defs[id])
	out.sort_custom(func(a, b): return a.designation_id < b.designation_id)
	return out

func _make_fallback() -> SlotDesignationDef:
	var d := SlotDesignationDef.new()
	d.designation_id = 1
	d.display_name   = "General"
	d.label_initial  = "G"
	d.icon_col       = 1
	d.color          = Color(0.6, 0.6, 0.6)
	d.can_deposit    = true
	d.can_withdraw   = true
	d.can_sleep      = true
	return d
