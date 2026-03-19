# BeezWorx MVP Spec: Job / Marker System

This document specifies `JobSystem`, the marker placement mechanic, job lifecycle,
job claiming by pawns, priority rules, failure handling, and ant pheromone trails.
It is the authoritative reference for `JobData`, `MarkerData`, and all interactions
between queen commands and autonomous worker behavior.

---

## Purpose and scope

The job system is the translation layer between strategic intent (queen places a marker,
hive slot needs filling, threat detected) and individual pawn action (carpenter navigates
to tree, forager claims nectar gather task, soldier patrols border).

It covers:
- Markers as craftable physical consumable items placed in the world
- Marker categories: job markers, navigation markers, info markers
- Job lifecycle: posted → claimed → executing → completed / failed
- Per-pawn task planning: how a pawn decides to source required materials
- Job sources: marker-derived, hive-slot-derived, AI-reactive
- Default fallback behaviors per role when no jobs are available
- Worker job discovery without per-tick global scanning
- Priority and preemption
- Failure, retry, and expiry
- Conveyor trail markers as a linked node system
- Territory decay of markers

It does **not** cover: pawn movement to the job site (navigation), ability execution at
the site (PawnAbilityExecutor), or hive slot management (HiveSystem). Those systems
consume jobs; this system only manages them.

---

## Core concepts

### Markers are physical craftable items

A **marker** is not an abstract system construct — it is a physical object that exists
in the world after being crafted and placed. The queen crafts marker items from materials
in her inventory (or a hive slot), then uses the `PLACE_MARKER` ability to deploy them
on a valid cell. The placed marker despawns the item from inventory and spawns a
world-visible marker node.

This means:
- Markers have a crafting cost. Running out of marker materials limits how many commands
  the queen can issue simultaneously.
- Markers can be picked up and redeployed (queen's alt-action on a placed marker removes
  it and returns the item to inventory at a small material penalty).
- Different marker types are different items, crafted from different materials.
- Info markers (placing signs/notes in the world) are just a marker type with no job
  generation and no decay — they are permanent labels.

### Marker categories

```
enum MarkerCategory {
    JOB,        # generates jobs for workers (build, gather, defend, graze, etc.)
    NAV,        # modifies navigation for specific species (ant conveyor, patrol route)
    INFO,       # world label only; no job or nav effect
}
```

All three categories use the same `MarkerDef` / `MarkerData` / `ItemDef` pipeline.
Category determines what happens after placement, not how placement works.

### Marker vs Job distinction

A **marker** is world-visible intent. It persists until explicitly removed, expires, or
decays. A **job** is an executable work unit derived from a marker or from world state.

```
Marker (physical item placed in world, persists)
  └── generates → Job(s) (claimed by one pawn, task-planned on claim)
```

When a job completes, `JobSystem` checks whether the marker still exists and whether
more jobs should be generated (e.g. a gather marker reposts as long as the resource
exists and the marker is present).

### Job sources

Jobs come from three sources:

1. **Marker-derived:** Queen places a marker item → `JobSystem` posts jobs.
2. **Hive-slot-derived:** `HiveSystem` detects an unfilled slot order → posts a craft or
   fetch job. These have no world-visible marker.
3. **Reactive:** `PawnAI` detects a local condition (low health, threat nearby, resource
   at feet) and posts a micro-job for itself only. Private — not claimed by others.

### Task planning (per-pawn, on job claim)

When a pawn claims a job that requires materials (e.g. BUILD_HIVE needs plant fiber and
propolis), it does not execute immediately. It first runs a **task planner** to determine
how to source the required materials. This replaces the old prerequisite-chain model.

The task planner evaluates two options for each required material:

**Option A — Fetch from colony inventory:**
- Cost = travel time to nearest hive containing the item + travel time back to job site
- Travel time accounts for inventory weight (laden bees move slower; plant fiber
  especially heavy relative to bee carry capacity)

**Option B — Harvest locally:**
- Cost = time to gather N units of raw material + time to craft if crafting needed +
  travel time to job site
