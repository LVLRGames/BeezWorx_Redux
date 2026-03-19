# BeezWorx MVP Spec: Combat / Threat / Raid System

This document specifies the combat resolution model, threat taxonomy, the raid
director, hive siege and breach mechanics, the soft boundary predator system, and
environmental hazards. It is the authoritative reference for `CombatSystem`,
`ThreatDirector`, and all hostile interactions between the colony and the world.

---

## Purpose and scope

Combat in BeezWorx is ecological, not mechanical. The colony is not an army — it is
a living organism that can be hurt, overwhelmed, and destroyed. Threats are part of
the ecosystem: bears want honey, hornets want territory, rival bees want resources.
The player's job is to manage the colony such that these pressures never become
catastrophic.

This spec covers:
- Combat resolution: hit, damage, death
- Threat taxonomy: insect threats, large animal threats, aerial threats, rival colony
- The raid director: how threats spawn, scale, and target the colony
- Hive siege: how large threats damage and breach hives
- The soft boundary predator system: birds in open airspace
- Environmental hazards: cold, heat, lightning
- Diplomatic resolution: threats that can be turned by alliance
- EventBus integration and save/load

It does **not** cover: active defense plant behavior (Active Defense Plant spec),
soldier bee AI targeting (AI spec), or alliance mechanics that prevent raids (ColonyState
spec). Those systems interface with combat but are specced separately.

---

## Combat resolution

### Hit model

Combat is resolved as discrete hit events, not continuous damage streams. Each hit:

1. Attacker uses an attack ability (`AbilityDef` with `effect_type = ATTACK`).
2. `CombatSystem.resolve_hit(attacker_id, target_id, ability)` is called.
3. Base damage is computed from ability + attacker stats.
4. Target's defence modifier is applied.
5. Special effects (poison, paralysis, knockback) are applied if present.
6. `PawnState.health` is decremented.
7. If health ≤ 0: `_kill_pawn(target_id, cause)`.

```
func resolve_hit(
    attacker_id: int,
    target_id: int,
    ability: AbilityDef,
    is_player_controlled: bool = false
) -> float:   # returns actual damage dealt

    var attacker: PawnState = PawnRegistry.get_state(attacker_id)
    var target: PawnState   = PawnRegistry.get_state(target_id)
    if target == null or not target.is_alive:
        return 0.0

    var base_damage: float = ability.damage
    var attack_mult: float = _get_attack_multiplier(attacker)
    var defence_mult: float = _get_defence_multiplier(target)

    # Player precision bonus: player-controlled attacker deals slightly more
    if is_player_controlled:
        attack_mult *= 1.1

    var damage: float = base_damage * attack_mult * defence_mult
    _apply_damage(target_id, damage, attacker_id)
    _apply_hit_effects(target_id, ability)
    return damage
```

### Attack and defence multipliers

```
func _get_attack_multiplier(state: PawnState) -> float:
    var mult: float = 1.0
    # Loyalty bonus: high-loyalty soldiers fight harder
    if state.loyalty > 0.85:
        mult *= 1.1
    # Active buff from zippyzap_serum or similar
    mult *= state.active_buffs.get(&"attack_mult", 1.0)
    return mult

func _get_defence_multiplier(state: PawnState) -> float:
    # Returns a damage reduction multiplier (< 1.0 = less damage taken)
    var mult: float = 1.0
    var species: SpeciesDef = Registry.get_species(state.species_id)
    mult *= species.base_defence_mult
    # Active buff from fortify honey or similar
    mult *= state.active_buffs.get(&"defence_mult", 1.0)
    # Hive integrity bonus: pawns fighting near/inside a heavily upgraded hive
    # get minor passive defense from the structure
    return mult
```

### Hit effects

Hit effects are applied after damage. At MVP:

| Effect | Source | Target condition |
|---|---|---|
| Poison | `poison_stinger` ability | Applies `poisoned` status: -2 hp/sec for 10 seconds |
| Paralysis | `paralyzer_stinger` ability | Applies `paralysed` status: movement speed → 0 for 5 seconds |
| Knockback | Large animal attacks (bear, badger) | Pushes target 2–3 units in attack direction |
| Stun | Whip vine (active plant) | Applies `stunned`: unable to act for 2 seconds |

