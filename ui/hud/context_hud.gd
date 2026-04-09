# context_hud.gd
# res://ui/hud/context_hud.gd
class_name ContextHUD
extends HBoxContainer

@onready var _context_panel:   ContextPanel   = $ContextPanel
@onready var _action_panel:    ActionPanel    = $ActionPanel
@onready var _inventory_panel: InventoryPanel = $InventoryPanel

var _pawn_id:     int        = -1
var _target_info: Dictionary = {}

func _ready() -> void:
	_context_panel.modulate.a   = 0.0
	_action_panel.modulate.a    = 0.0
	_inventory_panel.modulate.a = 0.0
	EventBus.pawn_possessed.connect(_on_pawn_possessed)
	EventBus.interaction_target_changed.connect(_on_target_changed)

func _setup_for_pawn(pawn_id: int) -> void:
	_pawn_id = pawn_id
	var pawn: PawnBase = PawnRegistry.get_pawn(pawn_id)
	if pawn == null:
		return
	var executor: PawnAbilityExecutor = pawn.get_node_or_null("PawnAbilityExecutor")
	var action_list: Array[AbilityDef] = executor.action_list() if executor else []
	var alt_list:    Array[AbilityDef] = executor.alt_list()    if executor else []
	_action_panel.setup_for_pawn(pawn_id, action_list, alt_list)
	_inventory_panel.set_pawn(pawn_id, PawnRegistry.get_state(pawn_id))

func _refresh() -> void:
	if _pawn_id < 0:
		_fade_all_out()
		return
	var pawn: PawnBase = PawnRegistry.get_pawn(_pawn_id)
	if pawn == null or not is_instance_valid(pawn):
		_fade_all_out()
		return

	# ── Context panel ─────────────────────────────────────────────────────
	var has_target: bool = not _target_info.is_empty() \
		and _target_info.get("type", &"none") != &"none"
	if has_target:
		_context_panel.set_target(_target_info)
		_context_panel.fade_in()
	else:
		_context_panel.fade_out()

	if _target_info.is_empty():
		_action_panel.fade_out()
		_inventory_panel.fade_out()
		return

	# ── Action panel ──────────────────────────────────────────────────────
	var executor: PawnAbilityExecutor = pawn.get_node_or_null("PawnAbilityExecutor")
	if executor == null:
		_action_panel.fade_out()
		_inventory_panel.fade_out()
		return

	var ctx: AbilityContext              = executor.make_context()
	var usable_action: Array[AbilityDef] = _get_usable(executor.action_list(), ctx)
	var usable_alt:    Array[AbilityDef] = _get_usable(executor.alt_list(),    ctx)
	var has_any: bool = not usable_action.is_empty() or not usable_alt.is_empty()

	_action_panel.update_context(usable_action, usable_alt)
	if has_any:
		_action_panel.fade_in()
	else:
		_action_panel.fade_out()

	# ── Inventory panel ───────────────────────────────────────────────────
	if not has_any:
		_inventory_panel.fade_out()
		return

	var needed_item: StringName = _get_required_item(
		_action_panel.get_selected_action(),
		_action_panel.get_selected_alt()
	)
	if needed_item != &"":
		_inventory_panel.filter_to_item(needed_item)
		_inventory_panel.fade_in()
	else:
		_inventory_panel.fade_out()

# ════════════════════════════════════════════════════════════════════════════ #
#  Helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _get_usable(abilities: Array[AbilityDef], ctx: AbilityContext) -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	for ability: AbilityDef in abilities:
		if ability != null and ability.can_use(ctx):
			out.append(ability)
	return out

func _get_required_item(action: AbilityDef, alt: AbilityDef) -> StringName:
	for ability: AbilityDef in [action, alt]:
		if ability == null:
			continue
		var req = ability.get("require_pawn_has")
		if req != null and not (req as Array).is_empty():
			return (req as Array)[0]
	return &""

func _fade_all_out() -> void:
	_context_panel.fade_out()
	_action_panel.fade_out()
	_inventory_panel.fade_out()

# ════════════════════════════════════════════════════════════════════════════ #
#  EventBus
# ════════════════════════════════════════════════════════════════════════════ #

func _on_pawn_possessed(player_slot: int, pawn_id: int) -> void:
	if player_slot != 1:
		return
	_setup_for_pawn(pawn_id)

func _on_target_changed(pawn_id: int, target_info: Dictionary) -> void:
	if pawn_id != _pawn_id:
		return
	_target_info = target_info
	_refresh()
