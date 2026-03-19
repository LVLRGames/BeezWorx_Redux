# BeezWorx MVP Spec: Colony State / Loyalty / Morale System

This document specifies `ColonyState`, the per-colony data autoload that owns queen
identity and history, heir tracking, recipe discovery, pawn loyalty, colony morale,
faction relations, and influence score. It is the authoritative reference for all
colony-level aggregate state and the rules that govern when pawns abandon the colony.

---

## Purpose and scope

`ColonyState` is the colony's "mind" — the persistent record of what a colony knows,
who leads it, who is loyal to it, and how it relates to the outside world. It does not
simulate individual pawn behavior (that is PawnAI) or hive infrastructure (that is
HiveSystem). It owns the colony-level aggregates that those systems read and write into.

This spec covers:
- ColonyData structure: one record per colony (player and AI)
- Queen identity, history, and succession state
- Heir tracking
- Recipe discovery and the known recipes registry
- Pawn loyalty: causes of gain and loss, abandonment threshold
- Colony morale: derived aggregate, effects on AI behavior
- Faction relations: alliance, neutrality, hostility, trade history
- Colony influence score: used by factions and rival colonies to assess the player
- EventBus integration and save/load

It does **not** cover: hive slot mechanics (HiveSystem), egg feeding (LifecycleSystem),
job claiming (JobSystem), or pawn AI behavior (AI spec). Those systems read from and
write to ColonyState via the API defined here.

---

## ColonyState (autoload)

```
class_name ColonyState
extends Node

var _colonies: Dictionary[int, ColonyData]   # colony_id → ColonyData
var _next_colony_id: int = 0
```

Player colony is always `colony_id = 0`, created at game start.
AI colonies are created by `LifecycleSystem` when princess exile triggers
`create_colony()` or by the world generator for pre-existing rival factions.

### Public API summary

```
func create_colony() -> int                              # returns new colony_id
func get_colony(colony_id: int) -> ColonyData
func get_player_colony() -> ColonyData                   # shorthand for get_colony(0)

# Queen
func set_queen(colony_id: int, pawn_id: int) -> void
func get_queen_id(colony_id: int) -> int                 # -1 if no queen
func record_queen_death(colony_id: int, cause: StringName) -> void

# Heirs
func add_heir(colony_id: int, pawn_id: int) -> void
func remove_heir(colony_id: int, pawn_id: int) -> void
func get_heirs(colony_id: int) -> Array[int]

# Recipes
func add_known_recipe(colony_id: int, recipe_id: StringName) -> void
func knows_recipe(colony_id: int, recipe_id: StringName) -> bool
func get_known_recipes(colony_id: int) -> Array[StringName]

# Loyalty
func get_loyalty(pawn_id: int) -> float
func modify_loyalty(pawn_id: int, delta: float, cause: StringName) -> void

# Morale
func get_morale(colony_id: int) -> float                 # derived, 0..1
func get_morale_modifiers(colony_id: int) -> Array[MoraleModifier]

# Factions
func get_relation(colony_id: int, faction_id: StringName) -> FactionRelation
func modify_relation(colony_id: int, faction_id: StringName, delta: float, cause: StringName) -> void
func get_alliance_level(colony_id: int, faction_id: StringName) -> float

# Influence
func get_influence_score(colony_id: int) -> float        # derived
func recompute_influence(colony_id: int) -> void
```

---

## ColonyData (RefCounted)

```
class_name ColonyData
extends RefCounted

var colony_id:      int
var display_name:   String      # "The Heatherbee Colony" etc; generated or player-named

# Queen and succession
var queen_pawn_id:  int = -1
var heir_ids:       Array[int]
var contest_active: bool = false
var contest_day:    int = -1
var queen_history:  Array[QueenRecord]

# Recipes
var known_recipe_ids: Array[StringName]

# Loyalty cache (pawn_id → loyalty float, mirrored from PawnState for fast queries)
var _loyalty_cache: Dictionary[int, float]

# Morale
var _morale_cache:       float = 1.0    # 0..1; rebuilt on dirty flag
var _morale_dirty:       bool = true
var _morale_modifiers:   Array[MoraleModifier]  # active modifiers contributing to morale

# Faction relations
var faction_relations: Dictionary[StringName, FactionRelation]  # faction_id → FactionRelation

# Influence
var _influence_score:  float = 0.0   # rebuilt by recompute_influence()
var _influence_dirty:  bool = true
```

