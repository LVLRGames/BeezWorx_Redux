# pawn_ability_executor.gd
# res://pawns/pawn_ability_executor.gd
#
# Handles targeting resolution, cooldown tracking, and ability effect dispatch
# for one pawn. Both player-controlled and AI-controlled pawns use this — there
# is no separate ability path for AI (per spec).
#
# PHASE 1 SCOPE:
#   Implemented effects:
#     GATHER_RESOURCE   — consume pollen or nectar from a plant cell
#     WATER_PLANT       — water a wilting plant
#     POLLINATE         — apply carried pollen to a flowering plant
#     INTERACT_GENERIC  — calls pawn._on_interact_generic(target)
#
#   Stubbed effects (TODO in later phases):
#     PLACE_MARKER, REMOVE_MARKER  — Phase 5 (markers + territory)
#     ATTACK                       — Phase 6 (combat)
#     BUILD_STRUCTURE              — Phase 5 (hive building)
#     CRAFT                        — Phase 4 (hive crafting)
#     OFFER_TRADE                  — Phase 7 (diplomacy)
#     LAY_EGG                      — Phase 9 (lifecycle)
#     POSSESS_PAWN                 — Phase 3 (possession service)
#     ENTER_HIVE, DROP_ITEM        — Phase 4
#
# TARGETING:
#   resolve_target() returns the best target for an ability or null.
#   For WORLD_CELL: returns Vector2i (hex cell).
#   For NEARBY_PAWN: returns PawnBase node.
#   For CONTEXTUAL: scores all valid targets and returns highest priority.
#   For SELF: returns the pawn itself.

class_name PawnAbilityExecutor
extends Node

var pawn: PawnBase
var cooldowns: Dictionary[StringName, float] = {}

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	pawn = get_parent() as PawnBase
	if pawn == null:
		push_error("PawnAbilityExecutor: parent is not a PawnBase")

func _process(delta: float) -> void:
	_tick_cooldowns(delta)

# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

func try_action() -> bool:
	var ability: Resource = pawn.action_ability
	if ability == null:
		# No ability def assigned — fall through to generic interact
		pawn._on_interact_generic(null)
		return true
	return _try_use(ability)

func try_alt_action() -> bool:
	var ability: Resource = pawn.alt_ability
	if ability == null:
		return false
	return _try_use(ability)

func try_interact() -> bool:
	var ability: Resource = pawn.interact_ability
	if ability == null:
		return false
	return _try_use(ability)

func can_use(ability: Resource) -> bool:
	if ability == null:
		return false
	var ability_id: StringName = ability.get("ability_id")
	if cooldowns.has(ability_id) and cooldowns[ability_id] > 0.0:
		return false
	# TODO Phase 3: check fatigue, pawn.state.is_awake, stamina_cost
	return true

func resolve_target(ability: Resource) -> Variant:
	if ability == null:
		return null

	var targeting_mode: int = ability.get("targeting_mode")
	if targeting_mode == null:
		return null

	# AbilityDef.TargetingMode enum values (from scaffold):
	# SELF=0, WORLD_CELL=1, NEARBY_ITEM=2, NEARBY_PAWN=3,
	# INVENTORY_ITEM=4, CONTEXTUAL=5, HIVE_SLOT=6
	match targeting_mode:
		0: # SELF
			return pawn

		1: # WORLD_CELL
			return _resolve_world_cell(ability)

		3: # NEARBY_PAWN
			return _resolve_nearby_pawn(ability)

		5: # CONTEXTUAL
			return _resolve_contextual()

		_:
			return null

func execute(ability: Resource, target: Variant) -> void:
	if ability == null:
		return

	var effect_type: int = ability.get("effect_type")
	if effect_type == null:
		return

	# AbilityDef.AbilityEffectType enum values (from scaffold):
	# GATHER_RESOURCE=0, DROP_ITEM=1, PLACE_MARKER=2, REMOVE_MARKER=3,
	# ATTACK=4, CRAFT=5, POLLINATE=6, WATER_PLANT=7, BUILD_STRUCTURE=8,
	# ENTER_HIVE=9, OFFER_TRADE=10, LAY_EGG=11, POSSESS_PAWN=12, INTERACT_GENERIC=13
	match effect_type:
		0: # GATHER_RESOURCE
			_execute_gather(ability, target)
		6: # POLLINATE
			_execute_pollinate(target)
		7: # WATER_PLANT
			_execute_water(target)
		13: # INTERACT_GENERIC
			pawn._on_interact_generic(target)
		2, 3: # PLACE_MARKER, REMOVE_MARKER
			push_warning("PawnAbilityExecutor: markers not implemented until Phase 5")
		4: # ATTACK
			push_warning("PawnAbilityExecutor: combat not implemented until Phase 6")
		5: # CRAFT
			push_warning("PawnAbilityExecutor: crafting not implemented until Phase 4")
		10: # OFFER_TRADE
			push_warning("PawnAbilityExecutor: trade not implemented until Phase 7")
		11: # LAY_EGG
			push_warning("PawnAbilityExecutor: egg laying not implemented until Phase 9")
		12: # POSSESS_PAWN
			push_warning("PawnAbilityExecutor: possession not implemented until Phase 3")
		_:
			push_warning("PawnAbilityExecutor: unhandled effect_type %d" % effect_type)

	# Start cooldown
	var ability_id: StringName = ability.get("ability_id")
	var cooldown: float = ability.get("cooldown")
	if ability_id and cooldown > 0.0:
		cooldowns[ability_id] = cooldown

