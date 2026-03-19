# FILE: res://autoloads/colony_state.gd
# Tracks colony-level metadata, queen records, diplomacy, and collective morale.
class_name ColonyState
extends Node

var _colonies: Dictionary[int, ColonyData] = {}
var _next_colony_id: int = 0

func create_colony() -> int:
	return 0

func get_colony(colony_id: int) -> ColonyData:
	return null

func get_player_colony() -> ColonyData:
	return null

func set_queen(colony_id: int, pawn_id: int) -> void:
	pass

func get_queen_id(colony_id: int) -> int:
	return 0

func record_queen_death(colony_id: int, cause: StringName) -> void:
	pass

func add_heir(colony_id: int, pawn_id: int) -> void:
	pass

func remove_heir(colony_id: int, pawn_id: int) -> void:
	pass

func get_heirs(colony_id: int) -> Array[int]:
	return []

func add_known_recipe(colony_id: int, recipe_id: StringName) -> void:
	pass

func knows_recipe(colony_id: int, recipe_id: StringName) -> bool:
	return false

func get_known_recipes(colony_id: int) -> Array[StringName]:
	return []

func add_known_plant(colony_id: int, plant_id: StringName) -> void:
	pass

func knows_plant(colony_id: int, plant_id: StringName) -> bool:
	return false

func get_loyalty(pawn_id: int) -> float:
	return 0.0

func modify_loyalty(pawn_id: int, delta: float, cause: StringName) -> void:
	pass

func get_morale(colony_id: int) -> float:
	return 0.0

func get_morale_modifiers(colony_id: int) -> Array:
	return []

func get_relation(colony_id: int, faction_id: StringName) -> float:
	return 0.0

func modify_relation(colony_id: int, faction_id: StringName, delta: float, cause: StringName) -> void:
	pass

func get_alliance_level(colony_id: int, faction_id: StringName) -> int:
	return 0

func resolve_gift(colony_id: int, faction_id: StringName, item_id: StringName, count: int) -> float:
	return 0.0

func get_influence_score(colony_id: int) -> float:
	return 0.0

func recompute_influence(colony_id: int) -> void:
	pass

func save_state() -> Dictionary:
	return {}

func load_state(data: Dictionary) -> void:
	pass
