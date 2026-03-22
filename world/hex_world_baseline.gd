# hex_world_baseline.gd
class_name HexWorldBaseline
extends RefCounted

var cfg: HexTerrainConfig
var registry: HexDefinitionRegistry

func setup(p_cfg: HexTerrainConfig, p_registry: HexDefinitionRegistry) -> void:
	cfg = p_cfg
	registry = p_registry

# ════════════════════════════════════════════════════════════════════ #
#  Public baseline API
# ════════════════════════════════════════════════════════════════════ #

func get_baseline_cell(
	cell: Vector2i,
	world_time: float,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	var state := HexCellState.new()
	state.origin = cell
	state.source = &"baseline"

	if cfg == null or registry == null:
		return state

	var object_id: String = get_baseline_object_id(cell, gen_cache)
	if object_id.is_empty():
		return state

	var def: HexGridObjectDef = registry.get_definition(object_id)
	if def == null:
		return state

	state.occupied = true
	state.object_id = object_id
	state.definition = def
	state.category = def.category

	if not (def is HexPlantDef):
		return state

	var plant_def: HexPlantDef = def as HexPlantDef
	var pd: HexPlantData = plant_def.plant_data
	if pd == null:
		return state

	var genes: HexPlantGenes = baseline_genes(cell, plant_def)
	var birth: float = derive_birth(cell, pd, genes.cycle_speed)
	var cycles_done: int = derive_cycles_done(pd, genes.cycle_speed, birth, world_time)
	var stage: int = pd.compute_stage(birth, world_time, genes.cycle_speed, cycles_done)

	state.genes = genes
	state.birth_time = birth
	state.stage = stage
	state.plant_variant = HexConsts.PlantVariant.NORMAL
	state.fruit_cycles_done = cycles_done

	var water_duration: float = maxf(pd.effective_water_duration(genes.drought_resist), 0.001)
	state.thirst = clampf((world_time - birth) / water_duration, 0.0, 1.0)

	var pollen_amt: float = pd.pollen_at_stage(stage, genes.pollen_yield_mult)
	var nectar_amt: float = pd.nectar_at_stage(stage, genes.nectar_yield_mult)

	state.has_pollen = pd.can_produce_pollen and stage == HexWorldState.Stage.FLOWERING and pollen_amt > 0.0
	state.pollen_amount = pollen_amt
	state.nectar_amount = nectar_amt

	if stage == HexWorldState.Stage.DEAD:
		state.occupied = false

	return state

func get_baseline_object_id(cell: Vector2i, gen_cache: HexChunkGenCache = null) -> String:
	if cfg == null or registry == null:
		return ""

	var biome: StringName = _biome_at(cell, gen_cache)
	if String(biome).is_empty():
		return ""

	var tree_id: String = _baseline_tree_object(cell, biome, gen_cache)
	if not tree_id.is_empty():
		return tree_id

	var def: HexGridObjectDef = _object_candidate(cell, biome, gen_cache)
	if def == null:
		return ""

	var place_n: float = placement_noise01(cell, gen_cache)
	if place_n < def.placement_threshold:
		return ""

	if not footprint_fits(cell, def, place_n, gen_cache):
		return ""

	if not wins_local_competition(cell, def, place_n, gen_cache):
		return ""

	return def.id

func baseline_genes(cell: Vector2i, def: HexPlantDef) -> HexPlantGenes:
	var age_n: float = cfg.age_noise.get_noise_2d(cell.x + 0.5, cell.y + 0.5)
	return def.genes.perturbed(age_n)

func derive_birth(cell: Vector2i, pd: HexPlantData, cycle_speed: float) -> float:
	var age_n: float = (cfg.age_noise.get_noise_2d(cell.x * 3.17, cell.y * 3.17) + 1.0) * 0.5
	var speed: float = maxf(cycle_speed, 0.01)

	var stages: Array[int] = [
		HexWorldState.Stage.SPROUT,
		HexWorldState.Stage.GROWTH,
		HexWorldState.Stage.FLOWERING,
		HexWorldState.Stage.FRUITING,
		HexWorldState.Stage.IDLE
	]

	var stage_idx: int = int(age_n * float(stages.size()))
	stage_idx = clampi(stage_idx, 0, stages.size() - 1)
	var target_stage: int = stages[stage_idx]

	var elapsed: float = 0.0
	for s: int in stages:
		var dur: float = pd.stage_durations[s] / speed
		if s == target_stage:
			elapsed += dur * 0.5
			break
		elapsed += dur

	return -elapsed

func derive_cycles_done(
	pd: HexPlantData,
	speed: float,
	birth: float,
	world_time: float
) -> int:
	var age: float = world_time - birth
	var elapsed: float = 0.0

	for s: int in [HexWorldState.Stage.SPROUT, HexWorldState.Stage.GROWTH]:
		elapsed += pd.stage_durations[s] / maxf(speed, 0.01)

	var cycle_len: float = 0.0
	for s: int in [HexWorldState.Stage.FLOWERING, HexWorldState.Stage.FRUITING, HexWorldState.Stage.IDLE]:
		cycle_len += pd.stage_durations[s] / maxf(speed, 0.01)

	var done: int = 0
	for _i: int in pd.max_fruit_cycles:
		if age >= elapsed + cycle_len:
			done += 1
			elapsed += cycle_len
		else:
			break

	return done

# ════════════════════════════════════════════════════════════════════ #
#  Tree baseline placement
# ════════════════════════════════════════════════════════════════════ #

func pick_tree_def_for_cell(
	cell: Vector2i,
	biome: StringName,
	gen_cache: HexChunkGenCache = null
) -> HexTreeDef:
	if gen_cache != null and gen_cache.has_cell(cell):
		return gen_cache.get_tree_candidate(cell)

	var table: Array = registry.get_tree_table(biome)
	if table.is_empty():
		return null

	var world: Vector2 = HexConsts.AXIAL_TO_WORLD(cell.x, cell.y)
	var temp: float = cfg.get_temperature(world.x, world.y)
	var moist: float = cfg.get_moisture(world.x, world.y)

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

	var roll: float = type_noise01(cell, gen_cache) * total_weight
	var accum: float = 0.0

	for tree_def: HexTreeDef in candidates:
		accum += tree_def.species_weight
		if roll <= accum:
			return tree_def

	return candidates[candidates.size() - 1]

func tree_candidate_wins(
	cell: Vector2i,
	def: HexTreeDef,
	gen_cache: HexChunkGenCache = null
) -> bool:
	var my_score: float = tree_score(cell, def, gen_cache)
	var radius: int = maxi(def.exclusion_radius, def.buffer_radius)

	if radius <= 0:
		return true

	for other_cell: Vector2i in hex_disk(cell, radius):
		if other_cell == cell:
			continue

		var other_biome: StringName = _biome_at(other_cell, gen_cache)
		if String(other_biome).is_empty():
			continue

		var other_def: HexTreeDef = pick_tree_def_for_cell(other_cell, other_biome, gen_cache)
		if other_def == null:
			continue

		if other_def.exclusion_group != def.exclusion_group:
			continue

		var other_place_n: float = placement_noise01(other_cell, gen_cache)
		if other_place_n < other_def.placement_threshold:
			continue

		if not footprint_fits(other_cell, other_def, other_place_n, gen_cache):
			continue

		var other_score: float = tree_score(other_cell, other_def, gen_cache)
		if other_score > my_score:
			return false
		if is_equal_approx(other_score, my_score) and cell_sort_before(other_cell, cell):
			return false

	return true

func tree_score(cell: Vector2i, def: HexTreeDef, gen_cache: HexChunkGenCache = null) -> float:
	var base: float = placement_noise01(cell, gen_cache)
	var cluster: float = forest_cluster_noise01(cell, gen_cache)
	var cluster_term: float = cluster * 0.15 * def.forest_cluster_affinity
	var giant_bonus: float = def.giant_priority_bonus if def.is_giant else 0.0
	var jitter: float = jitter01(cell, 913)
	return base + cluster_term + giant_bonus + jitter

# ════════════════════════════════════════════════════════════════════ #
#  General deterministic placement helpers
# ════════════════════════════════════════════════════════════════════ #

func footprint_fits(
	cell: Vector2i,
	def: HexGridObjectDef,
	place_n: float,
	gen_cache: HexChunkGenCache = null
) -> bool:
	for offset: Vector2i in def.footprint:
		if offset == Vector2i.ZERO:
			continue

		var other_cell: Vector2i = cell + offset
		var other_n: float = placement_noise01(other_cell, gen_cache)
		if other_n > place_n:
			return false

	return true

func wins_local_competition(
	cell: Vector2i,
	def: HexGridObjectDef,
	place_n: float,
	gen_cache: HexChunkGenCache = null
) -> bool:
	var radius: int = def.exclusion_radius
	if radius <= 0 or def.exclusion_group.is_empty():
		return true

	for other_cell: Vector2i in hex_disk(cell, radius):
		if other_cell == cell:
			continue

		var biome: StringName = _biome_at(other_cell, gen_cache)
		if String(biome).is_empty():
			continue

		var other_def: HexGridObjectDef = _object_candidate(other_cell, biome, gen_cache)
		if other_def == null:
			continue

		if other_def.exclusion_group != def.exclusion_group:
			continue

		var other_place_n: float = placement_noise01(other_cell, gen_cache)
		if other_place_n < other_def.placement_threshold:
			continue

		if not footprint_fits(other_cell, other_def, other_place_n, gen_cache):
			continue

		if other_place_n > place_n:
			return false
		if is_equal_approx(other_place_n, place_n) and cell_sort_before(other_cell, cell):
			return false

	return true

# ════════════════════════════════════════════════════════════════════ #
#  Cached/fallback samplers
# ════════════════════════════════════════════════════════════════════ #

func _biome_at(cell: Vector2i, gen_cache: HexChunkGenCache = null) -> StringName:
	if gen_cache != null and gen_cache.has_cell(cell):
		return gen_cache.get_biome(cell)
	return cfg.get_cell_biome(cell.x, cell.y)

func _object_candidate(
	cell: Vector2i,
	biome: StringName,
	gen_cache: HexChunkGenCache = null
) -> HexGridObjectDef:
	if gen_cache != null and gen_cache.has_cell(cell):
		return gen_cache.get_object_candidate(cell)

	var table: Array = registry.get_spawn_table(biome)
	if table.is_empty():
		return null

	var type_n: float = type_noise01(cell, gen_cache)
	var idx: int = int(type_n * float(table.size())) % table.size()
	return table[idx]

func placement_noise01(cell: Vector2i, gen_cache: HexChunkGenCache = null) -> float:
	if gen_cache != null and gen_cache.has_cell(cell):
		return gen_cache.get_placement(cell)
	return (cfg.placement_noise.get_noise_2d(cell.x, cell.y) + 1.0) * 0.5

func type_noise01(cell: Vector2i, gen_cache: HexChunkGenCache = null) -> float:
	if gen_cache != null and gen_cache.has_cell(cell):
		return gen_cache.get_type_noise(cell)
	return (cfg.type_noise.get_noise_2d(cell.x, cell.y) + 1.0) * 0.5

func forest_cluster_noise01(cell: Vector2i, gen_cache: HexChunkGenCache = null) -> float:
	if gen_cache != null and gen_cache.has_cell(cell):
		return gen_cache.get_forest_cluster(cell)
	if cfg.forest_cluster_noise == null:
		return 0.5
	return (cfg.forest_cluster_noise.get_noise_2d(cell.x, cell.y) + 1.0) * 0.5

func jitter01(cell: Vector2i, salt: int) -> float:
	var h: int = int((cell.x * 1619 + cell.y * 31337 + salt * 6971) ^ (cell.x * 1013))
	return float(h & 0xFFFF) / 65535.0 * 0.001

func cell_sort_before(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y

# ════════════════════════════════════════════════════════════════════ #
#  Internal baseline object selection
# ════════════════════════════════════════════════════════════════════ #

func _baseline_tree_object(
	cell: Vector2i,
	biome: StringName,
	gen_cache: HexChunkGenCache = null
) -> String:
	var def: HexTreeDef = pick_tree_def_for_cell(cell, biome, gen_cache)
	if def == null:
		return ""

	var place_n: float = placement_noise01(cell, gen_cache)
	if place_n < def.placement_threshold:
		return ""

	if not footprint_fits(cell, def, place_n, gen_cache):
		return ""

	if not tree_candidate_wins(cell, def, gen_cache):
		return ""

	return def.id

# ════════════════════════════════════════════════════════════════════ #
#  Hex helpers
# ════════════════════════════════════════════════════════════════════ #

static func hex_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius <= 0:
		return []

	var out: Array[Vector2i] = []
	const DIRS: Array[Vector2i] = [
		Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1),
		Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1),
	]

	var cur: Vector2i = center + Vector2i(0, -radius)
	for d: int in 6:
		for _s: int in radius:
			out.append(cur)
			cur += DIRS[d]

	return out

static func hex_disk(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q: int in range(-radius, radius + 1):
		for r: int in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
			out.append(center + Vector2i(q, r))
	return out

static func _hex_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	return hex_ring(center, radius)

static func _hex_disk(center: Vector2i, radius: int) -> Array[Vector2i]:
	return hex_disk(center, radius)
