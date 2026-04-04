# collect_ability_def.gd
# res://abilities/collect_ability_def.gd
#
# Takes an item from the context cell into the pawn's inventory.
# Replaces GatherAbilityDef.
#
# Example resources:
#   gather_nectar.tres — item_id=nectar, valid_stages=[FRUITING]
#   gather_pollen.tres — item_id=pollen, valid_stages=[FLOWERING]
#                        require_ctx_has=[pollen], require_ctx_has_mode=ALL

class_name CollectAbilityDef
extends AbilityDef

## Item to collect into inventory
@export var item_id: StringName = &""

## Plant stages at which collection is valid (empty = any stage)
@export var valid_stages: Array[HexWorldState.Stage] = []

## Cell categories valid for collection
@export var valid_categories: Array[HexGridObjectDef.Category] = [HexGridObjectDef.Category.RESOURCE_PLANT]

## How many inventory units per collect action
@export var units_per_collect: int = 1

## How much of the plant resource is consumed per collect
@export var consume_fraction: float = 1.0

# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	# Pawn inventory must have room
	if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
		return false
	if ctx.pawn.state.inventory.is_full():
		return false
	# Cell must exist and be the right category
	var cell: HexCellState = ctx.get_pawn_cell_state()
	if cell == null or not cell.occupied:
		return false
	if not valid_categories.has(cell.category):
		return false
	# Stage check
	if not valid_stages.is_empty() and not valid_stages.has(cell.stage):
		return false
	# Base requirement checks (ctx_has = resource must be present)
	return super.can_use(ctx)

func resolve_target(ctx: AbilityContext) -> Variant:
	var cell: HexCellState = ctx.get_pawn_cell_state()
	if cell == null or not cell.occupied:
		return null
	if not valid_categories.has(cell.category):
		return null
	if not valid_stages.is_empty() and not valid_stages.has(cell.stage):
		return null
	return ctx.pawn_cell

func execute(ctx: AbilityContext, target: Variant) -> void:
	if not target is Vector2i:
		return
	var cell: Vector2i = target
	var overflow: int = ctx.pawn.state.inventory.add_item(item_id, units_per_collect)
	if overflow > 0:
		return
	# Consume from cell
	match item_id:
		&"nectar": HexWorldState.consume_nectar(cell, consume_fraction)
		&"pollen": HexWorldState.consume_pollen(cell, consume_fraction)
		&"water":  HexWorldState.consume_water(cell,  consume_fraction)
	EventBus.item_collected.emit(ctx.pawn.pawn_id, item_id, units_per_collect)

func get_prompt(ctx: AbilityContext) -> String:
	var cell: HexCellState = ctx.get_pawn_cell_state()
	if cell == null or not cell.occupied:
		return ""
	return "Collect %s" % display_name
