# FILE: res://jobs/job_data.gd
# Data container for a single task posted to the job system.
class_name JobData
extends RefCounted

class JobMaterialReq:
	var item_id: StringName = &""
	var count: int = 0
	var per_colony: bool = false

enum JobStatus {
	POSTED,
	CLAIMED,
	EXECUTING,
	COMPLETED,
	FAILED,
	EXPIRED,
	CANCELLED
}

var job_id: int = 0
var job_type_id: StringName = &""
var source_marker_id: int = 0
var colony_id: int = 0
var target_cell: Vector2i = Vector2i.ZERO
var target_pawn_id: int = 0
var target_hive_id: int = 0
var required_role_tags: Array[StringName] = []
var required_items: Array[JobMaterialReq] = []
var priority: int = 0
var max_claimants: int = 1
var expires_at: float = 0.0
var status: int = JobStatus.POSTED
var claimant_ids: Array[int] = []
var posted_at: float = 0.0
var claimed_at: float = 0.0
var completed_at: float = 0.0
var fail_count: int = 0
var max_fails: int = 3
var progress: float = 0.0
var task_plan: Dictionary = {}

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> JobData:
	return null
