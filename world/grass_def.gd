# grass_def.gd
# res://defs/plants/grass_def.gd
#
# Grass is a PLANT with subcategory GRASS.
# Structurally identical to HexPlantDef — no new fields needed.
# All grass behaviour comes from:
#   1. plant_subcategory = GRASS  (routing, damage targeting)
#   2. pollen_species_tag = "grass"  (pollen isolation)
#   3. can_hybridize_across_species = false  (no cross-type hybrids)
#   4. Attached HexPlantData with grass-tuned stage durations and soil wilt flags
#
# AUTHORING GRASS DEF .tres FILES:
#   plant_subcategory          = GRASS
#   max_health                 = 50.0
#   toughness                  = 0.6
#   pollen_species_tag         = "grass"
#   can_hybridize_across_species = false
#   drop_item_id               = "plant_fiber"  (or empty if grass drops nothing)
#   drop_count                 = 1
#
#   plant_data (HexPlantData):
#     wilt_without_water       = false
#     soil_wilt_enabled        = true
#     wilt_wetness_min         = 0.05
#     wilt_toxicity_max        = 0.85
#     max_fruit_cycles         = 99
#     nectar_per_fruit         = 0.1
#     base_nectar_yield        = 0.05
#     sprout_chance            = 0.45
#     sprout_radius            = 2
#     stage_durations: see plant_system_overhaul_spec.md §6
#
# RENDERING:
#   Grass subcategory maps to the existing grass multimesh system in HexChunk.
#   Individual grass cells are a logical layer — health/lifecycle tracking only.
#   Shader receives health_remaining as a 0..1 value: damaged grass desaturates.
#   Stage DEAD suppresses grass rendering for that cell entirely.

class_name GrassDef
extends HexPlantDef

func _init() -> void:
	category          = Category.PLANT
	plant_subcategory = PlantSubcategory.GRASS
	pollen_species_tag           = &"grass"
	can_hybridize_across_species = false
	max_health        = 50.0
	toughness         = 0.6
