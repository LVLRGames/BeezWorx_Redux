# hex_grid_object_def.gd
# Base class for every placeable object in the hex grid.
#
# CATEGORY CHANGE (plant system overhaul):
#   Category now has three values: PLANT, ROCK, PORTAL.
#   RESOURCE_PLANT, TREE, DEFENSIVE_PASSIVE, DEFENSIVE_ACTIVE are REMOVED.
#   Plant-type distinction is now carried by HexPlantDef.PlantSubcategory.
#   HexConsts.CellCategory is decoupled — colony systems query PlantSubcategory
#   directly rather than matching Category integers.
#
# CONCRETE SUBCLASSES:
#   HexPlantDef   — extends HexGridObjectDef; category = PLANT
#   GrassDef      — extends HexPlantDef
#   HexTreeDef    — extends HexPlantDef; category = PLANT; subcategory = TREE
#   (plain HexGridObjectDef instances used for ROCK, PORTAL)
#
# FOOTPRINT CONVENTION:
#   footprint is Array[Vector2i] of axial offsets from the origin cell.
#   Always includes Vector2i(0,0).
#
# EXCLUSION:
#   exclusion_group gates which defs compete for space.
#   exclusion_radius = 0 disables.

class_name HexGridObjectDef
extends Resource

enum Category {
	PLANT,    # any living plant — see HexPlantDef.PlantSubcategory for specifics
	ROCK,     # impassable terrain object
	PORTAL,   # reserved — world transition node
}

# ── Identity ──────────────────────────────────────────────────────────
@export var id: String = ""
@export var category: Category = Category.ROCK

# ── Placement ─────────────────────────────────────────────────────────
@export var valid_biomes:           Array[String]    = []
@export var footprint:              Array[Vector2i]  = [Vector2i(0, 0)]
@export_range(0.0, 1.0, 0.001) var placement_threshold:    float            = 0.6
## Hex steps to check for same-group competitors. 0 = disabled.
@export var exclusion_radius:       int              = 1
## Shared tag among defs that compete for the same physical space.
@export var exclusion_group:        String           = ""
## If true, no other object (except grass) can spawn in footprint cells.
@export var blocks_objects:         bool             = true
## If true, grass is suppressed in footprint cells.
@export var blocks_grass:           bool             = true

# ── Rendering ─────────────────────────────────────────────────────────
@export var mesh:                   Mesh             = null
@export var material:               Material         = null
## ACTIVE_DEFENSE only — instantiated per cell.
@export var scene:                  PackedScene      = null
@export var random_rotation:        bool             = true
@export var random_scale_range:     Vector2          = Vector2(0.9, 1.1)

# ── Behaviour ─────────────────────────────────────────────────────────
## How many contiguous slots (starting from slot 0) this object occupies in its cell.
## 1 = single plant. 6 = full cell (tree). 2-4 = medium rocks.
## HexTreeDef._init() overrides this to 6.
@export var slots_occupied:         int              = 1

## If true, the object cannot die or be destroyed by any means.
## Only intended for royal giant trees. Most objects leave this false.
@export var is_permanent:           bool             = false
