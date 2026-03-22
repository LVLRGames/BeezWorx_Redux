# hex_terrain_config.gd
# A single .tres Resource that owns every knob for terrain generation.
# Drag it onto HexTerrainManager.  Both editor preview and runtime read
# the same file, so a given seed always produces the same world.


#@tool
class_name HexTerrainConfig
extends Resource

# ── Seed ─────────────────────────────────────────────────────────────
@export var world_seed: int = 1337:
	get: return _seed
	set(v): _seed = v; apply_seed()

# ── Water / Elevation bands ───────────────────────────────────────────
@export_group("Water")
@export var sea_level:          float = 0.0
## Steps below sea level where beach begins (negative, e.g. -5)
@export var beach_bottom_steps: int   = -5
## Steps above sea level where beach ends (positive, e.g. 10)
@export var beach_top_steps:    int   = 10

# ── Height shaping ────────────────────────────────────────────────────
@export_group("Height Shaping")
@export var beach_flatten_power:       float = 2.0
## Fraction of MAX_HEIGHT below which lowlands are flattened (0–1)
@export var lowland_flatten_threshold: float = 0.35
@export var lowland_flatten_power:     float = 3.0
@export var mountain_multiplier:       float = 2.5
@export var mountain_start_threshold: float = 0.12
@export var foothills_start_threshold: float = 0.12

@export_group("Continental")
## Large-scale land mass shape. Values > 0 = land, < 0 = ocean.
@export var continental_noise_scale: float = 1.0
@export var continental_noise: FastNoiseLite
@export var continental_detail_strength: float = 0.15
@export var continental_detail_noise: FastNoiseLite
## Remaps continental noise to height profile.
## X axis: continental noise (-1 to 1), Y axis: height multiplier (0 to 1)
## Peak of continent = 1.0, shoreline = ~0, ocean floor = negative
@export var continental_curve: Curve
@export var default_region:ContinentalRegion
@export var continental_regions:Array[ContinentalRegion] = []


@export_group("Mountains")
@export var mountain_mask_noise: FastNoiseLite
@export var mountain_detail_noise: FastNoiseLite
@export var mountain_mask_scale: float = 1.0
@export var mountain_max_height: float = 300.0
@export var mountain_curve: Curve
@export var elevation_regions: Array[ContinentalRegion] = []
@export var elevation_detail_noise: FastNoiseLite
@export var elevation_detail_strength: float = 0.1

# ── Biome climate ─────────────────────────────────────────────────────
@export_group("Climate")
@export_subgroup("Moisture")
@export var moisture_noise:       FastNoiseLite
@export_subgroup("Temperature")
@export var temperature_noise: FastNoiseLite
@export var temp_wobble_strength:    float = 0.15
@export var temp_wobble_noise:    FastNoiseLite

# ── Noise layers ──────────────────────────────────────────────────────
# Each slot is a standalone FastNoiseLite so you can tweak type / fractal
# settings per-channel directly in the Inspector without touching code.
@export_group("Noise Layers")
## Main height — sampled for vertex Y positions.
@export var height_noise:         FastNoiseLite
## Large-scale mountain height modifier.
@export var mountain_noise:       FastNoiseLite
## Object placement probability per cell.
@export var placement_noise:      FastNoiseLite
## Selects which object type from the biome spawn table.
@export var type_noise:           FastNoiseLite
## Mid-scale boost that clusters forests together.
@export var forest_cluster_noise: FastNoiseLite
## Per-hex age offset so lifecycle stages are naturally staggered.
@export var age_noise:            FastNoiseLite
## Grass density probability per hex.
@export var grass_density_noise:  FastNoiseLite
## Grass visual stage selector.
@export var grass_stage_noise:    FastNoiseLite

# ── Grass ─────────────────────────────────────────────────────────────
@export_group("Grass")
@export var grass_mesh:              Mesh
@export var grass_density_threshold: float = -0.2
@export var max_grass_per_hex:       int   = 6

# ── Registries ────────────────────────────────────────────────────────
@export_group("Registries")
@export var biome_definitions:  Array[HexBiome]         = []
@export var object_definitions: Array[HexGridObjectDef] = []
## Authored hybrid crosses: canonical "id_a::id_b" key → result HexPlantDef
@export var authored_crosses: Dictionary[StringName, HexPlantDef] = {}

# ── Private ───────────────────────────────────────────────────────────
var _seed: int = 0

var _biome_lookup:Dictionary[StringName,HexBiome] = {}

