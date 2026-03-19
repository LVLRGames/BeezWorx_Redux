# BeezWorx MVP Spec: Colony Lifecycle System

This document specifies pawn aging, egg laying, egg development, role determination
from feeding, pawn death, queen succession, the heir system, and the game-over
condition. It is the authoritative reference for all birth-to-death simulation of
colony members and for the queen mortality stakes that give the game its tension.

---

## Purpose and scope

The colony is a living organism. Workers are born, age, and die. The queen lays eggs
that grow into the next generation. What a larva is fed determines what it becomes.
When the queen dies, the colony faces crisis or collapse depending on whether an heir
exists. This system is what makes BeezWorx feel like a simulation of life rather than
a factory game with bee sprites.

This spec covers:
- Pawn aging: day-based aging, lifespan variance, natural death
- Fatigue and sleep: the daily cycle that keeps pawns moving through hives
- Egg laying: queen capacity, nursery slot requirements, capital hive rules
- Egg development: feeding schedule, role determination from feed log
- Maturation: new pawn creation, role assignment, personality generation
- Queen succession: heir detection, transition period, multiple princess handling
- Game over condition: queen dies with no viable heir
- ColonyState integration: known recipes, loyalty, morale as lifecycle inputs

It does **not** cover: hive slot mechanics for nursery designation (HiveSystem spec),
loyalty decay rates from lost beds or hunger (ColonyState spec), or the full pawn AI
behavior tree (AI spec). Those systems interact with lifecycle events via EventBus.

---

## Pawn aging

### Age tracking

Every pawn tracks age in whole days on `PawnState`:

```
var age_days:     int    # incremented on EventBus.day_changed
var max_age_days: int    # set at creation from SpeciesDef + personality variance
```

`max_age_days` is determined at pawn creation:

```
func _roll_lifespan(species_def: SpeciesDef, personality: PawnPersonality) -> int:
    var rng := RandomNumberGenerator.new()
    rng.seed = personality.seed + 7919   # deterministic from personality seed
    var base: int = species_def.base_lifespan_days
    var variance: int = species_def.lifespan_variance_days
    var roll: int = base + rng.randi_range(-variance, variance)
    # Stubbornness extends lifespan slightly — stubborn bees cling to life
    var stubbornness_bonus: int = int(personality.stubbornness * species_def.stubbornness_lifespan_bonus)
    return maxi(roll + stubbornness_bonus, species_def.min_lifespan_days)
```

### Lifespan values (MVP defaults, tunable on SpeciesDef)

| Species | Base lifespan (days) | Variance | Notes |
|---|---|---|---|
| Worker bee (all roles) | 35 | ±5 | ~1 month; 30–45 day range |
| Queen bee | 1095 | ±60 | 3 in-game years; ~180 real hours at default day length |
| Ant (allied) | 17 | ±3 | 15–20 days; turns over faster than bees |
| Beetle (allied) | 90 | ±10 | ~1 season; hearty and durable |
| Bear (allied) | 2190 | ±180 | 6 in-game years (range 5–8); outlives queens by generations |

**Bear lifespan note:** At 6 in-game years, a bear will outlive the player's first two
or three queens depending on succession timing. This enables "I knew your grandmother"
dialogue — the bear has genuine historical memory of the colony that no other creature
can have. Bear dialogue should reference past queens by name (readable from
`ColonyState.queen_history`, a log of past queens with their names and reign dates).
This is a free emotional depth win from the simulation — note it for writers.

### Natural death

On `EventBus.day_changed`, `LifecycleSystem` iterates all living pawns:

```
func _on_day_changed(new_day: int) -> void:
    for pawn_id in PawnRegistry.get_all_pawn_ids():
        var state: PawnState = PawnRegistry.get_state(pawn_id)
        if not state.is_alive:
            continue
        state.age_days += 1
        _check_natural_death(state)
```

