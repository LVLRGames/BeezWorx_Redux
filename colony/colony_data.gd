# FILE: res://colony/colony_data.gd
# Comprehensive data container for a single colony.
# Owned and indexed by ColonyState. Never touched by the world layer.
class_name ColonyData
extends RefCounted

var colony_id: int = 0
var display_name: String = ""
var queen_pawn_id: int = -1          # -1 = no queen assigned yet
var heir_ids: Array[int] = []
var contest_active: bool = false
var contest_day: int = 0
var queen_history: Array[QueenRecord] = []

var known_recipe_ids: Array[StringName] = []
var known_plants: Array[StringName] = []
var known_items: Array[StringName] = []
var discovered_biomes: Array[StringName] = []
var known_anchor_types: Array[StringName] = []

var _loyalty_cache: Dictionary[int, float] = {}
var _morale_cache: float = 1.0
var _morale_dirty: bool = true
var _morale_modifiers: Array[MoraleModifier] = []

var faction_relations: Dictionary[StringName, FactionRelation] = {}

var _influence_score: float = 0.0
var _influence_dirty: bool = true

# ════════════════════════════════════════════════════════════════════════════ #
#  Serialization
# ════════════════════════════════════════════════════════════════════════════ #

func to_dict() -> Dictionary:
	# Queen history
	var qh: Array = []
	for qr: QueenRecord in queen_history:
		qh.append({
			"pawn_name":   qr.pawn_name,
			"pawn_id":     qr.pawn_id,
			"reign_start": qr.reign_start,
			"reign_end":   qr.reign_end,
			"cause":       str(qr.cause),
		})

	# Morale modifiers — skip expired ones (expires_day == -1 means permanent)
	var mm: Array = []
	for mod: MoraleModifier in _morale_modifiers:
		mm.append({
			"source_id":   str(mod.source_id),
			"value":       mod.value,
			"expires_day": mod.expires_day,
			"description": mod.description,
		})

	# Loyalty cache
	var lc: Dictionary = {}
	for pawn_id: int in _loyalty_cache:
		lc[str(pawn_id)] = _loyalty_cache[pawn_id]

	# Faction relations
	var fr: Dictionary = {}
	for fid: StringName in faction_relations:
		fr[str(fid)] = faction_relations[fid].to_dict()

	return {
		"colony_id":          colony_id,
		"display_name":       display_name,
		"queen_pawn_id":      queen_pawn_id,
		"heir_ids":           heir_ids.duplicate(),
		"contest_active":     contest_active,
		"contest_day":        contest_day,
		"queen_history":      qh,
		"known_recipe_ids":   known_recipe_ids.map(func(s): return str(s)),
		"known_plants":       known_plants.map(func(s): return str(s)),
		"known_items":        known_items.map(func(s): return str(s)),
		"discovered_biomes":  discovered_biomes.map(func(s): return str(s)),
		"known_anchor_types": known_anchor_types.map(func(s): return str(s)),
		"morale_cache":       _morale_cache,
		"morale_modifiers":   mm,
		"loyalty_cache":      lc,
		"faction_relations":  fr,
		"influence_score":    _influence_score,
	}

static func from_dict(data: Dictionary) -> ColonyData:
	var cd := ColonyData.new()
	cd.colony_id       = data.get("colony_id",      0)
	cd.display_name    = data.get("display_name",   "")
	cd.queen_pawn_id   = data.get("queen_pawn_id",  -1)
	cd.contest_active  = data.get("contest_active", false)
	cd.contest_day     = data.get("contest_day",    0)
	cd._morale_cache   = data.get("morale_cache",   1.0)
	cd._morale_dirty   = false
	cd._influence_score = data.get("influence_score", 0.0)
	cd._influence_dirty = false

	for v in data.get("heir_ids", []):
		cd.heir_ids.append(int(v))

	for qh in data.get("queen_history", []):
		var qr := QueenRecord.new()
		qr.pawn_name   = qh.get("pawn_name",   "")
		qr.pawn_id     = qh.get("pawn_id",     0)
		qr.reign_start = qh.get("reign_start", 0)
		qr.reign_end   = qh.get("reign_end",   0)
		qr.cause       = StringName(qh.get("cause", ""))
		cd.queen_history.append(qr)

	for s in data.get("known_recipe_ids",   []): cd.known_recipe_ids.append(StringName(s))
	for s in data.get("known_plants",       []): cd.known_plants.append(StringName(s))
	for s in data.get("known_items",        []): cd.known_items.append(StringName(s))
	for s in data.get("discovered_biomes",  []): cd.discovered_biomes.append(StringName(s))
	for s in data.get("known_anchor_types", []): cd.known_anchor_types.append(StringName(s))

	for mm in data.get("morale_modifiers", []):
		var mod := MoraleModifier.new()
		mod.source_id   = StringName(mm.get("source_id",   ""))
		mod.value       = mm.get("value",       0.0)
		mod.expires_day = mm.get("expires_day", -1)
		mod.description = mm.get("description", "")
		cd._morale_modifiers.append(mod)

	var lc: Dictionary = data.get("loyalty_cache", {})
	for k: String in lc:
		cd._loyalty_cache[int(k)] = float(lc[k])

	var fr: Dictionary = data.get("faction_relations", {})
	for fid: String in fr:
		cd.faction_relations[StringName(fid)] = FactionRelation.from_dict(fr[fid])

	return cd
