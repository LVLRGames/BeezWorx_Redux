# FILE: res://pawns/pawn_ai.gd
# Utility AI controller that evaluates markers and jobs to decide behavior.
class_name PawnAI
extends Node

const AI_TICK_INTERVAL: float = 0.25
const ALERT_PROPAGATION_RADIUS: float = 8.0

var pawn: PawnBase = null
var ai_active: bool = true
var current_job: JobData = null
var current_subtask_index: int = 0
var _tick_timer: float = 0.0
var _nearest_threat_id: int = -1
var _current_nav_target: Vector3 = Vector3.ZERO
var _cached_path: PackedVector3Array = PackedVector3Array()

func _process(_delta: float) -> void:
	pass

func _evaluate() -> void:
	# TODO: Utility scoring of nearby markers/jobs
	pass

func _score_behavior(_behavior: Resource, _state: PawnState) -> float:
	return 0.0

func _evaluate_condition(_state: PawnState, _condition_id: StringName) -> bool:
	return false

func _try_claim_job(_behavior: Resource, _state: PawnState) -> bool:
	return false

func _tick_current_job(_delta: float) -> void:
	pass

func _execute_subtask(_subtask: Dictionary, _delta: float) -> bool:
	return false

func _build_subtask_sequence(_job: JobData) -> Array[Dictionary]:
	return []

func _check_threats() -> void:
	pass

func _decide_threat_response() -> StringName:
	return &""

func _compute_flee_threshold() -> float:
	return 0.0

func _alert_colony() -> void:
	pass

func receive_alert(_from_cell: Vector2i, _threat_id: int) -> void:
	pass

func _get_tick_interval() -> float:
	return 0.0

func _chunks_from_player() -> int:
	return 0