```
func _check_natural_death(state: PawnState) -> void:
    if state.age_days < state.max_age_days:
        return
    # Soft death: age beyond max triggers increasing daily death chance
    # rather than instant death on the exact day (feels more natural)
    var overage: int = state.age_days - state.max_age_days
    var death_chance: float = minf(float(overage) / 7.0, 1.0)  # reaches 100% at 7 days over
    if randf() < death_chance:
        _kill_pawn(state.pawn_id, &"old_age")
```

The soft death window (7 days over max) means pawns don't all die on the same day even
if they were born together. It also gives the player a brief grace period to prepare
replacements when they notice an elder pawn.

### Death notification

Elders (age ≥ `max_age_days - 3`) get a visual indicator in the pawn switch panel
(dimmed icon, "elder" tag). This is the player's warning that replacement is needed.

---

## Fatigue and sleep

Fatigue is a daily rhythm mechanic. It is not a lifecycle event but feeds into pawn
availability and indirectly into loyalty.

```
# On PawnState:
var fatigue: float = 0.0   # 0 = fully rested, 1.0 = must sleep immediately
```

Fatigue accumulates while awake at a rate defined on `SpeciesDef.fatigue_rate` (units
per in-game second). It depletes while sleeping at `SpeciesDef.rest_rate`. The rates
are tuned so a pawn naturally sleeps once per in-game day for roughly one-third of it.

When `fatigue >= 0.85`: pawn posts a reactive `SEEK_SLEEP` job (see JobSystem spec).
When `fatigue >= 1.0`: pawn stops all activity and sleeps wherever they are if no bed
is found within a short search radius (collapses in place — visible, unprotected).

Sleep in an assigned BED slot restores fatigue at full rate. Sleep in an unassigned
BED or GENERAL slot restores at 80% rate. Collapsing in place restores at 40% rate
and does not count as "rested" for loyalty purposes.

Loyalty impact: if a pawn fails to sleep in a proper slot for 3 consecutive days,
`ColonyState` begins loyalty decay for that pawn. This is the bed-shortage warning.

---

## Egg laying

### Queen capacity

The queen can lay one egg per `queen_lay_interval` in-game seconds (default: one egg
per in-game day, tunable on `SpeciesDef`). This interval is tracked on `PawnState`:

```
var next_lay_time: float   # TimeService.world_time when queen can next lay
```

The queen lays an egg by using her `LAY_EGG` ability on a NURSERY slot. The ability
validates:
1. `TimeService.world_time >= next_lay_time`
2. The target slot is NURSERY designation and is empty (no existing egg)
3. The slot is in the capital hive (for princess eggs) or any hive (for worker eggs)
4. The queen has sufficient nutrition (honey in inventory or nearby hive stock)

On success:
- An `EggState` is created in the slot.
- `next_lay_time = TimeService.world_time + queen_lay_interval`
- The queen consumes a small nutrition cost (defined on `SpeciesDef.lay_egg_cost`)
- `EventBus.egg_laid.emit(hive_id, slot_index, queen_pawn_id)`

### Egg maturation duration

Eggs mature after `base_maturation_days` in-game days (default: 3 days, tunable on
`SpeciesDef`). The `NURSERY` specialisation upgrade on the capital hive reduces this
by 25%. Maturation is tracked by comparing `TimeService.current_day` against
`egg_state.maturation_day`:

```
# Set when egg is laid:
egg_state.maturation_day = TimeService.current_day + base_maturation_days
# Modified if NURSERY upgrade is active:
if HiveSystem.get_hive(hive_id).specialisation == "NURSERY":
    egg_state.maturation_day -= int(base_maturation_days * 0.25)
```

`LifecycleSystem` checks for matured eggs on `EventBus.day_changed`.

---

## Egg feeding and role determination

### Feeding schedule

Nurse bees (and the queen early-game) feed eggs once per `feed_interval` in-game
seconds (default: every 4 in-game hours). If an egg misses two consecutive feeds, it
becomes `starved` and dies — lost silently as a visual wilt effect on the nursery slot.

