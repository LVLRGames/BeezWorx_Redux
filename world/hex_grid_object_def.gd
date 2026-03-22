# hex_object_def.gd
# Base class and concrete subclasses for every placeable object in the hex grid.
#
# CONCRETE CLASSES:
#   HexGridObjectDef — base; used directly for ROCK, PORTAL, DEFENSIVE_PASSIVE,
#                      DEFENSIVE_ACTIVE
#   HexPlantDef      — extends HexGridObjectDef; RESOURCE_PLANT category
#   HexTreeDef       — extends HexGridObjectDef; TREE category
#
# FOOTPRINT CONVENTION:
#   footprint is an Array[Vector2i] of axial offsets from the origin cell.
#   Always includes Vector2i(0, 0). The origin cell is the one with the
#   highest placement noise among all footprint cells.
#
# EXCLUSION:
#   exclusion_group gates which other defs compete for space.
#   e.g. all trees share exclusion_group "tree" so they space out from
#   each other regardless of species. Set exclusion_radius = 0 to disable.
#
# RENDERING CATEGORY ROUTING (used by HexChunk):
#   RESOURCE_PLANT    → shared sprout/bush meshes
#   TREE              → MultiMesh batches, now species+variant aware
#   ROCK              → MultiMesh per def.id
#   PORTAL            → MultiMesh per def.id
#   DEFENSIVE_PASSIVE → MultiMesh per def.id
#   DEFENSIVE_ACTIVE  → scene instantiation per cell

class_name HexGridObjectDef
extends Resource

enum Category {
	RESOURCE_PLANT,
	TREE,
	ROCK,
	PORTAL,
	DEFENSIVE_PASSIVE,
	DEFENSIVE_ACTIVE,
}

# ── Identity ──────────────────────────────────────────────────────────
@export var id: String = ""
@export var category: Category = Category.ROCK

# ── Placement ─────────────────────────────────────────────────────────
@export var valid_biomes: Array[String] = []
@export var footprint: Array[Vector2i] = [Vector2i(0, 0)]
@export_range(0.0, 1.0, 0.001) var placement_threshold: float = 0.6
## Hex steps to check for same-group competitors. 0 = disabled.
@export var exclusion_radius: int = 1
## Shared tag among defs that compete for the same physical space.
@export var exclusion_group: String = ""
## If true, no other object (except grass) can spawn in footprint cells.
@export var blocks_objects: bool = true
## If true, grass is suppressed in footprint cells.
@export var blocks_grass: bool = true

# ── Rendering ─────────────────────────────────────────────────────────
## Used directly by non-tree categories, and as fallback for trees without variants.
@export var mesh: Mesh = null
@export var material: Material = null
## DEFENSIVE_ACTIVE only
@export var scene: PackedScene = null

@export var random_rotation: bool = true
@export var random_scale_range: Vector2 = Vector2(0.9, 1.1)

# ── Behaviour ─────────────────────────────────────────────────────────
@export var is_permanent: bool = false
