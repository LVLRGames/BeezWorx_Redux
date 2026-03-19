# FILE: res://pawns/pawn_personality.gd
# Stores unique behavioral traits for a specific pawn.
class_name PawnPersonality
extends RefCounted

var seed: int = 0
var curiosity: float = 0.5
var boldness: float = 0.5
var diligence: float = 0.5
var chattiness: float = 0.5
var stubbornness: float = 0.5
var dialogue_tags: Array[StringName] = []

func generate(p_seed: int) -> void:
	pass

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> PawnPersonality:
	return null
