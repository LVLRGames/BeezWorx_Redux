#@tool
class_name HexConsts
extends Node

# Plant variant state. Determined at IDLE stage by plant simulation.
## Drives mesh archetype selection in the vertex shader.
##
## NORMAL  — two crossed quads (CROSS_QUAD). Standard expression.
## WILD    — 1–6 randomly offset/rotated quads (WILD_CLUSTER). Feral, irregular.
## LUSH    — cross quad + extra offset quads (LUSH_BUSH). Fuller, saturated.
## ROYAL   — three quads at 120° (TRI_CROSS). Symmetrical, majestic.
##
## Integer values are packed into INSTANCE_CUSTOM.r in the plant shader.
## Do NOT change these values without updating pack_variants() in HexPlantGenes
## and the unpack in resource_plant.gdshader.
enum PlantVariant {
	NORMAL = 0,
	WILD   = 1,
	LUSH   = 2,
	ROYAL  = 3,
}

## Describes what a hex cell is currently occupied by.
## Used by HexCellState.category and queried by colony, job, and rendering systems.
## Extends HexGridObjectDef.Category with colony-specific occupant types.
##
## IMPORTANT: The integer values of RESOURCE_PLANT through DEFENSIVE_ACTIVE must
## stay numerically identical to HexGridObjectDef.Category so that existing
## HexChunk rendering branches that compare category integers remain correct.
## When HexGridObjectDef.Category gains new entries, mirror them here.
enum CellCategory {
	# ── Terrain baseline ──────────────────────────────────────────────
	EMPTY             = -1,  # No occupant. Default for unoccupied cells.

	# ── Mirror of HexGridObjectDef.Category (values must match) ───────
	RESOURCE_PLANT    = 0,   # Harvestable plant — nectar, pollen, fruit.
	TREE              = 1,   # Tree trunk anchor. Hives can be built here.
	ROCK              = 2,   # Impassable terrain object.
	PORTAL            = 3,   # Reserved — world transition node.
	DEFENSIVE_PASSIVE = 4,   # Passive obstacle (thorns, dense brush).
	DEFENSIVE_ACTIVE  = 5,   # Combat plant — attacks nearby hostiles.

	# ── Colony layer (new in Phase 0) ─────────────────────────────────
	HIVE_ANCHOR       = 10,  # Cell holds a constructed hive structure.
	TERRITORY_MARKER  = 11,  # Queen-placed scent / command marker.
	PAWN_SPAWN        = 12,  # Designated pawn spawn point (nursery exit).
	RESOURCE_NODE     = 13,  # Non-plant harvestable (mineral, resin, water).
	TRAVERSABLE_STRUCTURE = 14, # Walkable colony construction (ramp, bridge).
}

## Hints passed with HexWorldState.cell_changed so listeners can skip
## full re-queries when the change is minor.
##
## Usage:
##   HexWorldState.cell_changed.emit(cell, CellChangeMutationHint.STAGE_CHANGE)
##
## Listeners that only care about structure (chunk rebuild) can ignore
## RESOURCE_CHANGE and MARKER_CHANGE entirely.
enum CellChangeMutationHint {
	STRUCTURAL       = 0,  # Object placed, removed, or replaced. Full re-query needed.
	STAGE_CHANGE     = 1,  # Plant stage advanced. Re-query plant state only.
	RESOURCE_CHANGE  = 2,  # Pollen/nectar amount changed. No mesh rebuild needed.
	MARKER_CHANGE    = 3,  # Territory marker placed or removed. Territory system listens.
}

const HEX_SIZE:    float = 4.0
const CHUNK_SIZE:  int   = 16
const MAX_HEIGHT:  float = 512.0
const HEIGHT_STEP: float = 2
const SQRT3:       float = 1.7320508075688772   # sqrt(3) — avoids runtime sqrt calls

const TERRAIN_ATLAS_COLS: int   = 16            # one column per biome
const TERRAIN_ATLAS_ROWS: int   = 4             # top / skirt-first / skirt-cont / spare
const TERRAIN_TILE_U:     float = 1.0 / TERRAIN_ATLAS_COLS   # 0.0625
const TERRAIN_TILE_V:     float = 1.0 / TERRAIN_ATLAS_ROWS   # 0.25

static func WORLD_TO_AXIAL(wx: float, wz: float) -> Vector2i:
	var qf := (SQRT3 / 3.0 * wx - 1.0 / 3.0 * wz) / HEX_SIZE
	var rf := (2.0 / 3.0 * wz) / HEX_SIZE
	var q := roundf(qf)
	var r := roundf(rf)
	var s := roundf(-qf - rf)
	var q_diff := absf(q - qf)
	var r_diff := absf(r - rf)
	var s_diff := absf(s - (-qf - rf))
	if q_diff > r_diff and q_diff > s_diff:
		q = -r - s
	elif r_diff > s_diff:
		r = -q - s
	return Vector2i(int(q), int(r))

static func AXIAL_TO_WORLD(q: int, r: int) -> Vector2:
	var x = HEX_SIZE * (SQRT3 * q + SQRT3 * 0.5 * r)
	var z = HEX_SIZE * 1.5 * r
	return Vector2(x, z)