- For materials the pawn cannot craft themselves (e.g. a carpenter cannot produce wax),
  Option B is unavailable for that material; pawn must use Option A or wait

The planner picks the lower-cost option per material. If neither option is immediately
available (hive empty, no local source, cannot craft), the job is released back to
POSTED and the pawn enters its fallback idle behavior.

```
# Pseudocode for task planner result:
class TaskPlan:
    var steps: Array[TaskStep]   # ordered list of what to do before reaching job site

class TaskStep:
    var step_type: StringName    # "FETCH_FROM_HIVE", "HARVEST_LOCAL", "CRAFT_AT_HIVE"
    var item_id: StringName
    var count: int
    var target_cell: Vector2i    # hive cell, harvest cell, or craft hive cell
    var valid_source_cells: Array[Vector2i]  # ranked sources for harvest
```

**Source validity for harvest:** The planner queries `HexWorldState` for nearby cells
containing the required resource plant or structural material. Plants/trees marked with
a `DO_NOT_HARVEST` marker are excluded. The pawn's species damage profile is checked —
a carpenter can break dead plants and stumps for fiber but should not destroy living
flowering plants (configurable per role via `RoleDef.harvest_restrictions`).

**Material depletion during execution:** Once at the job site, materials are consumed
at a rate of N units per time interval (defined on the `JobTemplateDef`). When inventory
is exhausted, the pawn returns to fetch more (runs task planner again for remaining
quantity), then returns to continue. The job tracks total progress as a float 0..1 so
partial work is preserved.

---

## MarkerDef (Resource)

```
class_name MarkerDef
extends Resource

@export var marker_type_id:       StringName
@export var marker_category:      MarkerCategory   # JOB, NAV, INFO
@export var display_name:         String
@export var icon:                 Texture2D
@export var color:                Color

# Physical item that gets consumed on placement
@export var crafted_from_item_id: StringName       # ItemDef id for the marker item
# (The marker item itself is defined in ItemDef; MarkerDef is what happens when placed)

# Placement rules
@export var requires_xz_alignment:  bool = true
@export var valid_cell_categories:  Array[int]
@export var max_per_cell:           int = 1
@export var can_place_outside_territory: bool = false

# For NAV markers: linked-node trail behavior
@export var is_trail_node:        bool = false     # if true, this marker is a trail node
@export var trail_species_tags:   Array[StringName]  # which species follow this trail
@export var trail_item_filter:    Array[StringName]  # item tags this trail carries (empty = all)

# Job generation (JOB category only)
@export var generates_jobs:       Array[JobTemplateDef]
@export var repost_on_complete:   bool = false
@export var repost_condition:     StringName

# Persistence
@export var is_persistent:        bool = false
@export var decay_outside_territory: bool = true
@export var manual_remove_only:   bool = false
@export var return_item_on_remove: bool = true     # return marker item to placer on manual remove
@export var return_item_cost:     float = 0.75     # fraction of material returned (0..1)
```

### JobTemplateDef (Resource, nested in MarkerDef)

```
class_name JobTemplateDef
extends Resource

@export var job_type_id:            StringName
@export var required_role_tags:     Array[StringName]
@export var required_items:         Array[JobMaterialReq]  # materials needed at job site
@export var priority:               int = 5
@export var max_claimants:          int = 1
@export var expires_after:          float = -1.0
@export var consumption_rate:       float = 1.0   # units of material consumed per second at site
@export var progress_on_completion: float = 1.0   # how much of job total this template completes
```

```
class JobMaterialReq:
    var item_id:      StringName
    var count:        int
    var per_colony:   bool = true   # if true, checks colony-wide inventory not just pawn
```

---

## MarkerData (runtime)

```
class_name MarkerData
extends RefCounted

var marker_id:       int
var marker_type_id:  StringName
var marker_category: int              # MarkerCategory enum
var def:             MarkerDef
var cell:            Vector2i
var placer_id:       int              # pawn_id (-1 for system-generated)
var colony_id:       int
var placed_at:       float
var decay_timer:     float = -1.0

# Job tracking (JOB markers)
var job_ids:         Array[int]
var job_progress:    float = 0.0      # 0..1; preserved across re-fetches

# Trail linkage (NAV trail markers)
var trail_id:        int = -1         # which trail this node belongs to (-1 = not a trail)
var trail_next_id:   int = -1         # next marker_id in trail direction A→B
var trail_prev_id:   int = -1         # prev marker_id in trail direction B→A
```

