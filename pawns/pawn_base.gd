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
@export var species_def:      SpeciesDef
@export var role_def:         RoleDef
## Prioritized list — first can_use() winner fires on action button press.
## Order in Inspector = priority order. Drag .tres files to reorder.
@export var action_abilities: Array[AbilityDef] = []
## Prioritized list — first can_use() winner fires on alt button press.
@export var alt_abilities: Array[AbilityDef] = []

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
var state: PawnState = null   # PawnState — typed loosely until Phase 3

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
	if not selector:
		selector = get_tree().get_first_node_in_group("selector") as HexSelector
		
	if pawn_id >= 0:
		# Loading from save — wire existing state
		state = PawnRegistry.get_state(pawn_id)
		if state == null:
			push_error("PawnBase: pawn_id %d set but no state in PawnRegistry" % pawn_id)
			return
		PawnRegistry.set_pawn(pawn_id, self)
		# Don't emit pawn_registered — possession is handled by WorldRoot
	else:
		# Fresh spawn — register normally
		pawn_id = PawnRegistry.register(self)
	# If not possessed, assign AI controller
	if pawn_id >= 0 and not is_possessed:
		if _pawn_ai != null:
			controller = controller
		# else: null controller — pawn just stands there
	print("PawnBase ready: pawn_id=", pawn_id, " controller=", controller, " is_possessed=", is_possessed)


func _physics_process(delta: float) -> void:
	if state:
		state.last_known_cell = HexConsts.WORLD_TO_AXIAL(
			global_position.x, global_position.z
		)
		state.last_world_pos = global_position
	
	# PlayerController drives the pawn directly via physics_tick().
	if controller != null:
		controller.call("physics_tick", delta)
		return

	# PawnAI drives via navigate_to(); we execute the movement here.
	if _navigating:
		_tick_navigation(delta)
	
	if pawn_id >= 0:
		var cell := HexConsts.WORLD_TO_AXIAL(global_position.x, global_position.z)
		if not state or cell != state.last_known_cell:
			PawnRegistry.update_cell(pawn_id, cell)
	
	

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
	#print("pawn_base.interact called, executor=", _executor)
	if _executor != null:
		_executor.call("try_action")
	

## Called by PlayerController on alt-action button press.
func alt_interact() -> void:
	#print("pawn_base.alt_interact called, executor=", _executor)
	if _executor != null:
		_executor.call("try_alt_action")

## Override hook for INTERACT_GENERIC ability type.
## Called by PawnAbilityExecutor when effect_type == INTERACT_GENERIC.
func _on_interact_generic(_target: Variant) -> void:
	pass

## Abstract — must be implemented by concrete bee/ant/etc. scenes.
@abstract func get_pawn_info() -> String


func refresh_name_tag() -> void:
	if not name_tag or not state:
		return
	if state.possessor_id >= 0:
		name_tag.info = "[P%d] %s" % [state.possessor_id, _get_display_name()]
	else:
		name_tag.info = _get_display_name()


func die() -> void:
	if state:
		state.is_alive = false
	PawnRegistry.deregister(pawn_id)
	EventBus.pawn_died.emit(pawn_id, state.colony_id if state else -1, &"unknown")
	queue_free()


# ════════════════════════════════════════════════════════════════════════════ #
#  Possession hooks
# ════════════════════════════════════════════════════════════════════════════ #

func on_possessed(by_player_slot: int) -> void:
	is_possessed = true
	if state:
		state.possessor_id        = by_player_slot
		state.player_boost_active = true
	if _pawn_ai:
		_pawn_ai.set("ai_active", false)
	if name_tag:
		name_tag.info = "[P%d] %s" % [by_player_slot, \
			_get_display_name() if state else name]
		name_tag.hide()


func on_unpossessed() -> void:
	is_possessed = false
	if state:
		state.possessor_id        = -1
		state.player_boost_active = false
	if _pawn_ai:
		_pawn_ai.set("ai_active", true)
	if name_tag:
		name_tag.info = _get_display_name() if state else name
		name_tag.show()


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


func _get_display_name() -> String:
	var base: String = state.pawn_name if state else name
	if state and PawnRegistry.is_queen(pawn_id, state.colony_id):
		return "👑 " + base
	return base