Effects are stored as `active_effects: Dictionary[StringName, EffectInstance]` on
`PawnState`. `CombatSystem._tick_effects(delta)` processes all active effects each frame
for living pawns.

```
class EffectInstance:
    var effect_id:    StringName
    var duration:     float    # remaining seconds
    var magnitude:    float    # effect strength
    var source_id:    int      # pawn that applied it
```

### Hive damage

Hives are not pawns but receive damage from the same system:

```
func apply_hive_damage(hive_id: int, amount: float, attacker_id: int) -> void:
    HiveSystem.apply_damage(hive_id, amount, attacker_id)
    EventBus.hive_integrity_changed.emit(hive_id, HiveSystem.get_hive(hive_id).integrity)
```

Large animals attack hives directly (bear swipes at the tree, badger digs at the base).
Hornets and rival bees attack the hive entrance to force breach. The distinction matters
for active defense plant response — briars slow ground attackers; whip vines target fliers.

---

## Threat taxonomy

### Category 1: Insect threats

Small, fast, numerous. Target honey and individual bees. Can be handled by soldiers.

| Threat | Behavior | Countered by |
|---|---|---|
| Hornet | Attacks flying bees, tries to breach hive entrance | Soldiers, whip vines |
| Rival bee swarm | Attacks territory, attempts hive takeover | Soldiers, defend markers |
| Caterpillar | Eats resource plants | Flytrap, sundew, birds |
| Grasshopper | Eats grass and low plants; controllable with hopperwine | Graze marker, beetle |
| Wasp | Attacks ground insects (ants) on logistics routes | Soldiers, patrol markers |

Insect threats are pawn entities — they have `PawnState`, run their own AI, and can be
killed by combat abilities. They are spawned by `ThreatDirector` as standard pawn nodes.

### Category 2: Large animal threats

Slow, powerful, hard to kill. Target hives directly for honey. Cannot be killed by
individual soldiers — require defensive plants, allied animals, or diplomacy.

| Threat | Behavior | Countered by |
|---|---|---|
| Bear | Approaches hive tree, swipes at it for honey; destroys hive if not stopped | Allied bears, briar slows, diplomatic honey |
| Badger | Digs at hive base (ground-level anchors); relentless | Allied badgers (rare), briar, deep-root upgrade |
| Human (post-MVP) | Attempts to harvest honey colony-wide | Diplomacy, smoke deterrent |

Large animals are not killable by soldier bees. Soldier stingers deal negligible damage
to them. They must be stopped by:
1. Defensive plants slowing/damaging them enough to deter them
2. An allied animal of the same or greater size fighting them off
3. Diplomatic resolution (offering appropriate honey before the raid begins)

**Bear-specific rule:** A bear that has been gifted appropriate honey within the last
`bear_gift_interval_days` is marked `is_allied = true` in `FactionRelation`. Allied
bears will intercept incoming bear raiders and fight them off. An un-allied bear will
raid regardless of any other colony state.

### Category 3: Aerial boundary threats

Exist specifically to enforce altitude boundaries and map soft limits.

| Threat | Behavior | Notes |
|---|---|---|
| Bird (hawk, crow) | Patrols open airspace above tree canopy; auto-attacks any bee that enters | Not spawned by ThreatDirector — always present above canopy threshold |
| Bird (owl) | Night version; patrols same zone | Activated on `EventBus.night_started` |

Birds are not combat encounters — they are instant kills on contact for any pawn that
crosses into their zone without special protection. Their purpose is to enforce the soft
altitude boundary without an invisible wall.

Special cases:
- Queen bee has higher `max_altitude` than workers by default, allowing slightly more
  exploration range before bird zone. Still dangerous.
- `cool_jelly` consumed before flight reduces bird detection range slightly (camouflage
  by scent reduction — not a hard counter but a risk reducer).
- A fully allied bird faction (post-MVP) would open airspace to the colony.

Birds are not pawn entities at MVP — they are triggerzones at altitude thresholds that
instantly call `CombatSystem.resolve_instant_kill(pawn_id, &"bird_strike")`.

### Category 4: Environmental hazards

Not creatures — passive damage sources.

