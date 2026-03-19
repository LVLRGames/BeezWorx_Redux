# BeezWorx Architecture Specification

This document is the canonical reference for system boundaries, ownership rules,
inter-system communication patterns, and cell occupancy contracts. All other specs
reference this document. When a spec conflicts with this document, this document wins
unless this document is explicitly updated.

---

## Guiding principles

1. **Autoloads own simulation state. Scene nodes own presentation and input.**
   No scene node holds canonical game state that another system needs to read. If two
   systems need the same data, it belongs in an autoload, not passed between nodes.

2. **Systems communicate through EventBus signals or direct autoload calls. Never through
   scene node references.**
   A system may call another autoload's public API directly. It must never hold a
   reference to a scene node belonging to another system.

3. **HexWorldState is a substrate, not a domain system.**
   It answers: "what is on this cell and what are its terrain properties?" It does not
   answer: "what is the hive's inventory?" or "what is this pawn's loyalty?" Those belong
   to domain autoloads.

4. **One source of truth per piece of state.**
   If `TerritorySystem` owns influence values, `HexWorldState` does not also store them.
   If `TimeService` owns world time, `HexTerrainManager` does not also track it.

5. **Data definitions are Resources. Runtime state is not.**
   `.tres` files define what things are. Autoloads and RefCounted objects hold what is
   currently happening.

6. **Signals describe events, not commands.**
   `EventBus.hive_destroyed(hive_id)` is correct. `EventBus.request_territory_recalculate()`
   is a command dressed as a signal and is wrong. Systems that need to react to events
   subscribe to signals. Systems that need to trigger behavior call the target autoload
   directly.

---

## System map

```
AUTOLOADS (process order matters — listed in dependency order)
├── EventBus          — typed signal hub, no state
├── TimeService       — world_time, day/night, seasons
├── HexWorldState     — terrain substrate, cell occupancy index, baseline/delta/sim
├── HiveSystem        — hive state, slot contents, hive integrity
├── TerritorySystem   — per-cell influence fields, fade timers, allegiance
├── ColonyState       — per-colony: queen identity, known recipes, morale summary
├── JobSystem         — job queue, job registration, job claiming by pawns
├── PawnRegistry      — lightweight index of all live pawns by id and cell
└── SaveManager       — orchestrates save/load across all systems

SCENE-OWNED MANAGERS (in the scene tree, not autoloads)
├── HexTerrainManager — chunk streaming, mesh generation, advances TimeService
├── PawnManager       — spawns/despawns pawn nodes, routes possession input
└── UIRoot            — HUD, hive slot overlay, pawn switch panel

DATA RESOURCES (.tres, read-only at runtime)
├── HexTerrainConfig  — all terrain generation parameters
├── ItemDef           — item identity, stack size, tags, nutrition
├── RecipeDef         — inputs, outputs, craft time, role requirements
├── RoleDef           — pawn role identity, ability kit references
├── SpeciesDef        — base stats per species
├── AbilityDef        — action/alt-action definition, targeting rules
├── HiveDef           — hive upgrade definitions
├── FactionDef        — faction personality, diplomacy preferences
├── MarkerDef         — marker type, job generated, placement rules
└── ThreatDef         — threat type, spawn conditions, behavior profile
```

---

## Autoload responsibilities

### EventBus

Owns no state. Declares all cross-system signals as typed methods. Systems connect to
and emit through EventBus only — never through direct node signal connections between
unrelated systems.

Key signals (full list in EventBus spec):

```
# World
cell_occupied(cell: Vector2i, category: int)
cell_cleared(cell: Vector2i)
cell_plant_stage_changed(cell: Vector2i, new_stage: int)
cell_plant_resources_changed(cell: Vector2i)  # pollen/nectar amounts changed

# Hive
hive_built(hive_id: int, anchor_cell: Vector2i, colony_id: int)
hive_destroyed(hive_id: int, anchor_cell: Vector2i, colony_id: int)
hive_integrity_changed(hive_id: int, new_integrity: float)
hive_slot_changed(hive_id: int, slot_index: int)

# Territory
territory_expanded(colony_id: int, cells: Array[Vector2i])
territory_faded(colony_id: int, cells: Array[Vector2i])

# Colony / Pawn
pawn_spawned(pawn_id: int, colony_id: int, cell: Vector2i)
pawn_died(pawn_id: int, colony_id: int)
pawn_loyalty_changed(pawn_id: int, new_loyalty: float)
queen_died(colony_id: int, had_heir: bool)
colony_founded(colony_id: int)
colony_dissolved(colony_id: int)

# Jobs
job_posted(job_id: int, job_type: int, cell: Vector2i)
job_claimed(job_id: int, pawn_id: int)
job_completed(job_id: int)
job_failed(job_id: int)

# Diplomacy
faction_relation_changed(colony_id: int, faction_id: int, new_relation: float)
trade_completed(colony_id: int, faction_id: int)

# Time
day_changed(new_day: int)
day_started
night_started
season_changed(new_season: int)
year_changed(new_year: int)

# Threats
raid_started(threat_id: int, target_colony_id: int)
raid_ended(threat_id: int)
```

