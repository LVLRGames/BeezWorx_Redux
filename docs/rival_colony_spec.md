# BeezWorx MVP Spec: Rival Colony System

This document specifies how AI bee colonies exist in the world, how they simulate
autonomously, how they interact with the player colony through territory pressure and
conflict, the hive takeover mechanic, and how daughter colonies from princess exile
integrate with the rival system. It is the authoritative reference for
`RivalColonySimulator` and all AI colony behavior.

---

## Purpose and scope

The world is not empty. Other bee colonies exist — some ancient and established, some
freshly founded from the player's own exiled princesses. They expand, compete for
resources, raid when threatened, and can be negotiated with, conquered, or ignored.

The rival system must feel alive without simulating every pawn at full fidelity. AI
colonies near the player get full simulation. Colonies far away are abstracted to
periodic state updates. The result is a world that reacts to the player's growth
without overwhelming the simulation budget.

This spec covers:
- AI colony archetypes and personalities
- Near vs far simulation: full fidelity vs abstract
- Territory competition and border pressure
- Raiding behavior toward the player colony
- Player raiding and hive takeover
- Daughter colony integration (princess exile)
- Diplomacy between player and rival colonies
- EventBus integration and save/load

It does **not** cover: territory influence computation (TerritorySystem spec), raid
spawning mechanics (Combat spec), or pawn AI behavior (AI spec). Those systems
serve rival colonies the same way they serve the player colony.

---

## AI colony archetypes

Each rival colony has a `ColonyArchetype` assigned at creation that shapes its
decision-making. Archetypes are not rigid behavior trees — they are weight modifiers
on utility scoring applied at the colony level by `RivalColonySimulator`.

```
enum ColonyArchetype {
    EXPANSIONIST,   # aggressively builds new hives; pushes territory outward
    ISOLATIONIST,   # defends existing territory densely; rarely raids unless threatened
    MERCHANT,       # prioritises diverse honey production; prefers diplomacy to conflict
    SWARM_RAIDER,   # frequently raids neighbors; builds fewer hives, more soldiers
    NOMADIC,        # relocates capital hive occasionally; hard to track and corner
}
```

Archetypes are assigned at colony creation:
- World-generator colonies: assigned from a weighted random distribution biased by biome
  (forest biomes favor Expansionist and Merchant; rocky biomes favor Isolationist)
