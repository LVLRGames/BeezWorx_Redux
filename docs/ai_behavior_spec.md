# BeezWorx MVP Spec: AI Behavior System

This document specifies the utility AI architecture, job execution loop, pathfinding,
role-based behavior profiles, fallback idle behaviors, threat response, and the
performance model for autonomous pawn behavior. It is the authoritative reference for
`PawnAI`, `UtilityBehaviorDef`, navigation, and all autonomous pawn decision-making.

---

## Purpose and scope

Every pawn that is not currently possessed by a player runs `PawnAI`. The AI must
feel believable — workers should look like they know what they're doing, soldiers
should patrol with purpose, and idle bees should behave naturally rather than standing
frozen. At the same time the AI must be cheap enough to run on 100+ simultaneous pawns
without frame budget problems.

This spec covers:
- The utility AI architecture: scoring, selection, execution
- The job execution loop: claim → plan → execute → complete/fail
- Pathfinding: ground and flying, navigation mesh vs steering
- Role behavior profiles: what each role prioritises
- Fallback idle behaviors per role
- Threat response: flee, fight, alert
- LOD simulation: distant pawns tick less frequently
- The "chosen one" boost: subtle player-controlled pawn advantages
- Performance model and tick budget

It does **not** cover: job posting (JobSystem spec), combat resolution (Combat spec),
hive slot assignment (HiveSystem spec), or possession mechanics (Pawn spec). Those
systems provide the context the AI acts within.

---

## Architecture overview

`PawnAI` uses a **utility AI + job polling** hybrid. This is the right choice for
BeezWorx specifically because:

- Utility AI handles the "what should I do right now" decision naturally across many
  competing needs (hunger, fatigue, danger, role duty, idle curiosity).
- Job polling handles the "how do I do it" execution with deterministic subtask steps
  that can be saved, resumed, and interrupted cleanly.
- The combination avoids behavior tree complexity while remaining more nuanced than
  pure finite state machines.

```
PawnAI decision loop (per tick):

1. Score all utility behaviors for this pawn
2. Select highest-scoring behavior
3. If behavior requires a job: query JobSystem for claimable jobs of that type
4. Claim the best job → run task planner → execute subtasks
5. On completion/failure: clear job, re-evaluate on next tick
6. If no job available: enter fallback idle for this behavior
```

---

## Utility scoring

### UtilityBehaviorDef (Resource)

Defined per role on `RoleDef.utility_behaviors`. Each behavior has a base weight and
optional conditions that modulate it.

```
class_name UtilityBehaviorDef
extends Resource

@export var behavior_id:      StringName
@export var job_type_ids:     Array[StringName]  # job types this behavior maps to
@export var base_weight:      float = 1.0
@export var conditions:       Array[UtilityCondition]
@export var score_curve:      Curve              # optional: modulate by a context float (0..1)
@export var fallback_behavior: StringName        # behavior_id to run if no job found
@export var interruptible:    bool = true        # can a higher-scoring behavior preempt this?
@export var min_recheck_interval: float = 0.25  # seconds before re-evaluating while executing
```

### UtilityCondition (Resource)

```
class_name UtilityCondition
extends Resource

@export var condition_id:  StringName   # e.g. "inventory_not_full", "health_low", "has_job_of_type:BUILD"
@export var multiplier:    float = 1.0  # applied to base_weight when condition is true
@export var invert:        bool = false # apply when condition is FALSE instead
```

Conditions are evaluated by `_evaluate_condition(pawn_state, condition_id) -> bool`.
The function is a match statement over known condition ids — not a scripting language,
just a closed set of readable condition checks that grow as needed.

### Scoring procedure

```
func _score_behavior(behavior: UtilityBehaviorDef, state: PawnState) -> float:
    var score: float = behavior.base_weight
    for condition in behavior.conditions:
        var met: bool = _evaluate_condition(state, condition.condition_id)
        if met != condition.invert:
            score *= condition.multiplier
    if behavior.score_curve:
        var context: float = _get_context_float(state, behavior.behavior_id)
        score *= behavior.score_curve.sample(context)
    return score
```