### TimeService

Owns the single authoritative world clock. All time-dependent systems read from here.
Full spec in `time_season_spec.md`.

```
world_time: float        # raw elapsed in-game seconds (read-only externally)
day_length: float        # real seconds per in-game day
days_per_season: int
current_day: int         # derived
day_phase: float         # 0..1 within current day
is_daytime: bool
current_season: int      # 0=spring 1=summer 2=fall 3=winter
current_year: int
```

`HexTerrainManager` calls `TimeService.advance(delta * time_scale)` each frame. Nothing
else advances the clock.

### HexWorldState

Owns terrain generation and the cell occupancy index. Provides the substrate that domain
systems register into and query.

**Does NOT own:** hive contents, pawn positions (canonical), territory influence values,
loyalty, inventory, colony identity.

**Owns:**
- `HexTerrainConfig`, `HexDefinitionRegistry`, `HexWorldBaseline`, `HexWorldDeltaStore`,
  `HexWorldSimulation`
- The cell cache (`Dictionary[Vector2i, HexCellState]`)
- Cell mutation API (place, clear, mutate, consume)
- Cross-pollination logic (`attempt_cross_sprout`)

**Signals emitted (on HexWorldState, not EventBus):**

```
# Internal use by HexChunk only:
cell_changed(cell: Vector2i, hint: CellChangeMutationHint)
```

`CellChangeMutationHint` is an enum:

```
enum CellChangeMutationHint {
    STRUCTURAL,      # object placed or removed — requires full refresh_objects()
    STAGE_CHANGE,    # plant stage advanced — requires refresh_plants()
    RESOURCE_CHANGE, # pollen/nectar/thirst changed — shader param update only
    MARKER_CHANGE,   # job marker added/removed — marker layer update only
}
```

`HexChunk._on_cell_changed` switches on the hint to call the appropriate refresh path.
After handling visual update, `HexChunk` forwards relevant changes to `EventBus`:
- STRUCTURAL changes that affect hive or territory → `EventBus.cell_occupied` /
  `EventBus.cell_cleared`
- STAGE_CHANGE → `EventBus.cell_plant_stage_changed`
- RESOURCE_CHANGE → `EventBus.cell_plant_resources_changed`

### HiveSystem

Owns all runtime hive state. Keyed by `hive_id: int` (autoincrement).

```
Dictionary[int, HiveState]        # hive_id → HiveState
Dictionary[Vector2i, int]         # anchor_cell → hive_id (fast lookup)
```

`HiveState` owns: anchor cell, colony id, slot array, integrity, upgrade flags, territory
radius, fade state if destroyed.

Subscribes to: `EventBus.hive_destroyed` (to start fade), `EventBus.colony_dissolved`
(to clean up all hives for that colony).

Public API used by other systems:
- `get_hive_at(cell) -> HiveState`
- `get_hives_for_colony(colony_id) -> Array[HiveState]`
- `get_capital_hive(colony_id) -> HiveState`
- `get_territory_radius(hive_id) -> int`

### TerritorySystem

Owns per-cell influence values and per-hive fade timers. No cell mesh data.

```
Dictionary[Vector2i, Dictionary[int, float]]  # cell → {colony_id: influence}
Dictionary[int, float]                        # hive_id → fade_timer
```

Subscribes to: `EventBus.hive_built`, `EventBus.hive_destroyed`.

On `hive_built`: flood-fill influence from anchor cell up to territory radius, register
cells.

On `hive_destroyed`: start fade timer for that hive's unique (non-overlapped) cells.
Tick fade each process frame. When a cell's influence for a colony reaches zero, emit
`EventBus.territory_faded` for that batch of cells.