---

## JobData (runtime)

```
class_name JobData
extends RefCounted

var job_id:           int
var job_type_id:      StringName
var source_marker_id: int = -1
var colony_id:        int
var target_cell:      Vector2i
var target_pawn_id:   int = -1
var target_hive_id:   int = -1

var required_role_tags:  Array[StringName]
var required_items:      Array[JobMaterialReq]
var priority:            int
var max_claimants:       int
var expires_at:          float = -1.0

var status:          JobStatus
var claimant_ids:    Array[int]
var posted_at:       float
var claimed_at:      float = -1.0
var completed_at:    float = -1.0
var fail_count:      int = 0
var max_fails:       int = 3

# Progress tracking (for jobs that consume materials over time)
var progress:        float = 0.0      # 0..1; persists across material re-fetches
var task_plan:       TaskPlan = null  # set when job is claimed

enum JobStatus {
    POSTED,
    CLAIMED,
    EXECUTING,       # pawn is at site consuming materials
    COMPLETED,
    FAILED,
    EXPIRED,
    CANCELLED,
}
```

---

## JobSystem (autoload)

```
class_name JobSystem
extends Node

var _markers:          Dictionary[int, MarkerData]
var _jobs:             Dictionary[int, JobData]
var _markers_by_cell:  Dictionary[Vector2i, Array[int]]
var _jobs_by_colony:   Dictionary[int, Array[int]]
var _jobs_by_type:     Dictionary[StringName, Array[int]]
var _claimed_by_pawn:  Dictionary[int, int]

# Trail system
var _trails:           Dictionary[int, TrailData]   # trail_id → TrailData
var _next_trail_id:    int = 0
var _next_marker_id:   int = 0
var _next_job_id:      int = 0
```

```
class TrailData:
    var trail_id:       int
    var colony_id:      int
    var species_tags:   Array[StringName]
    var item_filter:    Array[StringName]
    var node_ids:       Array[int]    # ordered marker_ids from A to B
    var is_loop:        bool = true   # A→B→A for conveyor; false for one-way patrol
```

### Marker placement API

```
func place_marker(
    cell: Vector2i,
    marker_type_id: StringName,
    colony_id: int,
    placer_id: int = -1,
    trail_id: int = -1      # if >= 0, append this node to an existing trail
) -> int:   # returns marker_id, or -1 on failure
```

Validation steps:
1. Load `MarkerDef`. Return -1 if not found.
2. Verify the placer's inventory contains one unit of `def.crafted_from_item_id`.
   Remove it from inventory (marker is consumed on placement).
3. Check `valid_cell_categories` against cell state.
4. Check `requires_xz_alignment` if applicable.
5. Check `max_per_cell`.
6. Territory check — start decay timer if outside and `decay_outside_territory`.
7. Create `MarkerData`. If `trail_id >= 0`, link prev/next pointers and append to trail.
8. For JOB markers: call `_generate_jobs_from_marker`.
9. For NAV trail markers: call `_register_trail_node`.
10. Emit `EventBus.marker_placed`.
11. Return `marker_id`.

```
func remove_marker(marker_id: int, reason: StringName = &"manual") -> void
```

On manual remove: if `def.return_item_on_remove`, return
`floor(def.return_item_cost × original_stack)` units of the marker item to the placer's
inventory (or nearest hive if placer is not accessible). Cancel POSTED jobs. Re-link
trail if this was a trail node (prev.next = this.next, next.prev = this.prev).

### Trail registration

```
func create_trail(
    colony_id: int,
    species_tags: Array[StringName],
    item_filter: Array[StringName],
    is_loop: bool = true
) -> int:   # returns trail_id

func append_trail_node(trail_id: int, marker_id: int) -> void
func close_trail(trail_id: int) -> void   # connects last node back to first for loop
func dissolve_trail(trail_id: int) -> void   # removes all nodes and returns items
```

