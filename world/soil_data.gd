# soil_data.gd
# res://defs/world/soil_data.gd
#
# Per-biome baseline soil parameters. Attached to HexBiome.soil_profile.
# Resolved soil state (after delta overrides) is stored on HexCellState.
#
# AUTHORING:
#   Create one .tres per biome where soil character matters.
#   Biomes without a soil_profile fall back to LOAM / wetness 0.5 / toxicity 0.0.
#
# GRASS WILT THRESHOLDS (from HexPlantData):
#   wilt_wetness_min  = 0.05  → grass only wilts in near-desert dryness
#   wilt_toxicity_max = 0.85  → grass only dies under extreme contamination
#
# TYPICAL VALUES BY SOIL TYPE:
#   LOAM:         base_wetness 0.5,  base_toxicity 0.0  — balanced, most plants thrive
#   CLAY:         base_wetness 0.65, base_toxicity 0.0  — wet, slow drainage
#   SAND:         base_wetness 0.25, base_toxicity 0.0  — dry, fast drainage
#   GRAVEL:       base_wetness 0.15, base_toxicity 0.0  — very dry, harsh
#   VOLCANIC:     base_wetness 0.35, base_toxicity 0.35 — nutrient-rich but toxic
#   CONTAMINATED: base_wetness 0.40, base_toxicity 0.90 — event-driven; most plants die
#
# WEATHER STUB:
#   drainage_rate will be read by a future WeatherSystem to decay wetness_override
#   back toward base_wetness over time. Not used until weather is implemented.

class_name SoilData
extends Resource

enum SoilType {
	LOAM,         # balanced; good for most plants
	CLAY,         # retains water well; slow drainage
	SAND,         # poor water retention; drains fast
	GRAVEL,       # very low retention; harsh on plants
	VOLCANIC,     # nutrient-rich but elevated base toxicity
	CONTAMINATED, # event-driven; high toxicity; most plants die
}

## Baseline soil composition for this biome.
@export var soil_type:     SoilType = SoilType.LOAM

## Baseline moisture level. 0.0 = bone dry, 1.0 = waterlogged.
## Individual cells are noise-perturbed around this value in HexWorldBaseline.
@export_range(0.0, 1.0, 0.01)
@export var base_wetness:  float    = 0.5

## Baseline toxicity. 0.0 = clean, 1.0 = fully toxic.
## Normally 0 except for VOLCANIC and CONTAMINATED types.
@export_range(0.0, 1.0, 0.01)
@export var base_toxicity: float    = 0.0

## How fast wetness_override decays toward base_wetness per in-game day.
## 0.1 = 10% recovery per day. Stubbed — not consumed until WeatherSystem exists.
@export_range(0.0, 1.0, 0.01)
@export var drainage_rate: float    = 0.1