Public API:
- `get_influence(cell, colony_id) -> float`  — 0..1
- `is_in_territory(cell, colony_id) -> bool`
- `get_controlling_colony(cell) -> int`      — colony with highest influence
- `get_all_colonies_at(cell) -> Array[int]`

Active plant allegiance is determined by `TerritorySystem.get_controlling_colony(cell)`.
If the controlling colony is not the player's colony, the plant may commit friendly fire.
Full rules in territory and active plant specs.

### ColonyState

One entry per colony (player and AI). Owns colony-level aggregates.

```
Dictionary[int, ColonyData]   # colony_id → ColonyData
```

`ColonyData` owns: queen pawn id, capital hive id, known recipe ids, princess pawn ids,
colony-wide morale (derived from pawn loyalty average), alliance/war state per faction,
influence score.

Subscribes to: `EventBus.queen_died`, `EventBus.pawn_died`, `EventBus.pawn_loyalty_changed`.

Player's colony_id is always `0` by convention.

### JobSystem

Full spec in `job_marker_spec.md`. Owns the job queue and marker registry.

```
Dictionary[int, JobData]       # job_id → JobData
Dictionary[Vector2i, Array[int]]  # cell → [marker_ids at that cell]
```

Markers are world-visible job intent. Jobs are executable work units. Markers spawn jobs.
Jobs are claimed by pawns.

### PawnRegistry

Lightweight index only. Owns no simulation state — that lives on pawn nodes.

```
Dictionary[int, Node]          # pawn_id → pawn node (weak ref pattern)
Dictionary[int, Array[int]]    # colony_id → [pawn_ids]
```

Other systems look up pawns by id via PawnRegistry. They do not hold node references
directly.

### SaveManager

Orchestrates save/load. Calls `save()` / `load()` on each stateful autoload in
dependency order. Full spec in save_load_spec.md.

---

## Scene node responsibilities

### HexTerrainManager

- Calls `TimeService.advance(delta * time_scale)` in `_process`.
- Manages chunk spawn/despawn queues and background generation.
- Does NOT own world time or terrain config (those belong to TimeService and HexWorldState).

### PawnManager

- Spawns and despawns pawn scene nodes in response to `EventBus.pawn_spawned` and
  `EventBus.pawn_died`.
- Routes player input to the currently possessed pawn via `PossessionService` (part of
  PawnManager or a child).
- Does NOT own pawn simulation state — pawn nodes own their own `PawnState` component,
  which is the canonical runtime state for that pawn.

### UIRoot

- Reads from autoloads. Emits player intent back to autoloads or PawnManager.
- Never mutates autoload state directly — always goes through the public API.

---

## Cell occupancy contract

### Categories

```
enum CellCategory {
    EMPTY             = 0,
    RESOURCE_PLANT    = 1,   # flowers, herbs, crops (up to 6 per cell)
    TREE              = 2,   # one per cell; also a valid hive anchor
    DEFENSIVE_ACTIVE  = 3,   # flytrap, whipvine, briar (one per cell)
    HIVE_ANCHOR       = 4,   # tree or alternate support structure with a hive built on it
    TRAVERSABLE_STRUCTURE = 5, # hollow log, stump, rock pile (single occupancy)
    RESOURCE_NODE     = 6,   # mineral deposit, water source (single occupancy)
    TERRITORY_MARKER  = 7,   # queen command scent marker (see marker rules below)
    PAWN_SPAWN        = 8,   # editor/designer-placed spawn point (not player-placed)
}
```

### Coexistence rules

| Category | Max per cell | Can coexist with |
|---|---|---|
| RESOURCE_PLANT | 6 | TREE, HIVE_ANCHOR, TERRITORY_MARKER |
| TREE | 1 | RESOURCE_PLANT, HIVE_ANCHOR (a tree becomes HIVE_ANCHOR when a hive is built on it; the tree definition remains), TERRITORY_MARKER |
| DEFENSIVE_ACTIVE | 1 | RESOURCE_PLANT, TERRITORY_MARKER |
| HIVE_ANCHOR | 1 | RESOURCE_PLANT, TERRITORY_MARKER (replaces TREE category when hive is placed) |
| TRAVERSABLE_STRUCTURE | 1 | TERRITORY_MARKER (ant pheromone markers only; see below) |
| RESOURCE_NODE | 1 | TERRITORY_MARKER |
| TERRITORY_MARKER | unlimited | everything |

