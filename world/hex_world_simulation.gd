# hex_world_simulation.gd
# Merges baseline + delta to produce the final HexCellState for any slot.
#
# PRIMARY ENTRY POINT: get_slot(slot_key, world_time, gen_cache)
#   slot_key = Vector3i(q, r, slot) where slot = 0-5
#
# BASELINE STUB:
#   Baseline is only consulted for slot 0. Slots 1-5 with no delta return empty.
#   Full multi-slot baseline generation is deferred to a later session.

class_name HexWorldSimulation
extends RefCounted

var cfg:         HexTerrainConfig
var registry:    HexDefinitionRegistry
var baseline:    HexWorldBaseline
var delta_store: HexWorldDeltaStore

func setup(
	p_cfg:         HexTerrainConfig,
	p_registry:    HexDefinitionRegistry,
	p_baseline:    HexWorldBaseline,
	p_delta_store: HexWorldDeltaStore
) -> void:
	cfg         = p_cfg
	registry    = p_registry
	baseline    = p_baseline
	delta_store = p_delta_store

# ── Primary slot query ─────────────────────────────────────────────────

func get_slot(
	slot_key: Vector3i,
	world_time: float,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	var cell: Vector2i = Vector2i(slot_key.x, slot_key.y)
	var slot: int      = slot_key.z

	var empty := HexCellState.new()
	empty.origin     = cell
	empty.slot_index = slot

	if cfg == null or registry == null or baseline == null or delta_store == null:
		return empty

	# ── Occupancy redirect ────────────────────────────────────────────
	var anchor: Vector3i = delta_store.get_anchor_for_slot(slot_key)
	if anchor != slot_key:
		var anchor_state: HexCellState = get_slot(anchor, world_time, gen_cache)
		if anchor_state.occupied:
			var s: HexCellState = anchor_state.duplicate_state()
			s.origin     = Vector2i(anchor.x, anchor.y)
			s.slot_index = slot
			return s
		return empty

	# ── Delta lookup ──────────────────────────────────────────────────
	var delta: HexCellDelta = delta_store.get_delta(slot_key)

	if delta != null and delta.delta_type == HexCellDelta.DeltaType.CLEARED:
		return empty

	# ── No delta → baseline (slot 0 only; stub) ───────────────────────
	if delta == null:
		if slot == 0:
			var bs: HexCellState = baseline.get_baseline_cell(cell, world_time, gen_cache)
			bs.slot_index = 0
			if bs.occupied and bs.definition is HexPlantDef:
				bs.plant_subcategory = (bs.definition as HexPlantDef).plant_subcategory
			return bs
		# Slots 1-5: grass baseline (requires biome.grass_plant_id to be set).
		return baseline.get_baseline_grass_slot(cell, slot, world_time, gen_cache)

	# ── Delta-driven resolution ───────────────────────────────────────
	var object_id: String = delta.object_id \
		if delta.object_id != "" \
		else baseline.get_baseline_object_id(cell, gen_cache)
	if object_id.is_empty():
		return empty

	var def: HexGridObjectDef = registry.get_definition(object_id)
	if def == null:
		return empty

	var state          := HexCellState.new()
	state.occupied      = true
	state.origin        = cell
	state.object_id     = object_id
	state.definition    = def
	state.category      = def.category
	state.source        = &"delta"
	state.slot_index    = slot

	# Populate plant_subcategory for all plants.
	if def is HexPlantDef:
		state.plant_subcategory = (def as HexPlantDef).plant_subcategory

	if not (def is HexPlantDef):
		return state

	# ── Plant-specific resolution ─────────────────────────────────────
	var plant_def: HexPlantDef = def as HexPlantDef
	var pd: HexPlantData       = plant_def.plant_data
	if pd == null:
		return state

	var genes:       HexPlantGenes = _resolve_genes(cell, plant_def, delta)
	var birth:       float         = _resolve_birth(cell, pd, genes, delta)
	var cycles_done: int           = _resolve_cycles_done(cell, pd, genes, birth, world_time, delta)
	var stage:       int           = _resolve_stage(pd, birth, world_time, genes, cycles_done, delta)

	stage = _apply_wilt_rule(stage, birth, world_time, pd, genes, delta)
	stage = _apply_soil_wilt_rule(stage, pd, delta)

	var last_watered: float = delta.last_watered if delta.last_watered >= 0.0 else birth
	var thirst: float = clampf(
		(world_time - last_watered) / maxf(pd.effective_water_duration(genes.drought_resist), 0.001),
		0.0, 1.0
	)

	var pollen_amt: float = pd.pollen_at_stage(stage, genes.pollen_yield_mult)
	if delta.pollen_remaining >= 0.0 and stage == HexWorldState.Stage.FLOWERING:
		pollen_amt = delta.pollen_remaining

	var nectar_amt: float = pd.nectar_at_stage(stage, genes.nectar_yield_mult)
	if delta.nectar_remaining >= 0.0 and stage == HexWorldState.Stage.FRUITING:
		nectar_amt = delta.nectar_remaining

	state.stage            = stage
	state.genes            = genes
	state.birth_time       = birth
	state.thirst           = thirst
	state.has_pollen       = pd.can_produce_pollen \
		and stage == HexWorldState.Stage.FLOWERING \
		and pollen_amt > 0.0
	state.pollen_amount    = pollen_amt
	state.nectar_amount    = nectar_amt
	state.fruit_cycles_done = cycles_done
	state.plant_variant    = delta.plant_variant \
		if delta.plant_variant >= 0 \
		else HexConsts.PlantVariant.NORMAL
	state.health_remaining = delta.health_remaining   # -1.0 = sentinel (full health)

	# Soil state — stub (no soil system yet; use deltas if present).
	state.soil_wetness  = delta.wetness_override  if delta.wetness_override  >= 0.0 else 0.5
	state.soil_toxicity = delta.toxicity_override if delta.toxicity_override >= 0.0 else 0.0

	if stage == HexWorldState.Stage.DEAD:
		state.occupied = false

	return state


# ── Legacy compat: get_cell(Vector2i) queries slot 0 ─────────────────
func get_cell(
	cell: Vector2i,
	world_time: float,
	gen_cache: HexChunkGenCache = null
) -> HexCellState:
	return get_slot(Vector3i(cell.x, cell.y, 0), world_time, gen_cache)


# ── Private resolution helpers ─────────────────────────────────────────

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


func _apply_soil_wilt_rule(
	stage: int,
	pd: HexPlantData,
	delta: HexCellDelta
) -> int:
	# Stub: soil wilt is gated by soil_wilt_enabled on HexPlantData.
	# Soil values come from delta overrides for now (no biome soil profile yet).
	if not pd.soil_wilt_enabled:
		return stage
	if stage >= HexWorldState.Stage.WILT:
		return stage

	var wetness:  float = delta.wetness_override  if delta.wetness_override  >= 0.0 else 0.5
	var toxicity: float = delta.toxicity_override if delta.toxicity_override >= 0.0 else 0.0

	if wetness  < pd.wilt_wetness_min or toxicity > pd.wilt_toxicity_max:
		return HexWorldState.Stage.WILT

	return stage
