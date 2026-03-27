# deposit_ability_def.gd
# res://abilities/deposit_ability_def.gd
#
# Deposits all inventory items into the nearest hive storage slot.
# Pawn must be within deposit_range hex cells of a hive anchor.
# Author as: deposit.tres

class_name DepositAbilityDef
extends AbilityDef

## Max hex distance to a hive anchor for deposit to be valid
@export var deposit_range: int = 3

## If set, only deposit this item type. Empty = deposit everything.
@export var filter_item_id: StringName = &""

# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
		return false
	if not ctx.pawn.state.inventory.has_any():
		return false
	return _find_nearest_hive(ctx) != null

func resolve_target(ctx: AbilityContext) -> Variant:
	return _find_nearest_hive(ctx)

func execute(ctx: AbilityContext, target: Variant) -> void:
	if not target is HiveState:
		return
	var hive: HiveState  = target
	var inv: PawnInventory = ctx.pawn.state.inventory

	for item_id: StringName in inv.get_item_ids():
		var count: int    = inv.get_count(item_id)
		var overflow: int = HiveSystem.deposit_item(hive.hive_id, item_id, count)
		var deposited: int = count - overflow
		if deposited > 0:
			inv.remove_item(item_id, deposited)
			EventBus.item_deposited.emit(ctx.pawn.pawn_id, hive.hive_id, item_id, deposited)


func get_prompt(ctx: AbilityContext) -> String:
	if _find_nearest_hive(ctx) != null:
		return "Deposit"
	return ""

# ── Helper ────────────────────────────────────────────────────────────────────

func _find_nearest_hive(ctx: AbilityContext) -> HiveState:
	if ctx.pawn.state == null:
		return null
	var colony_id: int = ctx.pawn.state.colony_id
	var hives: Array[HiveState] = HiveSystem.get_hives_for_colony(colony_id)
	var best: HiveState = null
	var best_dist: int  = deposit_range + 1

	for hs: HiveState in hives:
		var dist: int = _hex_dist(ctx.pawn_cell, hs.anchor_cell)
		if dist <= deposit_range and dist < best_dist:
			best_dist = dist
			best      = hs

	return best

static func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var dq: int = b.x - a.x
	var dr: int = b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