- Daughter colonies (from player's exiled princesses): inherit a blend of the exile
  princess's personality traits. A bold, curious princess founds an Expansionist colony.
  A stubborn, diligent princess founds an Isolationist one.

```
func _archetype_from_personality(personality: PawnPersonality) -> ColonyArchetype:
    if personality.curiosity > 0.7 and personality.boldness > 0.6:
        return ColonyArchetype.EXPANSIONIST
    if personality.stubbornness > 0.75 and personality.boldness < 0.4:
        return ColonyArchetype.ISOLATIONIST
    if personality.curiosity > 0.6 and personality.diligence > 0.7:
        return ColonyArchetype.MERCHANT
    if personality.boldness > 0.8:
        return ColonyArchetype.SWARM_RAIDER
    return ColonyArchetype.EXPANSIONIST   # default
```

This means the player's breeding choices — which personality traits get passed to
princesses — indirectly determine what kind of rival colonies populate the world.
A player who consistently raises bold, curious princesses populates the world with
aggressive neighbors. A player who raises stubborn, diligent princesses gets defensive
neighbors that largely leave them alone.

---

## Near vs far simulation

### Simulation tiers

```
enum SimulationTier {
    FULL,       # all colony pawns run normal PawnAI; full fidelity
    REDUCED,    # colony-level decisions only; pawns teleport to jobs
    ABSTRACT,   # periodic state updates; no individual pawn simulation
}
```

Tier is determined by distance from the nearest player WorldViewer:

| Distance (chunks) | Tier | Update interval |
|---|---|---|
| 0 – 8 | FULL | Per-pawn AI tick (normal) |
| 9 – 20 | REDUCED | Colony-level decision every 30 seconds |
| 21+ | ABSTRACT | Colony state update once per in-game day |

### Full simulation (FULL tier)

The rival colony runs exactly like the player colony — pawns have `PawnAI`, claim
jobs from `JobSystem`, navigate with `NavigationAgent3D`, and interact with the world
normally. The only difference is all decision-making is AI-driven; no player possession.

This tier activates when the player approaches a rival colony. The transition from
ABSTRACT to FULL is seamless: `RivalColonySimulator` spawns pawn nodes for all
abstract pawns when the colony enters FULL range.

### Reduced simulation (REDUCED tier)

Individual pawn AI is suspended. `RivalColonySimulator` makes colony-level decisions:

```
func _reduced_tick(colony_id: int, delta: float) -> void:
    var colony: ColonyData = ColonyState.get_colony(colony_id)
    var sim: RivalColonyState = _rival_states[colony_id]

    # Decision: should this colony expand?
    if _should_expand(colony_id):
        _abstract_build_hive(colony_id)

    # Decision: should this colony raid?
    if _should_raid(colony_id):
        _queue_abstract_raid(colony_id)

    # Resource simulation: colony produces honey proportional to hive count
    _simulate_resource_production(colony_id, delta)
```

Pawns in REDUCED tier teleport directly to job sites rather than pathfinding. Their
positions are updated to the job target cell at the start of each subtask. This is
invisible to the player since they are too far away to observe individual pawns.

### Abstract simulation (ABSTRACT tier)

Once per in-game day, `RivalColonySimulator` runs a lightweight state update:

```
func _abstract_day_tick(colony_id: int) -> void:
    var sim: RivalColonyState = _rival_states[colony_id]

    # Age all pawns by 1 day; apply natural death
    _age_abstract_pawns(colony_id)

    # Simulate production: honey accumulates proportional to hive count × population
    sim.honey_stock += sim.hive_count * sim.worker_count * ABSTRACT_HONEY_RATE

    # Simulate expansion: Expansionist colonies have a chance to build a new hive
    if _archetype_wants_expansion(colony_id) and randf() < ABSTRACT_EXPAND_CHANCE:
        sim.hive_count += 1
        sim.territory_radius_approx += BASE_TERRITORY_RADIUS

    # Simulate raids: Swarm Raider colonies periodically raid neighbors
    if _archetype_wants_raid(colony_id) and _has_neighbor(colony_id):
        _abstract_raid_result(colony_id)

    # Lifecycle: lay eggs at queen rate; grow population up to housing capacity
    _simulate_abstract_lifecycle(colony_id)
```

Abstract colonies have a `RivalColonyState` — a lightweight struct that summarises
their status without individual pawn data:

```
class RivalColonyState:
    var colony_id:             int
    var archetype:             ColonyArchetype
    var hive_count:            int
    var worker_count:          int
    var soldier_count:         int
    var honey_stock:           float
    var territory_radius_approx: float
    var queen_age_days:        int
    var queen_max_age:         int
    var heir_count:            int    # abstract heirs; no individual pawn tracking
    var last_raid_day:         int
    var relation_to_player:    float  # -1..1
```

When a colony transitions from ABSTRACT to FULL, `RivalColonySimulator` expands
`RivalColonyState` into full `ColonyData` and spawns pawn nodes proportional to
`worker_count` and `soldier_count`. The transition looks like the colony was always
there — because abstractly, it was.

---

## Territory competition

### Border pressure

When two colonies' territory radii overlap, both experience border pressure. The
`TerritorySystem` already handles the influence overlap — the contested cells have
non-zero influence from both colonies.

`RivalColonySimulator` queries contested cells and uses them to drive AI decisions:

```
func _compute_border_pressure(colony_id: int) -> float:
    var contested: int = TerritorySystem.get_contested_cell_count(colony_id)
    var own_cells: int = TerritorySystem.get_cell_count_for_colony(colony_id)
    return float(contested) / float(maxi(own_cells, 1))
```

High border pressure (> 0.3) modifies archetype behavior:
- **Expansionist:** increases expansion speed; tries to build hives that push the border
- **Isolationist:** increases defensive plant cultivation; places defend markers
- **Swarm Raider:** triggers raid evaluation sooner

### Marker competition

Rival colonies place their own job markers in their territory. These are the same
`MarkerData` records as player markers, with `colony_id` set to the rival colony.
Player pawns cannot claim rival colony jobs (colony_id filter in `get_claimable_jobs`).

Rival colony markers in contested cells cause interesting ecological effects:
- A rival GATHER marker on a shared plant means both colonies are competing for the
  same nectar source. Whichever pawn gets there first takes the resource.
- A rival DEFEND marker near the contested border means soldier pawns from the rival
  colony patrol that zone — the player will encounter them there.

---

## Raiding behavior

### AI-initiated raids against the player

`RivalColonySimulator` evaluates raid conditions on each REDUCED or ABSTRACT tick:

```
func _should_raid_player(colony_id: int) -> bool:
    var sim: RivalColonyState = _rival_states[colony_id]
    var rel: float = sim.relation_to_player
    var pressure: float = _compute_border_pressure(colony_id)
    var archetype: ColonyArchetype = sim.archetype

    # Swarm Raiders raid on low cooldown regardless of relation
    if archetype == ColonyArchetype.SWARM_RAIDER:
        return TimeService.current_day - sim.last_raid_day > 7

    # Others raid when border pressure is high and relation is negative
    return pressure > 0.4 and rel < -0.1 and \
           TimeService.current_day - sim.last_raid_day > 14
```

When raid conditions are met, `ThreatDirector` receives a `_queue_rival_raid` call
that spawns the rival colony's soldier pawns as a raid group targeting the player's
nearest hive. This uses the same raid mechanics as natural threats — the rival soldiers
are pawn entities that the player's soldiers and defense plants react to normally.

Rival colony raids are distinguishable from natural threats: rival bees wear the rival
colony's color (a shader parameter on the bee mesh set to the rival colony's hue) and
their name tags show the rival colony name. The player knows who is attacking.

