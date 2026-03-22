# pawn_ai.gd
# res://pawns/pawn_ai.gd
#
# Autonomous AI for unpossessed pawns. Structured for Phase 3 utility AI
# upgrade. Phase 1 behavior: simple wander (replaces AIController).
#
# ARCHITECTURE:
#   PawnAI drives the pawn by calling pawn.navigate_to(world_pos).
#   PawnBase._tick_navigation() then calls move_in_plane/face_direction
#   each physics frame until arrival. PawnAI never calls move_in_plane
#   directly — it only sets intent via navigate_to().
#
# PHASE 1 SCOPE:
#   _evaluate() picks a random wander target within wander_radius.
#   No job system integration. No threat response.
#
# PHASE 3 UPGRADE POINTS (marked with TODO):
#   - Replace _evaluate() wander with utility scoring + JobSystem query
#   - Implement _build_subtask_sequence() for real job execution
#   - Implement _check_threats() and _decide_threat_response()
#   - Implement alert propagation via receive_alert()
#   - Implement AI resume from state.ai_resume_state on possession release
#   - Implement _chunks_from_player() for load distance gating

class_name PawnAI
extends Node

# ── Spec constants ────────────────────────────────────────────────────────────
const AI_TICK_INTERVAL:        float = 0.25
const ALERT_PROPAGATION_RADIUS: int  = 8

# ── Runtime state ─────────────────────────────────────────────────────────────
var pawn: PawnBase  = null
var ai_active: bool = true

var current_job: Resource      = null   # JobData — Phase 3
var current_subtask_index: int = 0

var _tick_timer: float    = 0.0
var _nearest_threat_id:   int     = -1
var _current_nav_target:  Vector3 = Vector3.ZERO

# ── Phase 1 wander state ──────────────────────────────────────────────────────
@export var wander_radius: float = 10.0
var _wander_timer: float = 0.0
var _wander_dir:   Vector3 = Vector3.ZERO

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	pawn = get_parent() as PawnBase
	if pawn == null:
		push_error("PawnAI: parent is not a PawnBase")
		return
	# Stagger tick timers across pawns to spread load
	_tick_timer = randf() * AI_TICK_INTERVAL

func _process(delta: float) -> void:
	if not ai_active or pawn == null:
		return

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = AI_TICK_INTERVAL + randf() * 0.05  # jitter prevents sync spikes
		_evaluate()

# ════════════════════════════════════════════════════════════════════════════ #
#  Core evaluation loop
# ════════════════════════════════════════════════════════════════════════════ #

func _evaluate() -> void:
	# Phase 1: simple wander
	_wander_timer -= AI_TICK_INTERVAL
	if _wander_timer <= 0.0 or not pawn._navigating:
		_wander_timer = randf_range(1.0, 3.0)
		_pick_wander_target()

	# TODO Phase 3: replace above with utility scoring
	# var best_behavior = _score_all_behaviors()
	# if best_behavior != null:
	#     _try_claim_job(best_behavior, pawn.state)

func _pick_wander_target() -> void:
	var angle: float  = randf() * TAU
	var dist:  float  = randf_range(wander_radius * 0.3, wander_radius)
	var offset: Vector3 = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

	# Flying pawns add slight vertical variation
	if pawn is PawnFlyer:
		offset.y = randf_range(-2.0, 3.0)

	_current_nav_target = pawn.global_position + offset
	pawn.navigate_to(_current_nav_target)

# ════════════════════════════════════════════════════════════════════════════ #
#  Phase 3 stubs — structured interfaces ready for implementation
# ════════════════════════════════════════════════════════════════════════════ #

## Score a utility behavior against current pawn state.
## Returns 0.0 if conditions not met, positive float if viable.
func _score_behavior(_behavior: Resource, _state: Resource) -> float:
	# TODO Phase 3: evaluate UtilityBehaviorDef conditions and curve
	return 0.0

## Evaluate a condition tag against pawn state.
## Examples: "inventory_not_full", "has_item:nectar", "target_in_range"
func _evaluate_condition(_state: Resource, _condition_id: StringName) -> bool:
	# TODO Phase 3: implement condition evaluation
	return false

## Try to claim a job from JobSystem for the given behavior.
func _try_claim_job(_behavior: Resource, _state: Resource) -> bool:
	# TODO Phase 3: query JobSystem.get_claimable_jobs() and claim best match
	return false

## Advance the current job by one subtask.
func _tick_current_job(_delta: float) -> void:
	# TODO Phase 3: execute current_job subtasks, call executor.try_action() as needed
	pass

## Execute one subtask step. Returns true if subtask is complete.
func _execute_subtask(_subtask: Dictionary, _delta: float) -> bool:
	# TODO Phase 3: subtask types: NAVIGATE, EXECUTE_ABILITY, WAIT
	return false

## Build an ordered list of subtasks for a given job.
func _build_subtask_sequence(_job: Resource) -> Array:
	# TODO Phase 3: translate JobData into subtask steps
	return []

## Check for nearby threats and update _nearest_threat_id.
func _check_threats() -> void:
	# TODO Phase 3: query PawnRegistry for hostile pawns within alert_radius
	pass

## Decide how to respond to the current threat.
func _decide_threat_response() -> StringName:
	# TODO Phase 3: based on boldness trait — flee vs fight
	return &"flee"

## Compute the flee threshold from personality.
func _compute_flee_threshold() -> float:
	# TODO Phase 3: read pawn.state.personality.boldness
	return 0.3

## Alert nearby colony members of a threat.
func _alert_colony() -> void:
	# TODO Phase 3: signal nearby PawnAI nodes within ALERT_PROPAGATION_RADIUS
	pass

## Called by nearby PawnAI when a threat is detected.
func receive_alert(_from_cell: Vector2i, _threat_id: int) -> void:
	# TODO Phase 3: update _nearest_threat_id and interrupt current job
	pass

## How many chunks away from the player is this pawn?
## Used to gate AI tick frequency — distant pawns tick less often.
func _chunks_from_player() -> int:
	# TODO Phase 3: query HexTerrainManager for loaded chunk distance
	return 0

## Returns appropriate tick interval based on distance from player.
func _get_tick_interval() -> float:
	# TODO Phase 3: scale interval by _chunks_from_player()
	return AI_TICK_INTERVAL

## Snapshot current AI state for possession resume.
## Called by PawnBase.on_possessed() before suspending AI.
func snapshot_resume_state() -> Dictionary:
	return {
		"job_id":          current_job.get("job_id") if current_job else -1,
		"subtask_index":   current_subtask_index,
		"nav_target":      _current_nav_target,
		"wander_timer":    _wander_timer,
	}

## Restore AI state from snapshot after possession release.
func restore_from_snapshot(data: Dictionary) -> void:
	_current_nav_target = data.get("nav_target",    Vector3.ZERO)
	_wander_timer       = data.get("wander_timer",  0.0)
	current_subtask_index = data.get("subtask_index", 0)
	# TODO Phase 3: re-claim job_id from JobSystem if still available