| Hazard | Trigger | Effect | Counter |
|---|---|---|---|
| Cold zone | Entering biome below `cold_threshold` | -hp/sec; movement slow | spicy honey consumed before entry |
| Hot zone | Entering biome above `heat_threshold` | Fatigue doubles; -hp/sec | cool_jelly consumed before entry |
| Rain | Weather event (post-MVP) | Flying pawns ground speed; plant growth boost | Shelter in hive |
| Lightning | Rare weather event (post-MVP) | Instant kill on exposed flying pawn | Shelter in hive |

Cold and hot zone damage is applied by `CombatSystem._tick_hazards(delta)` which checks
each active pawn's current cell biome against `HexTerrainConfig` climate values each
second. The check is cheap (one float comparison per pawn per second).

Consuming honey/jelly before entering a hazard zone applies a timed buff on `PawnState`
that suppresses the hazard damage. Duration is determined by item quality grade and
chemistry channel strength.

---

## Threat director

`ThreatDirector` is a scene-owned manager (not an autoload) that schedules and spawns
threats based on colony state, season, time of day, and distance from territory.

```
class_name ThreatDirector
extends Node

var _spawn_queue:     Array[ThreatSpawnEntry]
var _active_threats:  Dictionary[int, PawnState]   # threat_pawn_id → state
var _raid_cooldowns:  Dictionary[StringName, float] # threat_type → next_allowed_time
```

### Threat scaling inputs

`ThreatDirector` samples these values when deciding whether to spawn a threat:

```
func _compute_threat_context() -> ThreatContext:
    return ThreatContext.new({
        "colony_influence":  ColonyState.get_influence_score(0),
        "hive_count":        HiveSystem.get_hives_for_colony(0).size(),
        "season":            TimeService.current_season,
        "is_night":          TimeService.is_night(),
        "territory_cells":   TerritorySystem.get_cell_count_for_colony(0),
        "honey_in_hives":    HiveSystem.get_colony_inventory_count(0, &"honey_basic"),
        "distance_frontier": _frontier_distance(),   # how far colony has expanded
    })
```

High honey in hives attracts bears and badgers. High influence attracts rival bee
swarms and hornet raids. Night triggers owl zone and nocturnal insects. Seasonal effects:
winter suppresses most insect threats; spring/summer is peak insect activity; fall
increases bear activity (pre-hibernation honey-seeking).

### ThreatDef (Resource)

```
class_name ThreatDef
extends Resource

@export var threat_id:        StringName
@export var threat_category:  int          # ThreatCategory enum
@export var species_id:       StringName   # which pawn species to spawn
@export var spawn_count_range: Vector2i    # min/max pawns in group
@export var spawn_distance_range: Vector2i # min/max hex cells from colony border

# Scaling
@export var base_spawn_chance:   float    # probability per check interval (0..1)
@export var influence_scale:     float    # how much colony influence increases this
@export var honey_scale:         float    # how much honey stock increases this
@export var seasonal_multipliers: Array[float]  # [spring, summer, fall, winter]

# Cooldown
@export var raid_cooldown_days:  float    # minimum in-game days between raids of this type

# Diplomatic resolution
@export var can_be_appeased:     bool = false
@export var appeasement_faction: StringName   # faction_id that, if allied, prevents this threat
```

### Spawn check loop

`ThreatDirector._process` runs a spawn check every `SPAWN_CHECK_INTERVAL` seconds
(default: 60 real seconds — one check per minute):

```
func _spawn_check() -> void:
    var context: ThreatContext = _compute_threat_context()
    for threat_def in Registry.get_all_threat_defs():
        if not _is_off_cooldown(threat_def.threat_id):
            continue
        if threat_def.can_be_appeased:
            if ColonyState.get_alliance_level(0, threat_def.appeasement_faction) >= 0.5:
                continue   # allied faction suppresses this threat
        var chance: float = _compute_spawn_chance(threat_def, context)
        if randf() < chance:
            _queue_raid(threat_def, context)
```

### Spawn chance computation

```
func _compute_spawn_chance(def: ThreatDef, ctx: ThreatContext) -> float:
    var chance: float = def.base_spawn_chance
    chance += ctx.colony_influence * def.influence_scale
    chance += ctx.honey_in_hives * def.honey_scale * 0.001  # normalise honey units
    chance *= def.seasonal_multipliers[ctx.season]
    return clampf(chance, 0.0, 0.8)   # hard cap: never guaranteed
```

