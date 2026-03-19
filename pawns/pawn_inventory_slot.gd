# FILE: res://pawns/pawn_inventory_slot.gd
# Data structure for a single item stack within a pawn's inventory.
class_name PawnInventorySlot
extends RefCounted

var item_id: StringName = &""
var count: int = 0
