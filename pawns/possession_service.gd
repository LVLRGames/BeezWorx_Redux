# FILE: res://pawns/possession_service.gd
# Manages player control of pawns, tracking which player possesses which entity.
class_name PossessionService
extends RefCounted

var possessed_pawns: Dictionary[int, int] = {} # player_slot -> pawn_id
var max_players: int = 1

func request_possess(player_slot: int, pawn_id: int) -> bool:
	return false

func request_release(player_slot: int) -> void:
	pass

func get_possessed_pawn(player_slot: int) -> Node:
	return null

func is_possessed(pawn_id: int) -> bool:
	return false

func get_possessor(pawn_id: int) -> int:
	return -1

func _can_possess(_player_slot: int, _pawn_id: int) -> bool:
	return false
