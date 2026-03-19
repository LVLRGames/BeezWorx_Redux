# BeezWorx MVP Spec: Pawn / Creature System

This document specifies all runtime pawn behavior: state, movement types, ability
execution, possession, AI resumption, multiplayer rules, chunk boundary behavior,
dialogue/interaction, personality, and the player performance boost. It is the
authoritative reference for `PawnBase`, `PawnState`, `PawnAI`, `PossessionService`,
and `AbilityDef`.

---

## Purpose and scope

A pawn is any non-plant creature that exists as a physics object in the world, can be
possessed by a player, and has autonomous AI behavior when not possessed. This includes
bees, ants, beetles, bears, hornets, badgers, and any other creature added later.

This spec covers:
- Pawn type taxonomy (ground vs flying)
- State ownership and the PawnState/PawnAI split
- The action/alt-action ability system
- Possession, multiplayer possession rules, and AI resumption
- Chunk boundary behavior and the WorldViewer system
- Dialogue and contextual interaction
- Personality and individuality
- The player performance boost
- PawnRegistry integration

This spec does **not** cover: job claiming logic (JobSystem spec), hive slot assignment
(HiveSystem spec), loyalty decay rules (ColonyState spec), or combat resolution
(Combat spec). Those systems interact with pawns via PawnRegistry and EventBus.

---

## Pawn taxonomy

### Movement types

All pawns are one of two movement types. This determines physics, camera behavior, and
ability availability.

```
enum MovementType {
    GROUND,   # walks/crawls; uses CharacterBody3D with gravity
    FLYING,   # flies; uses CharacterBody3D without gravity, full 3D movement
}
```

**Ground pawns:** beetles, ants, bears, badgers, caterpillars. Constrained to navigable
terrain. Cannot cross water without a traversable structure. Subject to gravity.

**Flying pawns:** bees (all roles), hornets, butterflies, birds. Full 3D movement within
altitude constraints. Flying pawns have a minimum altitude (cannot go underground) and
a soft maximum altitude (above tree canopy = bird predator zone).

Movement type is defined on `SpeciesDef` and never changes for an instance.

### Faction alignment

A pawn belongs to exactly one colony (identified by `colony_id: int`). Colony 0 is
always the player colony. AI colonies have ids ≥ 1. Neutral/wild creatures have
`colony_id = -1`.

Possession eligibility: `colony_id == player_colony_id` AND `is_awake` AND `is_alive`
AND `not currently_possessed`.

---

## State ownership

### PawnState (RefCounted — NOT a node)

`PawnState` is the canonical runtime data for one pawn. It is owned by the pawn node
but is also readable by other systems via `PawnRegistry`.

```
class_name PawnState
extends RefCounted

# Identity
var pawn_id:      int
var pawn_name:    String         # procedurally generated, persistent
var species_id:   StringName     # references SpeciesDef
var role_id:      StringName     # references RoleDef (can change on maturation)
var colony_id:    int
var movement_type: int           # MovementType enum

# Vitals
var health:       float          # 0..max_health
var max_health:   float
var fatigue:      float          # 0..1; 1.0 = must sleep
var age_days:     int            # incremented on day_changed signal
var max_age_days: int            # from SpeciesDef + personality variance
var is_alive:     bool
var is_awake:     bool

# Loyalty (colony bond)
var loyalty:      float          # 0..1; < threshold → abandons colony

# Inventory
var inventory:    PawnInventory  # see below

# Personality
var personality:  PawnPersonality  # see below

# Possession
var possessor_id: int = -1       # -1 = no possessor; ≥ 0 = player slot index
var player_boost_active: bool = false

# AI resume state
var ai_resume_state: Dictionary  # serialisable snapshot of AI task context

# World position (canonical cell for chunk purposes; physics position is on the node)
var last_known_cell: Vector2i
```

`PawnState` does NOT reference any node. It is safe to read from other autoloads.

### PawnInventory (RefCounted)

```
class_name PawnInventory
extends RefCounted

var capacity:  int                          # max item slots; from SpeciesDef
var slots:     Array[PawnInventorySlot]     # fixed-size array

# Fast lookup
var _totals: Dictionary[StringName, int]    # item_id → total count across slots

func add_item(item_id, count) -> int        # returns overflow
func remove_item(item_id, count) -> bool    # returns false if insufficient
func get_count(item_id) -> int
func is_full() -> bool
func get_carried_weight() -> float          # affects movement speed if > 0
```

