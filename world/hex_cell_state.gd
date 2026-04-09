# hex_cell_state.gd
# Read-only output object produced by HexWorldSimulation and cached in HexWorldState.
# Never mutate this directly — use HexWorldState mutation API.

class_name HexCellState
extends RefCounted

var occupied:          bool             = false
var origin:            Vector2i         = Vector2i.ZERO
var object_id:         String           = ""
var definition:        HexGridObjectDef = null
var category:          int              = -1   # HexGridObjectDef.Category int
var source:            StringName       = &"baseline"

# ── Slot (plant system overhaul) ──────────────────────────────────────
## Which slot (0-5) within the cell this occupant lives in.
## -1 = not yet assigned (non-slot objects, legacy compat).
var slot_index:        int              = -1

# ── Plant type ────────────────────────────────────────────────────────
## HexPlantDef.PlantSubcategory int. -1 for non-plant cells.
var plant_subcategory: int              = -1

# ── Plant lifecycle ───────────────────────────────────────────────────
var stage:             int              = -1
var genes:             HexPlantGenes   = null
var thirst:            float           = 0.0
var has_pollen:        bool            = false
var pollen_amount:     float           = 0.0
var nectar_amount:     float           = 0.0
var fruit_cycles_done: int             = 0
var birth_time:        float           = 0.0
## HexConsts.PlantVariant int. -1 = use NORMAL.
var plant_variant:     int             = -1

# ── Plant health ──────────────────────────────────────────────────────
## Current health. -1.0 = full health (delta sentinel — not yet damaged).
## Read max_health from (definition as HexPlantDef).max_health.
var health_remaining:  float           = -1.0

# ── Soil state ────────────────────────────────────────────────────────
## SoilData.SoilType int. -1 = no soil profile resolved.
var soil_type:         int             = -1
## Resolved moisture: biome baseline + delta wetness_override. 0.0–1.0.
var soil_wetness:      float           = 0.5
## Resolved toxicity: biome baseline + delta toxicity_override. 0.0–1.0.
var soil_toxicity:     float           = 0.0

# ════════════════════════════════════════════════════════════════════ #
#  Convenience accessors
# ════════════════════════════════════════════════════════════════════ #

## True if this cell has a living plant that can be damaged.
func is_damageable_plant() -> bool:
	return occupied \
		and category == HexGridObjectDef.Category.PLANT \
		and stage != HexWorldState.Stage.DEAD

## Resolved current health. Returns def.max_health when at sentinel (-1.0).
func get_health() -> float:
	if health_remaining >= 0.0:
		return health_remaining
	if definition is HexPlantDef:
		return (definition as HexPlantDef).max_health
	return 0.0

## Resolved max health from def. Returns 0 for non-plants.
func get_max_health() -> float:
	if definition is HexPlantDef:
		return (definition as HexPlantDef).max_health
	return 0.0

## Health as 0..1 fraction. Useful for shader COLOR channel.
func get_health_fraction() -> float:
	var mx: float = get_max_health()
	if mx <= 0.0:
		return 1.0
	return clampf(get_health() / mx, 0.0, 1.0)

# ════════════════════════════════════════════════════════════════════ #
#  Duplication / serialization
# ════════════════════════════════════════════════════════════════════ #

func duplicate_state() -> HexCellState:
	var s                  := HexCellState.new()
	s.occupied              = occupied
	s.origin                = origin
	s.object_id             = object_id
	s.definition            = definition
	s.category              = category
	s.source                = source
	s.slot_index            = slot_index
	s.plant_subcategory     = plant_subcategory
	s.stage                 = stage
	s.genes                 = genes
	s.thirst                = thirst
	s.has_pollen            = has_pollen
	s.pollen_amount         = pollen_amount
	s.nectar_amount         = nectar_amount
	s.fruit_cycles_done     = fruit_cycles_done
	s.birth_time            = birth_time
	s.plant_variant         = plant_variant
	s.health_remaining      = health_remaining
	s.soil_type             = soil_type
	s.soil_wetness          = soil_wetness
	s.soil_toxicity         = soil_toxicity
	return s


func to_dict() -> Dictionary:
	return {
		"occupied":          occupied,
		"origin":            origin,
		"object_id":         object_id,
		"category":          category,
		"plant_subcategory": plant_subcategory,
		"slot_index":        slot_index,
		"source":            source,
		"stage":             stage,
		"thirst":            thirst,
		"has_pollen":        has_pollen,
		"pollen_amount":     pollen_amount,
		"nectar_amount":     nectar_amount,
		"fruit_cycles_done": fruit_cycles_done,
		"birth_time":        birth_time,
		"plant_variant":     plant_variant,
		"health_remaining":  health_remaining,
		"soil_type":         soil_type,
		"soil_wetness":      soil_wetness,
		"soil_toxicity":     soil_toxicity,
	}

# ── Colony-layer occupant (world layer never reads this) ──────────────
## Set by HexWorldState.set_occupant_data(). Null for unclaimed cells.
## Only written from the main thread. Never read by terrain generation.
var occupant_data: CellOccupantData = null