**Pawns are not cell occupants.** Pawns use physics/navigation and can stand on any
traversable surface. Pawn positions are tracked by the pawn node and PawnRegistry, not
by HexCellState. Multiple pawns can occupy the same cell simultaneously.

**Hive anchor upgrade:** when a hive is built on a TREE cell, the cell's primary category
changes from TREE to HIVE_ANCHOR. The tree's `HexPlantGenes` and visual data are
preserved; only the category changes. The hive cannot be built on a cell with an active
plant or a second tree. It can coexist with resource plants.

**HIVE_ANCHOR replaces TREE** in the category field but the underlying definition remains
a `HexTreeDef`. `HexWorldState` records this as a STRUCTURAL delta. `HiveSystem` records
the hive data keyed by that cell.

### Marker placement rules

Territory markers (queen scent markers, job markers) are stored in `JobSystem`, not in
`HexWorldState`. They do not consume a cell occupancy slot. They are rendered as a
separate overlay layer.

Ant pheromone markers (placed by ants and the player while possessing an ant) follow
different rules:
- Can be placed on ground-level cells.
- Can be placed on TRAVERSABLE_STRUCTURE cells (hollow logs act as overpasses for ant
  lines — a pheromone marker on a hollow log causes ants to path over it rather than
  around it).
- Cannot be placed on cells with water or in ocean biome.
- Are stored in `JobSystem` as a special marker type with `is_persistent: true`.

### Multi-cell footprints

Large objects (giant trees, large rock formations) may occupy multiple cells. The anchor
cell holds the definition. Satellite cells hold a `CLEARED`-equivalent state pointing to
the anchor origin via `HexWorldDeltaStore` occupancy tracking. No other object can occupy
a satellite cell except TERRITORY_MARKER.

---

## Inter-system call patterns

### Permitted direct calls (A calls B's public API)

```
HexTerrainManager  → TimeService         (advance clock)
HexTerrainManager  → HexWorldState       (initialize, on_chunk_loaded, on_chunk_unloaded)
HexChunk           → HexWorldState       (get_cell_ref, on_chunk_loaded)
PawnManager        → PawnRegistry        (register, deregister)
PawnManager        → JobSystem           (claim_job, complete_job, fail_job)
PawnManager        → HexWorldState       (get_cell — for interaction checks)
PawnManager        → HiveSystem          (get_hive_at — for entering hive)
HiveSystem         → TerritorySystem     (get_influence — for supply chain checks)
HiveSystem         → ColonyState         (get_capital_hive — for management menu gate)
TerritorySystem    → HiveSystem          (get_territory_radius, get_hives_for_colony)
ColonyState        → PawnRegistry        (get pawns for colony)
JobSystem          → HexWorldState       (get_cell — to validate marker placement)
JobSystem          → TerritorySystem     (is_in_territory — markers decay outside territory)
Any system         → TimeService         (current_season, is_daytime, world_time)
```

### Prohibited patterns

- Scene nodes holding references to other scene nodes across system boundaries.
- Any autoload importing or instancing a scene node.
- `HexWorldState` calling `HiveSystem`, `TerritorySystem`, or `ColonyState`.
  (Dependency arrow is one-way: domain systems depend on substrate, not vice versa.)
- `HexChunk` calling any domain autoload directly. It emits `cell_changed` and forwards
  to `EventBus`. Domain systems subscribe to `EventBus`.

---

## Chunk-to-domain event forwarding

`HexChunk` is the only scene node connected to `HexWorldState.cell_changed`. It handles
visual refresh (its own responsibility) and then forwards semantic events to `EventBus`.

```
HexChunk._on_cell_changed(cell, hint):
    match hint:
        STRUCTURAL:
            refresh_objects()
            var state = HexWorldState.get_cell_ref(cell)
            if state.occupied:
                EventBus.cell_occupied.emit(cell, state.category)
            else:
                EventBus.cell_cleared.emit(cell)
        STAGE_CHANGE:
            refresh_plants()
            EventBus.cell_plant_stage_changed.emit(cell, HexWorldState.get_fresh_stage(cell))
        RESOURCE_CHANGE:
            _update_plant_shader_params(cell)
            EventBus.cell_plant_resources_changed.emit(cell)
        MARKER_CHANGE:
            _refresh_marker_overlay()
            # no EventBus emit needed; JobSystem already knows
```

