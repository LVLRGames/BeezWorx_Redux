# hex_plant_data.gd
# Lifecycle and farming parameters for a resource plant.
# Attached to HexPlantDef.  Shared across all individuals of that def.
#
# STAGE ORDER (indices match HexWorldState.Stage enum):
#   0 SPROUT  → 1 GROWTH  → 2 FLOWERING  → 3 FRUITING  → 4 IDLE
#   The FLOWERING→FRUITING→IDLE cycle repeats max_fruit_cycles times,
#   then: 5 WILT → 6 DEAD
#
# WATERING:
#   If wilt_without_water is true, the plant tracks time since last watering.
#   Effective water window = water_duration * genes.drought_resist.
#   When the window expires the stage is forced to WILT regardless of
#   the time-based progression.  Watering resets last_watered in the delta.
#
# POLLINATION:
#   Manual pollination (bee carries pollen from another flowering plant) sets
#   pollen_source_id in the delta and can skip straight to FRUITING.
#   Natural (wind/proximity) pollination uses pollen_radius + sprout_chance.
#@tool

class_name HexPlantData
extends Resource

# ── Stage durations (seconds of world time) ───────────────────────────
## One entry per stage in the order above.
## Index 0=SEED, 1=SPROUT, 2=GROWTH, 3=FLOWERING, 4=FRUITING, 5=IDLE, 6=WILT, 7=DEAD
## These are BASE durations; multiplied by genes.cycle_speed at runtime.
@export var stage_durations: Array[float] = [
	0.0,    # SEED
	60.0,   # SPROUT
	120.0,  # GROWTH
	180.0,  # FLOWERING
	120.0,  # FRUITING
	60.0,   # IDLE
	90.0,   # WILT
	30.0,   # DEAD  (how long the dead plant stays visible before clearing)
]

@export var max_fruit_cycles: int = 3

# ── Watering ──────────────────────────────────────────────────────────
@export var wilt_without_water: bool  = true
## Seconds before an unwatered plant begins wilting (base; scaled by drought_resist)
@export var water_duration:     float = 300.0

# ── Pollination / reproduction ────────────────────────────────────────
@export var can_produce_pollen: bool  = true
@export var can_receive_pollen: bool  = true
## How many hex steps pollen can drift naturally (overridden by genes.pollen_radius)
@export var base_pollen_radius: int   = 2
## Chance per pollination event that a nearby empty cell receives a sprout
@export var sprout_chance:      float = 0.25
## Max hex distance for natural sprout placement
@export var sprout_radius:      int   = 3
# In HexPlantData
@export var pollen_per_flower: float = 4.0   # total pollen when flowering
@export var base_pollen_yield: float = 1.0

# ── Nectar ────────────────────────────────────────────────────────────
## Base nectar yield per harvest (scaled by genes.yield_mult at runtime)
@export var nectar_per_fruit: float = 5.0    # total nectar when fruiting
@export var base_nectar_yield: float = 1.0

# ════════════════════════════════════════════════════════════════════ #
#  Runtime helpers  (called by HexWorldState — no Node needed)
# ════════════════════════════════════════════════════════════════════ #

## Compute which stage a plant is in given birth_time, world_time, and genes.
## Returns a Stage int (see HexWorldState.Stage).
## Does NOT apply the wilt-without-water override — caller does that.
func compute_stage(birth_time: float, world_time: float,
				   cycle_speed: float, fruit_cycles_done: int = 0) -> int:
	var age     := world_time - birth_time
	if age < 0.0: return HexWorldState.Stage.SPROUT

	var elapsed := 0.0
	var speed   := maxf(cycle_speed, 0.01)

	for s in [HexWorldState.Stage.SPROUT, HexWorldState.Stage.GROWTH]:
		elapsed += stage_durations[s] / speed
		if age < elapsed: return s

	# Add elapsed time for already-completed cycles
	for _c in fruit_cycles_done:
		for s in [HexWorldState.Stage.FLOWERING,
				  HexWorldState.Stage.FRUITING,
				  HexWorldState.Stage.IDLE]:
			elapsed += stage_durations[s] / speed

	# Now check remaining cycles
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

## Nectar amount at this stage, scaled by yield_mult.
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