### Spawn execution

When a raid is queued:

```
func _execute_raid(entry: ThreatSpawnEntry) -> void:
    var count: int = randi_range(entry.def.spawn_count_range.x, entry.def.spawn_count_range.y)
    var spawn_cell: Vector2i = _find_spawn_cell(entry.def.spawn_distance_range)

    for i in count:
        var pawn_id: int = PawnManager.spawn_threat_pawn(
            entry.def.species_id,
            spawn_cell,
            colony_id = -1   # neutral/hostile
        )
        _active_threats[pawn_id] = PawnRegistry.get_state(pawn_id)

    _raid_cooldowns[entry.def.threat_id] = TimeService.world_time + (
        entry.def.raid_cooldown_days * TimeService.config.day_length_seconds
    )
    EventBus.raid_started.emit(_next_raid_id, 0)   # target = player colony
    _next_raid_id += 1
```

Threat pawns spawn outside territory, just beyond the colony's fringe cells. They
navigate inward toward the highest honey concentration (bears) or toward the nearest
hive (hornets) or toward any bee pawn in territory (rival bees).

### Raid conclusion

A raid ends when:
- All threat pawns in the group are dead or fled (health < 20% triggers flee for most threats)
- The threat pawns have been repelled beyond `RETREAT_DISTANCE` from the colony border
- A time limit expires (large animals give up after `ThreatDef.max_raid_duration` seconds)

```
func _check_raid_end(raid_id: int) -> void:
    var all_fled: bool = _raid_pawns[raid_id].all(
        func(id): return not PawnRegistry.get_state(id).is_alive
                     or _is_beyond_retreat_distance(id)
    )
    if all_fled:
        EventBus.raid_ended.emit(raid_id)
        _cleanup_raid(raid_id)
```

---

## Hive siege mechanics

### Large animal siege

Bears and badgers target a specific hive (the one with the most honey, or the capital
hive if honey is tied). They navigate to the anchor cell and begin attacking:

```
# Bear attack loop (in PawnAI for bear threat pawn):
SUBTASK_NAVIGATE(target_hive.anchor_cell)
SUBTASK_ABILITY(attack_hive, repeat_until: "hive_integrity == 0 or deterred")
```

`attack_hive` is a special ability that calls `CombatSystem.apply_hive_damage` rather
than targeting another pawn. Damage per hit: 15–25 (tunable on ThreatDef). With
default hive integrity of 100, a bear needs 4–7 hits to destroy an undefended hive.

**Deterrence:** If the bear takes sufficient plant damage (briar thorns + whip vine
hits) during its approach, a deterrence score accumulates. At deterrence threshold, the
bear abandons the raid and retreats. This is the primary intended counter — not killing
the bear but making the approach painful enough it gives up.

### Hornet / rival bee breach

Flying insect threats do not attack the hive structure directly. They target the
entrance and attempt to breach the interior:

```
# Breach attempt:
var breach_time: float = HiveSystem.get_hive(hive_id).breach_timer
# breach_timer set by HiveSystem when integrity < breach_threshold
# Hornets accelerate breach by attacking the entrance zone
if attacker_near_entrance and hive.integrity < breach_threshold:
    hive.breach_timer -= HORNET_BREACH_ACCELERATION * delta
```

Once breach_timer reaches zero, hornets enter the hive interior. Inside:
- They attack sleeping bees (easy targets).
- They consume honey from storage slots.
- They are fought by any soldiers inside the hive.
- The HARDENED_ENTRANCE upgrade doubles breach_timer, making breach significantly harder.

Breach state is visualised: the hive model shows visible damage at the entrance, and
pawns sleeping inside that are attacked during breach have a chance to wake and flee.

---

## Soft boundary predator system

Birds enforce the altitude ceiling passively. No spawn check needed — they are always
present above the canopy threshold.

