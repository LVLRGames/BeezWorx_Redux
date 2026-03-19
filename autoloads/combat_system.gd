# FILE: res://autoloads/combat_system.gd
# Global resolver for combat hits, damage calculations, and hazard effects.
# class_name CombatSystem
extends Node

func resolve_hit(attacker_id: int, target_id: int, ability: AbilityDef, is_player_controlled: bool) -> float:
	return 0.0

func apply_hive_damage(hive_id: int, amount: float, attacker_id: int) -> void:
	pass

func _apply_damage(_pawn_id: int, _damage: float, _source_id: int) -> void:
	pass

func _apply_hit_effects(_pawn_id: int, _ability: AbilityDef) -> void:
	pass

func _get_attack_multiplier(_state: PawnState) -> float:
	return 1.0

func _get_defence_multiplier(_state: PawnState) -> float:
	return 1.0

func _tick_effects(_delta: float) -> void:
	pass

func _tick_hazards(_delta: float) -> void:
	pass

func _tick_boundary_threats(_delta: float) -> void:
	pass

func _trigger_bird_strike(_pawn_id: int) -> void:
	pass

func _kill_pawn(_pawn_id: int, _cause: StringName) -> void:
	pass

func resolve_instant_kill(_pawn_id: int, _cause: StringName) -> void:
	pass
