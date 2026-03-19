# FILE: res://autoloads/pawn_registry.gd
# Runtime database of all living entities (pawns), tracking their state and LOD nodes.
# class_name PawnRegistry
extends Node

var _states: Dictionary[int, PawnState] = {}
var _nodes: Dictionary[int, WeakRef] = {}
var _by_colony: Dictionary[int, Array] = {}
var _by_cell: Dictionary[Vector2i, Array] = {}
var _next_id: int = 0

func register(pawn_id: int, state: PawnState, node: Node) -> void:
	# TODO: Track pawn state and node
	pass

func deregister(pawn_id: int) -> void:
	pass

func get_state(pawn_id: int) -> PawnState:
	return null

func get_node(pawn_id: int) -> Node:
	return null

func get_ai(pawn_id: int) -> Node: # PawnAI
	return null

func get_pawns_for_colony(colony_id: int) -> Array[int]:
	return []

func get_all_pawn_ids() -> Array[int]:
	return []

func get_pawns_near_cell(cell: Vector2i, radius: int) -> Array[int]:
	return []

func get_pawns_in_hive(hive_id: int) -> Array[int]:
	return []

func next_id() -> int:
	_next_id += 1
	return _next_id

func update_cell(pawn_id: int, new_cell: Vector2i) -> void:
	# TODO: Update spatial indexing
	pass

func save_state() -> Dictionary:
	return {}

func load_state(data: Dictionary) -> void:
	pass