---

## Queen identity and history

### QueenRecord

```
class QueenRecord:
    var pawn_name:   String
    var pawn_id:     int
    var reign_start: int      # TimeService.current_day when she became queen
    var reign_end:   int = -1 # -1 while still reigning
    var cause:       StringName  # "old_age", "combat", "unknown"
```

When a queen is crowned, a new `QueenRecord` is appended with `reign_end = -1`.
When she dies, `reign_end` and `cause` are filled in by `record_queen_death`.

`queen_history` grows indefinitely. For long-running colonies this becomes a genuine
historical record. Long-lived allied creatures query it for dialogue:

```
# How to determine generational reference for bear dialogue:
func get_generations_since_first_contact(colony_id: int, first_contact_day: int) -> int:
    var count: int = 0
    for record in _colonies[colony_id].queen_history:
        if record.reign_start >= first_contact_day:
            count += 1
    return count
```

A bear who met the colony 800 days ago, with a queen lifespan of 1095 days, may have
outlived zero, one, or two queens depending on when contact was made. The dialogue
system queries this and selects: "I knew your mother" (1 predecessor), "I knew your
grandmother" (2), or "I've watched this colony since before your line began" (3+).

---

## Recipe discovery

### Known recipes registry

The queen discovers recipes by experimentation in a hive crafting slot. Once discovered,
any pawn with the appropriate `required_role_tags` on the `RecipeDef` can craft it.

```
func add_known_recipe(colony_id: int, recipe_id: StringName) -> void:
    var colony: ColonyData = _colonies[colony_id]
    if colony.known_recipe_ids.has(recipe_id):
        return
    colony.known_recipe_ids.append(recipe_id)
    EventBus.recipe_discovered.emit(colony_id, recipe_id)
```

`RecipeSystem` (a static helper class, not an autoload) validates ingredient combinations
and calls this when a match is found. It lives in `colony/recipe_system.gd`.

### Always-known recipes

At colony creation, `known_recipe_ids` is pre-populated with the always-known list
(see Item/Resource spec). AI colonies also start with this base set.

---

## Pawn loyalty

### What loyalty represents

Loyalty is a pawn's bond to their colony. A pawn with high loyalty works diligently,
tolerates hardship, and does not leave even under stress. A pawn with low loyalty works
reluctantly, is more likely to fail jobs, and will eventually abandon the colony.

Loyalty is a `float` on `PawnState` (0.0 to 1.0). `ColonyState` mirrors it in
`_loyalty_cache` for fast colony-wide queries without iterating all pawns.

### Starting loyalty

New pawns emerge with `loyalty = 0.75` — moderate commitment that must be earned up to
full loyalty through good conditions or can be lost through neglect.

### Loyalty gain causes

| Cause | Delta | Notes |
|---|---|---|
| Slept in assigned bed slot | +0.01/day | Small daily reward for proper housing |
| Fed (not starving) | +0.005/day | Basic needs met |
| Colony morale high (> 0.75) | +0.005/day | Collective mood is contagious |
| Successful job completion | +0.01 per job | Feeling productive |
| Queen personally performed action near pawn | +0.02 | Queen's presence inspires |
| Personality: stubbornness | multiplier on all gains | Stubborn bees hold loyalty longer |

"Queen personally performed action near pawn" fires when the player-controlled queen
uses any ability within 3 hex cells of a worker. This creates a subtle incentive for the
player to be present in the colony rather than always exploring — the queen's physical
presence matters to her workers.

### Loyalty loss causes

| Cause | Delta | Notes |
|---|---|---|
| No bed slot available | -0.03/day | Most damaging common cause |
| Slept in wrong slot (not assigned bed) | -0.01/day | Minor discomfort |
| Collapsed from fatigue (no slot found) | -0.05 per event | Acute penalty |
| Starving (no food in any hive) | -0.05/day | Severe |
| Hive destroyed (bed slot lost) | -0.10 immediate | Acute shock |
| Colony morale low (< 0.25) | -0.01/day | Collective despair |
| Job failed repeatedly | -0.005 per fail | Frustration |
| No queen in colony | -0.02/day | Leaderless anxiety |
| Personality: stubbornness | reduces all loss rates | Stubborn bees endure hardship |

### Abandonment

When `loyalty <= 0.0`:

