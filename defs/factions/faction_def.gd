# FILE: res://defs/factions/faction_def.gd
# Social and diplomatic configuration for a group or species.
class_name FactionDef
extends Resource

@export var faction_id: StringName = &""
@export var display_name: String = ""
@export var species_id: StringName = &""
@export var home_biomes: Array[StringName] = []
@export var is_unique: bool = false

@export_group("Preferences")
@export var pref_n_sweetness: float = 0.0
@export var pref_n_heat: float = 0.0
@export var pref_n_cool: float = 0.0
@export var pref_n_vigor: float = 0.0
@export var pref_n_calm: float = 0.0
@export var pref_p_protein: float = 0.0
@export var pref_p_lipid: float = 0.0
@export var pref_p_mineral: float = 0.0
@export var preferred_product_tag: StringName = &""

@export_group("Diplomacy")
@export var gift_sensitivity: float = 1.0
@export var gift_interval_days: int = 1
@export var decay_rate_per_day: float = 0.01
@export var min_match_for_effect: float = 0.5
@export var ally_threshold: float = 0.8
@export var hostile_threshold: float = 0.2

@export_group("Services")
@export var service_type: StringName = &""
@export_multiline var service_description: String = ""

@export_group("Dialogue")
@export var dialogue_set: Resource = null
@export var greeting_line: String = ""
@export var ally_greeting: String = ""
@export var hostile_warning: String = ""

@export_group("Behavior")
@export var will_approach_colony: bool = true
@export var patrol_territory: bool = false
@export var relocates_seasonally: bool = false
@export var reaction_to_raid_nearby: int = 0
@export var gift_memory_days: int = 7
