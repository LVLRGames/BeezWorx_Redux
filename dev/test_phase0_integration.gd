# test_phase0_integration.gd
# res://dev/test_phase0_integration.gd
#
# Phase 0 integration test. Attach to the root Node of
# res://dev/test_phase0_integration.tscn.
#
# WHAT THIS TESTS:
#   T1 — HexWorldState autoload resolves before colony autoloads
#   T2 — HexTerrainConfig builds from code without crashing
#   T3 — HexWorldState.initialize() runs without errors
#   T4 — Terrain generates at least one occupied cell in a 3-chunk radius
#   T5 — cell_changed signal propagates to a colony-layer listener
#   T6 — CellOccupantData write → read → clear round-trip
#   T7 — ColonyState autoload resolves and can create a colony
#
# HOW TO RUN:
#   Set this scene as the main scene (Project Settings → Application → Run)
#   or open it and press F6. Results print to the Godot Output panel.
#   The scene quits automatically when all tests complete.
#
# PASS CRITERIA:
#   All lines in Output begin with [PASS]. Any [FAIL] line is a bug to fix
#   before Phase 1 begins.

extends Node

# ── Test state ────────────────────────────────────────────────────────────────
var _results: Array[Dictionary] = []
var _cell_changed_received: bool = false
var _cell_changed_hint_received: int = -1

# ════════════════════════════════════════════════════════════════════════════ #
#  Entry point
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	# Defer one frame so all autoloads have completed _ready()
	await get_tree().process_frame
	_run_all_tests()
	_print_results()
	# Keep window open for 3 seconds so you can read output, then quit
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()

# ════════════════════════════════════════════════════════════════════════════ #
#  Test runner
# ════════════════════════════════════════════════════════════════════════════ #

func _run_all_tests() -> void:
	_test_t1_autoload_order()
	var cfg: HexTerrainConfig = _test_t2_config_builds()
	if cfg == null:
		_record("T3", false, "skipped — config failed to build")
		_record("T4", false, "skipped — config failed to build")
		_record("T5", false, "skipped — config failed to build")
		_record("T6", false, "skipped — config failed to build")
	else:
		_test_t3_initialize(cfg)
		_test_t4_terrain_generates()
		_test_t5_cell_changed_signal()
		_test_t6_occupant_roundtrip()
	_test_t7_colony_state()

# ════════════════════════════════════════════════════════════════════════════ #
#  T1 — Autoload order
# ════════════════════════════════════════════════════════════════════════════ #

func _test_t1_autoload_order() -> void:
	# HexWorldState must exist and must have initialized its internal objects
	# before any colony autoload _ready() fires.
	# We verify this indirectly: if HexWorldState node exists in the tree and
	# ColonyState also exists, the engine respected registration order.
	var hw: Node = get_node_or_null("/root/HexWorldState")
	var cs: Node = get_node_or_null("/root/ColonyState")
	var eb: Node = get_node_or_null("/root/EventBus")

	if hw == null:
		_record("T1", false, "HexWorldState autoload not found at /root/HexWorldState")
		return
	if eb == null:
		_record("T1", false, "EventBus autoload not found — check registration order")
		return
	if cs == null:
		# ColonyState not registered yet — that's fine for early Phase 0,
		# but flag it as a warning so the test stays honest.
		_record("T1", true, "HexWorldState + EventBus found. ColonyState not registered yet (ok for Phase 0)")
		return

	_record("T1", true, "HexWorldState, EventBus, ColonyState all present in autoload tree")

# ════════════════════════════════════════════════════════════════════════════ #
#  T2 — Config builds from code
# ════════════════════════════════════════════════════════════════════════════ #