```
func _check_abandonment(pawn_id: int) -> void:
    var state: PawnState = PawnRegistry.get_state(pawn_id)
    if state.loyalty > 0.0:
        return
    if state.role_id == &"queen":
        return   # queens do not abandon; they die

    # Pawn announces departure (dialogue line: "I can't do this anymore.")
    # Then walks to colony border and despawns
    _trigger_abandonment(pawn_id)
```

Abandonment is not instant. The pawn posts a private `LEAVE_COLONY` job, walks to
the territory border, emits a farewell ambient dialogue line, and despawns. This gives
the player a brief window to see what is happening and a reminder to fix the underlying
cause before more pawns follow.

### Loyalty thresholds and behavior effects

| Loyalty range | Behavior effect |
|---|---|
| 0.9 – 1.0 | Works at full efficiency; slight speed bonus (morale boost) |
| 0.6 – 0.9 | Normal behavior |
| 0.3 – 0.6 | Works 10% slower; more likely to idle between tasks |
| 0.1 – 0.3 | Works 25% slower; may skip low-priority jobs; visible sadness animation |
| 0.0 – 0.1 | Abandonment imminent; works minimally; dialogue hints at dissatisfaction |

Loyalty effects on work speed are applied as a multiplier in `PawnAI` when evaluating
job execution speed. The multiplier is read from a curve on `SpeciesDef` sampled by
`loyalty` value, same pattern as the carry weight speed curve.

---

## Colony morale

### What morale represents

Morale is a colony-wide derived float (0.0 to 1.0) representing the collective
wellbeing of the colony. It is not stored directly — it is recomputed when dirty
and cached. Individual loyalty scores are the inputs; morale is the output.

### Morale computation

```
func get_morale(colony_id: int) -> float:
    var colony: ColonyData = _colonies[colony_id]
    if not colony._morale_dirty:
        return colony._morale_cache

    var pawn_ids: Array[int] = PawnRegistry.get_pawns_for_colony(colony_id)
    if pawn_ids.is_empty():
        colony._morale_cache = 0.0
        colony._morale_dirty = false
        return 0.0

    var sum: float = 0.0
    for pawn_id in pawn_ids:
        sum += colony._loyalty_cache.get(pawn_id, 0.5)

    var base_morale: float = sum / pawn_ids.size()

    # Apply morale modifiers (events, upgrades, season effects)
    var modifier_total: float = 0.0
    for mod in colony._morale_modifiers:
        modifier_total += mod.value
    colony._morale_cache = clampf(base_morale + modifier_total, 0.0, 1.0)
    colony._morale_dirty = false
    return colony._morale_cache
```

### MoraleModifier

```
class MoraleModifier:
    var source_id:   StringName  # what caused this modifier
    var value:       float       # positive or negative
    var expires_day: int = -1    # -1 = permanent until removed; else removed on this day
    var description: String      # shown in colony management UI
```

Example modifiers:

| Source | Value | Duration | Trigger |
|---|---|---|---|
| Queen is present in capital hive | +0.05 | While active | Queen in capital |
| Hive destroyed | -0.15 | 7 days | `hive_destroyed` event |
| New ally gained | +0.10 | 14 days | `faction_relation_changed` to allied |
| Ally lost | -0.10 | 7 days | Relation drops below threshold |
| Winter (no food production) | -0.05 | Duration of winter | `season_changed` |
| Colony has a princess being raised | +0.05 | While egg exists | Heir in nursery |
| Successful raid defense | +0.15 | 5 days | Raid ended, colony survived |
| Queen died | -0.30 | Until new queen crowned | `queen_died` |

Morale feeds back into loyalty (high morale grants daily loyalty gain, low morale
causes daily loyalty loss — see loyalty table above), creating a coherent loop where
a colony under stress spirals downward and a thriving colony compounds its own strength.

### Morale dirty flag

`_morale_dirty` is set true whenever `modify_loyalty` is called or a morale modifier
is added or removed. The cache is rebuilt lazily on the next `get_morale` call. This
avoids rebuilding morale every frame while keeping it current when queried.

---

## Faction relations

### FactionRelation

```
class FactionRelation:
    var faction_id:      StringName
    var relation_score:  float = 0.0       # -1.0 (hostile) to 1.0 (full ally)
    var is_allied:       bool = false      # true when score >= ALLY_THRESHOLD (0.5)
    var is_hostile:      bool = false      # true when score <= HOSTILE_THRESHOLD (-0.3)
    var trade_history:   Array[TradeRecord]
    var first_contact_day: int = -1        # day player first encountered this faction
    var last_gift_day:   int = -1          # day of last diplomatic gift
    var preference_revealed: bool = false  # true once faction revealed their preferences
```

