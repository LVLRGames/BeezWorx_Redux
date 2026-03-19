# FILE: res://jobs/marker_data.gd
# State for a physical pheromone marker placed in the world.
class_name MarkerData
extends RefCounted

enum MarkerCategory {
	JOB,
	NAV,
	INFO
}

var marker_id: int = 0
var marker_type_id: StringName = &""
var marker_category: int = MarkerCategory.JOB
var def: MarkerDef = null
var cell: Vector2i = Vector2i.ZERO
var placer_id: int = 0
var colony_id: int = 0
var placed_at: float = 0.0
var decay_timer: float = 0.0
var job_ids: Array[int] = []
var job_progress: float = 0.0
var trail_id: int = 0
var trail_next_id: int = 0
var trail_prev_id: int = 0

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> MarkerData:
	return null
