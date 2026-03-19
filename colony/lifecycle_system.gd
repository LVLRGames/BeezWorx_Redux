# FILE: res://colony/lifecycle_system.gd
# Manages biological progression: aging, death, maturation, and succession.
class_name LifecycleSystem
extends Node

func _on_day_changed(new_day: int) -> void:
	pass

func _check_natural_death(state: PawnState) -> void:
	pass

func _roll_lifespan(species_def: SpeciesDef, personality: PawnPersonality) -> int:
	return 0

func _mature_egg(hive_id: int, slot_index: int) -> void:
	pass

func _determine_role(feed_log: Array) -> StringName:
	return &""

func _create_pawn(egg: EggState, role_tag: StringName, birth_hive_id: int) -> int:
	return 0

func _crown_queen(colony_id: int, princess_id: int) -> void:
	pass

func _exile_princess(origin_colony_id: int, princess_id: int) -> void:
	pass

func _trigger_game_over(colony_id: int) -> void:
	pass

func _recruit_retinue(colony_id: int, min_count: int, max_count: int) -> Array[int]:
	return []
