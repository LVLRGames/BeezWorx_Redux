# hex_plant_genes.gd
# Genetic traits for a plant.  Stored on HexPlantDef as the baseline;
# copied and perturbed for naturally-spawning individuals;
# blended and stored in HexCellDelta for hybrid offspring.
#
# COLOR CHANNELS — all colors are palette indices (0–31) into a shared
# 32×1 palette texture arranged as a hue wheel.
#
# PALETTE LAYOUT:
#   0–27: Hue wheel (red → orange → yellow → green → teal → blue → purple → pink)
#   28–31: Neutrals (white, cream, brown, near-black)
#
# CROSSBREEDING:
#   Each color gene has 1/3 chance: parent A, parent B, or hue-wheel blend.
#   Blend averages indices along the shorter arc of the hue wheel so
#   red(0) + pink(27) → blush, not green.
#   Neutral × hue = random pick (no meaningful midpoint).
#
# INSTANCE DATA PACKING (see resource_plant.gdshader):
#   INSTANCE_CUSTOM.r = stem×512 + flower×64 + fruit×8 + stage
#   INSTANCE_CUSTOM.g = primary×1024 + secondary×32 + accent
#   INSTANCE_CUSTOM.b = leaf×32 + fruit_color
#   INSTANCE_CUSTOM.a = free
#   COLOR             = free
#@tool
class_name HexPlantGenes
extends Resource

const PERTURB_RANGE := 0.15
const HUE_COUNT     := 28    # indices 0–27 are the hue wheel
const PALETTE_SIZE  := 32    # total palette entries

# ── Identity ─────────────────────────────────────────────────────────
@export var species_group: String = ""

# ── Atlas part selection ──────────────────────────────────────────────
@export var stem_variant:   int = 0   # row in stem/leaf atlas    (0–15)
@export var flower_variant: int = 0   # layer in flower atlas     (0–7)
@export var fruit_variant:  int = 0   # column in fruit atlas     (0–7)

# ── Color palette indices (0–31) ──────────────────────────────────────
@export_range(0, 31) var primary_idx:   int = 0   # flower petal A  (atlas R)
@export_range(0, 31) var secondary_idx: int = 0   # flower petal B  (atlas B)
@export_range(0, 31) var accent_idx:    int = 0   # flower stamen   (atlas G)
@export_range(0, 31) var leaf_idx:      int = 12  # stem / leaves   (default: medium green)
@export_range(0, 31) var fruit_idx:     int = 0   # fruit           (fruit atlas)

# ── Nectar ────────────────────────────────────────────────────────────
@export var nectar_type: String = "floral"

# ── Numeric traits ────────────────────────────────────────────────────
@export var pollen_yield_mult:     float = 1.0
@export var nectar_yield_mult:     float = 1.0
@export var cycle_speed:    float = 1.0
@export var drought_resist: float = 0.5
@export var bloom_offset:   float = 0.0
@export var pollen_radius:  int   = 3

# ════════════════════════════════════════════════════════════════════ #
#  Instance data packing
# ════════════════════════════════════════════════════════════════════ #

## Pack atlas variants + stage + plant_variant into INSTANCE_CUSTOM.r.
##
## Encoding:
##   variant(0–3) × 16384 + stem(0–15) × 512 + flower(0–7) × 64
##   + fruit(0–7) × 8 + stage(0–7)
##
## Max value: 3×16384 + 15×512 + 7×64 + 7×8 + 7 = 57,343
## Safe in float32 mantissa (exact up to 16,777,216). ✓
##
## variant defaults to NORMAL (0) so existing call sites without the arg
## continue to work correctly until all callers are updated.
func pack_variants(stage: int, variant: int = HexConsts.PlantVariant.NORMAL) -> float:
	return float(
		variant * 16384
		+ stem_variant * 512
		+ flower_variant * 64
		+ fruit_variant * 8
		+ stage
	)

## Pack primary, secondary, accent palette indices into a single float.
## Layout: primary(0–31)×1024 + secondary(0–31)×32 + accent(0–31)
## Max = 31×1024 + 31×32 + 31 = 32767
func pack_flower_colors() -> float:
	return float(primary_idx * 1024 + secondary_idx * 32 + accent_idx)