Trails are drawn by the player as a sequence of marker placements. Each placement of an
ANT_TRAIL or PATROL_ROUTE marker item checks whether an open trail exists for that colony
and species type. If one does, the node is appended. If not, a new trail is created.

The player signals "close the trail" by placing the final node within range of the first
node (snapping visual feedback when close enough), which calls `close_trail`.

### Job posting API (internal and hive-system-facing)

```
func post_job(
    job_type_id: StringName,
    target_cell: Vector2i,
    colony_id: int,
    priority: int,
    required_role_tags: Array[StringName],
    source_marker_id: int = -1,
    max_claimants: int = 1,
    expires_after: float = -1.0
) -> int:   # returns job_id
```

`HiveSystem` calls this directly (without markers) when a slot order needs filling.

### Job claiming API (called by PawnAI)

```
func get_claimable_jobs(
    pawn_id: int,
    colony_id: int,
    role_tags: Array[StringName],
    near_cell: Vector2i,
    search_radius: int = 12
) -> Array[JobData]:    # sorted by priority desc, then distance asc
```

Note: `required_item_tags` is removed from the query signature. Job material requirements
are no longer a pre-filter — the task planner evaluates sourcing after claim. A pawn
claims a job if it has the right role and the job is within range, then plans how to get
materials.

```
func claim_job(job_id: int, pawn_id: int) -> bool
```

On successful claim:
1. Set `job.claimant_ids.append(pawn_id)`, status → CLAIMED.
2. Run task planner: `job.task_plan = _build_task_plan(job, pawn_id)`.
3. If task planner returns null (no viable material source), immediately call
   `release_job` and return false. The job stays POSTED for another pawn to try.
4. Emit `EventBus.job_claimed`.

```
func release_job(job_id: int, pawn_id: int) -> void
func complete_job(job_id: int, pawn_id: int) -> void
func fail_job(job_id: int, pawn_id: int) -> void
func update_job_progress(job_id: int, progress_delta: float) -> void
```

`update_job_progress` is called by `PawnAbilityExecutor` each tick while the pawn is
EXECUTING at the job site. Progress accumulates; when it reaches 1.0, `complete_job`
is called automatically. If the pawn runs out of materials mid-execution, status reverts
to CLAIMED (not POSTED — the same pawn re-runs task planning for remaining materials).

### Job discovery performance

Scanning all POSTED jobs every AI tick would be O(jobs × pawns). Instead:

- `_jobs_by_colony` indexes POSTED jobs per colony. Foragers only scan jobs in their
  colony.
- `_jobs_by_type` allows role-filtered queries: a carpenter only fetches from
  `_jobs_by_type["BUILD"]` and `_jobs_by_type["GATHER_FIBER"]`.
- Distance filtering uses `HexWorldBaseline.hex_disk` around `near_cell` with
  `search_radius`. Only jobs whose `target_cell` falls in the disk are returned.
- AI ticks are staggered (see Pawn spec). With 50 pawns at 0.25s intervals, that's
  200 queries/second maximum, each scanning at most ~50 jobs in range.

For MVP this is acceptable. Post-MVP: spatial hash for job lookup by cell region.

---

## Job type definitions

Job types are `StringName` ids matched to behavior in `PawnAI`. Each role's
`RoleDef.utility_behaviors` lists which job types that role handles. Job types are not
Resources — they are just agreed-upon string ids. The canonical list for MVP:

### Resource jobs (Forager, Gardener, Queen)
- `"GATHER_NECTAR"` — go to plant cell, consume nectar into inventory
- `"GATHER_POLLEN"` — go to plant cell, consume pollen into inventory
- `"GATHER_WATER"` — go to water source, fill water capacity
- `"DEPOSIT_ITEMS"` — go to hive slot, deposit carried items
- `"POLLINATE_PLANT"` — go to target plant, apply pollen from inventory