The nurse's job is a repeating `FEED_EGG` job posted by `HiveSystem` for every occupied
nursery slot. Job priority is high (8/10) — nurses prioritise feeding over most other
tasks.

### Role determination

At maturation, `LifecycleSystem` evaluates `egg_state.feed_log` and determines the
emerging role:

```
func _determine_role(feed_log: Array[FeedEntry]) -> StringName:
    # Count total feeds per item_id
    var feed_counts: Dictionary[StringName, int] = {}
    for entry in feed_log:
        feed_counts[entry.item_id] = feed_counts.get(entry.item_id, 0) + 1

    # Find the item fed most often
    var dominant_item: StringName = &""
    var dominant_count: int = 0
    for item_id in feed_counts:
        if feed_counts[item_id] > dominant_count:
            dominant_item = item_id
            dominant_count = feed_counts[item_id]

    # Map to role via ItemDef.nursing_role_tag
    var item_def: ItemDef = Registry.get_item(dominant_item)
    if item_def and item_def.nursing_role_tag != &"":
        return item_def.nursing_role_tag

    return &"forager"   # fallback
```

### Feeding → role mapping (from ItemDef.nursing_role_tag)

| Primary food | Nursing role tag | Emerging role |
|---|---|---|
| `royal_jelly` | `"princess"` | Princess (queen candidate) |
| `honey_basic` (or any honey) | `"forager"` | Forager |
| `bee_jelly` | `"nurse"` | Nurse bee |
| `bee_bread` | `"crafter"` | Crafter bee |
| `pollen_basic` | `"gardener"` | Gardener |
| `plant_fiber_paste` | `"carpenter"` | Carpenter |
| `toxin_tonic` | `"soldier"` | Soldier |
| Mixed / no clear winner | — | Forager (fallback) |

**Princess rule:** only one egg in a colony may be fed royal_jelly at a time under
normal circumstances. `HiveSystem.feed_egg` rejects royal jelly on a second egg if
a princess is already being raised. Exception: queen is dying (health < 20%) — up to
3 princess eggs are permitted simultaneously to improve succession odds.

### Mixed feeding and edge cases

If the feed log has two items tied in count, the tie is broken by which was fed most
recently (recency wins). This means the nurse — or player — can shift a larva's role
trajectory mid-development by switching foods, but the earlier feeds still count
toward the final total. Switching roles mid-development is a legitimate strategy:
start with honey to establish a forager trajectory, then switch to toxin tonic in the
final feeding window to produce a soldier.

---

## Maturation

When `TimeService.current_day >= egg_state.maturation_day`:

```
func _mature_egg(hive_id: int, slot_index: int) -> void:
    var slot: HiveSlot = HiveSystem.get_slot(hive_id, slot_index)
    var egg: EggState = slot.egg_state

    if egg == null or egg.is_starved:
        slot.egg_state = null
        return

    var role_tag: StringName = _determine_role(egg.feed_log)
    var new_pawn_id: int = _create_pawn(egg, role_tag, hive_id)

    slot.egg_state = null
    HiveSystem.emit_slot_changed(hive_id, slot_index)
    EventBus.egg_matured.emit(hive_id, slot_index, role_tag, new_pawn_id)
```

