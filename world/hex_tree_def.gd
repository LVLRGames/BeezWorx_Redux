# hex_tree_def.gd
# Tree-specific plant def.
# Extends HexPlantDef (PLANT category, TREE subcategory).
# Occupies all 6 slots of its anchor cell.
# is_permanent = false by default — only royal giant trees should set this true.

class_name HexTreeDef
extends HexPlantDef

func _init() -> void:
	category          = Category.PLANT
	plant_subcategory = PlantSubcategory.TREE
	exclusion_group   = "tree"
	slots_occupied    = 6
	# is_permanent intentionally left false. Set true only on royal giant tree defs.

@export_group("Spacing")
## Minimum free ring / general spacing pressure around this tree.
@export var buffer_radius:  int   = 2
## Number of hive attachment points this tree supports.
@export var hive_capacity:  int   = 1
## Relative weighted chance within its eligible species pool.
@export_range(0.0, 100.0, 0.01) var species_weight: float = 1.0

@export_group("Climate Niche")
@export_range(0.0, 1.0, 0.001) var climate_temperature_min: float = 0.0
@export_range(0.0, 1.0, 0.001) var climate_temperature_max: float = 1.0
@export_range(0.0, 1.0, 0.001) var climate_moisture_min:    float = 0.0
@export_range(0.0, 1.0, 0.001) var climate_moisture_max:    float = 1.0

@export_group("Forest Behavior")
@export_range(0.0, 4.0, 0.01) var forest_cluster_affinity: float = 1.0
@export var is_giant:                bool  = false
@export_range(0.0, 1.0, 0.001) var giant_priority_bonus:    float = 0.0

@export_group("Variants")
@export var variants: Array[HexTreeVariant] = []

@export_group("Fallback")
@export var collision_mesh: ConcavePolygonShape3D

var _cached_collision_shape: Shape3D

func has_variants() -> bool:
	return not variants.is_empty()

func get_variant_count() -> int:
	return variants.size()

func get_variant(index: int) -> HexTreeVariant:
	if variants.is_empty():
		return null
	return variants[clampi(index, 0, variants.size() - 1)]

func matches_climate(temp: float, moist: float) -> bool:
	return temp >= climate_temperature_min \
		and temp <= climate_temperature_max \
		and moist >= climate_moisture_min \
		and moist <= climate_moisture_max

func get_collision_shape() -> Shape3D:
	if not variants.is_empty():
		var variant: HexTreeVariant = variants[0]
		if variant:
			var s: Shape3D = variant.get_collision_shape()
			if s:
				return s
	if not _cached_collision_shape:
		if collision_mesh:
			_cached_collision_shape = collision_mesh
		elif mesh:
			_cached_collision_shape = mesh.create_trimesh_shape()
	return _cached_collision_shape