### Construction jobs (Carpenter)
- `"GATHER_PLANT_FIBER"` — attack stump/dead plant for fiber
- `"GATHER_BEE_GLUE"` — craft glue at hive (prerequisite: has fiber + nectar)
- `"BUILD_HIVE"` — go to build marker, consume materials, build hive structure

### Defense jobs (Soldier)
- `"GATHER_THORNS"` — collect from briar/thistle
- `"GATHER_TOXIN"` — collect from toxic plants or defeated enemies
- `"CRAFT_STINGER"` — craft at hive slot
- `"PATROL"` — move to and hold position near threat zone
- `"ATTACK_THREAT"` — engage specific threat pawn

### Logistics jobs (Ant)
- `"CARRY_ITEM"` — pick up item at source cell, deliver to destination cell
- `"PLACE_PHEROMONE"` — place ant trail marker at cell
- `"REMOVE_PHEROMONE"` — remove ant trail marker at cell

### Nursery jobs (Nurse)
- `"FEED_EGG"` — go to nursery slot, deposit food item into slot
- `"TEND_EGG"` — periodic check-in on egg slot

### Management jobs (Queen)
- `"PLACE_MARKER"` — queen places a scent marker at target cell
- `"INITIATE_DIPLOMACY"` — queen approaches faction NPC, initiates trade
- `"LAY_EGG"` — queen deposits egg in available nursery slot

---

## Marker types (MVP)

All marker types below correspond to both a `MarkerDef` resource and a craftable
`ItemDef`. The item is what the queen holds and places; the def is what governs behavior
after placement.

### Hive Build Marker (JOB)
```
marker_type_id: "BUILD_HIVE"
marker_category: JOB
crafted_from_item_id: "marker_build_hive"   # crafted from royal_wax + bee_glue
valid_cell_categories: [TREE, TRAVERSABLE_STRUCTURE]
generates_jobs: [BUILD_HIVE]
required_items: [{item_id: "plant_fiber", count: 20}, {item_id: "propolis", count: 5}]
consumption_rate: 2.0 units/second
repost_on_complete: false
decay_outside_territory: true
```
The BUILD_HIVE job has a single template. The carpenter's task planner handles all
material sourcing. There are no prerequisite sub-jobs — sourcing is the pawn's
responsibility, not the job system's.

### Gather Marker (JOB)
```
marker_type_id: "GATHER"
marker_category: JOB
crafted_from_item_id: "marker_gather"   # crafted from basic wax + pollen
valid_cell_categories: [RESOURCE_PLANT, TREE]
generates_jobs: [GATHER_NECTAR or GATHER_POLLEN based on plant state at generation time]
max_claimants: 1
repost_on_complete: true
repost_condition: "plant_has_resource"
decay_outside_territory: true
```

### Defend Marker (JOB)
```
marker_type_id: "DEFEND"
marker_category: JOB
crafted_from_item_id: "marker_defend"   # crafted from toxin + wax
valid_cell_categories: [any]
generates_jobs: [PATROL]
max_claimants: 3
repost_on_complete: true
decay_outside_territory: false
manual_remove_only: true
```

### Graze Marker (JOB)
```
marker_type_id: "GRAZE"
marker_category: JOB
crafted_from_item_id: "marker_graze"   # crafted from nectar + pollen
valid_cell_categories: [RESOURCE_PLANT, EMPTY ground]
generates_jobs: [GRAZE_AREA]
max_claimants: 5   # multiple grasshoppers can work the same area
repost_on_complete: true
repost_condition: "area_has_grass"
decay_outside_territory: true
```
GRAZE_AREA job is claimed by allied grasshoppers. They consume grass in the area,
clearing it. Can also be used with hopperwine distraction (place graze marker on grass
with hopperwine item to attract wild grasshoppers without requiring alliance).

### Do Not Harvest Marker (JOB / guard)
```
marker_type_id: "DO_NOT_HARVEST"
marker_category: JOB
crafted_from_item_id: "marker_guard"
valid_cell_categories: [RESOURCE_PLANT, TREE]
generates_jobs: []   # no jobs; acts as a flag read by task planner
is_persistent: true
manual_remove_only: true
decay_outside_territory: false
```
Task planners check for this marker before designating a cell as a valid harvest source.
Plants/trees with this marker are excluded from autonomous harvest targeting.

