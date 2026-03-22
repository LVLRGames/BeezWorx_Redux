# hex_cell_delta.gd
# Stored only when a cell deviates from its deterministic baseline.
# Kept intentionally lean — only the fields needed to reconstruct full
# plant state are written; everything derivable from noise stays unwritten.
#
# DELTA TYPES:
#   CLEARED        — object removed (player destroyed or died and was cleaned up)
#   PLANTED        — player placed a specific object
#   SPROUT_SPAWNED — offspring placed by the pollination system
#   STATE_MUTATED  — an existing baseline object had its state changed
#                    (watered, manually pollinated, stage forced, etc.)
#
# FIELD USAGE BY TYPE:
#   CLEARED:        timestamp only
#   PLANTED:        object_id, timestamp
#   SPROUT_SPAWNED: object_id, timestamp, hybrid_genes (null if named hybrid),
#                   parent_a_cell, parent_b_cell
#   STATE_MUTATED:  object_id, timestamp, + whichever state fields changed
#
# NULL / SENTINEL VALUES:
#   stage_override  = -1    → derive stage from time (not overridden)
#   last_watered    = -1.0  → use birth_time as the watering baseline
#   pollen_source_id = ""   → not manually pollinated
#   fruit_cycles_done = -1  → derive from time
#   hybrid_genes    = null  → not a hybrid; use def genes + noise perturbation
#@tool

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
@export var timestamp:  float     = 0.0   # world_time when this delta was written

# ── Plant state overrides ─────────────────────────────────────────────
## -1 = derive from elapsed time
@export var stage_override:    int   = -1
## -1.0 = not explicitly watered; use birth_time as baseline
@export var last_watered:      float = -1.0
## "" = not manually pollinated this cycle
@export var pollen_source_id:  String = ""
## -1 = derive from elapsed time
@export var fruit_cycles_done: int   = -1
## -1 = not yet evaluated (baseline). Use HexConsts.PlantVariant enum.
## Written at IDLE stage by plant simulation. Not derived from time. 
@export var plant_variant: int = -1

# ── Hybrid identity ───────────────────────────────────────────────────
## Non-null only for SPROUT_SPAWNED offspring whose genes were procedurally
## blended.  Named hybrids (authored crosses) use a fixed def and leave this null.
@export var hybrid_genes:  HexPlantGenes = null
@export var parent_a_cell: Vector2i      = Vector2i.ZERO
@export var parent_b_cell: Vector2i      = Vector2i.ZERO


var pollen_amount: float = 10.0   # -1 = no override
var nectar_amount: float = -1.0   # -1 = no override
var pollen_remaining: float = -1.0   # -1 = use default (full)
var nectar_remaining: float = -1.0   # -1 = use default (full)
var pollinated_by: Vector2i = Vector2i.MAX  # sentinel = not pollinated

# ════════════════════════════════════════════════════════════════════ #
#  Serialization helpers
# ════════════════════════════════════════════════════════════════════ #

func to_dict() -> Dictionary:
	var d := {
		"type": delta_type,
		"oid":  object_id,
		"ts":   timestamp,
	}
	if stage_override    >= 0:   d["stage"]   = stage_override
	if last_watered      >= 0.0: d["watered"] = last_watered
	if pollen_source_id  != "":  d["pollen"]  = pollen_source_id
	if fruit_cycles_done >= 0:   d["cycles"]  = fruit_cycles_done
	if plant_variant     >= 0:   d["variant"] = plant_variant
	if parent_a_cell != Vector2i.ZERO:
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
	delta.pollen_source_id  = d.get("pollen",  "")
	delta.fruit_cycles_done = d.get("cycles",  -1)
	delta.plant_variant     = d.get("variant", -1)
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
		"sv":  g.stem_variant,
		"fv":  g.flower_variant,
		"av":  g.fruit_variant,
		"pc":  [g.primary_color.r,   g.primary_color.g,   g.primary_color.b],
		"sc":  [g.secondary_color.r, g.secondary_color.g, g.secondary_color.b],
		"ac":  [g.accent_color.r,    g.accent_color.g,    g.accent_color.b],
		"nt":  g.nectar_type,
		"ym":  g.yield_mult,
		"cs":  g.cycle_speed,
		"dr":  g.drought_resist,
		"bo":  g.bloom_offset,
		"pr":  g.pollen_radius,
	}

static func _genes_from_dict(d: Dictionary) -> HexPlantGenes:
	var g               := HexPlantGenes.new()
	g.species_group      = d.get("sg", "")
	g.stem_variant       = d.get("sv", 0)
	g.flower_variant     = d.get("fv", 0)
	g.fruit_variant      = d.get("av", 0)
	var pc: Array = d.get("pc", [1,1,1])
	var sc: Array = d.get("sc", [1,1,1])
	var ac: Array = d.get("ac", [1,1,1])
	g.primary_color      = Color(pc[0], pc[1], pc[2])
	g.secondary_color    = Color(sc[0], sc[1], sc[2])
	g.accent_color       = Color(ac[0], ac[1], ac[2])
	g.nectar_type        = d.get("nt", "floral")
	g.yield_mult         = d.get("ym", 1.0)
	g.cycle_speed        = d.get("cs", 1.0)
	g.drought_resist     = d.get("dr", 0.5)
	g.bloom_offset       = d.get("bo", 0.0)
	g.pollen_radius      = d.get("pr", 3)
	return g