All behaviors are scored every tick. The highest score wins. If the winner is different
from the current behavior and the current behavior has `interruptible = true`, the AI
switches. Non-interruptible behaviors (like CARRY_ITEM for an ant mid-delivery) run
to completion regardless of score changes.

### Built-in condition ids (MVP set)

```
"inventory_not_full"         — pawn.inventory is not at capacity
"inventory_empty"            — pawn.inventory has no items
"has_item:<item_id>"         — pawn carries at least 1 of specified item
"has_item_tag:<tag>"         — pawn carries at least 1 item with this tag
"health_low"                 — health < 0.3 × max_health
"health_critical"            — health < 0.15 × max_health
"fatigue_high"               — fatigue > 0.7
"fatigue_critical"           — fatigue > 0.9
"threat_nearby"              — threat pawn within alert_radius
"in_territory"               — pawn's current cell is in own colony territory
"outside_territory"          — inverse of in_territory
"no_queen"                   — colony has no queen (queen_pawn_id == -1)
"has_job_of_type:<type>"     — a claimable job of this type exists near pawn
"colony_morale_low"          — colony morale < 0.3
"is_carrying_heavy"          — current_carry_weight > 0.7 × max_carry
"plant_has_resource:<cell>"  — specific cell has nectar or pollen available
"season:<season_id>"         — current season matches
"is_night"                   — TimeService.is_night()
```

---

## Job execution loop

When a behavior wins and maps to a job type, the AI executes:

```
func _try_claim_job(behavior: UtilityBehaviorDef, state: PawnState) -> bool:
    for job_type in behavior.job_type_ids:
        var jobs: Array[JobData] = JobSystem.get_claimable_jobs(
            state.pawn_id,
            state.colony_id,
            _get_role_tags(state),
            state.last_known_cell,
            search_radius = 12
        )
        if jobs.is_empty():
            continue
        var job: JobData = jobs[0]   # highest priority, nearest
        if JobSystem.claim_job(job.job_id, state.pawn_id):
            _current_job = job
            _current_subtask_index = 0
            return true
    return false
```

### Subtask execution

Each job type maps to a subtask sequence defined in `_build_subtask_sequence`:

```
"GATHER_NECTAR" → [
    SUBTASK_NAVIGATE(target_cell),
    SUBTASK_ABILITY(action, repeat_until: "nectar_depleted or inventory_full"),
    SUBTASK_NAVIGATE(nearest_hive),
    SUBTASK_ABILITY(alt_action, "deposit_items"),
]

"BUILD_HIVE" → [
    # Task planner inserts fetch/craft steps first (see JobSystem spec)
    SUBTASK_NAVIGATE(job.target_cell),
    SUBTASK_ABILITY(alt_action, repeat_until: "job_progress >= 1.0"),
]

"PATROL" → [
    SUBTASK_NAVIGATE(nearest_patrol_node),
    SUBTASK_WAIT(patrol_dwell_time),  # stand and watch
    SUBTASK_NAVIGATE(next_patrol_node),  # random walk between nodes
    # Repeats until PATROL job is cancelled or threat triggers ATTACK
]
```

Subtask types:

```
enum SubtaskType {
    NAVIGATE,        # move to a world position or cell
    ABILITY,         # execute action or alt_action once or repeatedly
    WAIT,            # hold position for duration
    NAVIGATE_HOME,   # navigate to capital hive (used by queen safety)
    SEEK_SLEEP,      # find bed slot and navigate to it
}
```

### Subtask advancement

On each AI tick while executing:

