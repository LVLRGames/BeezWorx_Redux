# FILE: res://autoloads/save_manager.gd
# Orchestrates game persistence, versioning, and state migration.
class_name SaveManager
extends Node

const SAVE_DIR: String = "user://saves/"
const SAVE_EXTENSION: String = ".json"
const AUTOSAVE_SLOT: String = "autosave"
const MAX_SAVE_SLOTS: int = 10
const CURRENT_VERSION: String = "0.1.0"

var _active_slot: String = ""
var _autosave_timer: float = 0.0
var _autosave_interval: float = 300.0
var _is_saving: bool = false
var _is_loading: bool = false
var _total_play_time: float = 0.0

func save_game(slot_name: String) -> bool:
	# TODO: Collect state from all systems and write to disk
	return false

func load_game(slot_name: String) -> bool:
	# TODO: Read from disk and distribute state to systems
	return false

func delete_save(slot_name: String) -> void:
	pass

func get_save_slots() -> Array[String]:
	return []

func has_save(slot_name: String) -> bool:
	return false

func get_active_slot() -> String:
	return ""

func start_new_game(config: Dictionary) -> void:
	# TODO: Initialize systems for fresh session
	pass
