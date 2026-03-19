# FILE: res://world/hex_consts.gd
# Canonical hex grid constants and coordinate transformation utilities.
class_name HexConsts

const HEX_SIZE: float = 1.0
const SQRT3: float = 1.73205080757
const CHUNK_SIZE: int = 16
const MAX_HEIGHT: int = 10
const HEIGHT_STEP: float = 0.5
const TERRAIN_TILE_U: int = 4
const TERRAIN_TILE_V: int = 4

enum CellCategory {
	EMPTY,
	RESOURCE_PLANT,
	TREE,
	DEFENSIVE_ACTIVE,
	HIVE_ANCHOR,
	TRAVERSABLE_STRUCTURE,
	RESOURCE_NODE,
	TERRITORY_MARKER,
	PAWN_SPAWN
}

enum CellChangeMutationHint {
	STRUCTURAL,
	STAGE_CHANGE,
	RESOURCE_CHANGE,
	MARKER_CHANGE
}

static func AXIAL_TO_WORLD(q: int, r: int) -> Vector2:
	# TODO: Implement point-top hex conversion
	return Vector2.ZERO

static func WORLD_TO_AXIAL(x: float, z: float) -> Vector2i:
	# TODO: Implement inverse conversion
	return Vector2i.ZERO