### PawnPersonality (RefCounted)

Generated once on pawn creation, never changed. Stored in `PawnState` and persisted.

```
class_name PawnPersonality
extends RefCounted

var seed: int                   # source of all derived traits

# Trait scores — all 0..1, generated from seed
var curiosity:    float         # affects exploration radius when idle
var boldness:     float         # affects threat response (flee vs fight threshold)
var diligence:    float         # affects job re-attempt rate after failure
var chattiness:   float         # affects dialogue frequency and line selection
var stubbornness: float         # affects loyalty decay resistance

# Derived dialogue tags (subset selected from trait scores)
var dialogue_tags: Array[StringName]  # e.g. ["grumpy", "philosophical", "easily_distracted"]
```

`dialogue_tags` are matched against dialogue entry conditions in `DialogueDef` resources.
A pawn with `curiosity > 0.75` gets the `"explorer"` tag. Dialogue lines keyed to that
tag will be weighted higher for that pawn. This produces natural per-individual variation
without writing unique dialogue for each pawn.

---

## Pawn node structure

```
PawnBase (CharacterBody3D)
├── PawnState            (RefCounted — attached via @onready var state)
├── PawnAI               (Node — disabled when possessed)
├── PawnAbilityExecutor  (Node — shared execution engine)
├── CollisionShape3D
├── MeshInstance3D (or AnimatedMeshInstance3D)
├── InteractionDetector  (Area3D — detects nearby interactable targets)
├── DialogueDetector     (Area3D — detects nearby pawns for dialogue)
└── CameraRig            (Node3D — follows this pawn when possessed; disabled otherwise)
```

`PawnBase` is the scene root. Per-species scenes inherit from `PawnBase` and override:
- Mesh
- Collision shape
- `AbilityDef` references for action and alt-action slots
- Movement parameters (speed, acceleration, jump, altitude limits)
- `SpeciesDef` reference

### Species configuration (on the scene root or a child script)

Each species scene sets these exports:

```
@export var species_def:     SpeciesDef
@export var role_def:        RoleDef         # can be null for wild creatures
@export var action_ability:  AbilityDef      # bound to action button
@export var alt_ability:     AbilityDef      # bound to alt-action button
@export var interact_ability: AbilityDef     # bound to interact button (contextual prompt)
```

The queen is the only pawn where `action_ability`, `alt_ability`, and `interact_ability`
are runtime-mutable based on context. All other pawns have these set at scene design time
and do not change.

---

## Ability system

### Architecture decision

Abilities are defined as `AbilityDef` resources. `PawnAbilityExecutor` on each pawn node
reads the pawn's current ability slots and executes them. Per-creature scripts configure
which `AbilityDef` slots point to. Creatures that need non-standard behavior can override
specific virtual methods on `PawnBase` rather than reimplementing the whole executor.

This gives: data-driven tuning, shared execution path, per-creature override hooks, and
a contextual ability system for the queen that is just a regular ability with a different
targeting mode.

### AbilityDef (Resource)

```
class_name AbilityDef
extends Resource

@export var ability_id:       StringName
@export var display_name:     String
@export var description:      String
@export var icon:             Texture2D

# Targeting
@export var targeting_mode:        TargetingMode     # see enum below
@export var range:                 float = 1.5       # max 3D distance to valid target; interaction prompt appears within this range
@export var requires_xz_alignment: bool = false      # if true, pawn must be within the target's hex cell on the XZ plane (used for marker placement)
@export var valid_categories:      Array[int]        # CellCategory values this can target
@export var valid_item_tags:       Array[StringName] # item tags this can interact with
@export var valid_pawn_tags:       Array[StringName] # species/role tags for pawn targets

# Execution
@export var execution_mode:   ExecutionMode     # INSTANT, CHANNEL, TOGGLE
@export var channel_duration: float             # seconds for CHANNEL mode
@export var cooldown:         float             # seconds between uses
@export var stamina_cost:     float

# Effects — what actually happens
@export var effect_type:      AbilityEffectType # see enum below
@export var item_id:          StringName        # for GATHER, DROP, CRAFT effects
@export var item_count:       int = 1
@export var job_marker_type:  StringName        # for PLACE_MARKER effect
@export var damage:           float             # for ATTACK effects
@export var diplomacy_item_id: StringName       # for OFFER_TRADE effect

# Feedback
@export var animation_hint:   StringName        # passed to animation system
@export var vfx_id:           StringName
@export var sfx_id:           StringName

# AI hints
@export var ai_use_conditions: Array[StringName] # tags: "has_item:plant_fiber", "target_in_range", etc.
@export var ai_priority:       float             # weight for utility AI consideration
```