```
class TradeRecord:
    var day:         int
    var item_id:     StringName
    var item_count:  int
    var match_score: float       # how well the gift matched faction preferences (0..1)
    var relation_delta: float    # how much the relation changed
```

### Relation thresholds

| Score range | State | Effects |
|---|---|---|
| 0.5 – 1.0 | Allied | Faction provides services; loyalty to colony |
| 0.1 – 0.5 | Friendly | Faction is non-hostile; may help occasionally |
| -0.1 – 0.1 | Neutral | Faction ignores colony |
| -0.3 – -0.1 | Wary | Faction is avoidant; may warn colony away from their territory |
| -1.0 – -0.3 | Hostile | Faction actively threatens colony |

### Relation change from gifts

When the queen offers an item to a faction NPC:

```
func _resolve_gift(colony_id: int, faction_id: StringName, item_id: StringName, count: int) -> void:
    var faction_def: FactionDef = Registry.get_faction(faction_id)
    var match_score: float = _score_gift(item_id, count, faction_def)
    var delta: float = _compute_relation_delta(match_score, count, faction_def)

    modify_relation(colony_id, faction_id, delta, &"gift")

    # Record trade
    var record := TradeRecord.new()
    record.day = TimeService.current_day
    record.item_id = item_id
    record.item_count = count
    record.match_score = match_score
    record.relation_delta = delta
    get_relation(colony_id, faction_id).trade_history.append(record)

    # Reveal preferences if first gift above threshold quality
    if match_score >= 0.3 and not get_relation(colony_id, faction_id).preference_revealed:
        get_relation(colony_id, faction_id).preference_revealed = true
        EventBus.faction_preference_revealed.emit(colony_id, faction_id)
```

`_score_gift` computes the dot product between the item's chemistry channel values and
the faction's preference channel weights, normalised 0..1. See dialogue_hint_vocabulary.md
for the vocabulary that maps faction preferences to dialogue hints.

`_compute_relation_delta` scales with match score and quantity:

```
func _compute_relation_delta(match_score: float, count: int, def: FactionDef) -> float:
    # Base delta from match quality
    var base: float = match_score * def.gift_sensitivity   # gift_sensitivity: how much gifts move the needle
    # Diminishing returns on quantity (logarithmic)
    var quantity_mult: float = 1.0 + log(float(count)) * 0.1
    # Grade bonus: higher quality grade items give extra delta
    return base * quantity_mult
```

**Preference revealed:** On the first gift with `match_score >= 0.3`, the faction marks
`preference_revealed = true`. This triggers a special dialogue response from the faction
NPC that confirms the player is on the right track — not revealing the exact recipe,
but confirming the direction. "That... that's almost exactly what I've been wanting."
This is the mechanic reward for the dialogue hint vocabulary working correctly.

### Alliance decay

