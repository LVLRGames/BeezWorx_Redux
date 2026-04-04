@tool
class_name InventoryCell
extends Control

@onready var _hex_bg:      TextureRect   = $HexBG
@onready var _item_icon:   TextureRect   = $ItemIcon
@onready var _stack_count: RichTextLabel = $StackCount

var item_id: StringName = &""
var count:   int        = 0
var _ft:     Tween      = null  # fade tween
var _st:     Tween      = null  # selection tween

func set_item(p_item_id: StringName, p_count: int, icon: Texture2D = null) -> void:
	item_id = p_item_id
	count   = p_count
	if not is_node_ready():
		await ready
	_item_icon.texture   = icon
	_item_icon.visible   = icon != null
	_stack_count.text    = str(count) if count > 1 else ""
	_stack_count.visible = count > 1

func set_empty() -> void:
	item_id = &""
	count   = 0
	if not is_node_ready():
		await ready
	_item_icon.visible   = false
	_stack_count.text    = ""
	_stack_count.visible = false

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

func set_dimmed(_d: bool) -> void:
	pass  # handled via fade_to