### TargetingMode enum

```
enum TargetingMode {
    SELF,           # affects the pawn itself (e.g. rest, eat)
    WORLD_CELL,     # targets the hex cell under cursor / in front of pawn
    NEARBY_ITEM,    # targets an item on the ground within range
    NEARBY_PAWN,    # targets a pawn within range matching valid_pawn_tags
    INVENTORY_ITEM, # targets an item in the pawn's own inventory
    CONTEXTUAL,     # queen mode: runtime query of best target in range
    HIVE_SLOT,      # targets a specific hive slot (when inside a hive)
}
```

### ExecutionMode enum

```
enum ExecutionMode {
    INSTANT,    # fires immediately on button press
    CHANNEL,    # held; fires on release or after channel_duration
    TOGGLE,     # first press activates, second press deactivates
}
```

### AbilityEffectType enum

```
enum AbilityEffectType {
    GATHER_RESOURCE,    # extract resource from cell/object into inventory
    DROP_ITEM,          # place item from inventory onto ground/slot
    PLACE_MARKER,       # create a job marker at target cell
    REMOVE_MARKER,      # remove a job marker at target cell
    ATTACK,             # deal damage to target pawn
    CRAFT,              # begin a craft at a hive slot
    POLLINATE,          # apply pollen from inventory to target plant cell
    WATER_PLANT,        # apply water to target plant cell
    BUILD_STRUCTURE,    # consume items to build a hive or structure
    ENTER_HIVE,         # transition into hive interior UI
    OFFER_TRADE,        # initiate diplomacy offer with target pawn
    LAY_EGG,            # queen only: place egg in nursery slot
    POSSESS_PAWN,       # queen/player only: initiate possession of target
    INTERACT_GENERIC,   # catch-all for unique species behaviors (calls override hook)
}
```

### PawnAbilityExecutor (Node)

One per pawn. Handles targeting resolution, cooldown tracking, channeling, and effect
dispatch.

```
class_name PawnAbilityExecutor
extends Node

var pawn: PawnBase                  # set on _ready
var cooldowns: Dictionary[StringName, float]  # ability_id → remaining cooldown

func try_action() -> bool           # attempts pawn's action_ability
func try_alt_action() -> bool       # attempts pawn's alt_ability
func try_interact() -> bool         # attempts interact_ability (contextual prompt)
func can_use(ability: AbilityDef) -> bool
func resolve_target(ability: AbilityDef) -> Variant  # returns target or null
func execute(ability: AbilityDef, target: Variant) -> void
func _tick_cooldowns(delta: float) -> void
```

`execute` dispatches on `ability.effect_type` and calls the appropriate system:
- `GATHER_RESOURCE` → calls `HexWorldState.consume_pollen/consume_nectar` or removes
  item from world
- `PLACE_MARKER` → calls `JobSystem.place_marker`
- `ATTACK` → calls `CombatSystem.deal_damage` (combat spec)
- `BUILD_STRUCTURE` → calls `HiveSystem.begin_build`
- `OFFER_TRADE` → calls `ColonyState.initiate_diplomacy`
- `INTERACT_GENERIC` → calls `pawn._on_interact_generic(target)` (override hook)

For `CONTEXTUAL` targeting (queen), `resolve_target` queries `InteractionDetector` for
all objects in range, scores them by priority (hive slots > pawns > plants > ground
markers), and returns the highest-priority valid target for the most relevant ability.
The HUD displays what the action/alt buttons will do based on this resolved context.

---

## Movement

### Ground pawn movement

Uses `CharacterBody3D` with `move_and_slide`. Navigates using Godot's `NavigationAgent3D`
when AI-controlled. When player-controlled, direction input is converted to world-space
velocity.