```
func _tick_current_job(delta: float) -> void:
    if _current_subtask_index >= _subtasks.size():
        JobSystem.complete_job(_current_job.job_id, state.pawn_id)
        _current_job = null
        return

    var subtask: Subtask = _subtasks[_current_subtask_index]
    var done: bool = _execute_subtask(subtask, delta)
    if done:
        _current_subtask_index += 1
```

`_execute_subtask` returns `true` when the subtask condition is met. For NAVIGATE it
returns true when the pawn is within interaction range of the destination. For ABILITY
it returns true when the repeat condition is satisfied or the ability fires once
(INSTANT mode).

---

## Pathfinding

### Ground pawns

Ground pawns use Godot's `NavigationAgent3D` with a navigation mesh baked over loaded
terrain. The nav mesh is generated per chunk when the chunk finalises and stitched
together across chunk boundaries.

```
# On ground pawn node:
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func navigate_to(world_pos: Vector3) -> void:
    nav_agent.target_position = world_pos
```

Navigation mesh covers:
- Hex terrain surfaces (all loaded chunks within simulation radius)
- TRAVERSABLE_STRUCTURE cells (hollow logs, stumps, rock piles) — these are explicitly
  added as nav mesh connections so ants can path over them
- Excluded: water cells, steep cliffs exceeding `max_slope_angle` on `SpeciesDef`

Nav mesh is not regenerated every frame. It is rebuilt when:
- A HIVE_ANCHOR is placed or removed (structural change)
- A TRAVERSABLE_STRUCTURE cell changes occupancy
- A chunk loads or unloads (boundary stitching)

Plant growth does not trigger nav mesh rebuild — plants are not navigation obstacles
for ground pawns. They are obstacles only for the combat targeting system (active plants
trigger on pawns entering their area, not on pathfinding).

### Flying pawns

Flying pawns do not use the navigation mesh. They use a lightweight **steering behavior**:

```
func _fly_toward(target: Vector3, delta: float) -> void:
    var desired: Vector3 = (target - global_position).normalized()
    # Separation: steer away from nearby flying pawns to avoid clumping
    desired += _compute_separation_force()
    # Altitude clamp
    desired.y = clampf(desired.y, _min_altitude(), _soft_max_altitude())
    velocity = velocity.lerp(desired * move_speed, steering_factor * delta)
    move_and_slide()
```

Separation force prevents visible clumping of bee swarms without expensive pathfinding.
The `steering_factor` (default 5.0) controls how snappy the turning feels — higher = more
responsive but less organic. Tunable on `SpeciesDef`.

Flying pawns treat solid geometry (terrain, hive structures) as obstacles via
`CharacterBody3D.move_and_slide()` collision response rather than explicit pathfinding.
They are fast enough that collision avoidance through physics is sufficient for MVP.

### Path caching

Frequently repeated routes (forager to flower patch and back) are cached as
`_cached_path: PackedVector3Array` on the pawn. Cache is valid while:
- Source and destination cells have not changed occupancy
- No structural cell changes have occurred on the route (tracked via `cell_changed`
  STRUCTURAL hints along the path corridor)

Cache invalidation is cheap — the pawn simply re-requests the path on the next
NAVIGATE subtask if the cache is stale.

---

## Role behavior profiles

Each role's `RoleDef.utility_behaviors` defines its decision priorities. Listed in
priority order (highest base_weight first):

### Forager
1. `SEEK_SLEEP` (fatigue_critical) — weight 10.0, non-interruptible
2. `FLEE` (health_critical + threat_nearby) — weight 9.0
3. `DEPOSIT_ITEMS` (inventory_full) — weight 8.0
4. `GATHER_NECTAR` (inventory_not_full + has_job_of_type:GATHER_NECTAR) — weight 6.0
5. `GATHER_WATER` (inventory_not_full + has_job_of_type:GATHER_WATER) — weight 5.0
6. `SEEK_FOOD` (fatigue_high, no threat) — weight 3.0
7. **Fallback idle:** fly to nearest flowering plant within territory, hover near it

