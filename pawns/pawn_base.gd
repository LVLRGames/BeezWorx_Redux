# pawn_base.gd
# res://pawns/pawn_base.gd
#
# Abstract base for all pawn scene nodes. Merges the old Pawn.gd with
# the Gemini scaffold's PawnBase integration fields.
#
# HIERARCHY:
#   PawnBase (this file)
#   ├── PawnFlyer   (res://pawns/pawn_flyer.gd) — 3D flight physics
#   └── PawnWalker  (res://pawns/pawn_walker.gd) — surface-aligned walking
#
# RESPONSIBILITY SPLIT:
#   PawnBase    — identity, state, ability execution, navigate_to loop,
#                 possession hooks, registry integration
#   PawnFlyer   — flight-specific move_in_plane / face_direction physics
#   PawnWalker  — ground-specific move_in_plane / face_direction physics
#   PawnAI      — autonomous behavior when not possessed (child Node)
#   PlayerController — player input routing (Resource, set on controller var)
#
# NAVIGATION:
#   navigate_to(world_pos) sets _nav_target and enables _navigating.
#   _physics_process calls move_in_plane / face_direction automatically.
#   PawnAI calls navigate_to(). PlayerController bypasses it entirely
#   and calls move_in_plane / face_direction directly each physics frame.

@abstract
class_name PawnBase
extends CharacterBody3D

# ── Spec exports ──────────────────────────────────────────────────────────────
@export var species_def:      Resource   # SpeciesDef — typed loosely until Phase 3
@export var role_def:         Resource   # RoleDef
@export var action_ability:   Resource   # AbilityDef
@export var alt_ability:      Resource   # AbilityDef
@export var interact_ability: Resource   # AbilityDef

# ── Movement tuning ───────────────────────────────────────────────────────────
@export var move_speed:  float = 16.0
@export var turn_speed:  float = 16.0

# ── Bending ───────────────────────────────────────────────────────────────────
@export var bend_radius:   float = 0.8
@export var bend_strength: float = 1.0

# ── Selector / interaction ────────────────────────────────────────────────────
@export var reach: float = 1.5

## HexSelector node used to determine which cell the pawn is targeting.
## Falls back to first node in "selector" group if not assigned.
@export var selector: HexSelector:
	get:
		if selector:
			return selector
		selector = get_tree().get_first_node_in_group("selector") as HexSelector
		return selector

# ── Name tag ──────────────────────────────────────────────────────────────────
@export var name_tag: NameTag

# ── Runtime identity ──────────────────────────────────────────────────────────
## Set by PawnRegistry.register() when this pawn is added to the world.
## -1 means unregistered (freshly spawned, not yet in registry).
var pawn_id: int = -1

## PawnState ref — set by PawnRegistry.register(). Readable by any system.
var state: Resource = null   # PawnState — typed loosely until Phase 3

# ── Controller (player input routing) ────────────────────────────────────────
## Swap this to a PlayerController to possess, AIController stub during
## Phase 1, or null to let PawnAI drive entirely (Phase 3+).
## Phase 1 note: AIController is replaced by PawnAI in Phase 3.
##   During Phase 1 PawnAI.wander drives the pawn when not possessed.
var controller: Resource = null:  # Controller
	set = _set_controller

var is_possessed: bool = false

# ── Child node refs (set in _ready via @onready or get_node) ─────────────────
var _pawn_ai: Node = null             # PawnAI child
var _executor: Node = null            # PawnAbilityExecutor child

# ── Navigation state ──────────────────────────────────────────────────────────
## World-space destination set by PawnAI.navigate_to(). Cleared on arrival.
var _nav_target: Vector3 = Vector3.ZERO
var _navigating: bool    = false

const NAV_ARRIVE_THRESHOLD: float = 0.4

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	_pawn_ai  = get_node_or_null("PawnAI")
	_executor = get_node_or_null("PawnAbilityExecutor")

	# Default to AI-driven when not possessed
	if controller == null and _pawn_ai == null:
		# Phase 1 fallback: simple wander via AIController if PawnAI not present
		var ai_script: Script = load("res://pawns/ai_controller.gd")
		if ai_script:
			controller = ai_script.new()
			(controller as Resource).set("pawn", self)

	if not selector:
		selector = get_tree().get_first_node_in_group("selector") as HexSelector

	if name_tag:
		name_tag.info = name

