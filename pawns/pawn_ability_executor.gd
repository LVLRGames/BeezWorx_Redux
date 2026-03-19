# FILE: res://pawns/pawn_ability_executor.gd
# Handles the execution and cooldown management of pawn abilities.
class_name PawnAbilityExecutor
extends Node

var pawn: PawnBase = null
var cooldowns: Dictionary[StringName, float] = {}

func try_action() -> bool:
	return false

func try_alt_action() -> bool:
	return false

func try_interact() -> bool:
	return false

func can_use(_ability: AbilityDef) -> bool:
	return false

func resolve_target(_ability: AbilityDef) -> Variant:
	return null

func execute(_ability: AbilityDef, _target: Variant) -> void:
	# TODO: Trigger effect logic
	pass

func _tick_cooldowns(_delta: float) -> void:
	pass

func _on_interact_generic(_target: Variant) -> void:
	pass
