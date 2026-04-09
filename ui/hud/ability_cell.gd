@tool
class_name AbilityCell
extends Control

@onready var _hex_bg:     TextureRect   = $HexBG
@onready var _icon:       TextureRect   = $AbilityIcon
@onready var _name_label: RichTextLabel = $NameLabel

var _ability:   AbilityDef = null
var _ft:        Tween      = null  # fade tween
var _st:        Tween      = null  # selection tween

func set_ability(ability: AbilityDef) -> void:
	_ability = ability
	if not is_node_ready():
		await ready
	if ability == null:
		set_empty()
		return
	if ability.icon != null:
		_icon.texture = ability.icon
	else:
		_icon.texture = null
	_icon.visible   = ability.icon != null
	var words       := ability.display_name.split(" ", false)
	_name_label.text    = words[0] if words.size() > 0 else ""
	_name_label.visible = true

func set_empty() -> void:
	_ability = null
	if not is_node_ready():
		await ready
	_icon.visible       = false
	_name_label.text    = ""
	_name_label.visible = false

func set_selected(selected: bool) -> void:
	var target := Color(1.3, 1.15, 0.7, 1.0) if selected else Color(1, 1, 1, 1)
	if _st: _st.kill()
	_st = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_st.tween_property(_hex_bg, "modulate", target, 0.15)

func fade_in() -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", 1.0, 0.2)

func fade_out(hide_after: bool = false) -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", 0.0, 0.2)
	if hide_after:
		_ft.tween_callback(func(): visible = false)

func fade_to(alpha: float) -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", alpha, 0.2)

func get_ability() -> AbilityDef:
	return _ability
