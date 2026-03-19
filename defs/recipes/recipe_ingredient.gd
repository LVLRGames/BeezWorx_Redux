# FILE: res://defs/recipes/recipe_ingredient.gd
# Resource for specifying an ingredient in a manufacturing recipe.
class_name RecipeIngredient
extends Resource

@export var item_id: StringName = &""
@export var tag_filter: StringName = &""
@export var count: int = 1