Ground pawns cannot enter cells with `CellCategory.RESOURCE_NODE` water type unless they
have a `can_swim` flag on `SpeciesDef`. They can climb TRAVERSABLE_STRUCTURE cells
(hollow logs, stumps) via the navigation mesh.

### Flying pawn movement

Uses `CharacterBody3D` with gravity disabled. Player-controlled: full 3D directional
input. Altitude clamped by:
- `min_altitude: float` — from terrain height (cannot go underground)
- `soft_max_altitude: float` — above tree canopy; triggers bird predator zone check
- `hard_max_altitude: float` — absolute ceiling (mountain peaks, etc.)

AI-controlled flying pawns use a simplified steering behavior rather than full
navigation mesh to avoid nav mesh generation cost for 3D flight.

### Possession movement boost

When a pawn is possessed, a small multiplier is applied to its effective movement speed
and action speed. This is not a separate ability — it is applied by `PossessionService`
when it takes control of a pawn.

```
# On SpeciesDef:
@export var possession_speed_boost:  float = 1.08   # 8% faster
@export var possession_action_boost: float = 1.05   # 5% faster action/gather
```

These are tunable per species. The intent is subtle — the player feels slightly better
than the AI without the AI feeling incompetent. Do not advertise this to the player.

---

## Possession system

### PossessionService (part of PawnManager)

`PossessionService` tracks which pawn each player slot is controlling and handles
transitions.

```
class_name PossessionService
extends RefCounted

var possessed_pawns: Dictionary[int, int]   # player_slot → pawn_id (-1 if none)
var max_players: int = 4                    # local + remote

func request_possess(player_slot: int, pawn_id: int) -> bool
func request_release(player_slot: int) -> void
func get_possessed_pawn(player_slot: int) -> PawnBase
func is_possessed(pawn_id: int) -> bool
func get_possessor(pawn_id: int) -> int     # returns player_slot or -1
```

### Possession eligibility check

```
func _can_possess(player_slot: int, pawn_id: int) -> bool:
    var state = PawnRegistry.get_state(pawn_id)
    return (
        state != null
        and state.is_alive
        and state.is_awake
        and state.colony_id == _player_colony(player_slot)
        and state.possessor_id == -1
        and not _is_queen(pawn_id) or player_slot == 0   # only host/P1 can possess queen
    )
```

Only player slot 0 (host / first player) can possess the queen. All other player slots
can possess any other eligible pawn. If a pawn is already possessed, it cannot be
possessed again — `possessor_id != -1` blocks it.

### Possession transition sequence

1. Validate eligibility. Return `false` if not eligible.
2. If `player_slot` currently possesses another pawn, release it first (step 4 below).
3. Set `state.possessor_id = player_slot`, `state.player_boost_active = true`.
4. Suspend `PawnAI` on the pawn node (set `ai_active = false`, snapshot AI state to
   `state.ai_resume_state`).
5. Route `player_slot`'s input to the pawn's `PawnAbilityExecutor` and movement handler.
6. Transition camera rig to the new pawn.
7. If the queen is leaving a position outside a hive, trigger queen safety behavior
   (queen flies to and enters nearest hive — see queen safety section below).
8. Emit `EventBus.pawn_possessed(pawn_id, player_slot)`.

### Release transition sequence

1. Set `state.possessor_id = -1`, `state.player_boost_active = false`.
2. Restore AI from `state.ai_resume_state` (resume AI node).
3. Disconnect player input from this pawn.
4. Camera rig returns to previous pawn or disables.
5. Emit `EventBus.pawn_released(pawn_id, player_slot)`.

### Queen safety behavior

When possession is released from the queen while she is outside a hive:
- AI resumes with an overriding `SEEK_SAFETY` job as the highest priority task.
- The queen navigates to and enters the nearest colony hive.
- While in `SEEK_SAFETY` state, she does not process strategic jobs (no markers, no
  diplomacy).
- `SEEK_SAFETY` clears once she is inside a hive.
- If no hive is reachable (all hives destroyed), she enters `EXPOSED` state and the
  player receives a warning.

---

## AI system (PawnAI)

### Architecture

`PawnAI` is a Node child of `PawnBase`. It uses a **utility AI + job polling** pattern:

1. Every `AI_TICK_INTERVAL` seconds (staggered across pawns to spread load), the AI
   evaluates its current state and either continues its job or selects a new one.
