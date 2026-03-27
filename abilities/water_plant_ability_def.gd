# water_plant_ability_def.gd
# res://abilities/water_plant_ability_def.gd
#
# Waters a wilting plant at the pawn's current cell.
# Costs one unit of "water" from inventory if require_water_item = true.
# Author as: water_plant.tres

class_name WaterPlantAbilityDef
extends AbilityDef

## If true, consumes one "water" item from inventory
## If false, pawn can water for free (magic bees)
@export var require_water_item: bool = false

# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	var state: HexCellState = HexWorldState.get_cell(ctx.pawn_cell)
	if not state.occupied:
		return false
	if state.category != HexGridObjectDef.Category.RESOURCE_PLANT:
		return false
	if state.stage != HexWorldState.Stage.WILT:
		return false
	if require_water_item:
		if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
			return false
		if not ctx.pawn.state.inventory.has_item(&"water"):
			return false
	return true

func resolve_target(ctx: AbilityContext) -> Variant:
	var state: HexCellState = HexWorldState.get_cell(ctx.pawn_cell)
	if state.occupied and state.stage == HexWorldState.Stage.WILT:
		return ctx.pawn_cell
	return null

func execute(ctx: AbilityContext, target: Variant) -> void:
	if not target is Vector2i:
		return
	var cell: Vector2i = target
	if require_water_item:
		ctx.pawn.state.inventory.remove_item(&"water", 1)
	HexWorldState.water_plant(cell)

func get_prompt(_ctx: AbilityContext) -> String:
	return "Water Plant"
