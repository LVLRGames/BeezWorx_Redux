# FILE: res://autoloads/time_service.gd
# Manages the world clock, day/night cycles, and seasons.
# class_name TimeService
extends Node

const SPRING: int = 0
const SUMMER: int = 1
const FALL: int = 2
const WINTER: int = 3

var config: TimeConfig
var world_time: float = 0.0
var current_day: int = 0
var day_phase: float = 0.0
var is_daytime: bool = true
var day_of_year: int = 0
var current_season: int = SPRING
var current_year: int = 0

var _prev_day: int = 0
var _prev_season: int = SPRING
var _prev_year: int = 0

func initialize(p_config: TimeConfig) -> void:
	# TODO: Initialize clock with config
	pass

func advance(delta: float) -> void:
	# TODO: Advance world time and trigger transitions
	pass

func get_day_phase() -> float:
	return 0.0

func is_night() -> bool:
	return false

func time_until_dawn() -> float:
	return 0.0

func time_until_dusk() -> float:
	return 0.0

func get_current_season_name() -> String:
	return ""

func is_season(season: int) -> bool:
	return false

func day_of_current_season() -> int:
	return 0

func fraction_through_season() -> float:
	return 0.0

func world_time_for_day(p_day: int) -> float:
	return 0.0

func elapsed_days() -> int:
	return 0

func save_state() -> Dictionary:
	return {}

func load_state(data: Dictionary) -> void:
	# TODO: Restore time state
	pass
