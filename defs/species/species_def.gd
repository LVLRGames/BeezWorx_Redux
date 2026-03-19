# FILE: res://defs/species/species_def.gd
# Base biological constraints and capabilities for a taxonomic group.
class_name SpeciesDef
extends Resource

@export var species_id: StringName = &""
@export var display_name: String = ""
@export_enum("Grounded:0", "Flying:1", "Climbing:2") var movement_type: int = 0
@export var move_speed: float = 5.0
@export var max_health: float = 100.0
@export var base_defence_mult: float = 1.0
@export var base_lifespan_days: int = 30
@export var lifespan_variance_days: int = 5
@export var min_lifespan_days: int = 10
@export var stubbornness_lifespan_bonus: int = 5
@export var fatigue_rate: float = 1.0
@export var rest_rate: float = 2.0
@export var carry_capacity: int = 20
@export var reveal_radius: int = 5
@export var alert_radius: int = 10
@export var possession_speed_boost: float = 1.2
@export var possession_action_boost: float = 1.2
@export var carry_weight_speed_curve: Curve = null
@export var water_capacity: float = 50.0
@export var lay_egg_cost: float = 20.0
@export var hive_destruction_survival_chance: float = 0.5
