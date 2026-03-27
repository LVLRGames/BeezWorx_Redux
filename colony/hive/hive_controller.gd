# hive_controller.gd
# res://colony/hive/hive_controller.gd
#
# Attach to the root node of hive.tscn.
# Handles bee entry detection, squash-stretch tween, and UI open/close.
#
# SCENE REQUIREMENTS on hive.tscn:
#   Root (Node3D, this script)
#   ├── MeshInstance3D (or whatever the hive mesh root is) — named "HiveMesh"
#   ├── Area3D — named "EntryArea"
#   │   └── CollisionShape3D — trigger zone around hive
#   └── (other children from old project)
#
# ENTRY FLOW:
#   1. Bee flies into EntryArea
#   2. Hive plays squash-stretch (swallow)
#   3. Bee teleports to hive center, goes invisible
#   4. HiveUI opens
#
# EXIT FLOW:
#   1. Player closes HiveUI (escape or button)
#   2. Hive plays reverse bounce (spit out)
#   3. Bee reappears at exit_point, goes visible

class_name HiveController
extends Node3D

# ── Exports ───────────────────────────────────────────────────────────────────
@export var hive_mesh_path:  NodePath = ^"HiveMesh"
@export var entry_area_path: NodePath = ^"EntryArea"

## Height offset above the anchor cell world position
## Adjust so the hive sits convincingly on the trunk
@export var hang_height:  float = 3.5
@export var hang_offset:  Vector3 = Vector3(0.6, 0.0, 0.0)  # lateral offset from trunk centre
## Where the bee reappears on exit — local position relative to hive root
@export var exit_offset: Vector3 = Vector3(0.0, 2.0, 2.0)

## Squash/stretch tween settings
@export var squash_duration: float = 0.18
@export var stretch_scale:   Vector3 = Vector3(1.3, 0.7, 1.3)   # swallow squash
@export var spit_scale:      Vector3 = Vector3(0.7, 1.4, 0.7)   # spit stretch

# ── Data ──────────────────────────────────────────────────────────────────────
var hive_id: int = -1

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var _hive_name_label: Label3D = $HiveName
@onready var _mesh:  Node3D = get_node_or_null(hive_mesh_path)
@onready var _area:  Area3D = get_node_or_null(entry_area_path)

# ── Runtime ───────────────────────────────────────────────────────────────────
var _inside_pawn: PawnBase = null
var _tween: Tween = null
var _base_position: Vector3 = Vector3.ZERO

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	if _area == null:
		push_error("HiveController: EntryArea not found at '%s'" % entry_area_path)
		return
	_area.body_entered.connect(_on_body_entered)

func _unhandled_input(event: InputEvent) -> void:
	if _inside_pawn == null:
		return
	if event.is_action_pressed("p1_cancel") or event.is_action_pressed("ui_cancel"):
		_exit_hive()



# ════════════════════════════════════════════════════════════════════════════ #
#  Setup
# ════════════════════════════════════════════════════════════════════════════ #

## Called by HiveSystem after instantiation.
## anchor_world_pos is the AXIAL_TO_WORLD result for the anchor cell,
## with Y from terrain height.
func setup(p_hive_id: int, anchor_world_pos: Vector3) -> void:
	hive_id = p_hive_id
	_base_position = Vector3(
		anchor_world_pos.x + hang_offset.x,
		anchor_world_pos.y + hang_height,
		anchor_world_pos.z + hang_offset.z
	)
	global_position = _base_position
	_refresh_name_label()

# Add this method
func _refresh_name_label() -> void:
	if _hive_name_label == null:
		return
	var hs: HiveState = HiveSystem.get_hive(hive_id)
	if hs == null:
		return
	_hive_name_label.text = hs.hive_name if not hs.hive_name.is_empty() \
		else "Hive %d" % hive_id


func _fade_name_label(fade_in: bool) -> void:
	if _hive_name_label == null:
		return
	var target_alpha: float = 1.0 if fade_in else 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_hive_name_label, "modulate:a", target_alpha, 0.3)
	tween.tween_property(_hive_name_label, "outline_modulate:a", target_alpha, 0.3)



