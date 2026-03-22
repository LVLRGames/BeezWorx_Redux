# bee.gd
# res://pawns/bee/bee.gd
#
# Generic bee pawn. Inherits PawnFlyer. Role is entirely data-driven via
# RoleDef and AbilityDef resources — no subclasses per role.
#
# VISUAL DIFFERENTIATION (per spec):
#   Scale, color variation, and equipment accessory slots are configured
#   in the scene and/or driven by PawnState/SpeciesDef at spawn time.
#   The queen is this same scene with a larger scale, queen ability defs,
#   and a crown in the crown equipment slot.
#
# INTERACTION:
#   interact() and alt_interact() on PawnBase delegate to PawnAbilityExecutor.
#   Bee-specific fallback is kept here for Phase 1 until AbilityDef resources
#   are authored. Once ability defs exist, the fallback block can be removed.

class_name Bee
extends PawnFlyer

# ── Flight tuning overrides ───────────────────────────────────────────────────
@export var vertical_speed: float = 14.0
@export var max_roll:       float = 45.0

# ── Carried resources (Phase 1 interim — moves to PawnInventory in Phase 3) ──
var carried_pollen: Dictionary = {}  # {source_cell, object_id, genes}
var carried_nectar: float      = 0.0
var max_nectar:     float      = 10.0

var linear_velocity:float = 0.0
const POLLEN_COLLECT_AMOUNT: float = 0.25

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	# Map bee-specific tuning onto PawnFlyer knobs
	vertical_accel_scale = vertical_speed
	max_roll_deg         = max_roll
	super()

func _process(_delta: float) -> void:
	pass

# ════════════════════════════════════════════════════════════════════════════ #
#  Ability fallback (Phase 1)
#
#  PawnAbilityExecutor.try_action() is called by PawnBase.interact().
#  If no AbilityDef is set on action_ability, executor calls
#  pawn._on_interact_generic(target) as a fallback.
#  The logic below implements that fallback directly on the bee.
#  Phase 3: replace with authored AbilityDef resources and remove this block.
# ════════════════════════════════════════════════════════════════════════════ #

func _on_interact_generic(_target: Variant) -> void:
	_bee_interact()

func _bee_interact() -> void:
	if not selector:
		return
	var cell := HexConsts.WORLD_TO_AXIAL(
		selector.global_position.x,
		selector.global_position.z
	)
	var state_ref: HexCellState = HexWorldState.get_cell(cell)
	if not state_ref.occupied:
		return
	if state_ref.category != HexGridObjectDef.Category.RESOURCE_PLANT:
		return

	match state_ref.stage:
		HexWorldState.Stage.FLOWERING:
			if carried_pollen.is_empty():
				_collect_pollen(cell, state_ref)
			else:
				_pollinate(cell, state_ref)
		HexWorldState.Stage.FRUITING:
			_collect_nectar(cell, state_ref)

func _bee_alt_interact() -> void:
	if not selector:
		return
	var cell := HexConsts.WORLD_TO_AXIAL(
		selector.global_position.x,
		selector.global_position.z
	)
	var state_ref: HexCellState = HexWorldState.get_cell(cell)
	if not state_ref.occupied:
		return
	if state_ref.stage == HexWorldState.Stage.WILT:
		HexWorldState.water_plant(cell)

# ── Resource collection helpers ───────────────────────────────────────────────

func _collect_pollen(cell: Vector2i, plant_state: HexCellState) -> void:
	var pollen: float = plant_state.pollen_amount
	if pollen <= 0.0:
		return
	carried_pollen = {
		"source_cell": cell,
		"object_id":   plant_state.object_id,
		"genes":       plant_state.genes,
	}
	HexWorldState.consume_pollen(cell, pollen * POLLEN_COLLECT_AMOUNT)
	if selector:
		selector.bounce_cell()

func _pollinate(cell: Vector2i, plant_state: HexCellState) -> void:
	if cell == carried_pollen.get("source_cell"):
		return
	if plant_state.pollen_amount <= 0.0:
		return
	HexWorldState.apply_pollen(carried_pollen["source_cell"], cell)
	if selector:
		selector.bounce_cell()
	carried_pollen.clear()

func _collect_nectar(cell: Vector2i, plant_state: HexCellState) -> void:
	var nectar: float = plant_state.nectar_amount
	if nectar <= 0.0:
		return
	var space: float = max_nectar - carried_nectar
	if space <= 0.0:
		return
	var take: float = minf(nectar, space)
	carried_nectar += take
	HexWorldState.consume_nectar(cell, take)
	if selector:
		selector.bounce_cell()

# ════════════════════════════════════════════════════════════════════════════ #
#  PawnBase required override
# ════════════════════════════════════════════════════════════════════════════ #

func get_pawn_info() -> String:
	var role_name: String = "Bee"
	if role_def and role_def.get("display_name"):
		role_name = role_def.display_name

	var text := "--- %s ---" % role_name
	if carried_pollen.is_empty():
		text += "\nPollen: None"
	else:
		text += "\nPollen: %s" % carried_pollen.get("object_id", "?")
	text += "\nNectar: %.1f / %.1f" % [carried_nectar, max_nectar]
	return text
