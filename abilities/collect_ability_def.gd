# collect_ability_def.gd
# res://abilities/collect_ability_def.gd
#
# Takes an item from the context cell slot into the pawn's inventory.
#
# CATEGORY MIGRATION (plant system overhaul):
#   valid_categories (Array[HexGridObjectDef.Category]) replaced by
#   valid_plant_subcategories (Array[HexPlantDef.PlantSubcategory]).
#   All plants are now HexGridObjectDef.Category.PLANT; the subcategory
#   carries the semantic distinction (RESOURCE, GRASS, TREE, etc.).
#
# Example resources:
#   gather_nectar.tres — item_id=nectar, valid_plant_subcategories=[RESOURCE]
#                        valid_stages=[FRUITING]
#   gather_pollen.tres — item_id=pollen, valid_plant_subcategories=[RESOURCE]
#                        valid_stages=[FLOWERING], require_ctx_has=[pollen]

class_name CollectAbilityDef
extends AbilityDef

## Item to collect into inventory.
@export var item_id: StringName = &""

## Plant stages at which collection is valid. Empty = any stage.
@export var valid_stages: Array[HexWorldState.Stage] = []

## HexPlantDef.PlantSubcategory ints valid for collection.
## Empty = any plant subcategory is valid.
@export var valid_plant_subcategories: Array[int] = [HexPlantDef.PlantSubcategory.RESOURCE]

## How many inventory units per collect action.
@export var units_per_collect: int = 1

## How much of the plant resource is consumed per collect.
@export var consume_fraction: float = 1.0

# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
		return false
	if ctx.pawn.state.inventory.is_full():
		return false

	var cell: HexCellState = _get_plant_cell(ctx)
	if cell == null or not cell.occupied:
		return false

	# Must be a PLANT category cell.
	if cell.category != HexGridObjectDef.Category.PLANT:
		return false

	# Subcategory check.
	if not valid_plant_subcategories.is_empty() \
			and not valid_plant_subcategories.has(cell.plant_subcategory):
		return false

	# Stage check.
	if not valid_stages.is_empty() and not valid_stages.has(cell.stage):
		return false

	return super.can_use(ctx)


func resolve_target(ctx: AbilityContext) -> Variant:
	var cell: HexCellState = _get_plant_cell(ctx)
	if cell == null or not cell.occupied:
		return null
	if cell.category != HexGridObjectDef.Category.PLANT:
		return null
	if not valid_plant_subcategories.is_empty() \
			and not valid_plant_subcategories.has(cell.plant_subcategory):
		return null
	if not valid_stages.is_empty() and not valid_stages.has(cell.stage):
		return null
	# Return the cell the plant is actually at (target or pawn's own cell).
	var cell2: Vector2i = ctx.target_cell if ctx.has_target_cell() else ctx.pawn_cell
	return cell2


func execute(ctx: AbilityContext, target: Variant) -> void:
	if not target is Vector2i:
		return
	var cell: Vector2i = target
	var overflow: int = ctx.pawn.state.inventory.add_item(item_id, units_per_collect)
	if overflow > 0:
		return
	match item_id:
		&"nectar": HexWorldState.consume_nectar(cell, consume_fraction)
		&"pollen": HexWorldState.consume_pollen(cell, consume_fraction)
		&"water":  HexWorldState.consume_water(cell,  consume_fraction)
	EventBus.item_collected.emit(ctx.pawn.pawn_id, item_id, units_per_collect)



## Returns the plant cell state to act on: target_cell first, pawn_cell fallback.
func _get_plant_cell(ctx: AbilityContext) -> HexCellState:
	var cell: Vector2i = ctx.target_cell if ctx.has_target_cell() else ctx.pawn_cell
	var cell_world: Vector2 = HexConsts.AXIAL_TO_WORLD(cell.x, cell.y)
	var pawn_xz := Vector2(ctx.pawn.global_position.x, ctx.pawn.global_position.z)

	var best_state: HexCellState = null
	var best_dist:  float        = INF

	for slot: int in 6:
		var state: HexCellState = HexWorldState.get_slot(cell, slot)
		if state == null or not state.occupied:
			continue
		if state.category != HexGridObjectDef.Category.PLANT:
			continue
		if not valid_plant_subcategories.is_empty() \
				and not valid_plant_subcategories.has(state.plant_subcategory):
			continue
		if state.stage == HexWorldState.Stage.DEAD:
			continue
		# Pick the slot whose centroid is closest to the pawn.
		var offset: Vector3 = HexChunk._slot_centroid_offset(slot, HexConsts.HEX_SIZE)
		var slot_xz := Vector2(cell_world.x + offset.x, cell_world.y + offset.z)
		var dist: float = pawn_xz.distance_squared_to(slot_xz)
		if dist < best_dist:
			best_dist  = dist
			best_state = state

	return best_state
func get_prompt(ctx: AbilityContext) -> String:
	var cell: HexCellState = ctx.get_pawn_cell_state()
	if cell == null or not cell.occupied:
		return ""
	return "Collect %s" % display_name
