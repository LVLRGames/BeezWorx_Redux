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

## Full reset for scene reload. Call from WorldRoot._init_world().
func reset() -> void:
	_possessed.clear()

func request_possess(player_slot: int, pawn_id: int) -> bool:
	var pawn: PawnBase = _find_pawn(pawn_id)
	if pawn == null:
		return false
	if not _can_possess(player_slot, pawn):
		return false
	# Don't call request_release here — _local_possess handles it
	_local_possess(pawn, player_slot)  # already emits pawn_possessed
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
	print("_local_possess: pawn_id=", pawn.pawn_id, " slot=", player_slot)

	# Grab existing controller from previously possessed pawn before releasing
	var pc: PlayerController = null
	var prev_id: int = _possessed.get(player_slot, -1)
	if prev_id >= 0:
		var prev_pawn: PawnBase = _find_pawn(prev_id)
		if prev_pawn != null and prev_pawn.controller is PlayerController:
			pc = prev_pawn.controller as PlayerController
			prev_pawn.controller = null
			prev_pawn.on_unpossessed()
	_possessed.erase(player_slot)

	if pc == null:
		pc = PlayerController.new()
		pc.player_index = player_slot

	pawn.controller = pc
	pawn.on_possessed(player_slot)
	_possessed[player_slot] = pawn.pawn_id
	EventBus.pawn_possessed.emit(player_slot, pawn.pawn_id)


func _local_release(pawn: PawnBase, player_slot: int) -> void:
	# Restore AI — PawnAI takes over if present, otherwise null controller
	pawn.controller = null
	pawn.on_unpossessed()
	EventBus.pawn_released.emit(pawn.pawn_id, player_slot)
	# TODO Phase 3: trigger queen safety behavior if releasing queen outside hive

func _can_possess(player_slot: int, pawn: PawnBase) -> bool:
	print("_can_possess: pawn.is_possessed=", pawn.is_possessed, 
		  " pawn.state=", pawn.state,
		  " pawn.is_alive=", pawn.state.is_alive if pawn.state else "no state")
	# ... rest of function
	if pawn == null:
		return false
	if pawn.is_possessed:
		return false
	# Phase 3: use PawnState checks
	if pawn.state != null:
		if not pawn.state.is_alive:
			return false
		if not pawn.state.is_awake:
			return false
		# Queen can only be possessed by slot 0
		if PawnRegistry.is_queen(pawn.pawn_id, pawn.state.colony_id) \
				and player_slot != 1:
			return false
	return true


func _find_pawn(pawn_id: int) -> PawnBase:
	# O(1) lookup via PawnRegistry — replaces the O(n) tree scan
	return PawnRegistry.get_pawn(pawn_id)