### Gardener
1. `SEEK_SLEEP` (fatigue_critical) — weight 10.0
2. `FLEE` (health_critical) — weight 9.0
3. `DEPOSIT_ITEMS` (inventory_full) — weight 8.0
4. `POLLINATE_PLANT` (has_job_of_type:POLLINATE) — weight 7.0
5. `GATHER_POLLEN` (inventory_not_full) — weight 6.0
6. **Fallback idle:** fly between flowering plants in territory, pollinate opportunistically

### Carpenter
1. `SEEK_SLEEP` (fatigue_critical) — weight 10.0
2. `FLEE` (health_critical) — weight 9.0
3. `BUILD_HIVE` (has_job_of_type:BUILD_HIVE) — weight 8.0
4. `GATHER_PLANT_FIBER` (inventory_not_full) — weight 6.0
5. `CRAFT_ITEM` (hive has pending craft orders for carpenter) — weight 5.0
6. **Fallback idle:** gather plant fiber from nearest valid source and deposit at hive

### Soldier
1. `SEEK_SLEEP` (fatigue_critical) — weight 10.0
2. `ATTACK_THREAT` (threat_nearby) — weight 9.5, non-interruptible once engaged
3. `FLEE` (health_critical, outnumbered) — weight 9.0
4. `PATROL` (has_job_of_type:PATROL) — weight 7.0
5. `CRAFT_STINGER` (inventory empty of stingers + hive has materials) — weight 6.0
6. `GATHER_THORNS` (no stingers, thorns available) — weight 5.0
7. **Fallback idle:** orbit territory perimeter at medium altitude, stopping at high
   vantage points. This is the "guard on patrol" look that makes the colony feel
   protected even with no explicit patrol markers.

### Crafter
1. `SEEK_SLEEP` (fatigue_critical) — weight 10.0
2. `FLEE` (health_critical) — weight 9.0
3. `CRAFT_ITEM` (hive has pending craft orders) — weight 8.0, stays in hive
4. `DEPOSIT_ITEMS` (inventory has items for a craft order) — weight 6.0
5. `GATHER_NECTAR` (craft order needs nectar, none in hive) — weight 4.0
6. **Fallback idle:** remain near crafting slots; check for new orders every 30 seconds

### Nurse
1. `SEEK_SLEEP` (fatigue_critical) — weight 10.0
2. `FEED_EGG` (nursery slots have eggs) — weight 9.0, non-interruptible mid-feed
3. `SEEK_FOOD` (hive food stock below threshold) — weight 7.0
4. `GATHER_WATER` (hive water below threshold) — weight 6.0
5. **Fallback idle:** remain near nursery slots; tends sleeping bees (visual dressing)

### Queen (NPC — when player is possessing another pawn)
1. `SEEK_SLEEP` (fatigue_critical) — weight 10.0
2. `NAVIGATE_HOME` (outside capital hive) — weight 9.0, non-interruptible
3. **Once inside capital hive:** remain stationary. NPC queen does not perform
   strategic actions — no marker placement, no diplomacy, no lay_egg. These are
   player-only activities. The NPC queen is purely in a safe holding state.

This is intentional. The queen's strategic value is entirely player-driven. An NPC
queen that autonomously places markers and negotiates diplomacy would undermine the
player's sense of agency.

---

## Threat response

### Alert radius and threat detection

Each pawn has an `alert_radius` on `SpeciesDef` (default: 6 hex cells for bees,
3 for ground crawlers). When a hostile pawn enters the alert radius:

```
func _check_threats() -> void:
    var threats: Array[int] = PawnRegistry.get_pawns_near_cell(
        state.last_known_cell,
        alert_radius
    ).filter(func(id): return _is_hostile(id))

    if not threats.is_empty():
        _nearest_threat_id = _find_nearest(threats)
        _alert_colony()
```

`_alert_colony()` emits a local alert signal that nearby colony pawns also receive,
cascading awareness through a crowd without each pawn individually scanning.

