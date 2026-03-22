# FILE: res://autoloads/colony_state.gd
# Autoload. Owns all colony-level data: queen lineage, known recipes,
# loyalty, morale, faction relations, and influence scores.
#
# BOUNDARY CONTRACT:
#   Reads HexWorldState only for world_time when computing morale/loyalty decay.
#   Never writes to HexWorldState or calls into the world layer directly.
#   All cross-system communication goes through EventBus signals.
#
# NOTE: class_name intentionally omitted — accessed via autoload name ColonyState.
extends Node

# ── Constants ────────────────────────────────────────────────────────────────
const PLAYER_COLONY_ID: int = 0
const BASE_MORALE: float    = 1.0
const MIN_LOYALTY: float    = 0.0
const MAX_LOYALTY: float    = 1.0
const BASE_LOYALTY: float   = 0.75

# ── State ────────────────────────────────────────────────────────────────────
var _colonies: Dictionary[int, ColonyData] = {}
var _next_colony_id: int = 0

# ════════════════════════════════════════════════════════════════════════════ #
#  Colony lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func create_colony() -> int:
	var id: int = _next_colony_id
	_next_colony_id += 1

	var cd := ColonyData.new()
	cd.colony_id    = id
	cd.display_name = "Colony %d" % id
	cd._morale_cache = BASE_MORALE
	cd._morale_dirty = false

	_colonies[id] = cd

	EventBus.colony_founded.emit(id)
	return id

func get_colony(colony_id: int) -> ColonyData:
	return _colonies.get(colony_id, null)

func get_player_colony() -> ColonyData:
	return _colonies.get(PLAYER_COLONY_ID, null)

# ════════════════════════════════════════════════════════════════════════════ #
#  Queen management
# ════════════════════════════════════════════════════════════════════════════ #

func set_queen(colony_id: int, pawn_id: int) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		push_warning("ColonyState.set_queen: colony %d not found" % colony_id)
		return
	cd.queen_pawn_id = pawn_id

func get_queen_id(colony_id: int) -> int:
	var cd: ColonyData = _colonies.get(colony_id)
	return cd.queen_pawn_id if cd != null else -1