func _physics_process(delta: float) -> void:
	# PlayerController drives the pawn directly via physics_tick().
	if controller != null:
		controller.call("physics_tick", delta)
		return

	# PawnAI drives via navigate_to(); we execute the movement here.
	if _navigating:
		_tick_navigation(delta)

# ════════════════════════════════════════════════════════════════════════════ #
#  Navigation (called by PawnAI)
# ════════════════════════════════════════════════════════════════════════════ #

## Direct PawnBase to move toward world_pos. PawnAI calls this instead of
## calling move_in_plane directly — separation of intent from execution.
func navigate_to(world_pos: Vector3) -> void:
	_nav_target  = world_pos
	_navigating  = true

func stop_navigation() -> void:
	_navigating = false
	_nav_target = Vector3.ZERO

func _tick_navigation(delta: float) -> void:
	var to_target: Vector3 = _nav_target - global_position
	var dist: float = to_target.length()

	if dist < NAV_ARRIVE_THRESHOLD:
		_navigating = false
		_nav_target = Vector3.ZERO
		move_in_plane(Vector3.ZERO, delta)
		return

	var dir: Vector3 = to_target.normalized()
	move_in_plane(dir, delta)
	face_direction(dir, delta, _get_gfx_node())

## Returns the GFX child node if present (used for visual rotation separation).
func _get_gfx_node() -> Node3D:
	return get_node_or_null("GFX") as Node3D

# ════════════════════════════════════════════════════════════════════════════ #
#  Movement interface (overridden by PawnFlyer / PawnWalker)
# ════════════════════════════════════════════════════════════════════════════ #

## Move the pawn in the given world-space direction.
## dir is a normalised or zero vector. Subclasses implement physics.
func move_in_plane(dir: Vector3, _delta: float) -> void:
	var v := dir * move_speed
	velocity.x = v.x
	velocity.z = v.z
	move_and_slide()

## Rotate the pawn to face the given direction.
## gfx: optional separate visual node to rotate (keeps collision shape stable).
func face_direction(dir: Vector3, _delta: float, gfx: Node3D = null) -> void:
	if dir.length() < 0.001:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	var rot := Vector3(-dir.y, atan2(flat.x, flat.z), 0.0)
	if gfx:
		gfx.rotation = rot
	else:
		rotation = rot

# ════════════════════════════════════════════════════════════════════════════ #
#  Ability interface
# ════════════════════════════════════════════════════════════════════════════ #

## Called by PlayerController on action button press.
func interact() -> void:
	if _executor != null:
		_executor.call("try_action")
	elif selector:
		selector.bounce_cell()

## Called by PlayerController on alt-action button press.
func alt_interact() -> void:
	if _executor != null:
		_executor.call("try_alt_action")

## Override hook for INTERACT_GENERIC ability type.
## Called by PawnAbilityExecutor when effect_type == INTERACT_GENERIC.
func _on_interact_generic(_target: Variant) -> void:
	pass

## Abstract — must be implemented by concrete bee/ant/etc. scenes.
@abstract func get_pawn_info() -> String

# ════════════════════════════════════════════════════════════════════════════ #
#  Possession hooks
# ════════════════════════════════════════════════════════════════════════════ #

func on_possessed(by_player_slot: int) -> void:
	is_possessed = true
	if _pawn_ai:
		_pawn_ai.set("ai_active", false)
	if name_tag:
		name_tag.info = "[P%d] %s" % [by_player_slot, name]
	# TODO Phase 3: snapshot AI resume state, apply possession speed boost

func on_unpossessed() -> void:
	is_possessed = false
	if _pawn_ai:
		_pawn_ai.set("ai_active", true)
	if name_tag:
		name_tag.info = name
	# TODO Phase 3: restore AI from resume state

# ════════════════════════════════════════════════════════════════════════════ #
#  Controller setter
# ════════════════════════════════════════════════════════════════════════════ #

func _set_controller(c: Resource) -> void:
	if controller and controller.has_method("detach"):
		controller.call("detach")
	controller = c
	if controller and controller.has_method("attach"):
		controller.call("attach", self)

# ════════════════════════════════════════════════════════════════════════════ #
#  Utility
# ════════════════════════════════════════════════════════════════════════════ #

func distance_to_ground() -> float:
	var ss   := get_world_3d().direct_space_state
	var prqp := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 100.0,
		0xFFFFFFFF,
		[get_rid()]
	)
	var result: Dictionary = ss.intersect_ray(prqp)
	if result.has("position"):
		return global_position.distance_to(result["position"])
	return 0.0