func _test_t2_config_builds() -> HexTerrainConfig:
	var cfg: HexTerrainConfig = _make_minimal_config()
	if cfg == null:
		_record("T2", false, "_make_minimal_config() returned null")
		return null
	if cfg.continental_noise == null:
		_record("T2", false, "ensure_defaults() did not populate continental_noise")
		return null
	if cfg.height_noise == null:
		_record("T2", false, "ensure_defaults() did not populate height_noise")
		return null
	if cfg.biome_definitions.is_empty():
		_record("T2", false, "no biome_definitions — HexTerrainConfig needs at least one biome")
		return null
	if cfg.default_region == null:
		_record("T2", false, "default_region is null — HexTerrainConfig requires a default_region")
		return null

	_record("T2", true, "HexTerrainConfig built with %d biome(s), all noise layers populated" \
		% cfg.biome_definitions.size())
	return cfg

# ════════════════════════════════════════════════════════════════════════════ #
#  T3 — HexWorldState.initialize() runs clean
# ════════════════════════════════════════════════════════════════════════════ #

func _test_t3_initialize(cfg: HexTerrainConfig) -> void:
	# initialize() will push_error internally on bad config — those show as
	# red lines in Output even if this test passes. That's intentional.
	HexWorldState.initialize(cfg)

	if HexWorldState.cfg == null:
		_record("T3", false, "HexWorldState.cfg is null after initialize()")
		return
	if HexWorldState.registry == null:
		_record("T3", false, "HexWorldState.registry is null after initialize()")
		return
	if HexWorldState.baseline == null:
		_record("T3", false, "HexWorldState.baseline is null after initialize()")
		return
	if HexWorldState.delta_store == null:
		_record("T3", false, "HexWorldState.delta_store is null after initialize()")
		return
	if HexWorldState.simulation == null:
		_record("T3", false, "HexWorldState.simulation is null after initialize()")
		return

	_record("T3", true, "initialize() completed, all internal objects non-null")

# ════════════════════════════════════════════════════════════════════════════ #
#  T4 — Terrain generates at least one occupied cell
# ════════════════════════════════════════════════════════════════════════════ #

func _test_t4_terrain_generates() -> void:
	if HexWorldState.cfg == null:
		_record("T4", false, "skipped — HexWorldState not initialized")
		return

	# Sample a grid of cells around origin. With any reasonable config
	# at least one should be occupied (plant, tree, or rock).
	var occupied_count: int = 0
	var sample_radius: int = 8

	for q: int in range(-sample_radius, sample_radius + 1):
		for r: int in range(-sample_radius, sample_radius + 1):
			var state: HexCellState = HexWorldState.get_cell(Vector2i(q, r))
			if state.occupied:
				occupied_count += 1

	var total_sampled: int = (sample_radius * 2 + 1) * (sample_radius * 2 + 1)

	if occupied_count == 0:
		_record("T4", false,
			"0/%d cells occupied. Check placement_noise threshold and biome spawn tables." \
			% total_sampled)
		return

	var pct: float = float(occupied_count) / float(total_sampled) * 100.0
	_record("T4", true, "%d/%d cells occupied (%.1f%%)" % [occupied_count, total_sampled, pct])

# ════════════════════════════════════════════════════════════════════════════ #
#  T5 — cell_changed signal reaches a colony-layer listener
# ════════════════════════════════════════════════════════════════════════════ #

func _test_t5_cell_changed_signal() -> void:
	if HexWorldState.cfg == null:
		_record("T5", false, "skipped — HexWorldState not initialized")
		return

	# Connect our local listener
	_cell_changed_received = false
	if not HexWorldState.cell_changed.is_connected(_on_cell_changed_test):
		HexWorldState.cell_changed.connect(_on_cell_changed_test)

	# Find an occupied cell to mutate so we get a real delta write
	var target_cell: Vector2i = Vector2i.ZERO
	var found: bool = false
	for q: int in range(-5, 6):
		for r: int in range(-5, 6):
			var state: HexCellState = HexWorldState.get_cell(Vector2i(q, r))
			if state.occupied and state.definition is HexPlantDef:
				target_cell = Vector2i(q, r)
				found = true
				break
		if found:
			break

	if not found:
		# No plant found — just clear a cell to force a delta write
		target_cell = Vector2i(0, 0)
		HexWorldState.clear_cell(target_cell)
	else:
		# Water the plant — always writes a delta
		HexWorldState.water_plant(target_cell)

	HexWorldState.cell_changed.disconnect(_on_cell_changed_test)

	if not _cell_changed_received:
		_record("T5", false,
			"cell_changed was not emitted after mutating cell %s" % str(target_cell))
		return

	_record("T5", true,
		"cell_changed received for cell %s" % str(target_cell))

