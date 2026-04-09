# hex_cell_delta.gd
# Stored only when a cell slot deviates from its deterministic baseline.
# Key in HexWorldDeltaStore is Vector3i(q, r, slot) — one record per plant slot.
#
# SENTINEL VALUES (omitted from serialization):
#   stage_override   = -1     → derive from time
#   last_watered     = -1.0   → use birth_time as baseline
#   fruit_cycles_done = -1    → derive from time
#   plant_variant    = -1     → use NORMAL
#   health_remaining = -1.0   → full health (not yet damaged)
#   wetness_override = -1.0   → use biome soil_profile.base_wetness
#   toxicity_override = -1.0  → use biome soil_profile.base_toxicity
#   pollen_remaining = -1.0   → use computed value
#   nectar_remaining = -1.0   → use computed value
#   hybrid_genes     = null   → not a hybrid

class_name HexCellDelta
extends Resource

enum DeltaType {
	CLEARED,
	PLANTED,
	SPROUT_SPAWNED,
	STATE_MUTATED,
}

@export var delta_type: DeltaType = DeltaType.CLEARED
@export var object_id:  String    = ""
@export var timestamp:  float     = 0.0

# ── Plant state overrides ──────────────────────────────────────────────
@export var stage_override:    int    = -1
@export var last_watered:      float  = -1.0
@export var pollen_source_id:  String = ""
@export var fruit_cycles_done: int    = -1
## HexConsts.PlantVariant int. -1 = NORMAL.
@export var plant_variant:     int    = -1

# ── Health (damage system) ─────────────────────────────────────────────
## Current health of this plant. -1.0 = full health (sentinel — written on first hit).
var health_remaining:  float = -1.0

# ── Soil overrides ─────────────────────────────────────────────────────
## -1.0 = use biome baseline. Written by rain/drought events.
var wetness_override:  float = -1.0
## -1.0 = use biome baseline. Written by contamination events.
var toxicity_override: float = -1.0

# ── Pollen / nectar ────────────────────────────────────────────────────
var pollen_remaining:  float    = -1.0
var nectar_remaining:  float    = -1.0
var pollinated_by:     Vector2i = Vector2i.MAX   # sentinel = not pollinated

# ── Hybrid identity ────────────────────────────────────────────────────
@export var hybrid_genes:  HexPlantGenes = null
@export var parent_a_cell: Vector2i      = Vector2i.ZERO
@export var parent_b_cell: Vector2i      = Vector2i.ZERO

# ════════════════════════════════════════════════════════════════════ #
#  Serialization
# ════════════════════════════════════════════════════════════════════ #

func to_dict() -> Dictionary:
	var d := {
		"type": delta_type,
		"oid":  object_id,
		"ts":   timestamp,
	}
	if stage_override     >= 0:    d["stage"]    = stage_override
	if last_watered       >= 0.0:  d["watered"]  = last_watered
	if pollen_source_id   != "":   d["psrc"]     = pollen_source_id
	if fruit_cycles_done  >= 0:    d["cycles"]   = fruit_cycles_done
	if plant_variant      >= 0:    d["variant"]  = plant_variant
	if health_remaining   >= 0.0:  d["hp"]       = health_remaining
	if wetness_override   >= 0.0:  d["wet"]      = wetness_override
	if toxicity_override  >= 0.0:  d["tox"]      = toxicity_override
	if pollen_remaining   >= 0.0:  d["pr"]       = pollen_remaining
	if nectar_remaining   >= 0.0:  d["nr"]       = nectar_remaining
	if pollinated_by      != Vector2i.MAX:
		d["poly"] = [pollinated_by.x, pollinated_by.y]
	if parent_a_cell      != Vector2i.ZERO:
		d["pa"] = [parent_a_cell.x, parent_a_cell.y]
		d["pb"] = [parent_b_cell.x, parent_b_cell.y]
	if hybrid_genes != null:
		d["genes"] = _genes_to_dict(hybrid_genes)
	return d


static func from_dict(d: Dictionary) -> HexCellDelta:
	var delta              := HexCellDelta.new()
	delta.delta_type        = d["type"]
	delta.object_id         = d.get("oid",     "")
	delta.timestamp         = d.get("ts",      0.0)
	delta.stage_override    = d.get("stage",   -1)
	delta.last_watered      = d.get("watered", -1.0)
	delta.pollen_source_id  = d.get("psrc",    "")
	delta.fruit_cycles_done = d.get("cycles",  -1)
	delta.plant_variant     = d.get("variant", -1)
	delta.health_remaining  = d.get("hp",      -1.0)
	delta.wetness_override  = d.get("wet",     -1.0)
	delta.toxicity_override = d.get("tox",     -1.0)
	delta.pollen_remaining  = d.get("pr",      -1.0)
	delta.nectar_remaining  = d.get("nr",      -1.0)
	if d.has("poly"):
		var py: Array = d["poly"]
		delta.pollinated_by = Vector2i(py[0], py[1])
	if d.has("pa"):
		var pa: Array = d["pa"]; var pb: Array = d["pb"]
		delta.parent_a_cell = Vector2i(pa[0], pa[1])
		delta.parent_b_cell = Vector2i(pb[0], pb[1])
	if d.has("genes"):
		delta.hybrid_genes = _genes_from_dict(d["genes"])
	return delta


static func _genes_to_dict(g: HexPlantGenes) -> Dictionary:
	return {
		"sg":  g.species_group,
		"sv":  g.stem_variant,    "fv": g.flower_variant,  "av": g.fruit_variant,
		"pi":  g.primary_idx,     "si": g.secondary_idx,   "ai": g.accent_idx,
		"li":  g.leaf_idx,        "fi": g.fruit_idx,
		"nt":  g.nectar_type,
		"pym": g.pollen_yield_mult, "nym": g.nectar_yield_mult,
		"cs":  g.cycle_speed,     "dr": g.drought_resist,
		"bo":  g.bloom_offset,    "pr": g.pollen_radius,
	}


static func _genes_from_dict(d: Dictionary) -> HexPlantGenes:
	var g                := HexPlantGenes.new()
	g.species_group       = d.get("sg",  "")
	g.stem_variant        = d.get("sv",  0)
	g.flower_variant      = d.get("fv",  0)
	g.fruit_variant       = d.get("av",  0)
	g.primary_idx         = d.get("pi",  0)
	g.secondary_idx       = d.get("si",  0)
	g.accent_idx          = d.get("ai",  0)
	g.leaf_idx            = d.get("li",  12)
	g.fruit_idx           = d.get("fi",  0)
	g.nectar_type         = d.get("nt",  "floral")
	g.pollen_yield_mult   = d.get("pym", 1.0)
	g.nectar_yield_mult   = d.get("nym", 1.0)
	g.cycle_speed         = d.get("cs",  1.0)
	g.drought_resist      = d.get("dr",  0.5)
	g.bloom_offset        = d.get("bo",  0.0)
	g.pollen_radius       = d.get("pr",  3)
	return g