### Player-initiated raids against rival colonies

The player can raid a rival colony by directing their soldiers toward a rival hive.
There is no explicit "declare war" button — the player simply sends pawns toward the
rival territory and conflict begins when the rival colony's soldiers engage.

```
# Player places a DEFEND marker near rival territory (aggressive forward positioning)
# OR
# Player possesses a soldier and manually approaches rival hive
# → rival soldiers respond with ATTACK_THREAT
# → combat begins
# → escalation is automatic from there
```

The rival colony responds to incoming attacks by pulling soldiers from patrol routes
and ATTACK jobs, then potentially queuing a counter-raid.

---

## Hive takeover

The hive takeover is the alternative to destroying a rival hive. Instead of reducing
integrity to zero, the player can infiltrate and claim the infrastructure.

### Takeover conditions

A hive can be taken over when:
1. Integrity has been reduced below 30% (breach threshold — entrance is compromised)
2. The player queen enters the hive interior (via `ENTER_HIVE` ability at a breached
   rival hive — she forces entry)
3. The queen uses the `PLACE_COLONY_MARKER` ability on the hive's interior (a special
   queen ability that stamps the hive with her colony's pheromone)

```
# PLACE_COLONY_MARKER ability:
# Effect: sets hive.colony_id = player_colony_id
#         resets hive.integrity to 50% (damage remains but structure holds)
#         triggers worker morale resolution (see below)
#         emits EventBus.hive_captured(hive_id, new_colony_id, old_colony_id)
```

### Worker morale resolution

After the pheromone is placed, rival workers in the hive receive an allegiance check:

```
func _resolve_captured_workers(hive_id: int, old_colony_id: int, new_colony_id: int) -> void:
    var workers_in_hive: Array[int] = PawnRegistry.get_pawns_in_hive(hive_id)
    for pawn_id in workers_in_hive:
        var state: PawnState = PawnRegistry.get_state(pawn_id)
        var loyalty: float = ColonyState.get_loyalty(pawn_id)
        var roll: float = randf()

        if roll < loyalty * 0.5:
            # Loyal workers resist → sabotage attempt
            _attempt_sabotage(pawn_id, hive_id)
            _kill_pawn(pawn_id, &"resistance")   # queen's soldiers eliminate resisters
        elif roll < loyalty:
            # Moderately loyal → flee the hive
            _exile_worker(pawn_id)
        else:
            # Low loyalty → defect to player colony
            state.colony_id = new_colony_id
            state.loyalty = 0.3   # defectors start with low loyalty; must earn trust
            ColonyState.modify_loyalty(pawn_id, 0.0, &"defection")
```

Defecting workers are immediately useful — they have their existing skills and role.
A captured carpenter hive gives the player experienced carpenters. But their low
starting loyalty means they need good conditions to stay.

Workers that flee become neutral pawns in the world — they may found new small colonies,
join the wild, or occasionally wander into the player's territory and be recruited
by the queen's diplomacy.

### Rival colony response to capture

When the player captures a hive:
- The rival colony's `hive_count` drops by 1 in `RivalColonyState`
- If the captured hive was the rival capital: the rival queen is homeless → the rival
  colony enters its own succession crisis (the rival queen must find a new capital)
- If the rival colony has no remaining hives: the rival colony dissolves
  (`EventBus.colony_dissolved` fires); surviving rival pawns scatter

