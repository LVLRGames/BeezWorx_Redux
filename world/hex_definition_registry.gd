# hex_definition_registry.gd
class_name HexDefinitionRegistry
extends RefCounted

var biome_defs: Dictionary[String, HexBiome] = {}
var definitions: Dictionary[String, HexGridObjectDef] = {}
var spawn_tables: Dictionary[String, Array] = {}
var tree_tables: Dictionary[String, Array] = {}
var authored_crosses: Dictionary[String, HexPlantDef] = {}

func build_from_config(cfg: HexTerrainConfig) -> void:
	biome_defs.clear()
	definitions.clear()
	spawn_tables.clear()
	tree_tables.clear()
	authored_crosses.clear()

	for b: HexBiome in cfg.biome_definitions:
		biome_defs[b.id] = b

	for d: HexGridObjectDef in cfg.object_definitions:
		_register_def(d)

	if not definitions.has("wild_plant"):
		var wp := HexPlantDef.new()
		wp.id = "wild_plant"
		wp.genes = HexPlantGenes.new()
		wp.plant_data = HexPlantData.new()
		definitions["wild_plant"] = wp

	var authored: Dictionary = cfg.authored_crosses if cfg.authored_crosses else {}
	for raw_key in authored.keys():
		authored_crosses[_canonical_key_raw(str(raw_key))] = authored[raw_key]

func _register_def(def: HexGridObjectDef) -> void:
	definitions[def.id] = def

	for biome: String in def.valid_biomes:
		if def is HexTreeDef:
			if not tree_tables.has(biome):
				tree_tables[biome] = []
			if not tree_tables[biome].has(def):
				tree_tables[biome].append(def)
		else:
			if not spawn_tables.has(biome):
				spawn_tables[biome] = []
			if not spawn_tables[biome].has(def):
				spawn_tables[biome].append(def)

func get_definition(id: String) -> HexGridObjectDef:
	return definitions.get(id, null)

func get_biome_def(id: StringName) -> HexBiome:
	return biome_defs.get(String(id), null)

func get_spawn_table(biome: StringName) -> Array:
	return spawn_tables.get(String(biome), [])

func get_tree_table(biome: StringName) -> Array:
	return tree_tables.get(String(biome), [])

func get_authored_cross(key: String) -> HexPlantDef:
	return authored_crosses.get(key, null)

func get_generation_padding() -> int:
	var max_padding: int = 1

	for def_id: String in definitions:
		var def: HexGridObjectDef = definitions[def_id]
		if def == null:
			continue

		var footprint_radius: int = 0
		for offset: Vector2i in def.footprint:
			footprint_radius = maxi(footprint_radius, _hex_len(offset))

		var competition_radius: int = def.exclusion_radius
		if def is HexTreeDef:
			competition_radius = maxi(competition_radius, (def as HexTreeDef).buffer_radius)

		max_padding = maxi(max_padding, competition_radius + footprint_radius)

	return max_padding

static func _hex_len(v: Vector2i) -> int:
	return maxi(abs(v.x), maxi(abs(v.y), abs(-v.x - v.y)))

static func canonical_key(a: String, b: String) -> String:
	return (a + "::" + b) if a <= b else (b + "::" + a)

static func _canonical_key_raw(raw: String) -> String:
	var p: PackedStringArray = raw.split("::")
	return canonical_key(p[0], p[1]) if p.size() == 2 else raw