## Re-seed every noise layer deterministically from world_seed.
## Called automatically when world_seed changes and by HexWorldState.initialize().
func apply_seed() -> void:
	_seed_noise(continental_noise,           world_seed + 909)
	_seed_noise(height_noise,                world_seed + 0)
	_seed_noise(mountain_noise,              world_seed + 51)
	_seed_noise(placement_noise,             world_seed + 101)
	_seed_noise(type_noise,                  world_seed + 202)
	_seed_noise(moisture_noise,              world_seed + 303)
	_seed_noise(temp_wobble_noise,           world_seed + 404)
	_seed_noise(forest_cluster_noise,        world_seed + 505)
	_seed_noise(age_noise,                   world_seed + 606)
	_seed_noise(grass_density_noise,         world_seed + 707)
	_seed_noise(grass_stage_noise,           world_seed + 808)
	_seed_noise(continental_detail_noise,    world_seed + 1010)
	_seed_noise(mountain_mask_noise,         world_seed + 1300)
	_seed_noise(mountain_detail_noise,       world_seed + 1400)
	_seed_noise(elevation_detail_noise,      world_seed + 1500)
	for i in continental_regions.size():
		if continental_regions[i].height_noise:
			_seed_noise(continental_regions[i].height_noise, world_seed + 1100 + i * 10)
		if continental_regions[i].biome_selection_noise:
			_seed_noise(continental_regions[i].biome_selection_noise, world_seed + 1200 + i * 10)
	#print("apply_seed — continental freq: ", continental_noise.frequency if continental_noise else "null")

static func _seed_noise(n: FastNoiseLite, s: int) -> void:
	if n: n.seed = s

