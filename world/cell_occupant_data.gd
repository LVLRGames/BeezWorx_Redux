# cell_occupant_data.gd
# res://world/cell_occupant_data.gd
#
# Typed extension slot on HexCellState for colony-layer data.
#
# PURPOSE:
#   HexCellState is owned by the world layer (HexWorldSimulation, HexWorldBaseline).
#   It must never hold hive IDs, pawn IDs, loyalty values, or any other colony
#   data directly — that would couple the world layer to the colony layer.
#
#   Instead, HexCellState carries a single nullable field:
#       var occupant_data: CellOccupantData = null
#
#   Colony systems (HiveSystem, TerritorySystem, PawnRegistry) write a typed
#   subclass of CellOccupantData into that field. The world layer never reads it.
#   Rendering and query systems cast it to the expected subclass when needed.
#
# SUBCLASS CONVENTION:
#   Create one subclass per occupant type. Do NOT add fields directly to this
#   base class — keep it as a pure marker/interface so isinstance checks work.
#
#   Current subclasses (add files as phases build them):
#       HiveAnchorOccupant   (res://colony/hive/hive_anchor_occupant.gd)
#       MarkerOccupant       (res://colony/marker_occupant.gd)
#       PawnOccupant         (res://pawns/pawn_occupant.gd)
#
# LIFECYCLE:
#   - Written by: HiveSystem.register_hive(), JobSystem.place_marker(),
#                 PawnRegistry.update_cell()
#   - Cleared by: HiveSystem (on destruction), JobSystem (on marker removal),
#                 PawnRegistry (on pawn death or cell change)
#   - Read by:    HexChunk (category routing), CombatSystem, TerritorySystem
#
# THREAD SAFETY:
#   HexWorldState caches HexCellState objects and reads them from the worker
#   thread during chunk generation. Do NOT write occupant_data from a thread.
#   Write only from the main thread via HexWorldState.set_occupant_data().

class_name CellOccupantData
extends RefCounted

## The CellCategory value this occupant represents.
## Must match one of the colony-layer values in HexConsts.CellCategory.
## Set by the subclass constructor. Never changes after construction.
var category: int = HexConsts.CellCategory.EMPTY

## The world-time at which this occupant was placed.
## Used by TerritorySystem for fade calculations and SaveManager for delta ordering.
var placed_at: float = 0.0

## Serialise to a plain Dictionary for SaveManager.
## Override in every subclass — call super.to_dict() and merge.
func to_dict() -> Dictionary:
	return {
		"category":  category,
		"placed_at": placed_at,
	}

## Restore from a Dictionary produced by to_dict().
## Override in every subclass — call super.from_dict(d) first.
func from_dict(d: Dictionary) -> void:
	category  = d.get("category",  HexConsts.CellCategory.EMPTY)
	placed_at = d.get("placed_at", 0.0)