```
func _create_pawn(egg: EggState, role_tag: StringName, birth_hive_id: int) -> int:
    var pawn_id: int = PawnRegistry.next_id()

    var species_def: SpeciesDef = Registry.get_species(&"bee")   # MVP: all bees same species
    var role_def: RoleDef = Registry.get_role(role_tag)

    var personality := PawnPersonality.new()
    personality.generate(pawn_id * 1619 + egg.laid_at)   # deterministic from id + birth time

    var state := PawnState.new()
    state.pawn_id        = pawn_id
    state.pawn_name      = NameSystem.generate_name(&"bee", pawn_id)
    state.species_id     = &"bee"
    state.role_id        = role_tag
    state.colony_id      = HiveSystem.get_hive(birth_hive_id).colony_id
    state.max_age_days   = _roll_lifespan(species_def, personality)
    state.age_days       = 0
    state.health         = species_def.base_health
    state.max_health     = species_def.base_health
    state.loyalty        = 0.75   # new bees start with moderate loyalty; grows with good conditions
    state.personality    = personality
    state.last_known_cell = HiveSystem.get_hive(birth_hive_id).anchor_cell

    PawnRegistry.register(pawn_id, state)
    EventBus.pawn_spawned.emit(pawn_id, state.colony_id, state.last_known_cell)

    return pawn_id
```

New bees spawn at the anchor cell of their birth hive. `PawnManager` listens to
`EventBus.pawn_spawned` and instantiates the appropriate pawn scene node if the hive's
chunk is loaded.

---

## Queen succession

### The core mechanic: no queen pawn = no queen actions

There is no artificial transition timer after the queen dies. The player is blocked from
queen-exclusive actions (placing markers, initiating diplomacy, laying eggs, accessing
the colony management menu) for exactly as long as they have no queen pawn to switch to.
The block lifts the moment a princess matures, exits her nursery slot, and the player
switches to her.

This creates a natural risk/reward system around princess timing:

- **Princess just laid:** player waits the full 5-day maturation period with no queen.
- **Princess halfway through:** player waits the remaining days.
- **Princess emerges same day queen dies:** no downtime at all.
- **No princess in any nursery:** game over.

The player is rewarded for planning succession carefully and penalised for neglecting
it. A skilled player managing a long-lived queen will time a new princess to emerge
right as the old queen's soft-death window opens, minimising downtime to near zero.

### Princess maturation duration

```
# On SpeciesDef (queen/princess):
base_maturation_days: int = 5   # in-game days from egg to emergence
```

The NURSERY specialisation upgrade on the capital hive reduces this to 4 days (rounded).
Unlike worker eggs, princess maturation is not further reducible — the queen's biology
takes the time it takes.

### When the queen dies with one heir

1. Queen pawn is killed — `state.is_alive = false`.
2. `EventBus.pawn_died` fires with `cause = "old_age"` or `"combat"`.
3. `LifecycleSystem` detects the dead pawn is the colony queen.
4. Checks `ColonyState.heir_ids` for the colony.
5. One heir exists: `EventBus.queen_died.emit(colony_id, true)` — colony survives.
6. The heir continues maturing in her nursery slot normally. Nothing else changes.
7. When she matures (on `day_changed`), she emerges as a princess pawn with `role_id = "princess"`.
8. The player switches to the princess and performs `BECOME_QUEEN` action (contextual
   ability that fires when the player interacts with a BED slot in the capital hive as
   a princess).
9. `BECOME_QUEEN` sets `role_id = "queen"`, re-rolls `max_age_days` to queen lifespan,
   assigns her as colony queen in `ColonyState`, and unlocks all queen abilities.

The player must actively perform `BECOME_QUEEN` — the princess does not auto-promote.
This is intentional: the player should feel the weight of the coronation. It also means
a brief window where the player is controlling a princess pawn and can choose to explore
or prepare before "accepting" the crown.

### When the queen dies with multiple heirs

Multiple princesses maturing at the same time creates a succession contest:

1. If two or more princesses are in nursery slots simultaneously and the queen dies,
   they mature normally on their individual schedules.
2. If two or more princesses emerge on the **same in-game day**, a contest is triggered.
3. Contest duration: 1 extra in-game day during which no princess can perform
   `BECOME_QUEEN`. They are controllable as pawns but queen actions are blocked.
4. After the contest day, the eldest princess (highest `age_days` — meaning she was
   laid first) wins. She can now perform `BECOME_QUEEN`.
5. Losing princesses receive `is_exiled = true` on their `PawnState`. They cannot
   `BECOME_QUEEN`. Within 1–3 in-game days, exiled princesses leave the colony.

