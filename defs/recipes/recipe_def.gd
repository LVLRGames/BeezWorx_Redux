# FILE: res://defs/recipes/recipe_def.gd
# Configuration for crafting operations in hives or processing stations.
class_name RecipeDef
extends Resource


@export var recipe_id: StringName = &""
@export var display_name: String = ""
@export var ingredients: Array[RecipeIngredient] = []
@export var output_item_id: StringName = &""
@export var output_count: int = 1
@export var output_quality: int = 1
@export var required_role_tags: Array[StringName] = []
@export var craft_time: float = 5.0
@export var requires_hive_slot: bool = true
@export var required_station_tags: Array[StringName] = []
@export var is_discoverable: bool = true
@export var discovery_hint: String = ""
@export var channel_output_map: Dictionary = {}
