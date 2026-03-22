# possession_manager.gd
# res://pawns/possession_manager.gd
#
# Manages which player slot controls which pawn. Handles possession
# transitions, controller swapping, and camera rig targeting.
#
# Register as autoload: PossessionManager → res://pawns/possession_manager.gd
#
# CHANGES FROM OLD PROJECT:
#   - Multiplayer RPC possession removed for Phase 1 (singleplayer first)
#   - Uses pawn_id (int) instead of NodePath — routes through PawnRegistry
#     once it exists (Phase 3). For Phase 1, finds pawns by scanning tree.
#   - PossessionService spec (RefCounted) is merged here for now; will be
#     extracted to possession_service.gd in Phase 3 when PawnRegistry is live.
#   - Eligibility check is simplified for Phase 1; full check is Phase 3.
#
# NOTE: class_name intentionally omitted — accessed via autoload name.

extends Node

# ── State ─────────────────────────────────────────────────────────────────────
## player_slot → pawn_id (-1 = none)
var _possessed: Dictionary[int, int] = {}

const MAX_PLAYERS: int = 4

# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

## Request that player_slot takes possession of pawn with pawn_id.
## Returns false if pawn is not eligible.
func request_possess(player_slot: int, pawn_id: int) -> bool:
	var pawn: PawnBase = _find_pawn(pawn_id)
	if pawn == null:
		return false
	if not _can_possess(player_slot, pawn):
		return false

	# Release current possession for this slot if any
	if _possessed.get(player_slot, -1) != -1:
		request_release(player_slot)

	_local_possess(pawn, player_slot)
	return true

## Release whatever pawn player_slot is currently possessing.
func request_release(player_slot: int) -> void:
	var pawn_id: int = _possessed.get(player_slot, -1)
	if pawn_id == -1:
		return

	var pawn: PawnBase = _find_pawn(pawn_id)
	if pawn:
		_local_release(pawn, player_slot)

	_possessed.erase(player_slot)

## Returns the PawnBase node currently possessed by player_slot, or null.
func get_possessed_pawn(player_slot: int) -> PawnBase:
	var pawn_id: int = _possessed.get(player_slot, -1)
	if pawn_id == -1:
		return null
	return _find_pawn(pawn_id)

## Returns true if any player slot currently possesses pawn_id.
func is_possessed(pawn_id: int) -> bool:
	return _possessed.values().has(pawn_id)

## Returns the player slot possessing pawn_id, or -1.
func get_possessor(pawn_id: int) -> int:
	for slot: int in _possessed:
		if _possessed[slot] == pawn_id:
			return slot
	return -1

# ════════════════════════════════════════════════════════════════════════════ #
#  Internal
# ════════════════════════════════════════════════════════════════════════════ #

func _local_possess(pawn: PawnBase, player_slot: int) -> void:
	# Assign PlayerController
	var pc := PlayerController.new()
	pc.player_index = player_slot
	pawn.controller = pc

	pawn.on_possessed(player_slot)
	_possessed[player_slot] = pawn.pawn_id

	# Point camera rig at the new pawn
	var rig: CameraRig = CameraRig.for_player(player_slot)
	if rig:
		rig.set_target(pawn)

	# Add to "bees" group for selector debug info (backwards compat)
	if not pawn.is_in_group("bees"):
		pawn.add_to_group("bees")

	EventBus.pawn_spawned.emit(pawn.pawn_id, 0, Vector2i.ZERO)
	# TODO Phase 3: emit EventBus.pawn_possessed(pawn_id, player_slot)

func _local_release(pawn: PawnBase, player_slot: int) -> void:
	# Restore AI — PawnAI takes over if present, otherwise null controller
	pawn.controller = null
	pawn.on_unpossessed()

	# TODO Phase 3: emit EventBus.pawn_released(pawn_id, player_slot)
	# TODO Phase 3: trigger queen safety behavior if releasing queen outside hive

func _can_possess(player_slot: int, pawn: PawnBase) -> bool:
	# Phase 1 simplified check: pawn must be alive and not currently possessed
	if pawn == null:
		return false
	if pawn.is_possessed:
		return false
	# TODO Phase 3: check pawn.state.is_alive, is_awake, colony_id, queen slot rule
	return true

func _find_pawn(pawn_id: int) -> PawnBase:
	# Phase 1: scan tree for pawn with matching pawn_id.
	# Phase 3: replace with PawnRegistry.get_node(pawn_id).
	if pawn_id == -1:
		return null
	var pawns: Array = get_tree().get_nodes_in_group("pawns")
	for p: Node in pawns:
		if p is PawnBase and (p as PawnBase).pawn_id == pawn_id:
			return p as PawnBase
	return null
