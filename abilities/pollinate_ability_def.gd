# pollinate_ability_def.gd
# res://abilities/pollinate_ability_def.gd
#
# If the pawn carries pollen, applies it to the flowering plant at their cell.
# If the pawn has no pollen, collects pollen from the flowering plant instead.
# This mirrors the original bee interaction — one ability handles both directions.
#
# Author as: pollinate.tres

class_name PollinateAbilityDef
extends AbilityDef

## Inventory slot cost per pollination
@export var pollen_cost: int = 1

## Amount of pollen to consume from the plant when collecting
@export var collect_consume_fraction: float = 0.25

## Pollen units added to inventory when collecting
@export var collect_units: int = 1

# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
		return false
	var state: HexCellState = HexWorldState.get_cell(ctx.pawn_cell)
	if not state.occupied:
		return false
	if state.category != HexGridObjectDef.Category.RESOURCE_PLANT:
		return false
	if state.stage != HexWorldState.Stage.FLOWERING:
		return false
	return true

func resolve_target(ctx: AbilityContext) -> Variant:
	var state: HexCellState = HexWorldState.get_cell(ctx.pawn_cell)
	if not state.occupied:
		return null
	if state.stage != HexWorldState.Stage.FLOWERING:
		return null
	return ctx.pawn_cell

func execute(ctx: AbilityContext, target: Variant) -> void:
	if not target is Vector2i:
		return
	var cell: Vector2i       = target
	var inv: PawnInventory   = ctx.pawn.state.inventory
	var plant: HexCellState  = HexWorldState.get_cell(cell)

	if inv.has_item(&"pollen"):
		# Apply pollen to this plant — cross-pollinate
		# Find source cell from pollen origin if tracked, else use current
		# For now: apply to this cell directly (self-pollinate as fallback)
		if cell == _get_pollen_source(ctx):
			# Can't self-pollinate — collect instead
			_collect_pollen(ctx, cell, plant, inv)
			return
		HexWorldState.apply_pollen(_get_pollen_source(ctx), cell)
		inv.remove_item(&"pollen", pollen_cost)
		EventBus.item_used.emit(ctx.pawn.pawn_id, &"pollen", pollen_cost)
	else:
		_collect_pollen(ctx, cell, plant, inv)

func _collect_pollen(
	ctx: AbilityContext,
	cell: Vector2i,
	plant: HexCellState,
	inv: PawnInventory
) -> void:
	if plant.pollen_amount <= 0.0 or not plant.has_pollen:
		return
	if inv.is_full():
		return
	var overflow: int = inv.add_item(&"pollen", collect_units)
	if overflow == 0:
		HexWorldState.consume_pollen(cell, plant.pollen_amount * collect_consume_fraction)
		EventBus.item_collected.emit(ctx.pawn.pawn_id, &"pollen", collect_units)

func _get_pollen_source(ctx: AbilityContext) -> Vector2i:
	# TODO Phase 4: track pollen source cell in PawnState for cross-pollination
	# For now return an invalid cell so apply_pollen uses current cell
	return ctx.pawn_cell

func get_prompt(ctx: AbilityContext) -> String:
	if ctx.pawn.state and ctx.pawn.state.inventory:
		if ctx.pawn.state.inventory.has_item(&"pollen"):
			return "Pollinate"
		return "Collect Pollen"
	return ""