### Princess exile and daughter colonies

Exiled princesses do not simply despawn. They leave with a small retinue and attempt to
found a new colony:

```
func _exile_princess(origin_colony_id: int, princess_id: int) -> void:
    var retinue: Array[int] = _recruit_retinue(origin_colony_id, 2, 4)
    var new_colony_id: int = ColonyState.create_colony()

    PawnRegistry.get_state(princess_id).colony_id = new_colony_id
    PawnRegistry.get_state(princess_id).role_id = &"queen"
    for pawn_id in retinue:
        PawnRegistry.get_state(pawn_id).colony_id = new_colony_id

    ColonyState.set_queen(new_colony_id, princess_id)
    EventBus.colony_founded.emit(new_colony_id)
    # New colony AI immediately posts BUILD_HIVE as highest priority job
```

This is how new AI bee colonies organically seed the world — not from a procedural
faction spawner but as a direct consequence of the player's breeding choices. A prolific
queen who raises many princesses will naturally populate the surrounding territory with
daughter colonies, some friendly, some competitive depending on territory overlap.

### The succession incentive structure

| Situation | Consequence |
|---|---|
| No princess when queen dies | Game over |
| One princess, early in gestation | Long downtime; colony vulnerable |
| One princess, timed well | Short or no downtime; ideal |
| Multiple princesses, staggered timing | One succeeds, others exile → daughter colonies |
| Multiple princesses, same-day emergence | Contest adds 1 day penalty + exiles |
| Princess emerges same day queen dies | No downtime; maximum skill reward |

The soft death window (7 days of increasing chance past `max_age_days`) exists
specifically to enable the "timed well" scenario. The player sees the elder indicator
at `max_age_days - 3`, has a 10-day window (3 warning days + 7 soft death days) to
ensure a princess is appropriately timed. Planning around this is the late-game
resource management challenge.

---

## Game over condition

Game over fires when the queen dies and `heir_ids` is empty:

```
func _trigger_game_over(colony_id: int) -> void:
    EventBus.queen_died.emit(colony_id, false)   # had_heir = false
    # Game over is handled by the game state manager listening to this signal
    # It does not fire instantly — a brief "colony in chaos" sequence plays first
```

