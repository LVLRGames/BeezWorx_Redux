# FILE: res://ui/ui_root.gd
# Top-level UI manager coordinating HUD elements and full-screen overlays.
class_name UIRoot
extends CanvasLayer

@onready var pawn_card: Control = null
@onready var compass_strip: Control = null
@onready var season_time_indicator: Control = null
@onready var pawn_switch_panel: Control = null
@onready var inventory_context_panel: Control = null
@onready var marker_info_strip: Control = null
@onready var notification_feed: Control = null
@onready var hive_overlay: Control = null
@onready var colony_management_screen: Control = null
@onready var interaction_prompt: Control = null

func show_hive_overlay(hive_id: int) -> void:
	pass

func hide_hive_overlay() -> void:
	pass

func is_hive_overlay_open() -> bool:
	return false

func show_notification(text: String, duration: float, is_critical: bool) -> void:
	pass

func update_pawn_card(state: PawnState) -> void:
	pass

func open_colony_management() -> void:
	pass

func close_colony_management() -> void:
	pass

func update_interaction_prompt(action_label: String, alt_label: String) -> void:
	pass