# ════════════════════════════════════════════════════════════════════════════ #
#  Internal
# ════════════════════════════════════════════════════════════════════════════ #

func _try_use(ability: Resource) -> bool:
	if not can_use(ability):
		return false
	var target: Variant = resolve_target(ability)
	# null target is valid for SELF abilities
	execute(ability, target)
	return true

func _tick_cooldowns(delta: float) -> void:
	for ability_id: StringName in cooldowns.keys():
		cooldowns[ability_id] -= delta
		if cooldowns[ability_id] <= 0.0:
			cooldowns.erase(ability_id)

# ── Target resolvers ──────────────────────────────────────────────────────────

func _resolve_world_cell(ability: Resource) -> Variant:
	if not pawn.selector:
		return null

	var cell := HexConsts.WORLD_TO_AXIAL(
		pawn.selector.global_position.x,
		pawn.selector.global_position.z
	)

	# Range check — selector position vs pawn position
	var selector_world := pawn.selector.global_position
	var dist: float = pawn.global_position.distance_to(selector_world)
	var range_val: float = ability.get("range")
	if range_val != null and dist > range_val:
		return null

	# Category filter
	var valid_categories: Array = ability.get("valid_categories")
	if valid_categories != null and not valid_categories.is_empty():
		var cell_state: HexCellState = HexWorldState.get_cell(cell)
		if not valid_categories.has(cell_state.category):
			return null

	return cell

func _resolve_nearby_pawn(_ability: Resource) -> Variant:
	# TODO Phase 3: query InteractionDetector for pawns in range matching tags
	return null

func _resolve_contextual() -> Variant:
	# Contextual targeting for queen: score targets by priority.
	# Phase 1: fall back to world cell under selector.
	# Phase 3: replace with full InteractionDetector priority scoring per spec.
	if not pawn.selector:
		return null
	return HexConsts.WORLD_TO_AXIAL(
		pawn.selector.global_position.x,
		pawn.selector.global_position.z
	)

# ── Effect executors ──────────────────────────────────────────────────────────

func _execute_gather(ability: Resource, target: Variant) -> void:
	if not (target is Vector2i):
		return

	var cell: Vector2i     = target
	var cell_state: HexCellState = HexWorldState.get_cell(cell)
	if not cell_state.occupied:
		return
	if cell_state.category != HexGridObjectDef.Category.RESOURCE_PLANT:
		return

	var item_id: StringName = ability.get("item_id")

	match cell_state.stage:
		HexWorldState.Stage.FLOWERING:
			var pollen: float = cell_state.pollen_amount
			if pollen > 0.0:
				HexWorldState.consume_pollen(cell, pollen * 0.25)
				if pawn.selector:
					pawn.selector.bounce_cell()
				# TODO Phase 3: add to PawnInventory instead of bee-specific fields
				if pawn.has_method("_collect_pollen"):
					pawn.call("_collect_pollen", cell, cell_state)

		HexWorldState.Stage.FRUITING:
			var nectar: float = cell_state.nectar_amount
			if nectar > 0.0:
				# TODO Phase 3: use PawnInventory capacity
				HexWorldState.consume_nectar(cell, minf(nectar, 5.0))
				if pawn.selector:
					pawn.selector.bounce_cell()

func _execute_pollinate(target: Variant) -> void:
	if not (target is Vector2i):
		return
	# TODO Phase 3: read carried pollen from PawnInventory
	# For now the bee._pollinate fallback handles this via _on_interact_generic
	pawn._on_interact_generic(target)

func _execute_water(target: Variant) -> void:
	if not (target is Vector2i):
		return
	var cell: Vector2i = target
	var cell_state: HexCellState = HexWorldState.get_cell(cell)
	if not cell_state.occupied:
		return
	if cell_state.stage == HexWorldState.Stage.WILT:
		HexWorldState.water_plant(cell)
