# FILE: res://world/hex_terrain_manager.gd
# Existing file stub with added methods for active plant pooling and chunk updates.
class_name HexTerrainManager
extends Node3D

var _active_plant_pool: Dictionary[StringName, Array] = {}

func checkout_active_plant(type_id: StringName) -> Node3D:
	return null

func return_active_plant(_type_id: StringName, _node: Node3D) -> void:
	pass

func update_chunks_immediate() -> void:
	pass