## Update integrity visual — darken/crack as hive takes damage.
## Called by HiveSystem when integrity changes.
func set_integrity(integrity: float, max_integrity: float) -> void:
	var t: float = integrity / maxf(max_integrity, 1.0)
	# TODO Phase 5: drive a shader param or swap mesh variant based on t
	# For now just scale slightly to give visual feedback
	var s: float = lerpf(0.85, 1.0, t)
	scale = Vector3(s, s, s)

## Show destroyed state — fade out or replace with rubble mesh.
func show_destroyed() -> void:
	# TODO Phase 5: play destruction particles, swap to rubble mesh
	queue_free()

# ════════════════════════════════════════════════════════════════════════════ #
#  Entry
# ════════════════════════════════════════════════════════════════════════════ #

func _on_body_entered(body: Node3D) -> void:
	if _inside_pawn != null:
		return   # already occupied
	var pawn := body as PawnBase
	if pawn == null:
		return
	# Only possessed pawns can enter
	if not pawn.is_possessed:
		return

	_enter_hive(pawn)

func _enter_hive(pawn: PawnBase) -> void:
	_inside_pawn = pawn
	pawn.set_physics_process(false)
	pawn.set_process(false)
	_fade_name_label(false)   # fade out on entry
	_play_squash(_on_swallow_complete)
	var rig: CameraRig = CameraRig.for_player(1)
	if rig:
		rig.set_hive_mode(true)



func _on_swallow_complete() -> void:
	if _inside_pawn == null:
		return
	_inside_pawn.global_position = global_position
	_inside_pawn.visible = false
	var ui: HiveOverlay = _get_hive_ui()
	if ui:
		var slot: int = _inside_pawn.state.possessor_id if _inside_pawn.state else 1
		ui.open_hive(hive_id, self, slot)

# ════════════════════════════════════════════════════════════════════════════ #
#  Exit
# ════════════════════════════════════════════════════════════════════════════ #

func _exit_hive() -> void:
	if _inside_pawn == null:
		return
	var ui: HiveOverlay = _get_hive_ui()
	if ui:
		ui.close_hive()
	_fade_name_label(true)    # fade in on exit
	_play_spit(_on_spit_complete)
	var rig: CameraRig = CameraRig.for_player(1)
	if rig:
		rig.set_hive_mode(false)


func _on_spit_complete() -> void:
	if _inside_pawn == null:
		return

	# Reappear bee at exit point
	_inside_pawn.global_position = global_position + exit_offset
	_inside_pawn.visible = true
	_inside_pawn.set_physics_process(true)
	_inside_pawn.set_process(true)

	if _mesh:
		_mesh.scale = Vector3.ONE

	_inside_pawn = null

# ════════════════════════════════════════════════════════════════════════════ #
#  Tweens
# ════════════════════════════════════════════════════════════════════════════ #

func _play_squash(on_complete: Callable) -> void:
	if _tween:
		_tween.kill()
	if _mesh == null:
		on_complete.call()
		return

	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_mesh, "scale", stretch_scale, squash_duration * 0.5)
	_tween.tween_property(_mesh, "scale", squash_scale(), squash_duration * 0.5)
	_tween.tween_callback(on_complete)

func _play_spit(on_complete: Callable) -> void:
	if _tween:
		_tween.kill()
	if _mesh == null:
		on_complete.call()
		return

	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_mesh, "scale", spit_scale, squash_duration * 0.5)
	_tween.tween_property(_mesh, "scale", Vector3.ONE, squash_duration * 0.5)
	_tween.tween_callback(on_complete)

func squash_scale() -> Vector3:
	# Inverse of stretch — if stretch squashes Y, squash squashes X/Z
	return Vector3(
		1.0 / stretch_scale.x,
		1.0 / stretch_scale.y,
		1.0 / stretch_scale.z
	)

# ════════════════════════════════════════════════════════════════════════════ #
#  Helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _get_hive_ui() -> HiveOverlay:
	# Find HiveOverlay in the scene tree — it lives on UIRoot
	return get_tree().get_first_node_in_group("hive_overlay") as HiveOverlay

## Called by HiveOverlay exit button
func request_exit() -> void:
	_exit_hive()

func get_inside_pawn() -> PawnBase:
	return _inside_pawn
