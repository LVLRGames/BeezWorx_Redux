# deposit_ability_def.gd
# res://abilities/deposit_ability_def.gd
#
# Puts an item from the pawn's inventory into a target.
# Target can be a plant cell, a hive, or another pawn.
#
# Example resources:
#   pollinate.tres    — item_id=pollen, deposit_target=PLANT, valid_stages=[FLOWERING]
#   water_plant.tres  — item_id=water,  deposit_target=PLANT, valid_stages=[WILT]
#   hive_deposit.tres — item_id="",     deposit_target=HIVE,  deposit_range=3
#   give_pawn.tres    — item_id="",     deposit_target=PAWN,  deposit_range=2

class_name DepositAbilityDef
extends AbilityDef

enum DepositTarget { PLANT, HIVE, PAWN, ANY }

@export var deposit_target: DepositTarget = DepositTarget.PLANT
@export var item_id:        StringName    = &""
@export var item_count:     int           = 1

## Plant stages valid for plant deposit (empty = any)
@export var valid_stages: Array[HexWorldState.Stage] = []

## HexPlantDef.PlantSubcategory ints valid for plant deposit (empty = any plant)
@export var valid_plant_subcategories: Array[int] = [HexPlantDef.PlantSubcategory.RESOURCE]

@export var deposit_range:  int   = 3
@export var deposit_amount: float = 1.0

# ════════════════════════════════════════════════════════════════════════════ #
#  can_use
# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
		return false
	if item_id != &"" and not ctx.pawn.state.inventory.has_item(item_id):
		return false
	if item_id == &"" and not ctx.pawn.state.inventory.has_any():
		return false
	match deposit_target:
		DepositTarget.PLANT: return _can_use_plant(ctx)
		DepositTarget.HIVE:  return _resolve_hive(ctx) != null
		DepositTarget.PAWN:  return _resolve_pawn(ctx) != null
		DepositTarget.ANY:
			return _can_use_plant(ctx) \
				or _resolve_hive(ctx) != null \
				or _resolve_pawn(ctx) != null
	return false


func _can_use_plant(ctx: AbilityContext) -> bool:
	var cell: HexCellState = _get_plant_cell(ctx)
	if cell == null or not cell.occupied:
		return false
	if cell.category != HexGridObjectDef.Category.PLANT:
		return false
	if not valid_plant_subcategories.is_empty() \
			and not valid_plant_subcategories.has(cell.plant_subcategory):
		return false
	if not valid_stages.is_empty() and not valid_stages.has(cell.stage):
		return false
	return super.can_use(ctx)

# ════════════════════════════════════════════════════════════════════════════ #
#  resolve_target
# ════════════════════════════════════════════════════════════════════════════ #

func resolve_target(ctx: AbilityContext) -> Variant:
	match deposit_target:
		DepositTarget.PLANT: return _resolve_plant(ctx)
		DepositTarget.HIVE:  return _resolve_hive(ctx)
		DepositTarget.PAWN:  return _resolve_pawn(ctx)
		DepositTarget.ANY:
			var plant = _resolve_plant(ctx)
			if plant != null: return plant
			var hive = _resolve_hive(ctx)
			if hive != null: return hive
			return _resolve_pawn(ctx)
	return null


func _resolve_plant(ctx: AbilityContext) -> Variant:
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
	return ctx.target_cell if ctx.has_target_cell() else ctx.pawn_cell


func _resolve_hive(ctx: AbilityContext) -> HiveState:
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


func _resolve_pawn(ctx: AbilityContext) -> PawnBase:
	if ctx.target_pawn == null:
		return null
	var dist: int = _hex_dist(ctx.pawn_cell,
		HexConsts.WORLD_TO_AXIAL(
			ctx.target_pawn.global_position.x,
			ctx.target_pawn.global_position.z))
	return ctx.target_pawn if dist <= deposit_range else null


func _get_plant_cell(ctx: AbilityContext) -> HexCellState:
	if ctx.has_target_cell():
		return ctx.get_target_cell_state()
	return ctx.get_pawn_cell_state()

# ════════════════════════════════════════════════════════════════════════════ #
#  execute
# ════════════════════════════════════════════════════════════════════════════ #

func execute(ctx: AbilityContext, target: Variant) -> void:
	if target is Vector2i:
		_execute_plant(ctx, target)
	elif target is HiveState:
		_execute_hive(ctx, target)
	elif target is PawnBase:
		_execute_pawn(ctx, target)


func _execute_plant(ctx: AbilityContext, cell: Vector2i) -> void:
	var inv: PawnInventory = ctx.pawn.state.inventory
	var actual_item: StringName = item_id
	var amount: int = item_count if item_count > 0 else inv.get_count(item_id)
	if inv.remove_item(actual_item, amount):
		match actual_item:
			&"pollen": HexWorldState.apply_pollen(cell, cell)
			&"water":  HexWorldState.water_plant(cell)
			_: pass
		EventBus.item_used.emit(ctx.pawn.pawn_id, actual_item, amount)


func _execute_hive(ctx: AbilityContext, hive: HiveState) -> void:
	var inv: PawnInventory = ctx.pawn.state.inventory
	var items: Array[StringName] = [item_id] if item_id != &"" \
		else inv.get_item_ids()
	for id: StringName in items:
		var count: int    = inv.get_count(id) if item_count == 0 else item_count
		var overflow: int = HiveSystem.deposit_item(hive.hive_id, id, count)
		var deposited: int = count - overflow
		if deposited > 0:
			inv.remove_item(id, deposited)
			EventBus.item_deposited.emit(ctx.pawn.pawn_id, hive.hive_id, id, deposited)


func _execute_pawn(ctx: AbilityContext, target: PawnBase) -> void:
	if target.state == null or target.state.inventory == null:
		return
	var inv: PawnInventory = ctx.pawn.state.inventory
	var items: Array[StringName] = [item_id] if item_id != &"" \
		else inv.get_item_ids()
	for id: StringName in items:
		var count: int    = inv.get_count(id) if item_count == 0 else item_count
		var overflow: int = target.state.inventory.add_item(id, count)
		var given: int    = count - overflow
		if given > 0:
			inv.remove_item(id, given)
			EventBus.item_given.emit(ctx.pawn.pawn_id, target.pawn_id, id, given)

# ════════════════════════════════════════════════════════════════════════════ #
#  get_prompt
# ════════════════════════════════════════════════════════════════════════════ #

func get_prompt(ctx: AbilityContext) -> String:
	match deposit_target:
		DepositTarget.PLANT:
			if item_id != &"":
				return "Apply %s" % ItemRegistry.get_display_name(item_id)
			return display_name
		DepositTarget.HIVE:
			return "Deposit"
		DepositTarget.PAWN:
			if ctx.target_pawn and ctx.target_pawn.state:
				return "Give to %s" % ctx.target_pawn.state.pawn_name
			return "Give"
		_:
			return display_name

static func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var dq: int = b.x - a.x
	var dr: int = b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
