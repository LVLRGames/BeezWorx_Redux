# pawn_ability_executor.gd
# res://pawns/pawn_ability_executor.gd
#
# Resolves and executes abilities from prioritized lists.
# Both action and alt slots are fully contextual — the first ability
# in each list whose can_use() returns true wins.
#
# RESOLUTION ORDER:
#   For each slot (action / alt):
#     1. Skip if on cooldown
#     2. Call can_use(ctx) — first true wins
#     3. Call resolve_target(ctx)
#     4. Call execute(ctx, target)
#
# AI USAGE:
#   PawnAI can call try_action() / try_alt_action() directly —
#   same path as player input, no separate AI ability execution.
#
# HUD USAGE:
#   Call get_action_prompt() / get_alt_prompt() each frame to get
#   the current winning ability's label for button display.

class_name PawnAbilityExecutor
extends Node

var pawn: PawnBase
var _cooldowns: Dictionary[StringName, float] = {}

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
#  Public API — player / AI input
# ════════════════════════════════════════════════════════════════════════════ #

func try_action() -> bool:
	var ability: AbilityDef = _resolve(pawn.action_abilities)
	if ability == null:
		return false
	return _execute_resolved(ability)

func try_alt_action() -> bool:
	var ability: AbilityDef = _resolve(pawn.alt_abilities)
	if ability == null:
		return false
	return _execute_resolved(ability)

# ── HUD queries ───────────────────────────────────────────────────────────────

func get_action_prompt() -> String:
	var ability: AbilityDef = _resolve(pawn.action_abilities)
	if ability == null:
		return ""
	return ability.get_prompt(make_context())

func get_alt_prompt() -> String:
	var ability: AbilityDef = _resolve(pawn.alt_abilities)
	if ability == null:
		return ""
	return ability.get_prompt(make_context())

## Returns the ability that would fire for action right now, or null.
func peek_action() -> AbilityDef:
	return _resolve(pawn.action_abilities)

## Returns the ability that would fire for alt right now, or null.
func peek_alt() -> AbilityDef:
	return _resolve(pawn.alt_abilities)

## True if any action ability is currently usable.
func has_action() -> bool:
	return _resolve(pawn.action_abilities) != null

## True if any alt ability is currently usable.
func has_alt() -> bool:
	return _resolve(pawn.alt_abilities) != null

# ════════════════════════════════════════════════════════════════════════════ #
#  Resolution
# ════════════════════════════════════════════════════════════════════════════ #

## Returns the first ability in the list whose can_use() passes.
## Returns null if none are usable.
func _resolve(abilities: Array) -> AbilityDef:
	if abilities.is_empty():
		return null
	var ctx: AbilityContext = make_context()
	for entry in abilities:
		var ability: AbilityDef = entry as AbilityDef
		if ability == null:
			continue
		if _on_cooldown(ability.ability_id):
			continue
		if ability.can_use(ctx):
			return ability
	return null

# ════════════════════════════════════════════════════════════════════════════ #
#  Execution
# ════════════════════════════════════════════════════════════════════════════ #

func _execute_resolved(ability: AbilityDef) -> bool:
	var ctx: AbilityContext = make_context()
	# Re-check — context may have changed between resolve and execute
	if not ability.can_use(ctx):
		return false
	var target: Variant = ability.resolve_target(ctx)
	ability.execute(ctx, target)
	if ability.cooldown > 0.0 and ability.ability_id != &"":
		_cooldowns[ability.ability_id] = ability.cooldown
	return true

# ════════════════════════════════════════════════════════════════════════════ #
#  Context
# ════════════════════════════════════════════════════════════════════════════ #

func make_context() -> AbilityContext:
	var ctx := AbilityContext.new()
	ctx.pawn       = pawn
	ctx.pawn_cell  = HexConsts.WORLD_TO_AXIAL(
		pawn.global_position.x,
		pawn.global_position.z
	)
	ctx.world_time = TimeService.world_time
 
	var detector: InteractionDetector = pawn.get_node_or_null("InteractionDetector")
	if detector != null:
		var info: Dictionary = detector.get_current_target()
		match info.get("type", &""):
			&"plant":
				ctx.target_cell = info.get("cell", Vector2i(-9999, -9999))
			&"hive":
				ctx.target_hive_id = info.get("hive_id", -1)
			&"pawn":
				var pid: int = info.get("pawn_id", -1)
				if pid >= 0:
					ctx.target_pawn = PawnRegistry.get_pawn(pid)
 
	# Always resolve nearest hive for deposit range checks
	if pawn.state != null:
		var hives: Array[HiveState] = HiveSystem.get_hives_for_colony(pawn.state.colony_id)
		var best_dist: int = 4
		for hs: HiveState in hives:
			var dist: int = _hex_dist(ctx.pawn_cell, hs.anchor_cell)
			if dist < best_dist:
				best_dist        = dist
				ctx.target_hive_id = hs.hive_id
 
	return ctx


static func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var dq: int = b.x - a.x
	var dr: int = b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


# ════════════════════════════════════════════════════════════════════════════ #
#  Cooldowns
# ════════════════════════════════════════════════════════════════════════════ #

func _on_cooldown(ability_id: StringName) -> bool:
	if ability_id == &"":
		return false
	return _cooldowns.get(ability_id, 0.0) > 0.0

func _tick_cooldowns(delta: float) -> void:
	for id: StringName in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)

func get_cooldown_remaining(ability_id: StringName) -> float:
	return maxf(0.0, _cooldowns.get(ability_id, 0.0))
