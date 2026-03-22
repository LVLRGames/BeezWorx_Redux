# hive_anchor_occupant.gd
# res://colony/hive/hive_anchor_occupant.gd
#
# CellOccupantData subclass written into HexCellState.occupant_data
# when a hive is registered at a cell. Owned by HiveSystem.
# The world layer never reads this — it only allocates the slot.

class_name HiveAnchorOccupant
extends CellOccupantData

var hive_id: int = -1
var colony_id: int = -1

func _init() -> void:
	category = HexConsts.CellCategory.HIVE_ANCHOR

func to_dict() -> Dictionary:
	var d: Dictionary = super.to_dict()
	d["hive_id"]   = hive_id
	d["colony_id"] = colony_id
	return d

func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	hive_id   = d.get("hive_id",   -1)
	colony_id = d.get("colony_id", -1)
