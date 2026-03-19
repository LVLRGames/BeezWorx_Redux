# FILE: res://colony/hive/egg_state.gd
# Tracks the lifecycle of a maturing larva/egg within a nursery slot.
class_name EggState
extends RefCounted


var laid_at: float = 0.0
var laid_by: int = 0
var maturation_day: int = 0
var feed_log: Array[FeedEntry] = []
var is_starved: bool = false
var emerging_role: StringName = &""

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> EggState:
	return null