### Flee vs fight decision

```
func _decide_threat_response() -> StringName:
    var threat_state: PawnState = PawnRegistry.get_state(_nearest_threat_id)
    var my_health_fraction: float = state.health / state.max_health
    var flee_threshold: float = _compute_flee_threshold()
    
    if my_health_fraction < flee_threshold:
        return &"FLEE"
    if state.role_id == &"soldier":
        return &"ATTACK"
    if state.role_id in [&"forager", &"gardener", &"nurse"]:
        return &"FLEE"
    return &"FLEE"   # default non-combat roles flee
```

```
func _compute_flee_threshold() -> float:
    # Base threshold from role: soldiers fight longer
    var base: float = 0.15 if state.role_id == &"soldier" else 0.4
    # Boldness personality: bold bees fight further into damage
    base -= state.personality.boldness * 0.2
    # Outnumbered: more threats = flee earlier
    var threat_count: int = _count_threats_in_radius()
    base += float(threat_count - 1) * 0.1
    return clampf(base, 0.05, 0.8)
```

The flee path takes the pawn toward the nearest hive entrance or colony territory
boundary, whichever is faster to reach. Fleeing pawns do not abandon jobs — on arrival
at safety they re-evaluate utility scores and may re-claim the interrupted job if the
threat has passed.

### Alert propagation

When a pawn triggers alert:

```
func _alert_colony() -> void:
    var nearby_allies: Array[int] = PawnRegistry.get_pawns_near_cell(
        state.last_known_cell,
        ALERT_PROPAGATION_RADIUS   # default 8 hex cells
    ).filter(func(id):
        return PawnRegistry.get_state(id).colony_id == state.colony_id
    )
    for ally_id in nearby_allies:
        var ally_ai: PawnAI = PawnRegistry.get_ai(ally_id)
        if ally_ai:
            ally_ai.receive_alert(state.last_known_cell, _nearest_threat_id)
```

Soldiers who receive an alert immediately preempt their current interruptible behavior
and switch to `ATTACK_THREAT` or `NAVIGATE_TO_THREAT` if the threat is outside their
current alert radius. Non-soldiers who receive an alert add `threat_nearby = true` to
their condition evaluation, raising the weight of `FLEE`.

---

## LOD simulation

Running full utility evaluation on 150 pawns every 0.25 seconds is ~600 evaluations/second.
Acceptable at MVP but needs LOD as colony size grows.

### Distance-based tick intervals

```
# In PawnAI._process:
func _get_tick_interval() -> float:
    var dist: int = _chunks_from_player()
    if dist <= 2:   return 0.25   # full fidelity: near player
    if dist <= 5:   return 1.0    # medium: visible range
    if dist <= 8:   return 5.0    # far: active but slow
    return 30.0                   # very far: occasional check-in
```

`_chunks_from_player()` computes the Chebyshev distance in chunk coordinates between
the pawn's current chunk and the nearest player WorldViewer chunk. This is a single
integer subtraction — cheap.

### Behavior at each LOD level

| Distance (chunks) | Tick interval | Behavior |
|---|---|---|
| 0–2 | 0.25s | Full utility evaluation, full path following, animations active |
| 3–5 | 1.0s | Full utility evaluation, simplified path (waypoint-to-waypoint) |
| 6–8 | 5.0s | Need-check only (fatigue, hunger, threat), teleport to job site |
| 9+ | 30.0s | Abstract simulation: increment age, consume food from hive totals, complete jobs instantly |

At LOD 9+ ("abstract simulation"), the pawn does not have an active scene node. Its
job completion is simulated by checking whether the job conditions are met and applying
the result directly to world state. This is the same pattern as unloaded chunk pawns
described in the Pawn spec.

### LOD transitions

