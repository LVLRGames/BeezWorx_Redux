# FILE: res://defs/time_config.gd
# Global settings for the passage of time and seasonal transitions.
class_name TimeConfig
extends Resource

@export var day_length_seconds: float = 600.0
@export var days_per_season: int = 91
@export var day_night_split: float = 0.6
@export var time_scale: float = 1.0
