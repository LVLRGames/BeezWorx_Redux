# FILE: res://autoloads/hive_system.gd
# Manages all hives, their contents, slots, and colony-wide inventory tracking.
# class_name HiveSystem
extends Node

var _hives: Dictionary[int, HiveState] = {}
var _hives_by_cell: Dictionary[Vector2i, int] = {}
var _next_hive_id: int = 0
var _colony_inventory_cache: Dictionary = {}
var _colony_inventory_dirty: Dictionary = {}

func register_hive(anchor_cell: Vector2i, colony_id: int, builder_pawn_id: int) -> int:
	# TODO: Create and track new HiveState
	return 0

func get_hive(hive_id: int) -> HiveState:
	return null

func get_hives_for_colony(colony_id: int) -> Array[HiveState]:
	return []

func get_capital_hive(colony_id: int) -> HiveState:
	return null

func set_queen_bed(hive_id: int, slot_index: int, queen_pawn_id: int) -> void:
	# TODO: Designate slot as queen's bed
	pass

func get_all_living_hives() -> Array[HiveState]:
	return []

func get_colony_inventory_count(colony_id: int, item_id: StringName) -> int:
	return 0

func find_nearest_hive_with_item(colony_id: int, item_id: StringName, min_count: int, near_cell: Vector2i) -> HiveState:
	return null

func find_nearest_hive_with_storage(colony_id: int, item_id: StringName, near_cell: Vector2i) -> HiveState:
	return null

func withdraw_item(hive_id: int, item_id: StringName, count: int) -> bool:
	return false

func deposit_item(hive_id: int, item_id: StringName, count: int) -> bool:
	return false

func find_sleep_slot(pawn_id: int, colony_id: int, near_cell: Vector2i) -> Vector2i:
	return Vector2i.ZERO

func reserve_sleep_slot(hive_id: int, slot_index: int, pawn_id: int) -> bool:
	return false

func release_sleep_slot(hive_id: int, slot_index: int, pawn_id: int) -> void:
	pass

func apply_damage(hive_id: int, amount: float, attacker_id: int) -> void:
	pass

func repair_hive(hive_id: int, amount: float, repairer_pawn_id: int) -> void:
	pass

func apply_upgrade(hive_id: int, upgrade_type_id: StringName) -> void:
	pass

func get_slot(hive_id: int, slot_index: int) -> HiveSlot:
	return null

func get_slots_by_designation(hive_id: int, designation: int) -> Array[HiveSlot]:
	return []

func get_all_craft_orders(hive_id: int) -> Array[CraftOrder]:
	return []

func get_nursery_eggs(colony_id: int) -> Array[EggState]:
	return []

func emit_slot_changed(hive_id: int, slot_index: int) -> void:
	pass

func save_state() -> Dictionary:
	return {}

func load_state(data: Dictionary) -> void:
	pass