When a pawn transitions from abstract to active (player moves toward their chunk):
- `PawnManager` spawns the pawn node at `state.last_known_cell`.
- `PawnAI` runs a fresh utility evaluation immediately.
- Any job in progress is restored from `state.ai_resume_state`.
- The pawn resumes at full fidelity on the next tick.

Transition from active to abstract (player moves away):
- `PawnManager` records `ai_resume_state`, removes the node.
- Abstract simulation begins on the next AI tick.

---

## The "chosen one" boost

When the player possesses a pawn, `PossessionService` applies subtle stat multipliers:

```
# Applied on possession:
state.player_boost_active = true

# Read by movement handler:
func _get_effective_move_speed() -> float:
    var base: float = species_def.move_speed
    if state.player_boost_active:
        base *= species_def.possession_speed_boost   # default 1.08
    if state.player_boost_active and state.loyalty > 0.8:
        base *= 1.02   # tiny additional boost for well-bonded pawns
    return base * _carry_weight_multiplier()

# Read by ability executor:
func _get_effective_action_speed() -> float:
    var base: float = 1.0
    if state.player_boost_active:
        base *= species_def.possession_action_boost  # default 1.05
    return base
```

Additionally, possessed pawns have **precision targeting** — when the player manually
aims at a target, the ability executor uses the exact aimed target rather than the
nearest valid target the AI would select. This is the real "chosen one" advantage:
not raw stats but intentionality. A player-controlled soldier shoots the threat nearest
the hive rather than the threat nearest to themselves.

The boost is never displayed to the player. It should be felt, not announced.

---

## Performance model

### Tick budget at MVP scale

| Colony size | Pawns | Ticks/sec (near) | Ticks/sec (total) | Estimated cost |
|---|---|---|---|---|
| Early game | 15 | 60 | 80 | Trivial |
| Mid game | 50 | 120 | 200 | Acceptable |
| Late game | 150 | 200 | 400 | Manageable with LOD |
| Large empire | 300 | 200 | 500 | Requires LOD strictly |

"Near" = within 2 chunks of any player WorldViewer. "Total" = all active (non-abstract)
pawns. Abstract pawns cost ~1 evaluation per 30 seconds — negligible.

### Key performance rules

- Never run pathfinding queries synchronously on the main thread for abstract pawns.
- Cache `PawnRegistry.get_pawns_near_cell` results per cell per frame — multiple pawns
  near the same cell would otherwise each trigger the same spatial query.
- Alert propagation is O(nearby allies), not O(all colony pawns). Radius is small.
- Utility scoring is pure math — no allocations, no dictionary lookups in the hot path.
  Conditions are evaluated as bitfield flags where possible post-MVP.

---

## Save / load

`PawnAI` saves only what is needed to resume:

```
# Saved as part of PawnState.ai_resume_state:
{
    "job_id":             current_job.job_id if current_job else -1,
    "subtask_index":      _current_subtask_index,
    "nav_target":         _current_nav_target,   # Vector3
    "cached_path_valid":  false,                 # always invalidate path on load
}
```

On load, `PawnAI` reads `ai_resume_state` from `PawnState`. If the saved `job_id` still
exists and is claimable, the job is re-claimed and subtask execution resumes from
`subtask_index`. Otherwise, a fresh utility evaluation runs on the first tick.

---

## MVP scope notes

Deferred past MVP:

- Group coordination (soldiers actively flanking threats, foragers signalling each
  other to a rich patch). At MVP soldiers and foragers act individually.
- Learning and adaptation (AI adjusting behavior weights based on past outcomes).
- Formation movement for ant conveyors (ants spacing themselves evenly along routes).
  At MVP ants walk the route individually; even spacing is emergent from their speed.
- Emotional state modifiers on AI (a pawn who witnessed the queen die behaves
  differently for a few days). The personality system supports this but AI expression
  of emotional state is post-MVP.
- Full behavior tree for complex multi-step social behaviors (queen negotiation sequence
  as an NPC, not just as a player action).