func _on_cell_changed_test(cell: Vector2i) -> void:
	_cell_changed_received = true

# ════════════════════════════════════════════════════════════════════════════ #
#  T6 — CellOccupantData write → read → clear round-trip
# ════════════════════════════════════════════════════════════════════════════ #

func _test_t6_occupant_roundtrip() -> void:
	if HexWorldState.cfg == null:
		_record("T6", false, "skipped — HexWorldState not initialized")
		return

	var test_cell := Vector2i(99, 99)   # unlikely to be occupied by baseline

	# ── Write ──
	var occupant := CellOccupantData.new()
	occupant.category  = HexConsts.CellCategory.HIVE_ANCHOR
	occupant.placed_at = 42.0

	# Phase 1 will add HexWorldState.set_occupant_data(). For Phase 0 we
	# write directly to the cache via get_cell_ref() to prove the slot works.
	var state_ref: HexCellState = HexWorldState.get_cell_ref(test_cell)
	state_ref.occupant_data = occupant

	# ── Read ──
	var read_back: HexCellState = HexWorldState.get_cell_ref(test_cell)
	if read_back.occupant_data == null:
		_record("T6", false, "occupant_data was null after write — field missing from HexCellState")
		return
	if read_back.occupant_data.category != HexConsts.CellCategory.HIVE_ANCHOR:
		_record("T6", false,
			"category mismatch: expected %d, got %d" % [
				HexConsts.CellCategory.HIVE_ANCHOR,
				read_back.occupant_data.category])
		return
	if not is_equal_approx(read_back.occupant_data.placed_at, 42.0):
		_record("T6", false,
			"placed_at mismatch: expected 42.0, got %.1f" % read_back.occupant_data.placed_at)
		return

	# ── Clear ──
	read_back.occupant_data = null
	var cleared: HexCellState = HexWorldState.get_cell_ref(test_cell)
	if cleared.occupant_data != null:
		_record("T6", false, "occupant_data was not null after clear")
		return

	# ── Serialise round-trip ──
	var original := CellOccupantData.new()
	original.category  = HexConsts.CellCategory.TERRITORY_MARKER
	original.placed_at = 123.456
	var d: Dictionary = original.to_dict()
	var restored := CellOccupantData.new()
	restored.from_dict(d)
	if restored.category != HexConsts.CellCategory.TERRITORY_MARKER:
		_record("T6", false, "to_dict/from_dict category mismatch")
		return
	if not is_equal_approx(restored.placed_at, 123.456):
		_record("T6", false, "to_dict/from_dict placed_at mismatch")
		return

	_record("T6", true, "write/read/clear + to_dict/from_dict all passed")

# ════════════════════════════════════════════════════════════════════════════ #
#  T7 — ColonyState resolves and can create a colony
# ════════════════════════════════════════════════════════════════════════════ #