The game over is not instant. A brief sequence occurs:
1. Workers begin panic behavior (random movement, no jobs claimed).
2. Documentary narrator line fires (e.g. "Without a queen, the colony loses its heart.
   The hive will not survive the season.").
3. After ~10 seconds of colony chaos, the game over screen appears.
4. Player is offered: restart from last save, or continue in "memorial mode" (watch
   the colony dissolve, no further player input).

The 10-second delay gives the moment weight. It should feel like a consequence, not
a glitch.

---

## Lifecycle events summary (EventBus)

```
# Emitted by LifecycleSystem:
EventBus.egg_laid(hive_id, slot_index, queen_pawn_id)
EventBus.egg_matured(hive_id, slot_index, role_tag, new_pawn_id)
EventBus.egg_starved(hive_id, slot_index)
EventBus.pawn_aged(pawn_id, new_age_days)         # emitted daily; used by UI elder indicator
EventBus.pawn_died(pawn_id, colony_id, cause)     # cause: "old_age", "combat", "starvation", etc.
EventBus.queen_died(colony_id, had_heir)
EventBus.colony_founded(colony_id)                # from princess exile
EventBus.succession_started(colony_id)
EventBus.succession_ended(colony_id, new_queen_id)

# Consumed by LifecycleSystem:
EventBus.day_changed     → age all pawns, check maturation, check natural death
EventBus.pawn_died       → check if queen, trigger succession or game over
EventBus.hive_destroyed  → survival check for sleeping pawns
```

---

## ColonyState integration

`ColonyState` owns the colony-level data that lifecycle events update:

```
# Per colony on ColonyState:
var queen_pawn_id:       int           # -1 if no living queen
var heir_ids:            Array[int]    # pawn_ids of living princesses (in nursery or emerged)
var contest_active:      bool = false  # true during 1-day succession contest
var contest_day:         int = -1      # day contest started; resolves next day_changed
var population:          int           # derived: count of living pawns with this colony_id
var average_loyalty:     float         # derived: average loyalty across all colony pawns

# Historical record — used by long-lived creature dialogue (bears, ancient trees, etc.)
var queen_history:       Array[QueenRecord]
```

```
class QueenRecord:
    var pawn_name:    String
    var reign_start:  int    # current_day when she became queen
    var reign_end:    int    # current_day when she died (-1 if still reigning)
    var cause:        StringName  # "old_age", "combat", "unknown"
```

`queen_history` is appended when a queen dies or abdicates. Long-lived allied creatures
(particularly bears) can reference this log in dialogue — "I knew your mother's mother,
and she was a wise queen." The bear compares the current queen's name against the history
log and selects the appropriate generational reference based on how many queens have
reigned since it first met the colony.

`queen_pawn_id == -1` is the authoritative signal that no queen exists. All systems
that gate on queen presence check this value. No timer, no transition flag.

---

## Aging visual indicators

Elder pawns communicate their age through the world, not through a HUD interruption.
Three escalating signals, each appearing at a different threshold:

**Label3D nametag icon** (appears when player is within dialogue range):
At `age_days >= max_age_days - 7` (entering the warning window), a small elder icon
appears beside the pawn's name in their floating Label3D. Visible to any player who
gets close enough to interact. Unobtrusive but findable.

**Pawn switch panel icon** (always visible in the quick-switch UI):
Same threshold. An elder glyph appears beside the pawn's name in the left-panel list.
This is the primary way an attentive player monitors their colony's age distribution
without going into the management screen.

**Visual aging on the pawn mesh:**
At `age_days >= max_age_days - 3` (3 days before soft death window opens), the pawn's
mesh visibly ages. For bees specifically: the dark/black portions of the bee's body
shift toward grey via a shader parameter (`elder_greying: float`, 0.0 to 1.0 ramping
over the 3-day window). Movement speed is reduced by 15% to reflect reduced vigour.
This makes elder bees visually distinct in the world without requiring the player to
check any UI.

**Colony management summary stat:**
The colony management screen (accessible from capital hive) shows a population breakdown
including `% elderly` — the proportion of pawns currently in their warning window.
A high elderly percentage is a clear signal to prioritise nursing new eggs toward the
affected roles.

**No death animation by default.** Natural death occurs overnight (during sleep) when
possible — the pawn simply does not wake from their next sleep cycle. If the pawn is
active when they die (death chance triggered during waking hours), they stop moving,
emit a brief particle effect, and fade out. No dramatic death scene for workers — they
lived a full life. The moment is quiet.

---

## Save / load

`LifecycleSystem` itself has no saved state — it is a pure event processor. All
lifecycle data lives on `PawnState` (saved via PawnRegistry) and `HiveState.slots`
(saved via HiveSystem). The only additional save needed is `ColonyState.succession_in_progress`
and `succession_day`, which are part of `ColonyState.save_state()`.

On load, `LifecycleSystem` re-subscribes to all EventBus signals. No state hydration
needed.

---

## MVP scope notes

Deferred past MVP:

- Worker bee gender distinction (drones). At MVP all workers are female workers for
  simplicity. Drones as a male caste with specific gameplay role is post-MVP.
- Disease and parasite systems (varroa mite equivalent). Age and combat are the only
  death causes at MVP.
- Pawn retirement (very old pawns becoming advisors rather than dying — a quality-of-life
  option for beloved named bees the player is attached to).
- Cross-colony princess negotiation (exile princess choosing to ally with player instead
  of found rival colony, creating a new NPC faction with history).
- Full grief/memorial system for named pawns with long histories.
