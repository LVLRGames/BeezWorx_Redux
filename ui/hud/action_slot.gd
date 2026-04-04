# action_slot.gd
# res://ui/hud/action_slot.gd
#
# A single action slot — styled hex cell showing ability icon, name, button prompt.
# Lives inside ActionPanel.
#
# SCENE STRUCTURE:
#   ActionSlot (PanelContainer, this script)
#   ├── HexBG       (TextureRect)   — hex background
#   ├── AbilityIcon (TextureRect)   — ability icon centered
#   └── PromptLabel (Label)         — "[A] Gather Nectar"

class_name ActionSlot
extends PanelContainer

@onready var _hex_bg:      TextureRect = $HexBG
@onready var _ability_icon: TextureRect = $AbilityIcon
@onready var _prompt_label: Label       = $PromptLabel

var _ability: AbilityDef = null

# ════════════════════════════════════════════════════════════════════════════ #
#  Public
# ════════════════════════════════════════════════════════════════════════════ #

func set_ability(ability: AbilityDef, button_prompt: String) -> void:
	_ability = ability
	if ability.icon != null:
		_ability_icon.texture = ability.icon
		_ability_icon.visible = true
	else:
		_ability_icon.visible = false
	_prompt_label.text = "%s %s" % [button_prompt, ability.display_name]

func clear() -> void:
	_ability = null
	_ability_icon.visible = false
	_prompt_label.text    = ""

func get_ability() -> AbilityDef:
	return _ability
