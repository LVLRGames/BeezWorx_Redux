#@tool
# hex_biome.gd
class_name HexBiome
extends Resource

enum Moisture{ NONE = -1, ARID, DRY, MOIST, WET}
enum Temperature{ NONE = -1, POLAR, SUBPOLAR, TEMPERATE, TROPICAL}


@export var id: String
@export var display_name: String
@export var terrain_atlas_col: float = 0.0
@export var has_grass: bool = true
@export var grass_atlas_rows: Array[int] = [0]
@export var grass_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var grass_placement_threshold: float = 0.5
@export var grass_density_threshold: float = 0.5
@export var preferred_temperature: Temperature = Temperature.NONE
@export var preferred_moisture: Moisture = Moisture.NONE



func is_in_range(temp: float, moist: float) -> bool:
	if preferred_temperature == Temperature.NONE or preferred_moisture == Moisture.NONE:
		return false
	var t_band := clampi(int(temp * 4.0), 0, 3)
	var m_band := clampi(int(moist * 4.0), 0, 3)
	return t_band == preferred_temperature and m_band == preferred_moisture
