
class_name HexTreeDef
extends HexGridObjectDef

func _init() -> void:
	category = Category.TREE
	exclusion_group = "tree"

@export_group("Spacing")
## Minimum free ring / general spacing pressure around this tree.
@export var buffer_radius: int = 2
## Number of hive attachment points this tree supports.
@export var hive_capacity: int = 1
## Relative weighted chance within its eligible species pool.
@export_range(0.0, 100.0, 0.01) var species_weight: float = 1.0

@export_group("Climate Niche")
@export_range(0.0, 1.0, 0.001) var climate_temperature_min: float = 0.0
@export_range(0.0, 1.0, 0.001) var climate_temperature_max: float = 1.0
@export_range(0.0, 1.0, 0.001) var climate_moisture_min: float = 0.0
@export_range(0.0, 1.0, 0.001) var climate_moisture_max: float = 1.0

@export_group("Forest Behavior")
## How strongly this species benefits from dense forest-cluster regions.
@export_range(0.0, 4.0, 0.01) var forest_cluster_affinity: float = 1.0
## Landmark / solitary giant flag.
@export var is_giant: bool = false
## Extra score applied during local-winner competition.
@export_range(0.0, 1.0, 0.001) var giant_priority_bonus: float = 0.0

@export_group("Variants")
## 3 to 5 typical, but supports any count.
@export var variants: Array[HexTreeVariant] = []

@export_group("Fallback")
## Used if no variant-specific collision exists and no variants are authored.
@export var collision_mesh: ConcavePolygonShape3D

var _cached_collision_shape: Shape3D

func has_variants() -> bool:
	return not variants.is_empty()

func get_variant_count() -> int:
	return variants.size()

func get_variant(index: int) -> HexTreeVariant:
	if variants.is_empty():
		return null
	index = clampi(index, 0, variants.size() - 1)
	return variants[index]

func matches_climate(temp: float, moist: float) -> bool:
	return temp >= climate_temperature_min \
		and temp <= climate_temperature_max \
		and moist >= climate_moisture_min \
		and moist <= climate_moisture_max

func get_collision_shape() -> Shape3D:
	# Fallback behavior:
	# 1. first variant collision, if variants exist and the first has one
	# 2. explicit fallback collision_mesh
	# 3. generated trimesh from fallback mesh
	if not variants.is_empty():
		var variant: HexTreeVariant = variants[0]
		if variant:
			var variant_shape: Shape3D = variant.get_collision_shape()
			if variant_shape:
				return variant_shape

	if not _cached_collision_shape:
		if collision_mesh:
			_cached_collision_shape = collision_mesh
		elif mesh:
			_cached_collision_shape = mesh.create_trimesh_shape()

	return _cached_collision_shape
