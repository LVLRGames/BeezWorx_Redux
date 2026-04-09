# damage_plant_ability_def.gd
# res://abilities/damage_plant_ability_def.gd
#
# Deals damage to a plant at the pawn's current cell, across any slot (0-5).
# Grass lives in slots 1-5; resource plants in slot 0.
# _get_plant_cell() iterates all slots and returns the first matching plant.
# resolve_target() returns Vector3i(cell, slot) so execute() knows the exact slot.

class_name DamagePlantAbilityDef
extends AbilityDef

## Damage dealt per execute() call. Reduced by plant's toughness inside damage_plant().
@export var damage: float = 25.0

## HexPlantDef.PlantSubcategory ints this ability is allowed to target.
## Empty = any subcategory. [0,1] = GRASS + RESOURCE.
@export var valid_plant_subcategories: Array[int] = []

## Plant stages during which damage is allowed. Empty = any stage.
@export var valid_stages: Array[int] = []

## Override the item drop on kill. Empty = use plant def's drop_item_id.
@export var drop_item_override: StringName = &""

# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	var state: HexCellState = _get_plant_cell(ctx)
	if state == null:
		return false
	return super.can_use(ctx)


func resolve_target(ctx: AbilityContext) -> Variant:
	var state: HexCellState = _get_plant_cell(ctx)
	if state == null:
		return null
	var cell: Vector2i = ctx.target_cell if ctx.has_target_cell() else ctx.pawn_cell
	var slot: int = state.slot_index if state.slot_index >= 0 else 0
	return Vector3i(cell.x, cell.y, slot)


func execute(ctx: AbilityContext, target: Variant) -> void:
	var cell: Vector2i
	var slot: int = 0
	if target is Vector3i:
		var sk: Vector3i = target as Vector3i
		cell = Vector2i(sk.x, sk.y)
		slot = sk.z
	elif target is Vector2i:
		cell = target as Vector2i
	else:
		return
	HexWorldState.damage_plant(cell, slot, damage, ctx.pawn.pawn_id, drop_item_override)


func get_prompt(ctx: AbilityContext) -> String:
	if _get_plant_cell(ctx) == null:
		return ""
	return display_name if not display_name.is_empty() else "Eat"

# ════════════════════════════════════════════════════════════════════════════ #
#  Internal
# ════════════════════════════════════════════════════════════════════════════ #

## Iterates all 6 slots of the target/pawn cell and returns the first plant
## that matches this ability's subcategory and stage filters.
## Returns null if no valid plant is found.
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
		var offset: Vector3 = HexChunk._slot_centroid_offset(slot, HexConsts.HEX_SIZE)
		var slot_xz := Vector2(cell_world.x + offset.x, cell_world.y + offset.z)
		var dist: float = pawn_xz.distance_squared_to(slot_xz)
		if dist < best_dist:
			best_dist  = dist
			best_state = state

	return best_state