---

## Save/load contract

Each stateful autoload implements:

```
func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

`SaveManager` calls these in dependency order (TimeService first, HexWorldState second,
etc.) and writes to a versioned save file. The save file contains:

- `TimeService` state (world_time, current_day, current_season)
- `HexWorldDeltaStore` deltas (compact diff from procedural baseline)
- `HiveSystem` state (all HiveState records)
- `TerritorySystem` state (only fade timers and partially-faded cells; full influence is
  recomputed from hive positions on load)
- `ColonyState` (known recipes, queen id, alliances)
- `JobSystem` (persistent markers only — transient jobs are re-derived on load)
- `PawnRegistry` pawn state (id, species, role, loyalty, inventory, cell position)

Terrain baseline is never saved (it's fully procedural from the seed). Only deltas are
saved. This keeps save files small regardless of world size explored.

---

## Data resource dependency rules

Resources reference other Resources freely. Resources never reference autoload state or
scene nodes. Example:

- `RecipeDef` references `Array[ItemDef]` — fine.
- `HiveDef` references `Array[HiveUpgradeDef]` — fine.
- `RecipeDef` calling `ColonyState.known_recipes` — wrong; that is runtime state.

---

## Folder structure

```
res://
  autoloads/
    event_bus.gd
    time_service.gd
    hex_world_state.gd
    hive_system.gd
    territory_system.gd
    colony_state.gd
    job_system.gd
    pawn_registry.gd
    save_manager.gd

  world/
    hex_terrain_manager.gd
    hex_chunk.gd
    hex_chunk_gen_cache.gd
    hex_world_baseline.gd
    hex_world_simulation.gd
    hex_world_delta_store.gd
    hex_mesh_lut.gd
    hex_consts.gd

  colony/
    hive/
      hive_state.gd
      hive_slot.gd
    territory/
      territory_system.gd        (also registered as autoload)
    colony_data.gd

  pawns/
    pawn_base.gd
    pawn_state.gd
    pawn_ai.gd
    possession_service.gd
    roles/
      role_forager.gd
      role_gardener.gd
      role_carpenter.gd
      role_soldier.gd
      role_queen.gd
    species/
      species_ant.gd
      species_beetle.gd

  jobs/
    job_data.gd
    job_system.gd               (also registered as autoload)
    marker_data.gd

  defs/
    items/
    recipes/
    plants/
    species/
    roles/
    abilities/
    hives/
    factions/
    threats/
    markers/
    biomes/

  scenes/
    world_root.tscn
    pawn_manager.tscn
    ui_root.tscn

  ui/
    hud/
    hive_overlay/
    pawn_switch_panel/
    compass/
    minimap/

  assets/
    meshes/
    textures/
    audio/
```

---

## Versioning and extensibility rules

- Every save file has a `version: int` field. `SaveManager` handles migration.
- Every `HexCellDelta` record has a `schema_version: int` field for forward compatibility.
- New cell categories can be added to the `CellCategory` enum without breaking existing
  saves because deltas store `object_id` strings, not category ints.
- New signals can be added to `EventBus` freely. Removing signals requires a migration
  pass across all subscribers.
- New autoloads should be added between existing ones in dependency order. Process order
  in Godot autoloads matches declaration order in Project Settings.

---

## What the existing architecture.md got wrong

The original `architecture.md` is superseded by this document. Key corrections:

- `WorldManager` is now split into `HexWorldState` (substrate) and domain autoloads
  (`HiveSystem`, `TerritorySystem`, `ColonyState`).
- `RenderManager` does not exist as a separate node. Rendering is handled by
  `HexTerrainManager` (chunks) and `PawnManager` (pawns). Per-plant rendering lives in
  `HexChunk`.
- `InputManager` is replaced by `PawnManager`/`PossessionService` routing input to the
  possessed pawn.
- `TimeService` and `SaveManager` were listed but are now fully specified.
- `JobSystem` was listed and is now specified with its relationship to MarkerSystem
  (markers are a subset of jobs, not a separate system).
- `HiveStructure` is renamed `HiveState` and lives in `HiveSystem`, not the scene tree.
- `TerritoryComponent` is replaced by `TerritorySystem` as a standalone autoload.
