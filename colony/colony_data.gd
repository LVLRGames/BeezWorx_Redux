# FILE: res://colony/colony_data.gd
# Comprehensive data container for a single colony/faction.
class_name ColonyData
extends RefCounted


var colony_id: int = 0
var display_name: String = ""
var queen_pawn_id: int = 0
var heir_ids: Array[int] = []
var contest_active: bool = false
var contest_day: int = 0
var queen_history: Array[QueenRecord] = []
var known_recipe_ids: Array[StringName] = []
var known_plants: Array[StringName] = []
var known_items: Array[StringName] = []
var discovered_biomes: Array[StringName] = []
var known_anchor_types: Array[StringName] = []

var _loyalty_cache: Dictionary[int, float] = {}
var _morale_cache: float = 1.0
var _morale_dirty: bool = true
var _morale_modifiers: Array[MoraleModifier] = []
var faction_relations: Dictionary[StringName, FactionRelation] = {}
var _influence_score: float = 0.0
var _influence_dirty: bool = true

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> ColonyData:
	return null