## Pack leaf and fruit palette indices into a single float.
## Layout: leaf(0–31)×32 + fruit_color(0–31)
## Max = 31×32 + 31 = 1023
func pack_foliage_colors() -> float:
	return float(leaf_idx * 32 + fruit_idx)

# ════════════════════════════════════════════════════════════════════ #
#  Color blending for crossbreeding
# ════════════════════════════════════════════════════════════════════ #

## Blend two palette indices for crossbreeding.
## 1/3 chance: parent A's color, parent B's color, or hue-wheel blend.
## Hue-wheel blend averages along the shorter arc (handles red↔pink wrap).
## If either parent is a neutral (28–31), blend falls back to random pick
## since there's no meaningful midpoint between a hue and a neutral.
static func _blend_color_idx(a_idx: int, b_idx: int) -> int:
	if a_idx == b_idx:
		return a_idx

	var roll := randf()
	if roll < 0.33:
		return a_idx
	elif roll < 0.66:
		return b_idx

	# Blend: compute midpoint
	var a_is_neutral: bool = a_idx >= HUE_COUNT
	var b_is_neutral: bool = b_idx >= HUE_COUNT

	# Neutral × anything → random pick (no sensible midpoint)
	if a_is_neutral or b_is_neutral:
		return a_idx if randf() < 0.5 else b_idx

	# Both are hue-wheel indices (0–27): average along shorter arc
	var diff: int = absi(a_idx - b_idx)
	if diff <= HUE_COUNT / 2:
		# Short path — simple average
		return (a_idx + b_idx) / 2
	else:
		# Long path — wrap around
		return ((a_idx + b_idx + HUE_COUNT) / 2) % HUE_COUNT

# ════════════════════════════════════════════════════════════════════ #
#  Helpers
# ════════════════════════════════════════════════════════════════════ #

func perturbed(noise_val: float) -> HexPlantGenes:
	var g := duplicate(false) as HexPlantGenes
	var t := noise_val * PERTURB_RANGE
	g.pollen_yield_mult = clampf(pollen_yield_mult     + t,             0.1, 4.0)
	g.nectar_yield_mult = clampf(nectar_yield_mult     + t,             0.1, 4.0)
	g.cycle_speed       = clampf(cycle_speed    + t * 0.5,       0.2, 3.0)
	g.drought_resist    = clampf(drought_resist + t * 0.5,       0.0, 1.0)
	return g

## Blend two gene sets for a procedural hybrid offspring.
## Each color gene: 1/3 parent A, 1/3 parent B, 1/3 hue-wheel midpoint.
static func blend(a: HexPlantGenes, b: HexPlantGenes) -> HexPlantGenes:
	var g := HexPlantGenes.new()
	g.species_group   = a.species_group

	# Atlas variants: stem from A, flower from B, fruit random
	g.stem_variant    = a.stem_variant
	g.flower_variant  = b.flower_variant
	g.fruit_variant   = a.fruit_variant if randf() < 0.5 else b.fruit_variant

	# Color genes: each independently rolls A / B / blend
	g.primary_idx     = _blend_color_idx(a.primary_idx,   b.primary_idx)
	g.secondary_idx   = _blend_color_idx(a.secondary_idx, b.secondary_idx)
	g.accent_idx      = _blend_color_idx(a.accent_idx,    b.accent_idx)
	g.leaf_idx        = _blend_color_idx(a.leaf_idx,      b.leaf_idx)
	g.fruit_idx       = _blend_color_idx(a.fruit_idx,     b.fruit_idx)

	# Numeric traits
	g.nectar_type     = a.nectar_type if randf() < 0.5 else b.nectar_type
	g.yield_mult      = lerpf(a.yield_mult,     b.yield_mult,     0.5)
	g.cycle_speed     = lerpf(a.cycle_speed,    b.cycle_speed,    0.5)
	g.drought_resist  = maxf(a.drought_resist,  b.drought_resist)
	g.bloom_offset    = lerpf(a.bloom_offset,   b.bloom_offset,   0.5)
	g.pollen_radius   = (a.pollen_radius + b.pollen_radius) / 2.0
	return g

func signature() -> Vector4:
	return Vector4(
		float(primary_idx * 32 + stem_variant),
		float(secondary_idx * 32 + flower_variant),
		float(accent_idx * 32 + fruit_variant),
		hash(nectar_type) % 1000)
