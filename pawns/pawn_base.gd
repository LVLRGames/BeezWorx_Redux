# FILE: res://pawns/pawn_base.gd
# Base scene for all physical entities. Extends CharacterBody3D for physics.
class_name PawnBase
extends CharacterBody3D

@onready var state: PawnState = null
@onready var ai: PawnAI = null
@onready var executor: PawnAbilityExecutor = null
@onready var interaction_detector: Area3D = null
@onready var dialogue_detector: Area3D = null

@export var species_def: SpeciesDef = null
@export var role_def: RoleDef = null
@export var action_ability: AbilityDef = null
@export var alt_ability: AbilityDef = null
@export var interact_ability: AbilityDef = null

func get_pawn_id() -> int:
	return 0

func _physics_process(_delta: float) -> void:
	pass

func _on_interaction_targets_changed(_targets: Array[Node3D]) -> void:
	pass

func _on_body_entered_dialogue(_body: Node3D) -> void:
	pass

func navigate_to(_world_pos: Vector3) -> void:
	# TODO: Set target for AI nav
	pass

func _get_effective_move_speed() -> float:
	return 0.0

func _get_effective_action_speed() -> float:
	return 0.0