2. Selection uses a utility score per available behavior. The highest score wins.
3. Once a job is selected, the AI executes it step-by-step, calling
   `PawnAbilityExecutor` for actions (the same executor the player uses — no separate
   AI ability path).

```
class_name PawnAI
extends Node

var pawn: PawnBase
var ai_active: bool = true
var current_job: JobData = null
var current_subtask_index: int = 0
var utility_scores: Dictionary[StringName, float]

const AI_TICK_INTERVAL: float = 0.25   # seconds between utility evaluations
var _tick_timer: float = 0.0

func _process(delta: float) -> void:
    if not ai_active: return
    _tick_timer -= delta
    if _tick_timer <= 0.0:
        _tick_timer = AI_TICK_INTERVAL + randf() * 0.05  # jitter
        _evaluate()

func _evaluate() -> void:
    # ... score behaviors, select job, execute next subtask
```

### Utility scoring

Each pawn role has a `RoleDef` that lists its utility behaviors and base weights:

```
# In RoleDef:
@export var utility_behaviors: Array[UtilityBehaviorDef]
```

`UtilityBehaviorDef` is a small resource:

```
class_name UtilityBehaviorDef
extends Resource

@export var behavior_id:   StringName
@export var base_weight:   float
@export var conditions:    Array[StringName]  # "inventory_not_full", "has_job_of_type:BUILD", etc.
@export var score_curve:   Curve              # optional: modulate weight by a context float
```

At tick time, each behavior's score is: `base_weight * condition_multiplier * curve_sample`.
The highest-scoring behavior with a valid job in `JobSystem` is claimed.

### AI resume on possession release

When `PawnAI.ai_active` is set back to `true`, it reads `state.ai_resume_state`:

```
# Saved when possession begins:
state.ai_resume_state = {
    "job_id": current_job.job_id if current_job else -1,
    "subtask_index": current_subtask_index,
    "nav_target": _current_nav_target,
}
```

On resume:
- If the saved `job_id` still exists in `JobSystem` and is still claimed by this pawn,
  resume from `subtask_index`.
- Otherwise, clear state and run a fresh utility evaluation on the next tick.

The AI should feel like it picks up from where it was rather than restarting from scratch,
but it is acceptable for it to re-evaluate if the world changed significantly while the
player was in control.

---

## Chunk boundary behavior

### The problem

When a player possesses a pawn and moves far enough from their starting area, the chunk
under the pawn may be the only loaded chunk in that direction. If the player leaves that
pawn and the primary WorldViewer (camera) moves away, that chunk will despawn and the
pawn will be on unloaded terrain.

### WorldViewer system

A `WorldViewer` is any source that keeps chunks loaded around it. `HexTerrainManager`
processes a list of `WorldViewer` registrations and ensures chunks within
`view_radius_chunks` of each viewer are loaded.

```
# In HexTerrainManager:
var world_viewers: Array[WorldViewerData] = []

class WorldViewerData:
    var viewer_id: int
    var position_source: Callable    # () -> Vector3; called each frame
    var view_radius: int             # chunks
    var is_primary: bool             # primary viewer drives despawn of old chunks
```

By default, only the primary player's camera is a WorldViewer. When a second player
joins (local co-op or splitscreen), a second WorldViewer is registered for their camera.

**Rule:** A chunk is only despawned when NO WorldViewer requires it.

### Unloaded pawn handling

When a chunk despawns beneath a pawn that is NOT currently possessed:

1. The pawn's physics node is removed from the scene tree (`queue_free` or reparented
   to a holding node).
2. `PawnState` is preserved in `PawnRegistry` — the pawn is not dead.
3. The pawn's `last_known_cell` is updated one final time before node removal.
4. The pawn is marked `is_loaded: false` in `PawnRegistry`.
5. When a chunk containing `last_known_cell` is loaded again, `PawnManager` respawns
   the pawn node at that position.

**Unloaded pawns do not simulate.** Their jobs pause. Their age does not increment.
Fatigue does not advance. They resume exactly where they were when their chunk reloads.

**Exception: queen.** The queen always has a WorldViewer attached, even when the player
is possessing a different pawn. This ensures the queen's chunk never despawns. If the
queen is currently inside a hive, the hive's chunk is the queen's WorldViewer origin.