Allied factions expect regular gifts. If `TimeService.current_day - last_gift_day >
faction_def.gift_interval_days`, the relation score decays at `faction_def.decay_rate`
per day until it drops below the ally threshold. The player receives a subtle warning
(faction's ambient dialogue shifts to hints of dissatisfaction) before the alliance breaks.

This prevents "gift once, ally forever" and keeps the player engaged in the ongoing
relationship. Different factions have different `gift_interval_days` and `decay_rate`
values — bears are patient and need gifting only a few times per season; ants need
more regular attention since their queen is managing a large active workforce.

### Service unlocks

When `is_allied` becomes true for a faction, `EventBus.faction_relation_changed` fires.
Systems that provide services subscribe to this event:

- Ant colony allied → `JobSystem` unlocks ant conveyor trail marker placement
- Bear allied → `CombatSystem` unlocks bear as defensive ally
- Beetle allied → `JobSystem` unlocks beetle earthmoving jobs
- Butterfly swarm allied → `HexWorldState` unlocks access to protected flower fields

Services are revoked when `is_allied` becomes false.

---

## Colony influence score

Influence score is a single float representing how significant the colony appears to
the world — other factions, rival colonies, and the threat director use it to calibrate
their behavior.

```
func recompute_influence(colony_id: int) -> void:
    var colony: ColonyData = _colonies[colony_id]
    var hives: Array[HiveState] = HiveSystem.get_hives_for_colony(colony_id)
    var population: int = PawnRegistry.get_pawns_for_colony(colony_id).size()
    var territory_cells: int = TerritorySystem.get_cell_count_for_colony(colony_id)
    var ally_count: int = _count_allied_factions(colony_id)
    var known_recipes: int = colony.known_recipe_ids.size()

    colony._influence_score = (
        float(hives.size())     * 10.0 +
        float(population)       * 1.0  +
        float(territory_cells)  * 0.1  +
        float(ally_count)       * 15.0 +
        float(known_recipes)    * 2.0
    )
    colony._influence_dirty = false
    EventBus.colony_influence_changed.emit(colony_id, colony._influence_score)
```

Weights are tunable constants. At MVP the formula rewards alliances heavily (15 points
per ally) to encourage the player toward diplomacy as a core strategy.

`recompute_influence` is called on:
- `hive_built`, `hive_destroyed`
- `pawn_spawned`, `pawn_died`
- `territory_expanded`, `territory_faded`
- `faction_relation_changed` (to/from allied)
- `recipe_discovered`

High influence causes rival colonies to perceive the player as a threat and begin
territorial pressure. The threat director uses influence thresholds to scale raid
frequency and intensity (see Combat spec).

---

## EventBus integration

```
# Emitted by ColonyState:
EventBus.recipe_discovered(colony_id, recipe_id)
EventBus.faction_relation_changed(colony_id, faction_id, new_score, new_state)
EventBus.faction_preference_revealed(colony_id, faction_id)
EventBus.trade_completed(colony_id, faction_id, item_id, match_score)
EventBus.pawn_loyalty_changed(pawn_id, new_loyalty)
EventBus.colony_influence_changed(colony_id, new_score)
EventBus.colony_morale_changed(colony_id, new_morale)  # emitted when cache rebuilds and value changed by > 0.05

# Consumed by ColonyState:
EventBus.pawn_died          → remove from loyalty cache, remove from heir_ids if princess
EventBus.pawn_spawned       → add to loyalty cache with starting loyalty
EventBus.hive_built         → recompute influence
EventBus.hive_destroyed     → add morale modifier, recompute influence
EventBus.day_changed        → apply loyalty decay/gain, expire morale modifiers, check alliance decay
EventBus.season_changed     → add/remove seasonal morale modifiers
EventBus.queen_died         → add queen_death morale modifier, record_queen_death
EventBus.egg_matured        → if princess: add to heir_ids
EventBus.territory_expanded → recompute influence
EventBus.territory_faded    → recompute influence
```

---

## Save / load

```
func save_state() -> Dictionary:
    var colonies = []
    for colony_id in _colonies:
        var colony: ColonyData = _colonies[colony_id]
        colonies.append({
            "colony_id":        colony.colony_id,
            "display_name":     colony.display_name,
            "queen_pawn_id":    colony.queen_pawn_id,
            "heir_ids":         colony.heir_ids.duplicate(),
            "contest_active":   colony.contest_active,
            "contest_day":      colony.contest_day,
            "queen_history":    colony.queen_history.map(func(r): return r.to_dict()),
            "known_recipe_ids": colony.known_recipe_ids.duplicate(),
            "loyalty_cache":    colony._loyalty_cache.duplicate(),
            "morale_modifiers": colony._morale_modifiers.map(func(m): return m.to_dict()),
            "faction_relations": _save_faction_relations(colony),
        })
    return {"colonies": colonies, "next_colony_id": _next_colony_id, "schema_version": 1}
```

On load: colonies are restored first, then `_morale_dirty` and `_influence_dirty` are
set true so both values recompute cleanly on first query. Loyalty cache is restored
directly (not recomputed) since it mirrors saved `PawnState` loyalty values.

---

## MVP scope notes

Deferred past MVP:

- Per-pawn relationship tracking (friendship/rivalry between specific pawns). At MVP,
  loyalty is a colony bond only — not a social graph between individuals.
- Faction sub-factions (e.g. individual ant colonies within the larger ant faction, each
  with their own preferences and queen). At MVP, each faction is monolithic.
- Reputation spillover between factions (impressing the ants impresses the beetles
  slightly, because they trade). Diplomacy is bilateral at MVP.
- Player-named colonies and custom colony heraldry.
- Colony vs colony diplomacy (player colony negotiating with rival bee colony rather
  than just competing with it). Post-MVP once rival colony AI is more developed.
