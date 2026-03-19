# FILE: res://pawns/pawn_state.gd
# Persistent state for a single living entity (bee, ant, beetle, etc.).
class_name PawnState
extends RefCounted

class EffectInstance:
	var effect_id: StringName = &""
	var duration: float = 0.0
	var magnitude: float = 0.0
	var source_id: int = 0

var pawn_id: int = 0
var pawn_name: String = ""
var species_id: StringName = &""
var role_id: StringName = &""
var colony_id: int = 0
var movement_type: int = 0
var health: float = 100.0
var max_health: float = 100.0
var fatigue: float = 0.0
var age_days: int = 0
var max_age_days: int = 0
var is_alive: bool = true
var is_awake: bool = true
var loyalty: float = 0.5
var inventory: PawnInventory = null
var personality: PawnPersonality = null
var possessor_id: int = -1
var player_boost_active: bool = false
var ai_resume_state: Dictionary = {}
var last_known_cell: Vector2i = Vector2i.ZERO
var active_buffs: Dictionary[StringName, float] = {}
var active_effects: Dictionary[StringName, EffectInstance] = {}

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> PawnState:
	return null
