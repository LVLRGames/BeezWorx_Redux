# hex_world_simulation.gd
class_name HexWorldSimulation
extends RefCounted

var cfg: HexTerrainConfig
var registry: HexDefinitionRegistry
var baseline: HexWorldBaseline
var delta_store: HexWorldDeltaStore

func setup(
	p_cfg: HexTerrainConfig,
	p_registry: HexDefinitionRegistry,
	p_baseline: HexWorldBaseline,
	p_delta_store: HexWorldDeltaStore
) -> void:
	cfg = p_cfg
	registry = p_registry
	baseline = p_baseline
	delta_store = p_delta_store

func get_cell(
	cell: Vector2i,
	world_time: float,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	var empty := HexCellState.new()
	empty.origin = cell

	if cfg == null or registry == null or baseline == null or delta_store == null:
		return empty

	var occupant: Vector2i = delta_store.get_origin_for_cell(cell)
	if occupant != cell:
		var origin_state: HexCellState = get_cell(occupant, world_time, gen_cache)
		if origin_state.occupied:
			var s: HexCellState = origin_state.duplicate_state()
			s.origin = occupant
			return s
		return empty

	var delta: HexCellDelta = delta_store.get_delta(cell)

	if delta != null and delta.delta_type == HexCellDelta.DeltaType.CLEARED:
		return empty

	if delta == null:
		return baseline.get_baseline_cell(cell, world_time, gen_cache)

	var object_id: String = delta.object_id if delta.object_id != "" else baseline.get_baseline_object_id(cell, gen_cache)
	if object_id.is_empty():
		return empty

	var def: HexGridObjectDef = registry.get_definition(object_id)
	if def == null:
		return empty

	var state := HexCellState.new()
	state.occupied = true
	state.origin = cell
	state.object_id = object_id
	state.definition = def
	state.category = def.category
	state.source = &"delta"

	if not (def is HexPlantDef):
		return state

	var plant_def: HexPlantDef = def as HexPlantDef
	var pd: HexPlantData = plant_def.plant_data
	if pd == null:
		return state

	var genes: HexPlantGenes = _resolve_genes(cell, plant_def, delta)
	var birth: float = _resolve_birth(cell, pd, genes, delta)
	var cycles_done: int = _resolve_cycles_done(cell, pd, genes, birth, world_time, delta)
	var stage: int = _resolve_stage(pd, birth, world_time, genes, cycles_done, delta)

	stage = _apply_wilt_rule(stage, birth, world_time, pd, genes, delta)

	var last_watered: float = delta.last_watered if delta.last_watered >= 0.0 else birth
	var thirst: float = clampf(
		(world_time - last_watered) / maxf(pd.effective_water_duration(genes.drought_resist), 0.001),
		0.0,
		1.0
	)

	var pollen_amt: float = pd.pollen_at_stage(stage, genes.pollen_yield_mult)
	if delta.pollen_remaining >= 0.0 and stage == HexWorldState.Stage.FLOWERING:
		pollen_amt = delta.pollen_remaining

	var nectar_amt: float = pd.nectar_at_stage(stage, genes.nectar_yield_mult)
	if delta.nectar_remaining >= 0.0 and stage == HexWorldState.Stage.FRUITING:
		nectar_amt = delta.nectar_remaining

	state.stage = stage
	state.genes = genes
	state.birth_time = birth
	state.thirst = thirst
	state.has_pollen = pd.can_produce_pollen and stage == HexWorldState.Stage.FLOWERING and pollen_amt > 0.0
	state.pollen_amount = pollen_amt
	state.nectar_amount = nectar_amt
	state.fruit_cycles_done = cycles_done
	state.plant_variant = delta.plant_variant if delta.plant_variant >= 0 \
		else HexConsts.PlantVariant.NORMAL
	
	if stage == HexWorldState.Stage.DEAD:
		state.occupied = false

	return state

func _resolve_genes(cell: Vector2i, plant_def: HexPlantDef, delta: HexCellDelta) -> HexPlantGenes:
	if delta.hybrid_genes != null:
		return delta.hybrid_genes

	var age_n: float = cfg.age_noise.get_noise_2d(cell.x + 0.5, cell.y + 0.5)
	return plant_def.genes.perturbed(age_n)

func _resolve_birth(
	cell: Vector2i,
	pd: HexPlantData,
	genes: HexPlantGenes,
	delta: HexCellDelta
) -> float:
	match delta.delta_type:
		HexCellDelta.DeltaType.PLANTED, HexCellDelta.DeltaType.SPROUT_SPAWNED:
			return delta.timestamp
		HexCellDelta.DeltaType.STATE_MUTATED:
			return baseline.derive_birth(cell, pd, genes.cycle_speed)
		_:
			return baseline.derive_birth(cell, pd, genes.cycle_speed)

func _resolve_cycles_done(
	cell: Vector2i,
	pd: HexPlantData,
	genes: HexPlantGenes,
	birth: float,
	world_time: float,
	delta: HexCellDelta
) -> int:
	if delta.fruit_cycles_done >= 0:
		return delta.fruit_cycles_done

	match delta.delta_type:
		HexCellDelta.DeltaType.PLANTED, HexCellDelta.DeltaType.SPROUT_SPAWNED:
			return 0
		HexCellDelta.DeltaType.STATE_MUTATED:
			return baseline.derive_cycles_done(pd, genes.cycle_speed, birth, world_time)
		_:
			return baseline.derive_cycles_done(pd, genes.cycle_speed, birth, world_time)

func _resolve_stage(
	pd: HexPlantData,
	birth: float,
	world_time: float,
	genes: HexPlantGenes,
	cycles_done: int,
	delta: HexCellDelta
) -> int:
	if delta.stage_override >= 0:
		return delta.stage_override

	return pd.compute_stage(birth, world_time, genes.cycle_speed, cycles_done)

func _apply_wilt_rule(
	stage: int,
	birth: float,
	world_time: float,
	pd: HexPlantData,
	genes: HexPlantGenes,
	delta: HexCellDelta
) -> int:
	if not pd.wilt_without_water:
		return stage
	if stage >= HexWorldState.Stage.WILT:
		return stage

	var has_delta_watering: bool = delta.last_watered >= 0.0
	var last_w: float = delta.last_watered if has_delta_watering else birth

	if has_delta_watering \
			or delta.delta_type == HexCellDelta.DeltaType.PLANTED \
			or delta.delta_type == HexCellDelta.DeltaType.SPROUT_SPAWNED:
		if world_time - last_w > pd.effective_water_duration(genes.drought_resist):
			return HexWorldState.Stage.WILT

	return stage