## Populate null noise slots with sensible defaults, then apply seed.
## Call after creating a config in code; the Inspector creates via GUI.
func ensure_defaults() -> void:
	continental_noise           = _make_or(continental_noise,           0.0003, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	height_noise                = _make_or(height_noise,                0.0005, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	mountain_noise              = _make_or(mountain_noise,              0.0025, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	placement_noise             = _make_or(placement_noise,             0.08,   FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	type_noise                  = _make_or(type_noise,                  0.09,   FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	moisture_noise              = _make_or(moisture_noise,              0.008,  FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	temp_wobble_noise           = _make_or(temp_wobble_noise,           0.03,   FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	forest_cluster_noise        = _make_or(forest_cluster_noise,        0.018,  FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	age_noise                   = _make_or(age_noise,                   0.06,   FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	grass_density_noise         = _make_or(grass_density_noise,         0.1,    FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	grass_stage_noise           = _make_or(grass_stage_noise,           0.15,   FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	continental_detail_noise    = _make_or(continental_detail_noise,    0.002,  FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	mountain_mask_noise         = _make_or(mountain_mask_noise,         0.001,  FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	mountain_detail_noise       = _make_or(mountain_detail_noise,       0.005,  FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	apply_seed()

static func _make_or(existing: FastNoiseLite, freq: float, type: int) -> FastNoiseLite:
	if existing: return existing
	var n := FastNoiseLite.new()
	n.frequency  = freq
	n.noise_type = type
	return n


func sync_biome_lookup():
	_biome_lookup.clear()
	for b in biome_definitions:
		_biome_lookup[b.id] = b


func get_biome_definition(biome_id:StringName) -> HexBiome:
	if _biome_lookup.size() != biome_definitions.size():
		sync_biome_lookup()
	var biome_def:HexBiome = _biome_lookup[biome_id]
	return biome_def


func get_climate_biome(wx:float, wz:float) -> StringName:
	var temp:float = get_temperature(wx, wz)
	var moist:float = get_moisture(wx, wz)
	for def in biome_definitions:
		if def.is_in_range(temp, moist):
			return def.id
	return default_region.default_biome


# ── New internal helper (no noise sampling) ──
func _region_for_cntl(cntl: float) -> ContinentalRegion:
	for region in continental_regions:
		if region.is_in_range(cntl):
			return region
	return default_region


# ── Rewrite the public API to sample once ──
func get_cell_height(q: int, r: int) -> float:
	var w := HexConsts.AXIAL_TO_WORLD(q, r)
	return get_height(w.x, w.y)


func get_height(wx: float, wz: float) -> float:
	return get_terrain_context(wx, wz)["height"]


func get_mountainousness(wx: float, wz: float, cntl: float) -> float:
	if not mountain_mask_noise:
		return 0.0
	
	# Only allow mountains on land — fade out near coastline
	var land_fade := clampf(remap(cntl, 0.0, 0.4, 0.0, 1.0), 0.0, 1.0)
	if land_fade <= 0.0:
		return 0.0
	
	# Broad mountain range mask
	var mask := mountain_mask_noise.get_noise_2d(
		wx / mountain_mask_scale, wz / mountain_mask_scale)
	mask = remap(mask, -1.0, 1.0, 0.0, 1.0)
	
	# Shape with curve — lets you make ranges sharp-edged or gradual
	if mountain_curve:
		mask = mountain_curve.sample(mask)
	
	# Detail noise for individual peaks and ridges
	var detail := 1.0
	if mountain_detail_noise:
		detail = remap(mountain_detail_noise.get_noise_2d(wx, wz), -1.0, 1.0, 0.3, 1.0)
	
	#var mtn := remap(mountain_noise.get_noise_2d(wx,wz), -1,1, 0,1) * detail
	
	return mask * detail * land_fade * mountain_max_height


func get_cell_continentalness(q:int, r:int) -> float:
	var w := HexConsts.AXIAL_TO_WORLD(q, r)
	return get_continentalness(w.x, w.y)

func get_continentalness(wx: float, wz: float) -> float:
	var sx := wx / continental_noise_scale
	var sz := wz / continental_noise_scale
	var cntl := continental_noise.get_noise_2d(sx, sz)
	if continental_detail_noise:
		var fade := 1.0 - absf(cntl) / 0.55
		fade = clampf(fade, 0.0, 1.0)
		cntl += continental_detail_noise.get_noise_2d(wx, wz) * continental_detail_strength * fade
	cntl = clampf(remap(cntl, -0.55, 0.55, -1.0, 1.0), -1.0, 1.0)
	return cntl


func get_cell_continental_region(q:int, r:int) -> ContinentalRegion:
	var w := HexConsts.AXIAL_TO_WORLD(q, r)
	return get_continental_region(w.x, w.y)

func get_continental_region(wx: float, wz: float) -> ContinentalRegion:
	return get_terrain_context(wx, wz)["region"]

func get_cell_biome(q:int, r:int) -> StringName:
	var w := HexConsts.AXIAL_TO_WORLD(q, r)
	return get_biome(w.x, w.y)

func get_biome(wx: float, wz: float) -> StringName:
	return get_terrain_context(wx, wz)["biome"]



func get_temperature(wx: float, wz: float) -> float:
	var cntl := get_continentalness(wx, wz)
	var curved := continental_curve.sample(cntl) if continental_curve else cntl
	var temp := 1.0 - remap(curved, -1.0, 1.0, 0.0, 1.0)
	return clampf(temp, 0.0, 1.0)

func get_moisture(wx: float, wz: float) -> float:
	return clampf(remap(moisture_noise.get_noise_2d(wx, wz), -1.0, 1.0, 0.0, 1.0), 0.0, 1.0)


func _expand_range(v: float, power: float = 0.5) -> float:
	return signf(v) * pow(absf(v), power)


func get_terrain_context(wx: float, wz: float) -> Dictionary:
	var raw := get_continentalness(wx, wz)
	var cntl := continental_curve.sample(raw) if continental_curve else raw
	var base_h := cntl * HexConsts.MAX_HEIGHT
	var region := _region_for_cntl(raw)
	var region_h := region.get_height(wx, wz, raw, base_h)
	var mountain_h := get_mountainousness(wx, wz, raw)
	var height := region_h + mountain_h
	var climate_biome := get_climate_biome(wx, wz)
	var biome := region.get_biome_at(wx, wz, height, climate_biome)
	if not biome:
		biome = default_region.default_biome
	
	var max_possible := HexConsts.MAX_HEIGHT + mountain_max_height
	var height_normalized := clampf(height / max_possible, -1.0, 1.0)
	var h_norm := remap(height_normalized, -0.45, 0.45, -1.0, 1.0)

	if elevation_detail_noise:
		h_norm += elevation_detail_noise.get_noise_2d(wx, wz) * elevation_detail_strength
		h_norm = clampf(h_norm, -1.0, 1.0)

	for elev_region in elevation_regions:
		if elev_region.is_in_range(raw, h_norm):
			var elev_biome := elev_region.get_biome_at(wx, wz, h_norm, climate_biome)
			if elev_biome:
				biome = elev_biome
				region = elev_region
				break

	return {
		"raw_cntl": raw,
		"cntl": cntl,
		"height": height,
		"mountain": mountain_h,
		"region": region,
		"biome": biome,
	}







#
