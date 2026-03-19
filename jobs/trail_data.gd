# FILE: res://jobs/trail_data.gd
# Definition of a sequence of markers forming a logical path (e.g. ant trail).
class_name TrailData
extends RefCounted

var trail_id: int = 0
var colony_id: int = 0
var species_tags: Array[StringName] = []
var item_filter: Array[StringName] = []
var node_ids: Array[int] = []
var is_loop: bool = false

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> TrailData:
	return null