```
# In CombatSystem._tick_boundary_threats(delta):
for pawn_id in PawnRegistry.get_all_flying_pawn_ids():
    var state: PawnState = PawnRegistry.get_state(pawn_id)
    var altitude: float = PawnManager.get_node(pawn_id).global_position.y
    var terrain_height: float = HexWorldState.get_height_at(state.last_known_cell)
    var canopy_height: float = terrain_height + CANOPY_THRESHOLD   # ~3.0 units above terrain

    if altitude > canopy_height + BIRD_ZONE_ENTRY_MARGIN:
        # Check if pawn has active bird deterrent buff
        if not state.active_buffs.has(&"bird_deterrent"):
            _trigger_bird_strike(pawn_id)
```

`_trigger_bird_strike` is called at most once per pawn per 5 seconds — birds don't
machine-gun the player but they don't miss either. A single bird strike on a worker
bee is instant death. On the queen, it deals 60% of max health (survivable once,
lethal if she stays in the zone).

The player should learn the altitude boundary through early encounters, not a tutorial
popup. The first time a bee flies too high and dies to a bird strike is the lesson.

**Distance boundary:** The further a pawn strays from territory, the more frequent
and aggressive random hostile spawns become. This is handled by `ThreatDirector`
sampling `_frontier_distance()` — spawns outside territory scale in frequency with
distance. At very large distances, threats spawn in large groups and respawn quickly,
making extended exploration without an ally escort extremely dangerous.

---

## Diplomatic threat resolution

Some threats have `can_be_appeased = true` and an `appeasement_faction` field.
When the player has established alliance with that faction above 0.5 relation:

```
# In _spawn_check():
if threat_def.can_be_appeased:
    if ColonyState.get_alliance_level(0, threat_def.appeasement_faction) >= 0.5:
        continue   # threat suppressed
```

This means alliances have direct combat consequences:
- Allied bears fight off bear raiders.
- Allied ant colony defends against rival ant swarms.
- Allied bird flock (post-MVP) opens airspace.

The player must maintain alliances to maintain these protections. Alliance decay (from
ColonyState spec) means the protection is not permanent — the player must keep gifting.

---

## EventBus integration

```
# Emitted by CombatSystem:
EventBus.pawn_hit(attacker_id, target_id, damage, effect_ids)
EventBus.pawn_died(pawn_id, colony_id, cause)
EventBus.hive_breached(hive_id, attacker_type)

# Emitted by ThreatDirector:
EventBus.raid_started(raid_id, target_colony_id)
EventBus.raid_ended(raid_id)
EventBus.threat_spawned(pawn_id, threat_type, near_cell)
EventBus.threat_deterred(pawn_id, threat_type)   # large animal gave up

# Consumed by CombatSystem:
EventBus.day_changed        → tick hazard checks; reset daily deterrence accumulators
EventBus.season_changed     → update active threat spawn tables
EventBus.faction_relation_changed → recheck appeasement states for all active threats

# Consumed by ThreatDirector:
EventBus.hive_built         → recompute threat targeting priority (new honey target)
EventBus.hive_destroyed     → remove from threat target list
EventBus.territory_expanded → update frontier_distance
EventBus.colony_influence_changed → update spawn chance cache
```

---

## Save / load

`ThreatDirector` saves:

```
func save_state() -> Dictionary:
    return {
        "raid_cooldowns":  _raid_cooldowns.duplicate(),
        "active_raids":    _save_active_raids(),
        "schema_version":  1,
    }
```

Active threat pawns are saved as part of `PawnRegistry` (they are standard pawn states
with `colony_id = -1`). Raid cooldowns are saved so the player cannot exploit reloads
to reset threat timers. Active raids are restored on load — if a bear was mid-approach
when the player saved, it continues its approach on load.

---

## MVP scope notes

Deferred past MVP:

- Human threats and smoke deterrent mechanics.
- Full weather-driven combat (rain grounds flying pawns, lightning as instant kill).
- Birds as a full allied faction (opening airspace as a diplomatic reward).
- Multi-colony warfare (rival bee colony coordinated raids rather than just swarm
  skirmishes — this requires the Rival Colony spec to be fully implemented).
- Badger-specific counter mechanics (badgers are notoriously hard to appease — post-MVP
  design challenge).
- Threat escalation over multiple failed raids (a bear that has been deterred twice
  comes back with more determination — persistent threat memory).
- Hive takeover flow as a full player-initiated operation (data model supports it via
  integrity system; the full infiltration sequence is designed but post-MVP).
