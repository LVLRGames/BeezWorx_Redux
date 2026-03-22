# hex_chunk_gen_cache.gd
class_name HexChunkGenCache
extends RefCounted

var cfg: HexTerrainConfig
var registry: HexDefinitionRegistry
var chunk_coord: Vector2i
var chunk_size: int
var padding: int = 1

var biomes: Dictionary[Vector2i, StringName] = {}
var placements: Dictionary[Vector2i, float] = {}
var types: Dictionary[Vector2i, float] = {}
var forest_clusters: Dictionary[Vector2i, float] = {}
var temperatures: Dictionary[Vector2i, float] = {}
var moistures: Dictionary[Vector2i, float] = {}

var tree_candidates: Dictionary[Vector2i, HexTreeDef] = {}
var object_candidates: Dictionary[Vector2i, HexGridObjectDef] = {}

func build(
	p_cfg: HexTerrainConfig,
	p_registry: HexDefinitionRegistry,
	p_chunk_coord: Vector2i,
	p_chunk_size: int
) -> void:
	cfg = p_cfg
	registry = p_registry
	chunk_coord = p_chunk_coord
	chunk_size = p_chunk_size
	padding = registry.get_generation_padding()

	biomes.clear()
	placements.clear()
	types.clear()
	forest_clusters.clear()
	temperatures.clear()
	moistures.clear()
	tree_candidates.clear()
	object_candidates.clear()

	var start_q: int = chunk_coord.x * chunk_size - padding
	var end_q: int = chunk_coord.x * chunk_size + chunk_size - 1 + padding
	var start_r: int = chunk_coord.y * chunk_size - padding
	var end_r: int = chunk_coord.y * chunk_size + chunk_size - 1 + padding

	# Pass 1: raw deterministic context
	for q: int in range(start_q, end_q + 1):
		for r: int in range(start_r, end_r + 1):
			var cell := Vector2i(q, r)
			var world: Vector2 = HexConsts.AXIAL_TO_WORLD(q, r)

			biomes[cell] = cfg.get_cell_biome(q, r)
			placements[cell] = (cfg.placement_noise.get_noise_2d(q, r) + 1.0) * 0.5
			types[cell] = (cfg.type_noise.get_noise_2d(q, r) + 1.0) * 0.5
			forest_clusters[cell] = (cfg.forest_cluster_noise.get_noise_2d(q, r) + 1.0) * 0.5 \
				if cfg.forest_cluster_noise != null else 0.5
			temperatures[cell] = cfg.get_temperature(world.x, world.y)
			moistures[cell] = cfg.get_moisture(world.x, world.y)

	# Pass 2: baseline candidates
	for q: int in range(start_q, end_q + 1):
		for r: int in range(start_r, end_r + 1):
			var cell := Vector2i(q, r)
			var biome: StringName = biomes.get(cell, &"")

			tree_candidates[cell] = _pick_tree_candidate(cell, biome)
			object_candidates[cell] = _pick_object_candidate(cell, biome)

func has_cell(cell: Vector2i) -> bool:
	return biomes.has(cell)

func get_biome(cell: Vector2i) -> StringName:
	return biomes.get(cell, &"")

func get_placement(cell: Vector2i) -> float:
	return placements.get(cell, 0.0)

func get_type_noise(cell: Vector2i) -> float:
	return types.get(cell, 0.0)

func get_forest_cluster(cell: Vector2i) -> float:
	return forest_clusters.get(cell, 0.5)

func get_temperature(cell: Vector2i) -> float:
	return temperatures.get(cell, 0.5)

func get_moisture(cell: Vector2i) -> float:
	return moistures.get(cell, 0.5)

func get_tree_candidate(cell: Vector2i) -> HexTreeDef:
	return tree_candidates.get(cell, null)

func get_object_candidate(cell: Vector2i) -> HexGridObjectDef:
	return object_candidates.get(cell, null)

func _pick_tree_candidate(cell: Vector2i, biome: StringName) -> HexTreeDef:
	var table: Array = registry.get_tree_table(biome)
	if table.is_empty():
		return null

	var temp: float = temperatures.get(cell, 0.5)
	var moist: float = moistures.get(cell, 0.5)

	var candidates: Array[HexTreeDef] = []
	var total_weight: float = 0.0

	for entry in table:
		var tree_def: HexTreeDef = entry as HexTreeDef
		if tree_def == null:
			continue
		if not tree_def.matches_climate(temp, moist):
			continue

		var w: float = maxf(tree_def.species_weight, 0.0)
		if w <= 0.0:
			continue

		candidates.append(tree_def)
		total_weight += w

	if candidates.is_empty() or total_weight <= 0.0:
		return null

	var roll: float = types.get(cell, 0.0) * total_weight
	var accum: float = 0.0

	for tree_def: HexTreeDef in candidates:
		accum += tree_def.species_weight
		if roll <= accum:
			return tree_def

	return candidates[candidates.size() - 1]

func _pick_object_candidate(cell: Vector2i, biome: StringName) -> HexGridObjectDef:
	var table: Array = registry.get_spawn_table(biome)
	if table.is_empty():
		return null

	var type_n: float = types.get(cell, 0.0)
	var idx: int = int(type_n * float(table.size())) % table.size()
	return table[idx]
