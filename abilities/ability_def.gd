# ability_def.gd
# res://abilities/ability_def.gd

@abstract
class_name AbilityDef
extends Resource

enum RequireMode { ALL, ANY, NONE }

@export var ability_id:    StringName = &""
@export var display_name:  String     = ""
@export var description:   String     = ""
@export var icon:          Texture2D  = null

@export_group("Timing")
@export var cooldown:         float = 0.5
@export var channel_duration: float = 0.0

@export_group("Targeting")
@export var range: float = 2.0

@export_group("Requirements")
## Items pawn must have in inventory to use this ability
@export var require_pawn_has_mode: RequireMode       = RequireMode.ALL
@export var require_pawn_has:      Array[StringName] = []
## Resource ids the context target must have (nectar, pollen, water, etc.)
@export var require_ctx_has_mode:  RequireMode       = RequireMode.ALL
@export var require_ctx_has:       Array[StringName] = []

@export_group("AI")
@export var ai_priority: float = 1.0

# ════════════════════════════════════════════════════════════════════════════ #
#  Requirement helpers — called by subclass can_use()
# ════════════════════════════════════════════════════════════════════════════ #

func _pawn_has_requirements(ctx: AbilityContext) -> bool:
	if require_pawn_has.is_empty():
		return true
	if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
		return require_pawn_has_mode == RequireMode.NONE
	var inv: PawnInventory = ctx.pawn.state.inventory
	match require_pawn_has_mode:
		RequireMode.ALL:
			for item: StringName in require_pawn_has:
				if not inv.has_item(item):
					return false
			return true
		RequireMode.ANY:
			for item: StringName in require_pawn_has:
				if inv.has_item(item):
					return true
			return false
		RequireMode.NONE:
			for item: StringName in require_pawn_has:
				if inv.has_item(item):
					return false
			return true
	return true

func _ctx_has_requirements(ctx: AbilityContext) -> bool:
	if require_ctx_has.is_empty():
		return true
	var cell_state: HexCellState = ctx.get_pawn_cell_state()
	if cell_state == null:
		return require_ctx_has_mode == RequireMode.NONE
	match require_ctx_has_mode:
		RequireMode.ALL:
			for res_id: StringName in require_ctx_has:
				if not _cell_has_resource(cell_state, res_id):
					return false
			return true
		RequireMode.ANY:
			for res_id: StringName in require_ctx_has:
				if _cell_has_resource(cell_state, res_id):
					return true
			return false
		RequireMode.NONE:
			for res_id: StringName in require_ctx_has:
				if _cell_has_resource(cell_state, res_id):
					return false
			return true
	return true

static func _cell_has_resource(state: HexCellState, res_id: StringName) -> bool:
	match res_id:
		&"nectar": return state.nectar_amount > 0.0
		&"pollen": return state.pollen_amount > 0.0 and state.has_pollen
		&"water":  return state.water_amount  > 0.0
		_:         return false

# ════════════════════════════════════════════════════════════════════════════ #
#  Virtual interface
# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	return _pawn_has_requirements(ctx) and _ctx_has_requirements(ctx)

func resolve_target(ctx: AbilityContext) -> Variant:
	return null

func execute(ctx: AbilityContext, target: Variant) -> void:
	pass

func get_prompt(ctx: AbilityContext) -> String:
	return display_name