### Multiplayer WorldViewers

Each connected player (local or remote) registers a WorldViewer. The union of all
viewer radii determines which chunks stay loaded. The primary player's viewer also drives
spawn queue priority (nearest to P1 loads first). Remote player viewers add to the loaded
set but do not reorder the spawn queue.

---

## Dialogue and contextual interaction

### DialogueDetector

An `Area3D` child of `PawnBase`. When another pawn enters the detection radius:

1. Check `dialogue_cooldown` — if the pawn spoke recently, skip.
2. Check `chattiness` personality trait — random roll against it.
3. If both pass and the approaching pawn is different from the last dialogue partner,
   select a dialogue entry from `DialogueDef` matching the current context tags.
4. Display the line as a world-space speech bubble above the pawn.
5. No input required from the player for ambient dialogue.

When the player is possessing a pawn and another creature enters range:

1. If the creature has a `DialogueDef` entry with `requires_interact: true` (meaningful
   dialogue, trade offers, diplomacy), the `InteractionDetector` fires an interaction
   prompt.
2. The action button label on the HUD changes to the prompt text (e.g. "Talk to Queen
   Ant").
3. Pressing action calls `try_interact()` on `PawnAbilityExecutor`, which dispatches
   `OFFER_TRADE` or an appropriate ability.

### InteractionDetector

An `Area3D` child of `PawnBase`. Scans for interactable targets: hive entrances,
plants, items on the ground, other pawns with interaction abilities.

The detector's collision radius is set to the **maximum range** of the pawn's equipped
abilities. For most pawns this is 1.5–2.0 world units. For soldiers with ranged stinger
attacks it may be 4–6 units. The interaction prompt does not appear until the target is
within the specific ability's `range` value — the detector simply defines the outer
boundary of what gets checked.

For marker placement abilities, `requires_xz_alignment = true` means the prompt only
appears when the pawn is within the target hex cell's XZ boundary (directly above it),
regardless of vertical distance up to 3–4 units. This is checked by projecting the
pawn's XZ position into hex coordinates and comparing to the target cell coordinate.

Emits `interaction_targets_changed(targets: Array[Variant])` whenever the set of
valid targets changes. `PawnAbilityExecutor` listens to this to update contextual ability
resolution. The HUD listens to this to update button labels.

For the queen specifically, `resolve_target(CONTEXTUAL)` queries `InteractionDetector`
and scores all current targets:

```
Priority order:
1. Hive entrance (if facing hive and near entrance)
2. Pawn with trade/diplomacy dialogue available
3. Plant cell with pollen (if has_pollen and gardener-adjacent action)
4. Plant cell needing water
5. Ground marker to remove
6. Empty cell for new marker
```

The highest priority valid target determines what the action and alt-action buttons do.
HUD shows both button labels dynamically.

### DialogueDef (Resource)

```
class_name DialogueDef
extends Resource

@export var dialogue_id:       StringName
@export var speaker_tags:      Array[StringName]  # personality or role tags required on speaker
@export var context_tags:      Array[StringName]  # world-state tags: "in_territory", "winter", etc.
@export var requires_interact: bool = false        # if true, needs player to press interact
@export var lines:             Array[DialogueLine]
```

```
class DialogueLine:
    var text:              String
    var personality_tags:  Array[StringName]  # weighted higher for matching personality
    var weight:            float = 1.0
```

Lines are selected weighted randomly. Pawns with matching personality tags get higher
weight on lines tagged for their personality. This produces natural variation: a
"grumpy" forager and a "cheerful" forager will express different lines from the same
`DialogueDef` pool when complaining about being tired.

---

## Personality and individuality

### Generation

`PawnPersonality` is generated once when a pawn matures from an egg. It is derived from
a `personality_seed: int` that is stored on the pawn and used to generate all trait
values deterministically:

```
func generate(seed: int) -> void:
    var rng = RandomNumberGenerator.new()
    rng.seed = seed
    curiosity    = rng.randf()
    boldness     = rng.randf()
    diligence    = rng.randf()
    chattiness   = rng.randf()
    stubbornness = rng.randf()
    _derive_tags()
```

### Name generation

Names are generated from a name pool defined in a `NamePoolDef` resource per species.
The name is stored as a string on `PawnState` and never regenerates.

```
class_name NamePoolDef
extends Resource

@export var species_id:     StringName
@export var first_syllables: Array[String]
@export var mid_syllables:   Array[String]
@export var end_syllables:   Array[String]
@export var syllable_count_range: Vector2i = Vector2i(2, 3)
```

Name is generated by combining syllables using `pawn_id` as the seed, ensuring the same
pawn always has the same name if regenerated.

### Personality effects summary

| Trait | High value effect | Low value effect |
|---|---|---|
| `curiosity` | Wider idle exploration radius, seeks new plant types | Stays close to hive |
| `boldness` | Fights threats longer before fleeing | Flees earlier |
| `diligence` | Re-attempts failed jobs faster | Idles longer after failure |
| `chattiness` | Initiates ambient dialogue often | Rarely speaks |
| `stubbornness` | Loyalty decays slower | Loyalty decays faster |

These are implemented as multipliers in the relevant system (AI behavior weights, loyalty
decay rate in ColonyState, flee threshold in Combat). The pawn system exposes the trait
values; consuming systems apply them.

---

## PawnRegistry integration

`PawnRegistry` (autoload) maintains a lightweight index. It does NOT store `PawnState`
— the pawn node owns `PawnState`. `PawnRegistry` stores:

```
var _states:        Dictionary[int, PawnState]    # pawn_id → PawnState (direct reference)
var _nodes:         Dictionary[int, WeakRef]       # pawn_id → WeakRef to pawn node
var _by_colony:     Dictionary[int, Array[int]]    # colony_id → [pawn_ids]
var _by_cell:       Dictionary[Vector2i, Array[int]] # cell → [pawn_ids near that cell]
var _next_id:       int = 0
```

`PawnState` references are direct (not weak) because `PawnState` is a `RefCounted`
object owned by the pawn node. `PawnRegistry` holds a second reference so the state
survives if the pawn node is temporarily removed from the tree (chunk unload).

When a pawn node is freed (pawn dies), it calls `PawnRegistry.deregister(pawn_id)`.
When a chunk unloads under a pawn, the pawn node is queue_freed but `PawnState` persists
in `PawnRegistry` via that second reference.

---

## Save / load

`PawnRegistry` implements the standard save/load contract. On save, it serialises each
`PawnState` to a dictionary. On load, it restores all `PawnState` records.
`PawnManager` then spawns pawn nodes for each state that has a loaded chunk beneath it.

```
# PawnRegistry.save_state():
var pawns = []
for pawn_id in _states:
    pawns.append(_states[pawn_id].to_dict())
return {"pawns": pawns, "next_id": _next_id, "schema_version": 1}

# PawnRegistry.load_state(data):
for p in data["pawns"]:
    var state = PawnState.from_dict(p)
    _states[state.pawn_id] = state
    _by_colony.get_or_add(state.colony_id, []).append(state.pawn_id)
_next_id = data["next_id"]
```

On load, `PawnManager` iterates all loaded pawn states, checks which cells are currently
loaded, and spawns nodes for those. Pawns in unloaded chunks remain as state-only records
until their chunk loads.

---

## Multiplayer rules summary

| Rule | Detail |
|---|---|
| Queen possession | Player slot 0 only (host) |
| Other pawn possession | Any player slot, if pawn is not already possessed |
| Simultaneous possession | Each player can possess exactly one pawn at a time |
| WorldViewers | One per connected player; union keeps all player-nearby chunks loaded |
| Pawn switch UI | Each player has their own switch panel showing colony members |
| AI during multiplayer | Unpossessed pawns AI as normal; no change for remote players |
| Possession handoff | Only possible if target is unpossessed; no stealing |

---

## MVP scope notes

The following are explicitly deferred past MVP:

- Online multiplayer (WorldViewer and possession logic is designed to support it, but
  network synchronisation is not specced here).
- Per-pawn equipment slots or visual customisation.
- Full voiced dialogue (text lines only at MVP; audio hook `sfx_id` is present on
  `DialogueLine` for future use).
- Pawn relationships (friendship/rivalry between specific pawn pairs).
- Creature taming from wild state (wild creatures have `colony_id = -1`; taming
  mechanics that change this are post-MVP).
- Spectator camera mode for unloaded-pawn situations where player has no eligible pawns
  to possess.