Dissolving a rival colony does not mean the queen dies — she is now a homeless queen
looking for a new territory. She becomes a unique encounter: the player can approach her
diplomatically (she may accept terms if the player colony is strong) or treat her as
a threat.

---

## Daughter colony integration

Colonies founded by exiled player princesses (from the lifecycle system) behave like
any other AI colony but start with:

- `relation_to_player = 0.3` — slightly positive from shared lineage
- Archetype based on the princess's personality
- A record in `ColonyState.queen_history` tying them to the player's lineage
- No hives — the exiled queen must build her first hive immediately

The slight positive relation means daughter colonies are less likely to raid the player
early. They are not automatic allies — the relation must be developed through the normal
diplomacy system. But there is an additional dialogue hook: the daughter queen
recognises the player's queen as her predecessor's successor and has unique dialogue
lines that reference the shared history.

This is the "daughter diplomacy" arc — the player's daughters in the world are not
enemies by default, but they are not allies by right either. Building a relationship
with a daughter colony feels different from building one with a wild colony.

---

## RivalColonySimulator

`RivalColonySimulator` is a scene-owned manager node (not an autoload — it is a
`Node` child of `WorldRoot`). It owns `_rival_states` and orchestrates all AI colony
simulation.

```
class_name RivalColonySimulator
extends Node

var _rival_states: Dictionary[int, RivalColonyState]  # colony_id → state
var _simulation_tiers: Dictionary[int, SimulationTier]  # colony_id → current tier

func _process(delta: float) -> void:
    for colony_id in _rival_states:
        match _simulation_tiers[colony_id]:
            SimulationTier.FULL:
                pass  # full simulation handled by individual PawnAI nodes
            SimulationTier.REDUCED:
                _reduced_tick(colony_id, delta)

func _on_day_changed(new_day: int) -> void:
    for colony_id in _rival_states:
        if _simulation_tiers[colony_id] == SimulationTier.ABSTRACT:
            _abstract_day_tick(colony_id)
        _update_simulation_tier(colony_id)
```

`_update_simulation_tier` checks the distance from all player WorldViewers and
promotes or demotes the colony's tier accordingly.

---

## EventBus integration

```
# Emitted by RivalColonySimulator:
EventBus.colony_founded(colony_id)         # new rival colony appears
EventBus.colony_dissolved(colony_id)       # rival colony eliminated
EventBus.hive_captured(hive_id, new_colony_id, old_colony_id)

# Consumed by RivalColonySimulator:
EventBus.pawn_spawned     → if colony_id != 0 and colony_id != -1: register in rival sim
EventBus.pawn_died        → update abstract pawn counts
EventBus.hive_built       → update hive_count in abstract state
EventBus.hive_destroyed   → update hive_count; check colony dissolution
EventBus.day_changed      → abstract tick
EventBus.territory_expanded → recompute border pressure for all adjacent rival colonies
EventBus.queen_died       → if rival queen: check heir; if no heir: colony dissolution
EventBus.egg_matured      → if rival colony egg: update heir_count
```

---

## Save / load

`RivalColonySimulator` saves `_rival_states` for all non-player colonies:

```
func save_state() -> Dictionary:
    var states = []
    for colony_id in _rival_states:
        states.append(_rival_states[colony_id].to_dict())
    return {"rival_states": states, "schema_version": 1}
```

Full `ColonyData` for FULL-tier colonies is saved by `ColonyState` (which saves all
colonies, not just the player colony). `RivalColonyState` lightweight summaries are
saved here for ABSTRACT colonies.

On load:
1. `ColonyState` restores all colony data records.
2. `RivalColonySimulator` restores lightweight states and determines current tier.
3. FULL-tier colonies: `PawnManager` spawns pawn nodes.
4. ABSTRACT-tier colonies: no node spawning — state only.

---

## MVP scope notes

Deferred past MVP:

- Formal diplomacy between player and rival bee colonies (at MVP, rival bee colonies
  are competitors not partners; inter-colony diplomacy is limited to not raiding and
  occasional contested-resource encounters).
- Rival colony alliance chains (two rival colonies allying against the player).
- Nomadic colony relocation mechanic (capital hive moves periodically — data model
  supports it but NPC logic for deciding when and where to move is post-MVP).
- Rival colony quest arcs (helping a struggling rival colony survive a bear attack
  in exchange for a ceasefire).
- Full rival colony NPC queen as a diplomatic target (at MVP the rival queen is just
  a pawn; she becomes a full faction NPC with dialogue post-MVP).
