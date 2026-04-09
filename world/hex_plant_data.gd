# hex_plant_data.gd
# Lifecycle and farming parameters for any HexPlantDef.
# Shared across all individuals of that def.
#
# STAGE ORDER (indices match HexWorldState.Stage enum):
#   0 SEED → 1 SPROUT → 2 GROWTH → 3 FLOWERING → 4 FRUITING → 5 IDLE
#   The FLOWERING→FRUITING→IDLE cycle repeats max_fruit_cycles times,
#   then: 6 WILT → 7 DEAD
#
# WILT SOURCES (two independent paths, both checked by HexWorldSimulation):
#   1. Water timer: wilt_without_water = true → tracks time since last_watered.
#   2. Soil conditions: soil_wilt_enabled = true → checks resolved soil_wetness
#      and soil_toxicity against thresholds. Used by grass and soil-sensitive plants.
#
# GRASS DEFAULTS (see GrassDef and plant_system_overhaul_spec.md §6):
#   wilt_without_water = false
#   soil_wilt_enabled  = true
#   max_fruit_cycles   = 99
#   nectar_per_fruit   = 0.1
#   sprout_chance      = 0.45
#
# TREE DEFAULTS:
#   max_fruit_cycles = 999  (effectively infinite cycling, never reaches WILT)
#   wilt_without_water = false
#   soil_wilt_enabled  = false
#   (is_permanent on HexGridObjectDef suppresses WILT/DEAD stage entirely)

class_name HexPlantData
extends Resource

# ── Stage durations (world-seconds) ───────────────────────────────────
## One entry per stage in the Stage enum order.
## Index: 0=SEED, 1=SPROUT, 2=GROWTH, 3=FLOWERING, 4=FRUITING, 5=IDLE, 6=WILT, 7=DEAD
## Base durations — multiplied by genes.cycle_speed at runtime.
@export var stage_durations: Array[float] = [
	0.0,    # SEED     (not used in baseline generation; sprouts start at SPROUT)
	60.0,   # SPROUT
	120.0,  # GROWTH
	180.0,  # FLOWERING
	120.0,  # FRUITING
	60.0,   # IDLE
	90.0,   # WILT
	30.0,   # DEAD
]

@export var max_fruit_cycles: int = 3

# ── Watering ──────────────────────────────────────────────────────────
## If true, plant tracks time since last_watered and wilts when window expires.
## Set false for grass, trees, and soil-only-sensitive plants.
@export var wilt_without_water: bool  = true
## Seconds before an unwatered plant begins wilting (scaled by genes.drought_resist).
@export var water_duration:     float = 300.0

# ── Soil wilt conditions ───────────────────────────────────────────────
## If true, plant checks resolved soil_wetness and soil_toxicity for wilt.
## Independent of wilt_without_water — both paths can coexist.
@export var soil_wilt_enabled:  bool  = false
## Wilt is forced when soil_wetness falls below this threshold.
## Default 0.05 = only bone-dry conditions trigger wilt.
@export var wilt_wetness_min:   float = 0.05
## Wilt is forced when soil_toxicity exceeds this threshold.
## Default 0.85 = only extreme toxicity triggers wilt.
@export var wilt_toxicity_max:  float = 0.85

# ── Pollination / reproduction ─────────────────────────────────────────
@export var can_produce_pollen: bool  = true
@export var can_receive_pollen: bool  = true
## How many hex steps pollen can drift naturally (overridden by genes.pollen_radius).
@export var base_pollen_radius: int   = 2
## Chance per pollination event that a nearby empty cell receives a sprout.
@export var sprout_chance:      float = 0.25
## Max hex distance for natural sprout placement.
@export var sprout_radius:      int   = 3

# ── Pollen yield ───────────────────────────────────────────────────────
@export var pollen_per_flower:  float = 4.0
@export var base_pollen_yield:  float = 1.0

# ── Nectar ─────────────────────────────────────────────────────────────
@export var nectar_per_fruit:   float = 5.0
@export var base_nectar_yield:  float = 1.0

# ── Respawn on death (active defense plants) ───────────────────────────
## When this plant dies and fruit_cycles_done > 0 (it produced seeds at least once),
## roll this chance to place a SPROUT in the same slot instead of clearing the cell.
## 0.0 = no chance. ~0.25 for active defense plants.
## No item gem drops on a successful seed-respawn roll.
@export var seed_respawn_chance: float = 0.0

# ════════════════════════════════════════════════════════════════════ #
#  Runtime helpers
# ════════════════════════════════════════════════════════════════════ #

## Compute stage from elapsed time. Does NOT apply wilt overrides — caller does that.
func compute_stage(birth_time: float, world_time: float,
				   cycle_speed: float, fruit_cycles_done: int = 0) -> int:
	var age     := world_time - birth_time
	if age < 0.0: return HexWorldState.Stage.SPROUT

	var elapsed := 0.0
	var speed   := maxf(cycle_speed, 0.01)

	for s in [HexWorldState.Stage.SPROUT, HexWorldState.Stage.GROWTH]:
		elapsed += stage_durations[s] / speed
		if age < elapsed: return s

	for _c in fruit_cycles_done:
		for s in [HexWorldState.Stage.FLOWERING,
				  HexWorldState.Stage.FRUITING,
				  HexWorldState.Stage.IDLE]:
			elapsed += stage_durations[s] / speed

	var cycles_remaining := max_fruit_cycles - fruit_cycles_done
	for _c in cycles_remaining:
		for s in [HexWorldState.Stage.FLOWERING,
				  HexWorldState.Stage.FRUITING,
				  HexWorldState.Stage.IDLE]:
			elapsed += stage_durations[s] / speed
			if age < elapsed: return s

	for s in [HexWorldState.Stage.WILT, HexWorldState.Stage.DEAD]:
		elapsed += stage_durations[s] / speed
		if age < elapsed: return s

	return HexWorldState.Stage.DEAD


## Effective water window in seconds for a given drought_resist gene value.
func effective_water_duration(drought_resist: float) -> float:
	return water_duration * lerpf(0.3, 2.0, drought_resist)


func nectar_at_stage(stage: int, yield_mult: float) -> float:
	match stage:
		HexWorldState.Stage.FLOWERING: return base_nectar_yield * yield_mult * 0.5
		HexWorldState.Stage.FRUITING:  return base_nectar_yield * yield_mult
		_: return 0.0


func pollen_at_stage(stage: int, yield_mult: float) -> float:
	match stage:
		HexWorldState.Stage.FLOWERING: return base_pollen_yield * yield_mult
		HexWorldState.Stage.FRUITING:  return base_pollen_yield * yield_mult * 0.5
		_: return 0.0