func record_queen_death(colony_id: int, cause: StringName) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return

	var ts: int = _current_day()
	var qr := QueenRecord.new()
	qr.pawn_id     = cd.queen_pawn_id
	qr.pawn_name   = ""          # PawnRegistry fills this in Phase 3
	qr.reign_start = cd.queen_history.back().reign_start \
		if not cd.queen_history.is_empty() else 0
	qr.reign_end   = ts
	qr.cause       = cause
	cd.queen_history.append(qr)

	cd.queen_pawn_id = -1

	var had_heir: bool = not cd.heir_ids.is_empty()
	EventBus.queen_died.emit(colony_id, had_heir)

	if not had_heir:
		EventBus.colony_dissolved.emit(colony_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  Heirs
# ════════════════════════════════════════════════════════════════════════════ #

func add_heir(colony_id: int, pawn_id: int) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return
	if not cd.heir_ids.has(pawn_id):
		cd.heir_ids.append(pawn_id)

func remove_heir(colony_id: int, pawn_id: int) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return
	cd.heir_ids.erase(pawn_id)

func get_heirs(colony_id: int) -> Array[int]:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return []
	return cd.heir_ids.duplicate()

# ════════════════════════════════════════════════════════════════════════════ #
#  Knowledge
# ════════════════════════════════════════════════════════════════════════════ #

func add_known_recipe(colony_id: int, recipe_id: StringName) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return
	if not cd.known_recipe_ids.has(recipe_id):
		cd.known_recipe_ids.append(recipe_id)
		EventBus.recipe_discovered.emit(colony_id, recipe_id)

func knows_recipe(colony_id: int, recipe_id: StringName) -> bool:
	var cd: ColonyData = _colonies.get(colony_id)
	return cd != null and cd.known_recipe_ids.has(recipe_id)

func get_known_recipes(colony_id: int) -> Array[StringName]:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return []
	return cd.known_recipe_ids.duplicate()

func add_known_plant(colony_id: int, plant_id: StringName) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return
	if not cd.known_plants.has(plant_id):
		cd.known_plants.append(plant_id)

func knows_plant(colony_id: int, plant_id: StringName) -> bool:
	var cd: ColonyData = _colonies.get(colony_id)
	return cd != null and cd.known_plants.has(plant_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  Loyalty
# ════════════════════════════════════════════════════════════════════════════ #

func get_loyalty(pawn_id: int) -> float:
	# Loyalty is stored per-pawn in the colony that owns them.
	# We search all colonies since PawnRegistry isn't queried here.
	for cd: ColonyData in _colonies.values():
		if cd._loyalty_cache.has(pawn_id):
			return cd._loyalty_cache[pawn_id]
	return BASE_LOYALTY

func modify_loyalty(pawn_id: int, delta: float, cause: StringName) -> void:
	# Find the colony that owns this pawn
	for cd: ColonyData in _colonies.values():
		if cd._loyalty_cache.has(pawn_id):
			var old_val: float = cd._loyalty_cache[pawn_id]
			var new_val: float = clampf(old_val + delta, MIN_LOYALTY, MAX_LOYALTY)
			cd._loyalty_cache[pawn_id] = new_val
			EventBus.pawn_loyalty_changed.emit(pawn_id, new_val)
			return

	# Pawn not yet in cache — initialise at base loyalty and apply delta
	# Find the colony via PawnRegistry once it exists (Phase 3 TODO).
	# For now default to player colony.
	var cd: ColonyData = _colonies.get(PLAYER_COLONY_ID)
	if cd == null:
		return
	var new_val: float = clampf(BASE_LOYALTY + delta, MIN_LOYALTY, MAX_LOYALTY)
	cd._loyalty_cache[pawn_id] = new_val
	EventBus.pawn_loyalty_changed.emit(pawn_id, new_val)

## Called by PawnRegistry when a pawn is first registered to initialise
## their loyalty entry. Phase 3 will wire this up.
func init_pawn_loyalty(colony_id: int, pawn_id: int, initial: float = BASE_LOYALTY) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return
	cd._loyalty_cache[pawn_id] = clampf(initial, MIN_LOYALTY, MAX_LOYALTY)

## Called by PawnRegistry on pawn death / deregistration.
func remove_pawn_loyalty(pawn_id: int) -> void:
	for cd: ColonyData in _colonies.values():
		cd._loyalty_cache.erase(pawn_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  Morale
# ════════════════════════════════════════════════════════════════════════════ #

func get_morale(colony_id: int) -> float:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return 0.0
	if cd._morale_dirty:
		_recompute_morale(cd)
	return cd._morale_cache

func get_morale_modifiers(colony_id: int) -> Array:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return []
	return cd._morale_modifiers.duplicate()

## Add a temporary or permanent morale modifier.
## expires_day = -1 means permanent until explicitly removed.
func add_morale_modifier(colony_id: int, mod: MoraleModifier) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return
	# Replace existing modifier with same source_id
	for i: int in cd._morale_modifiers.size():
		if cd._morale_modifiers[i].source_id == mod.source_id:
			cd._morale_modifiers[i] = mod
			cd._morale_dirty = true
			EventBus.colony_morale_changed.emit(colony_id, get_morale(colony_id))
			return
	cd._morale_modifiers.append(mod)
	cd._morale_dirty = true
	EventBus.colony_morale_changed.emit(colony_id, get_morale(colony_id))

## Tick morale — expire timed modifiers. Call from TimeService.day_changed.
func tick_morale(current_day: int) -> void:
	for cd: ColonyData in _colonies.values():
		var before: int = cd._morale_modifiers.size()
		cd._morale_modifiers = cd._morale_modifiers.filter(
			func(m: MoraleModifier) -> bool:
				return m.expires_day < 0 or m.expires_day > current_day
		)
		if cd._morale_modifiers.size() != before:
			cd._morale_dirty = true

func _recompute_morale(cd: ColonyData) -> void:
	var total: float = BASE_MORALE
	for mod: MoraleModifier in cd._morale_modifiers:
		total += mod.value
	cd._morale_cache = clampf(total, 0.0, 2.0)
	cd._morale_dirty = false

# ════════════════════════════════════════════════════════════════════════════ #
#  Faction relations
# ════════════════════════════════════════════════════════════════════════════ #

func get_relation(colony_id: int, faction_id: StringName) -> float:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return 0.0
	var fr: FactionRelation = cd.faction_relations.get(faction_id)
	return fr.relation_score if fr != null else 0.0

func modify_relation(colony_id: int, faction_id: StringName,
		delta: float, _cause: StringName) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return
	var fr: FactionRelation = _get_or_create_relation(cd, faction_id)
	fr.relation_score = clampf(fr.relation_score + delta, -1.0, 1.0)
	_update_alliance_flags(fr)
	EventBus.faction_relation_changed.emit(colony_id, faction_id, fr.relation_score)

## Returns 1 = allied, 0 = neutral, -1 = hostile.
## Thresholds will be driven by FactionDef in Phase 7.
func get_alliance_level(colony_id: int, faction_id: StringName) -> int:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return 0
	var fr: FactionRelation = cd.faction_relations.get(faction_id)
	if fr == null:
		return 0
	if fr.is_allied:
		return 1
	if fr.is_hostile:
		return -1
	return 0

## Record a gift trade and update relation score.
## match_score is 0.0–1.0 indicating how well the item matched faction preferences.
## FactionDef-driven preference logic is Phase 7. For now uses a flat scale.
func resolve_gift(colony_id: int, faction_id: StringName,
		item_id: StringName, count: int) -> float:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return 0.0

	# Placeholder match score until FactionDef preference data exists
	var match_score: float = 0.5
	var relation_delta: float = match_score * clampf(count * 0.01, 0.0, 0.2)

	var fr: FactionRelation = _get_or_create_relation(cd, faction_id)
	fr.last_gift_day = _current_day()

	var tr := TradeRecord.new()
	tr.day            = fr.last_gift_day
	tr.item_id        = item_id
	tr.item_count     = count
	tr.match_score    = match_score
	tr.relation_delta = relation_delta
	fr.trade_history.append(tr)

	# Keep trade history bounded to last 50 trades
	if fr.trade_history.size() > 50:
		fr.trade_history.pop_front()

	modify_relation(colony_id, faction_id, relation_delta, &"gift")
	EventBus.trade_completed.emit(colony_id, faction_id, item_id, match_score)

	return match_score

func _get_or_create_relation(cd: ColonyData, faction_id: StringName) -> FactionRelation:
	if not cd.faction_relations.has(faction_id):
		var fr := FactionRelation.new()
		fr.faction_id        = faction_id
		fr.first_contact_day = _current_day()
		cd.faction_relations[faction_id] = fr
	return cd.faction_relations[faction_id]

func _update_alliance_flags(fr: FactionRelation) -> void:
	# Thresholds: allied >= 0.6, hostile <= -0.4
	# These will be overridden by FactionDef.ally_threshold in Phase 7.
	fr.is_allied  = fr.relation_score >= 0.6
	fr.is_hostile = fr.relation_score <= -0.4

# ════════════════════════════════════════════════════════════════════════════ #
#  Influence
# ════════════════════════════════════════════════════════════════════════════ #

func get_influence_score(colony_id: int) -> float:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return 0.0
	if cd._influence_dirty:
		recompute_influence(colony_id)
	return cd._influence_score

## Recompute influence from known recipes, allies, and hive count.
## Full formula is Phase 5 (territory) + Phase 7 (diplomacy).
## For now: recipes × 1 + allied factions × 10.
func recompute_influence(colony_id: int) -> void:
	var cd: ColonyData = _colonies.get(colony_id)
	if cd == null:
		return
	var score: float = float(cd.known_recipe_ids.size())
	for fid: StringName in cd.faction_relations:
		if cd.faction_relations[fid].is_allied:
			score += 10.0
	cd._influence_score = score
	cd._influence_dirty = false
	EventBus.colony_influence_changed.emit(colony_id, score)

# ════════════════════════════════════════════════════════════════════════════ #
#  Save / Load
# ════════════════════════════════════════════════════════════════════════════ #

func save_state() -> Dictionary:
	var out: Dictionary = {}
	for id: int in _colonies:
		out[str(id)] = _colonies[id].to_dict()
	return {
		"colonies":        out,
		"next_colony_id":  _next_colony_id,
	}

func load_state(data: Dictionary) -> void:
	_colonies.clear()
	_next_colony_id = data.get("next_colony_id", 0)
	var raw: Dictionary = data.get("colonies", {})
	for key: String in raw:
		var cd: ColonyData = ColonyData.from_dict(raw[key])
		_colonies[int(key)] = cd

# ════════════════════════════════════════════════════════════════════════════ #
#  Helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _current_day() -> int:
	# TimeService is registered after ColonyState in autoload order,
	# so guard against it not being ready during early init.
	var ts: Node = get_node_or_null("/root/TimeService")
	if ts != null and ts.has_method("elapsed_days"):
		return ts.elapsed_days()
	return 0
