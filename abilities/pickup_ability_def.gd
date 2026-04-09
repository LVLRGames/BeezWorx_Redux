# pickup_ability_def.gd
# res://abilities/pickup_ability_def.gd
#
# Finds and collects the nearest ItemGem within pickup_radius.
# Uses the "item_gems" group — ItemGem adds itself to this group in _ready().
#
# AUTHORING:
#   Create pickup_item.tres (PickupAbilityDef):
#     ability_id    = &"pickup_item"
#     display_name  = "Pick Up"
#     pickup_radius = 4.0
#     cooldown      = 0.3
#
#   Assign to ant's action_abilities in the Inspector (before or after
#   gather_nectar / gather_pollen, depending on priority order you want).
#
# DEPOSIT:
#   The ant already has hive_deposit.tres in alt_abilities — no change needed.
#   Pickup → carry in inventory → walk to hive → alt to deposit.

class_name PickupAbilityDef
extends AbilityDef

## Max distance in world units from the pawn to pick up a gem.
@export var pickup_radius: float = 4.0

# ════════════════════════════════════════════════════════════════════════════ #

func can_use(ctx: AbilityContext) -> bool:
	if ctx.pawn.state == null or ctx.pawn.state.inventory == null:
		return false
	if ctx.pawn.state.inventory.is_full():
		return false
	return _find_nearest_gem(ctx) != null


func resolve_target(ctx: AbilityContext) -> Variant:
	return _find_nearest_gem(ctx)


func execute(ctx: AbilityContext, target: Variant) -> void:
	if not target is ItemGem:
		return
	var gem: ItemGem = target as ItemGem
	if not is_instance_valid(gem):
		return
	gem.collect(ctx.pawn)


func get_prompt(ctx: AbilityContext) -> String:
	var gem: ItemGem = _find_nearest_gem(ctx)
	if gem == null:
		return ""
	var name: String = ItemRegistry.get_display_name(gem.item_id) \
		if ItemRegistry else String(gem.item_id)
	return "Pick Up %s" % name

# ── Internal ──────────────────────────────────────────────────────────────────

func _find_nearest_gem(ctx: AbilityContext) -> ItemGem:
	var gems: Array[Node] = ctx.pawn.get_tree().get_nodes_in_group("item_gems")
	var best: ItemGem     = null
	var best_dist: float  = pickup_radius * pickup_radius   # compare squared

	for node: Node in gems:
		var gem: ItemGem = node as ItemGem
		if gem == null or not is_instance_valid(gem):
			continue
		var dist: float = ctx.pawn.global_position.distance_squared_to(gem.global_position)
		if dist < best_dist:
			best_dist = dist
			best      = gem

	return best
