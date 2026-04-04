# action_panel.gd
class_name ActionPanel
extends HBoxContainer

@onready var _action_slot: AbilitySlot = $ActionSlot
@onready var _alt_slot:    AbilitySlot = $AltSlot

var _pawn_id: int  = -1
var _ft:      Tween = null

func fade_in() -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", 1.0, 0.25)

func fade_out() -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", 0.0, 0.25)

func setup_for_pawn(pawn_id: int,
	action_abilities: Array[AbilityDef],
	alt_abilities:    Array[AbilityDef]) -> void:
	_pawn_id = pawn_id
	_action_slot.setup_for_pawn(pawn_id, action_abilities)
	_alt_slot.setup_for_pawn(pawn_id, alt_abilities)

func update_context(usable_action: Array[AbilityDef], usable_alt: Array[AbilityDef]) -> void:
	_action_slot.update_usable(usable_action)
	_alt_slot.update_usable(usable_alt)
	if not usable_action.is_empty():
		_action_slot.fade_in()
	else:
		_action_slot.fade_out()
	if not usable_alt.is_empty():
		_alt_slot.fade_in()
	else:
		_alt_slot.fade_out()

func get_selected_action() -> AbilityDef:
	return _action_slot.get_selected_ability()

func get_selected_alt() -> AbilityDef:
	return _alt_slot.get_selected_ability()

func set_pawn(pawn_id: int) -> void:
	_pawn_id = pawn_id
