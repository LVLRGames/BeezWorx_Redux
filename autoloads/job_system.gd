# FILE: res://autoloads/job_system.gd
# Central dispatcher for pheromone markers, worker tasks, and ant trails.
# class_name JobSystem
extends Node

const MARKER_DECAY_DURATION: float = 30.0

var _markers: Dictionary[int, MarkerData] = {}
var _jobs: Dictionary[int, JobData] = {}
var _markers_by_cell: Dictionary[Vector2i, Array] = {}
var _jobs_by_colony: Dictionary[int, Array] = {}
var _jobs_by_type: Dictionary[StringName, Array] = {}
var _claimed_by_pawn: Dictionary[int, int] = {}
var _trails: Dictionary[int, TrailData] = {}
var _next_marker_id: int = 0
var _next_job_id: int = 0
var _next_trail_id: int = 0

func place_marker(cell: Vector2i, marker_type_id: StringName, colony_id: int, placer_id: int, trail_id: int) -> int:
	# TODO: Create and register marker
	return 0

func remove_marker(marker_id: int, reason: StringName) -> void:
	pass

func post_job(job_type_id: StringName, target_cell: Vector2i, colony_id: int, priority: int, required_role_tags: Array[StringName], source_marker_id: int, max_claimants: int, expires_after: float) -> int:
	# TODO: Create and post new job
	return 0

func get_claimable_jobs(pawn_id: int, colony_id: int, role_tags: Array[StringName], near_cell: Vector2i, search_radius: int) -> Array[JobData]:
	return []

func claim_job(job_id: int, pawn_id: int) -> bool:
	return false

func release_job(job_id: int, pawn_id: int) -> void:
	pass

func complete_job(job_id: int, pawn_id: int) -> void:
	pass

func fail_job(job_id: int, pawn_id: int) -> void:
	pass

func update_job_progress(job_id: int, progress_delta: float) -> void:
	pass

func create_trail(colony_id: int, species_tags: Array[StringName], item_filter: Array[StringName], is_loop: bool) -> int:
	return 0

func append_trail_node(trail_id: int, marker_id: int) -> void:
	pass

func close_trail(trail_id: int) -> void:
	pass

func dissolve_trail(trail_id: int) -> void:
	pass

func get_markers_for_colony(colony_id: int) -> Array[MarkerData]:
	return []

func get_jobs_for_marker(marker_id: int) -> Array[JobData]:
	return []

func get_job_claimed_by(pawn_id: int) -> JobData:
	return null

func get_markers_at_cell(cell: Vector2i) -> Array[MarkerData]:
	return []

func save_state() -> Dictionary:
	return {}

func load_state(data: Dictionary) -> void:
	pass