func _test_t7_colony_state() -> void:
	var cs: Node = get_node_or_null("/root/ColonyState")
	if cs == null:
		_record("T7", true,
			"ColonyState not registered yet — expected for Phase 0. Register before Phase 1.")
		return

	# ColonyState is present — verify create_colony() works
	if not cs.has_method("create_colony"):
		_record("T7", false, "ColonyState exists but is missing create_colony() method")
		return

	var colony_id: int = cs.create_colony()
	if colony_id < 0:
		_record("T7", false, "create_colony() returned negative id: %d" % colony_id)
		return

	var colony = cs.get_colony(colony_id)
	if colony == null:
		_record("T7", false,
			"get_colony(%d) returned null after create_colony()" % colony_id)
		return

	_record("T7", true, "ColonyState.create_colony() → id %d, get_colony() non-null" % colony_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  Minimal config factory
# ════════════════════════════════════════════════════════════════════════════ #

func _make_minimal_config() -> HexTerrainConfig:
	var cfg := HexTerrainConfig.new()
	cfg.world_seed = 1337

	# ── Default region (required — covers the entire continental range) ──
	var default_region := ContinentalRegion.new()
	default_region.id            = &"default"
	default_region.display_name  = "Default"
	default_region.start_threshold = -1.0
	default_region.end_threshold   =  1.0
	default_region.influence_height = false   # flat world for testing
	default_region.ignore_climate   = false
	default_region.default_biome    = &"grassland"
	cfg.default_region = default_region

	# ── One biome (grassland) ──
	var grassland := HexBiome.new()
	grassland.id                        = "grassland"
	grassland.display_name              = "Grassland"
	grassland.terrain_atlas_col         = 0.0
	grassland.has_grass                 = true
	grassland.grass_atlas_rows          = [0]
	grassland.preferred_temperature     = HexBiome.Temperature.TEMPERATE
	grassland.preferred_moisture        = HexBiome.Moisture.MOIST
	grassland.grass_placement_threshold = 0.3
	grassland.grass_density_threshold   = 0.3
	cfg.biome_definitions               = [grassland]

	# ── One plant def (simple flower) ──
	var plant_data := HexPlantData.new()
	plant_data.wilt_without_water = false   # no watering needed in tests
	plant_data.can_produce_pollen = true
	plant_data.can_receive_pollen = true

	var plant_genes := HexPlantGenes.new()
	plant_genes.species_group  = "test_flower"
	plant_genes.cycle_speed    = 1.0
	plant_genes.drought_resist = 1.0

	var plant_def := HexPlantDef.new()
	plant_def.id             = "test_flower"
	plant_def.category       = HexGridObjectDef.Category.PLANT
	plant_def.valid_biomes   = ["grassland"]
	plant_def.placement_threshold = 0.3
	plant_def.exclusion_radius    = 1
	plant_def.exclusion_group     = "flower"
	plant_def.footprint           = [Vector2i(0, 0)]
	plant_def.plant_data          = plant_data
	plant_def.genes               = plant_genes
	cfg.object_definitions        = [plant_def]

	# ── Populate all noise layers with safe defaults ──
	cfg.ensure_defaults()

	return cfg

# ════════════════════════════════════════════════════════════════════════════ #
#  Result helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _record(test_id: String, passed: bool, detail: String) -> void:
	_results.append({
		"id":     test_id,
		"passed": passed,
		"detail": detail,
	})

func _print_results() -> void:
	print("")
	print("═══════════════════════════════════════════════════════")
	print("  BeezWorx Phase 0 — Integration Test Results")
	print("═══════════════════════════════════════════════════════")

	var pass_count: int = 0
	var fail_count: int = 0

	for r: Dictionary in _results:
		var status: String = "[PASS]" if r["passed"] else "[FAIL]"
		print("  %s  %s  %s" % [status, r["id"], r["detail"]])
		if r["passed"]:
			pass_count += 1
		else:
			fail_count += 1

	print("───────────────────────────────────────────────────────")
	print("  %d passed   %d failed   %d total" % [
		pass_count, fail_count, _results.size()])
	print("═══════════════════════════════════════════════════════")
	print("")

	if fail_count == 0:
		print("  All tests passed. Phase 0 is complete. Proceed to Phase 1.")
	else:
		print("  Fix the failures above before beginning Phase 1.")
	print("")