### Conveyor Trail Node (NAV)
```
marker_type_id: "ANT_CONVEYOR_NODE"
marker_category: NAV
crafted_from_item_id: "marker_ant_trail"   # crafted from ant_jelly + wax
valid_cell_categories: [any ground-traversable, TRAVERSABLE_STRUCTURE]
is_trail_node: true
trail_species_tags: ["ant"]
is_persistent: true
manual_remove_only: true
decay_outside_territory: false
```
Trail nodes are linked into `TrailData` records. Ants following a trail walk the A→B→A
loop. Items dropped on any cell within 1 unit of a trail node are picked up by passing
ants and carried to the next node, deposited, and picked up by the next ant. This creates
a bucket-brigade conveyor. The `item_filter` on `TrailData` restricts which items the
trail carries (empty = all items).

Hollow log / TRAVERSABLE_STRUCTURE trail nodes cause ants to path over the structure,
enabling overpasses and crossing water gaps.

### Patrol Route Node (NAV)
```
marker_type_id: "PATROL_NODE"
marker_category: NAV
crafted_from_item_id: "marker_patrol"   # crafted from toxin + wax
valid_cell_categories: [any]
is_trail_node: true
trail_species_tags: ["soldier_bee", "soldier_ant", "guard_beetle"]
is_persistent: true
manual_remove_only: true
decay_outside_territory: false
```
Patrol nodes work exactly like conveyor nodes but for soldiers. When a soldier claims a
PATROL job derived from a DEFEND marker, it walks between the nearest patrol nodes
randomly, watching for threats. If no patrol nodes exist near the defend marker, the
soldier orbits the marker cell instead.

### Info Marker (INFO)
```
marker_type_id: "INFO"
marker_category: INFO
crafted_from_item_id: "marker_info"   # crafted from basic wax
valid_cell_categories: [any]
is_persistent: true
manual_remove_only: true
decay_outside_territory: false
generates_jobs: []
```
Stores a text string (up to 120 characters) set at placement time. When any pawn or
player is within interaction range of an info marker, the interaction prompt shows
"Read sign." Pressing interact displays the text. Effectively a world-space label.
Useful for multiplayer coordination and personal notation.

---

## Territory decay

`JobSystem._process` runs a decay pass once per second (not every frame):

```
func _decay_pass() -> void:
    var now: float = TimeService.world_time
    for marker_id in _markers:
        var marker: MarkerData = _markers[marker_id]
        if not marker.def.decay_outside_territory:
            continue
        var in_territory: bool = TerritorySystem.is_in_territory(
            marker.cell, marker.colony_id
        )
        if in_territory:
            marker.decay_timer = -1.0   # reset decay if back in territory
        else:
            if marker.decay_timer < 0.0:
                marker.decay_timer = MARKER_DECAY_DURATION   # start decay
            else:
                marker.decay_timer -= 1.0
                if marker.decay_timer <= 0.0:
                    remove_marker(marker_id, &"territory_decay")
```

`MARKER_DECAY_DURATION` is a config constant (default: 30 seconds). This gives the
player a grace period to reclaim territory before markers evaporate.

---

## Default fallback behaviors (no jobs available)

When `get_claimable_jobs` returns empty, `PawnAI` falls back to role-defined default
behaviors. These are not jobs — they are autonomous routines defined on `RoleDef`.

| Role | Primary fallback | Secondary fallback |
|---|---|---|
| Forager | Gather main resource (nectar/water) and deposit at nearest hive | Rest if fatigue high |
| Gardener | Pollinate nearby flowering plants | Gather pollen and deposit |
| Carpenter | Gather plant fiber and deposit at hive | Craft queued hive slot orders |
| Soldier | Patrol territory perimeter (orbit capital hive boundary) | Guard hive entrance |
| Crafter | Check hive slot orders, craft whatever is queued | Rest |
| Nurse | Check nursery slots for eggs needing feeding | Gather food |
| Queen (NPC) | Enter capital hive and remain there | (no secondary) |

