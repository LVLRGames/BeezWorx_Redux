# FILE: res://world/fog_of_war_system.gd
# Handles visibility state and exploration tracking across the world map.
class_name FogOfWarSystem
extends Node

var _revealed: Dictionary[Vector2i, bool] = {}

func reveal_around(cell: Vector2i, radius: int) -> void:
	# TODO: Update revealed map
	pass

func is_revealed(cell: Vector2i) -> bool:
	return false

func save_state() -> Dictionary:
	return {}

func load_state(data: Dictionary) -> void:
	pass
