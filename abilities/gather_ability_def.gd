# gather_ability_def.gd
# res://abilities/gather_ability_def.gd
#
# Collects a specific item type from a plant cell into the pawn's inventory.
# Author one .tres per gatherable item:
#   gather_nectar.tres — item_id=nectar, valid_stages=[FRUITING]
#   gather_pollen.tres — item_id=pollen, valid_stages=[FLOWERING]
#
# TARGETING: the cell the pawn is currently occupying.
# If the cell is occupied by a RESOURCE_PLANT at a valid stage, collect.

class_name GatherAbilityDef
extends AbilityDef

@export var item_id: StringName = &"nectar"

## Stages at which this gather is valid
@export var valid_stages: Array[int] = [HexWorldState.Stage.FRUITING]

## How many inventory units to collect per use
@export var units_per_collect: int = 1

## How much of the plant resource to consume per collect
@export var consume_amount: float = 1.0

# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
		return false
	if ctx.pawn.state.inventory.is_full():
		return false
	return true

func resolve_target(ctx: AbilityContext) -> Variant:
	var state: HexCellState = HexWorldState.get_cell(ctx.pawn_cell)
	if not state.occupied:
		return null
	if state.category != HexGridObjectDef.Category.RESOURCE_PLANT:
		return null
	if not valid_stages.has(state.stage):
		return null
	# Check the plant actually has the resource
	match item_id:
		&"nectar":
			if state.nectar_amount <= 0.0:
				return null
		&"pollen":
			if state.pollen_amount <= 0.0 or not state.has_pollen:
				return null
	return ctx.pawn_cell

func execute(ctx: AbilityContext, target: Variant) -> void:
	if not target is Vector2i:
		return
	var cell: Vector2i = target
	var overflow: int = ctx.pawn.state.inventory.add_item(item_id, units_per_collect)
	if overflow > 0:
		return   # inventory full — shouldn't reach here if can_use() was checked

	match item_id:
		&"nectar":
			HexWorldState.consume_nectar(cell, consume_amount)
		&"pollen":
			HexWorldState.consume_pollen(cell, consume_amount * 0.25)

	EventBus.item_collected.emit(ctx.pawn.pawn_id, item_id, units_per_collect)

func get_prompt(ctx: AbilityContext) -> String:
	var state: HexCellState = HexWorldState.get_cell(ctx.pawn_cell)
	if state.occupied and valid_stages.has(state.stage):
		return "Collect %s" % display_name
	return ""