Fallback behavior consumes the same `PawnAbilityExecutor` path as job execution — the
difference is there is no `JobData` record. Fallback progress is not tracked or saved.
Fallback is interrupted immediately when a real job becomes claimable.

**Craft-before-gather rule:** If a pawn's next action requires a crafted item (e.g.
carpenter needs propolis to build), and that item is not in hive inventory, the pawn
checks if it can craft it. If yes and it has the ingredients, it crafts first. If it
lacks ingredients it cannot produce itself (e.g. carpenter lacks wax), it waits in the
hive for the item to be stored, checks periodically, and re-evaluates after a short
delay (30 seconds by default, tunable on `RoleDef`).

---

## Reactive / private jobs

`PawnAI` can post jobs that are only claimable by itself. These have `max_claimants = 1`
and `colony_id = -pawn_id` (a negative id convention that `get_claimable_jobs` treats
as private). Examples:

- `"SEEK_SLEEP"` — post when fatigue > 0.85; navigate to bed slot
- `"SEEK_FOOD"` — post when hunger > threshold; find food in nearest hive
- `"FLEE"` — post when health low and threat nearby; navigate away

Reactive jobs use the same job lifecycle but are never shown in colony management UI
and cannot be claimed by other pawns.

---

## EventBus integration

```
# Emitted by JobSystem:
EventBus.job_posted(job_id, job_type_id, target_cell, colony_id, priority)
EventBus.job_claimed(job_id, pawn_id)
EventBus.job_completed(job_id, pawn_id)
EventBus.job_failed(job_id, pawn_id)
EventBus.marker_placed(marker_id, marker_type_id, cell, colony_id)
EventBus.marker_removed(marker_id, cell, reason)

# Consumed by JobSystem:
EventBus.hive_destroyed     → cancel BUILD_HIVE jobs targeting that hive
EventBus.territory_faded    → trigger decay pass for affected cells
EventBus.pawn_died          → release any job claimed by that pawn
```

---

## Save / load

```
func save_state() -> Dictionary:
    var markers = []
    for m in _markers.values():
        markers.append(m.to_dict())

    var trails = []
    for t in _trails.values():
        trails.append(t.to_dict())

    var persistent_jobs = []
    for j in _jobs.values():
        if j.colony_id >= 0 and j.status in [JobStatus.POSTED, JobStatus.CLAIMED, JobStatus.EXECUTING]:
            persistent_jobs.append(j.to_dict())

    return {
        "markers": markers,
        "trails": trails,
        "jobs": persistent_jobs,
        "next_marker_id": _next_marker_id,
        "next_trail_id": _next_trail_id,
        "next_job_id": _next_job_id,
        "schema_version": 1,
    }
```

On load: markers restored first (to rebuild `_markers_by_cell`), then trails (to
re-link node pointers), then jobs. CLAIMED and EXECUTING jobs are restored as POSTED —
pawns re-claim on first AI tick. Task plans are not saved; they are recomputed on claim.
Reactive jobs (`colony_id < 0`) are not saved.

---

## EventBus integration

```
# Emitted by JobSystem:
EventBus.marker_placed(marker_id, marker_type_id, cell, colony_id)
EventBus.marker_removed(marker_id, cell, reason)
EventBus.job_posted(job_id, job_type_id, target_cell, colony_id, priority)
EventBus.job_claimed(job_id, pawn_id)
EventBus.job_completed(job_id, pawn_id)
EventBus.job_failed(job_id, pawn_id)

# Consumed by JobSystem:
EventBus.hive_destroyed     → cancel BUILD_HIVE jobs targeting that hive
EventBus.territory_faded    → trigger decay pass for affected cells
EventBus.pawn_died          → release any job claimed by that pawn
```

---

## MVP scope notes

Deferred past MVP:

- Scout bee remote command system.
- Marker priority override by player.
- Competing colony markers (rival markers visible and removable via infiltration).
- Item filter UI on conveyor trail (player setting which items a trail carries).
- Trail visualisation overlay on the minimap.
- Seed / transplant marker type.
- Info marker text input UI (the data model is ready; the UI widget is post-MVP).
