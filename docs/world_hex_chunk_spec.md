# BeezWorx MVP Spec: World / Hex Grid / Chunk Streaming System

This document specifies the world representation, hex coordinate system, chunk streaming
architecture, and cell state model for BeezWorx. It is grounded in the existing codebase
and is intended to be the authoritative reference for all systems that read or write world
state. Implementation details are described precisely enough for an AI coder to produce
correct GDScript without additional context.

---

## Purpose and scope

The world system is the shared substrate that all other systems depend on. It must
provide a consistent, deterministic, thread-safe view of every hex cell's occupant and
environmental properties. It must stream an infinite procedural world efficiently by only
simulating and rendering chunks near the player. It must support persistent player-driven
modifications on top of a purely deterministic baseline so that saves are compact.

This spec covers the following responsibilities:

- Hex coordinate math and constants
- Chunk streaming (load, unload, prioritisation)
- Per-cell state resolution (baseline → delta → final state)
- Cell mutation API (place, clear, mutate, consume)
- Cross-chunk plant propagation
- Editor preview support
- Performance and threading rules

It does **not** cover territory, hive placement, pawn pathfinding, or plant simulation
ticking. Those systems read from this system but are specced separately.

---

## Coordinate system

All world positions use **axial hex coordinates** stored as `Vector2i(q, r)`.

The flat-top hex layout is used. Converting between axial and world (3D) space:

```
world.x = HEX_SIZE * SQRT3 * (q + r / 2.0)
world.z = HEX_SIZE * 1.5 * r
```

**Constants** — all live in `HexConsts` (autoload or static class):

| Constant | Value | Notes |
|---|---|---|
| `HEX_SIZE` | 1.0 | Circumradius in world units |
| `SQRT3` | 1.7320508... | Precomputed |
| `CHUNK_SIZE` | 8 | Cells per chunk edge (tunable via config) |
| `MAX_HEIGHT` | configurable | Used to normalise height for biome selection |
| `HEIGHT_STEP` | configurable | Discrete height snap unit |
| `TERRAIN_TILE_U` | configurable | UV atlas column width |
| `TERRAIN_TILE_V` | configurable | UV atlas row height |

The six axial neighbour directions are:

```
(+1, 0), (0, +1), (-1, +1), (-1, 0), (0, -1), (+1, -1)
```

**Chunk coordinate** — a `Vector2i(cx, cz)` where:

```
cx = floor(q / CHUNK_SIZE)
cz = floor(r / CHUNK_SIZE)
```

Converting world position to chunk coordinate (as used in `HexTerrainManager`):

```
q_frac = (SQRT3/3 * pos.x - 1/3 * pos.z) / HEX_SIZE
r_frac = (2/3 * pos.z) / HEX_SIZE
cx = floor(round(q_frac) / CHUNK_SIZE)
cz = floor(round(r_frac) / CHUNK_SIZE)
```

---

## System map

```
HexTerrainManager          — Node3D, orchestrates chunk lifecycle
HexWorldState              — Autoload singleton, primary public API
  HexTerrainConfig         — Resource, all generation parameters and noise layers
  HexDefinitionRegistry    — RefCounted, biome + object definition lookup tables
  HexWorldBaseline         — RefCounted, deterministic procedural cell resolution
  HexWorldDeltaStore       — RefCounted, persistent player-driven overrides
  HexWorldSimulation       — RefCounted, merges baseline + delta into HexCellState

HexChunk                   — Node3D, one loaded chunk (mesh, multimeshes, plant state)
HexChunkGenCache           — RefCounted, per-chunk generation scratch data (thread-local)
HexCellState               — RefCounted, resolved state for one cell (read-only output)
HexCellDelta               — Resource, one stored override record
HexPlantGenes              — Resource, per-plant genetic profile
```

---

## HexWorldState (autoload singleton)

`HexWorldState` is the only entry point that other systems should call. Direct access to
`HexWorldBaseline`, `HexWorldDeltaStore`, or `HexWorldSimulation` from outside this file
is a code smell.

### Initialisation

```
HexWorldState.initialize(config: HexTerrainConfig) -> void
```

Must be called once before any other method. Calling it a second time (e.g. in editor
preview) fully resets all internal state. Steps:

1. Store `cfg` reference.
2. Call `cfg.apply_seed()` to re-seed all noise layers deterministically.
3. Build `HexDefinitionRegistry` from `cfg.biome_definitions` and `cfg.object_definitions`.
4. Construct `HexWorldBaseline` and call `baseline.setup(cfg, registry)`.
5. Construct a fresh `HexWorldDeltaStore`.
6. Construct `HexWorldSimulation` and call `simulation.setup(cfg, registry, baseline, delta_store)`.
7. Clear `_cell_cache`.
8. Call `load_deltas()` to restore any saved player modifications.

### Cell cache

`HexWorldState` maintains a `Dictionary[Vector2i, HexCellState]` cache protected by a
`Mutex`. The cache holds resolved states so that repeated reads of the same cell during
one frame are cheap.

Cache invalidation rules:

- `invalidate_cell(cell)` — erases one entry. Called after every `_write_delta`.
- `invalidate_cells(cells: Array[Vector2i])` — batch erasure. Called by chunk
  load/unload.
- `clear_cache()` — full wipe. Used during re-initialisation.

The cache is **never** written to from background threads. Only `get_cell_ref` writes
to it from the main thread after acquiring the mutex.

### Public read API

```
get_cell(cell, world_time?) -> HexCellState      # returns a deep copy
get_cell_ref(cell, world_time?) -> HexCellState  # returns the cached instance (read-only)
get_baseline_cell(cell, world_time?) -> HexCellState
get_fresh_stage(cell) -> int
has_delta(cell) -> bool
get_delta(cell) -> HexCellDelta
```

`get_cell` is safe to hold across frames. `get_cell_ref` is faster but callers must not
mutate the returned object.

`world_time` defaults to `current_world_time` when omitted.

### Public mutation API

All mutations go through `_write_delta` → `delta_store.set_delta` → `invalidate_cell` →
`cell_changed.emit`. No system should bypass this path.

| Method | Purpose |
|---|---|
| `set_cell(cell, object_id, overrides?)` | Place an object (plant, hive anchor, etc.) |
| `clear_cell(cell)` | Remove object; writes a CLEARED delta |
| `mutate_cell(cell, overrides)` | Patch fields on an existing delta |
| `water_plant(cell)` | Sets `last_watered`, reverts WILT if applicable |
| `consume_pollen(cell, amount)` | Decrements pollen; triggers `cell_changed` |
| `consume_nectar(cell, amount)` | Decrements nectar; advances to IDLE if exhausted |
| `apply_pollen(source, target)` | Records pollination source on target cell |
| `set_plant_stage(cell, stage)` | Force stage override (e.g. for debug or event) |
| `attempt_cross_sprout(ca, cb, ga, gb)` | Tries to spawn a hybrid sprout near cb |

`attempt_cross_sprout` is the entry point for the plant breeding loop. It validates
species group compatibility, finds a free neighbour cell within `gb.pollen_radius`, looks
up authored cross definitions, and either places a known hybrid or a `wild_plant` with
blended genes.

### Signals

```
signal cell_changed(cell: Vector2i)
```

Emitted after every `_write_delta` call. `HexChunk` subscribes to this to trigger
`_on_cell_changed`, which refreshes the affected cell's visual representation.

### Chunk lifecycle hooks

```
on_chunk_loaded(chunk_coord, chunk_size, cached_states?)
on_chunk_unloaded(chunk_coord, chunk_size)
```

These invalidate the cache for all cells in the chunk and update occupancy tracking in
`delta_store` so multi-cell footprints remain consistent across chunk boundaries.

### Time

```
current_world_time: float  # advances in _process via HexTerrainManager.world_time_scale
```

`_process` also pushes `engine_time` to the global shader parameter each frame.

### Persistence

```
save_deltas() -> void   # writes delta_store to "user://world_deltas.dat"
load_deltas() -> void   # reads on initialise; errors are non-fatal
```

---

## HexTerrainConfig (Resource)

A single `.tres` file that owns every generation knob. One instance is assigned to
`HexTerrainManager` and passed into `HexWorldState.initialize`. Changing `world_seed`
automatically re-seeds all noise layers via the `set` property hook.

### Key field groups

**Seed**
- `world_seed: int` — changing this re-seeds every noise layer deterministically.

**Noise layers** (each a `FastNoiseLite`):
- `height_noise` — vertex Y positions
- `continental_noise` — large-scale land mass shape
- `mountain_mask_noise` — which regions have peaks
- `placement_noise` — per-cell object spawn probability
- `type_noise` — which object from the spawn table
- `forest_cluster_noise` — tree clustering boost
- `age_noise` — lifecycle stagger offset per cell
- `moisture_noise`, `temperature_noise` — climate
- `grass_density_noise`, `grass_stage_noise` — grass distribution

**Terrain shaping**
- `sea_level`, `beach_bottom_steps`, `beach_top_steps`
- `continental_curve: Curve` — remaps continentalness to height multiplier
- `mountain_curve: Curve` — shapes mountain mask
- `mountain_max_height: float`

**Biome and object registries**
- `biome_definitions: Array[HexBiome]`
- `object_definitions: Array[HexGridObjectDef]`
- `authored_crosses: Dictionary[StringName, HexPlantDef]`

**Grass**
- `grass_mesh: Mesh`
- `grass_density_threshold: float`
- `max_grass_per_hex: int`

### Key methods

```
apply_seed() -> void            # re-seeds all noise layers
ensure_defaults() -> void       # fills null noise slots with reasonable defaults
get_height(wx, wz) -> float
get_biome(wx, wz) -> StringName
get_cell_biome(q, r) -> StringName
get_temperature(wx, wz) -> float
get_moisture(wx, wz) -> float
get_terrain_context(wx, wz) -> Dictionary  # single-pass: height, biome, region, cntl
```

`get_terrain_context` is the preferred method when multiple values are needed for the
same cell; it avoids redundant noise sampling.

---

## HexDefinitionRegistry (RefCounted)

Built once during `initialize`. Never modified at runtime.

### Responsibilities

- Indexes all `HexGridObjectDef` (and subclass `HexTreeDef`, `HexPlantDef`) by `id`.
- Builds per-biome spawn tables and tree tables from `valid_biomes` on each def.
- Ensures `wild_plant` exists (creates a minimal default if absent).
- Canonicalises authored cross keys: `canonical_key(a, b)` = lexicographic order joined
  by `"::"`.
- Computes generation padding (maximum `exclusion_radius + footprint_radius` across all
  defs) for `HexChunkGenCache`.

### Key methods

```
get_definition(id) -> HexGridObjectDef
get_spawn_table(biome) -> Array
get_tree_table(biome) -> Array
get_authored_cross(key) -> HexPlantDef
static canonical_key(a, b) -> String
```

---

## HexWorldBaseline (RefCounted)

Computes the fully deterministic "what would be here if the player had never touched it"
state for any cell. Stateless after `setup` — all inputs come from `cfg` and
`registry`. Thread-safe (reads only).

### Placement pipeline

For a given cell, baseline object selection follows this priority order:

1. **Tree candidate**: `pick_tree_def_for_cell` selects a species weighted by climate
   affinity and `species_weight`. Placement is accepted only if `placement_noise` exceeds
   `placement_threshold`, the footprint fits (no higher-noise neighbour in footprint),
   and `tree_candidate_wins` (no competing tree with higher score in exclusion radius).

2. **Object candidate**: falls through to the biome spawn table, selects by `type_noise`
   index, then applies `placement_threshold` and footprint/exclusion checks.

3. **Empty**: returns an unoccupied `HexCellState`.

Tree score formula:

```
score = placement_noise01(cell)
      + forest_cluster_noise01(cell) * 0.15 * def.forest_cluster_affinity
      + (def.giant_priority_bonus if def.is_giant else 0)
      + jitter01(cell, 913)   # tiny tie-breaker
```

### Plant state derivation

For baseline plants, genes and birth time are derived deterministically from noise:

- `baseline_genes(cell, def)` — perturbs `def.genes` using `age_noise`.
- `derive_birth(cell, pd, cycle_speed)` — offsets birth so plants are in varied lifecycle
  stages on world load (target stage is selected from noise, then elapsed time is
  back-calculated to place the plant mid-stage).
- `derive_cycles_done(pd, speed, birth, world_time)` — counts completed fruit cycles.

### Hex utilities (static)

```
static hex_ring(center, radius) -> Array[Vector2i]
static hex_disk(center, radius) -> Array[Vector2i]
```

---

## HexWorldDeltaStore (RefCounted)

Stores player-driven cell overrides as `HexCellDelta` records. Handles occupancy tracking
for multi-cell footprints.

### Delta types

```
enum DeltaType {
    PLANTED,         # player or event placed an object
    SPROUT_SPAWNED,  # breeding system spawned a new plant
    STATE_MUTATED,   # partial override (watering, stage change, etc.)
    CLEARED          # object was explicitly removed
}
```

### Occupancy tracking

For objects with multi-cell footprints, the store records which origin cell owns each
satellite cell. `get_origin_for_cell(cell)` returns the origin (defaults to `cell` if
not tracked). This is used by `HexWorldSimulation.get_cell` to fill satellite cells with
a copy of the origin cell's state.

Occupancy is re-registered on `on_chunk_loaded` and cleared on `on_chunk_unloaded` to
prevent stale entries from unloaded chunks interfering with new chunks.

### Key methods

```
set_delta(cell, delta) -> void
get_delta(cell) -> HexCellDelta
has_delta(cell) -> bool
get_origin_for_cell(cell) -> Vector2i
set_occupancy(cell, footprint: Array[Vector2i]) -> void
clear_occupancy_in_chunk(chunk_coord, chunk_size) -> void
save(path) -> bool
load(path) -> bool
```

---

## HexWorldSimulation (RefCounted)

Merges baseline and delta to produce the final resolved `HexCellState` for any cell.

### Resolution order

1. Check occupancy: if `cell` is a satellite of another origin, resolve the origin and
   return a copy.
2. Retrieve delta. If `CLEARED`, return empty state.
3. If no delta, delegate to `baseline.get_baseline_cell`.
4. Determine `object_id`: delta's `object_id` if set, else baseline fallback.
5. Fetch `HexGridObjectDef` from registry.
6. For non-plant objects, return state with `occupied = true`.
7. For plants, resolve: genes, birth time, cycles done, stage, wilt rule, thirst, pollen,
   nectar.

### Plant resolution detail

**Genes**: delta `hybrid_genes` if present; otherwise `baseline_genes` perturbed by age
noise.

**Birth**: if delta type is `PLANTED` or `SPROUT_SPAWNED`, use `delta.timestamp`. If
`STATE_MUTATED`, re-derive from baseline (preserves continuity after partial mutations).

**Stage**: `delta.stage_override` takes precedence. Otherwise `pd.compute_stage(birth,
world_time, cycle_speed, cycles_done)`.

**Wilt rule**: if `pd.wilt_without_water` is true and time since last watering exceeds
`pd.effective_water_duration(drought_resist)`, override stage to `WILT`. Only applied
when a watering record exists (PLANTED, SPROUT_SPAWNED, or explicit `last_watered`).

**Pollen/nectar**: use delta overrides if present; otherwise compute from plant data and
genes. If `nectar_remaining` is exhausted (≤ 0) and stage is FRUITING, stage advances to
IDLE at next resolution.

---

## HexCellState (RefCounted)

Read-only output object. Produced by `HexWorldSimulation` and cached in `HexWorldState`.

### Fields

| Field | Type | Notes |
|---|---|---|
| `occupied` | bool | false = empty cell |
| `origin` | Vector2i | canonical cell for multi-cell objects |
| `object_id` | String | matches a registry definition id |
| `definition` | HexGridObjectDef | direct def reference |
| `category` | int | enum from HexGridObjectDef.Category |
| `source` | StringName | `"baseline"` or `"delta"` |
| `stage` | int | lifecycle stage enum (see plant lifecycle spec) |
| `genes` | HexPlantGenes | null for non-plants |
| `thirst` | float | 0.0–1.0; drives desaturation shader |
| `has_pollen` | bool | true only during FLOWERING stage |
| `pollen_amount` | float | current pollen remaining |
| `nectar_amount` | float | current nectar remaining |
| `fruit_cycles_done` | int | completed fruiting cycles |
| `birth_time` | float | world_time when plant first appeared |

`duplicate_state()` returns a deep copy safe to hold across frames.

Dead plants (`stage == DEAD`) set `occupied = false` so the cell appears empty to other
systems without requiring a CLEARED delta.

---

## HexCellDelta (Resource)

One override record per cell. Serialised to disk for persistence.

### Fields

| Field | Type | Default | Notes |
|---|---|---|---|
| `delta_type` | DeltaType | — | Required |
| `object_id` | String | `""` | Non-empty for PLANTED/SPROUT_SPAWNED |
| `timestamp` | float | 0.0 | world_time at creation |
| `stage_override` | int | -1 | -1 = not overridden |
| `last_watered` | float | -1.0 | -1 = never explicitly watered |
| `hybrid_genes` | HexPlantGenes | null | non-null for hybrid sprouts |
| `parent_a_cell` | Vector2i | — | lineage tracking |
| `parent_b_cell` | Vector2i | — | lineage tracking |
| `fruit_cycles_done` | int | -1 | -1 = derive from baseline |
| `pollen_remaining` | float | -1.0 | -1 = use computed value |
| `nectar_remaining` | float | -1.0 | -1 = use computed value |
| `pollinated_by` | Vector2i | — | source cell for cross-pollination |
| `pollen_source_id` | String | `""` | fallback if source cell unavailable |

---

## HexChunkGenCache (RefCounted)

Built once per chunk on the worker thread before generation begins. Stores all
noise-sampled values for the chunk region (including padding cells needed for exclusion
radius checks) so that noise is sampled once and reused across all generation passes.

### Build inputs

- `cfg`, `registry`, `chunk_coord`, `chunk_size`
- Padding computed from `registry.get_generation_padding()` (covers the widest exclusion
  radius + footprint in any definition)

### Cached per cell (in padded region)

- `biomes: Dictionary[Vector2i, StringName]`
- `placements: Dictionary[Vector2i, float]` — 0..1 from placement noise
- `types: Dictionary[Vector2i, float]` — 0..1 from type noise
- `forest_clusters: Dictionary[Vector2i, float]`
- `temperatures: Dictionary[Vector2i, float]`
- `moistures: Dictionary[Vector2i, float]`
- `tree_candidates: Dictionary[Vector2i, HexTreeDef]` — selected tree species per cell
- `object_candidates: Dictionary[Vector2i, HexGridObjectDef]` — selected non-tree object

### Usage rule

All baseline and chunk generation code should call through the cache when the cell falls
within the cached region. For cells outside the cache (e.g. exclusion checks that reach
beyond the padded region), fall back to direct noise sampling. The cache accessors handle
this transparently.

---

## HexChunk (Node3D)

Owns one chunk's visual representation and plant simulation state.

### Mesh generation pipeline

`generate_all_data()` runs on a worker thread:

1. `_precompute_heights()` — fills `_height_cache[_HC_STRIDE * _HC_STRIDE]` including
   one-cell border for skirt geometry.
2. `_precompute_ramps()` — for each cell, determines which edges have lower neighbours
   and which qualify as single-step ramps (a ramp replaces the skirt with a sloped face).
3. `_generate_terrain_mesh()` — emits hex faces and skirt geometry via `SurfaceTool`.
   Uses `HexMeshLUT` to resolve triangle indices from skirt mask and ramp edge.
4. `_generate_grass()` — builds a `MultiMesh` for grass billboards; density and stage
   driven by biome definition and noise.
5. `_generate_objects()` — builds `MultiMesh` instances for trees and static objects,
   two `MultiMesh` instances for plants (sprout mesh and bush mesh), and a map of active
   plant scenes. Populates `_cell_states` and `_next_transition` caches.

`finalize_chunk(shape?)` runs on the main thread after generation:

- Adds `MeshInstance3D` for terrain.
- Adds `MultiMeshInstance3D` nodes for grass, sprouts, bushes, and static objects.
- Instantiates active-plant scenes.
- Adds terrain `StaticBody3D` with prebuilt or freshly computed trimesh shape.
- Conditionally adds tree collision bodies (within `COLLISION_RADIUS` of player).

### Plant simulation

`_check_stale_plants()` runs at most once per `CHECK_INTERVAL` seconds and only when
within `CHECK_RADIUS` chunks of the player:

1. On first check after chunk load, recompute all `_next_transition` times.
2. On subsequent checks, collect all cells where `_next_transition[cell] <= now`.
3. For each stale cell, mark it in `_pending_bounces` and add to `changed_cells`.
4. Invalidate stale cells in `HexWorldState`.
5. Call `refresh_plants()` to rebuild the sprout/bush multimeshes.
6. Clear pending bounces.
7. Recompute `_next_transition` for all changed cells.

`_next_transition` stores the `world_time` at which the current lifecycle stage will
end. It is computed from `_compute_next_transition` which reads `pd.stage_durations[stage]
/ cycle_speed`.

### Plant visual update entry points

| Method | When called |
|---|---|
| `refresh_plants()` | Stage transition; rebuilds sprout/bush MMs only |
| `refresh_objects()` | Full object change (new tree, new active plant scene) |
| `_on_cell_changed(cell)` | Signal handler — calls `refresh_objects()` then clears bounces |
| `trigger_plant_bounce(cell)` | Writes a time value into custom_data.a; shader animates |

### Cell state cache

`_cell_states: Dictionary[Vector2i, HexCellState]` — populated during `_generate_objects`
and kept up to date by `refresh_plants` and `refresh_objects`. Used by `_check_stale_plants`
to compute next transition without re-calling `HexWorldState.get_cell_ref`.

### Tree collision

Added/removed dynamically as the player moves. Within `COLLISION_RADIUS` chunks:
`_add_tree_collision()` instantiates `StaticBody3D` + `CollisionShape3D` for every tree
instance in the chunk's object multimeshes using the shape from `HexTreeDef` or its
selected `HexTreeVariant`. Marked with meta `"tree_collision"` for cleanup.

---

## HexTerrainManager (Node3D)

Thin orchestrator. Owns the loaded chunk dictionary and manages spawn/despawn queues.

### Key state

```
_loaded: Dictionary[Vector2i, HexChunk]
_spawn_queue: Array[Vector2i]      # sorted nearest-first
_despawn_queue: Array[Vector2i]
_finalize_queue: Array[Array]      # [[chunk, shape], ...]
_deferred_free_queue: Array[HexChunk]  # chunks mid-generation when despawned
_active_jobs: int                  # background threads currently running
```

### _process loop

Each frame (runtime only):

1. Finalise one chunk from `_finalize_queue` (add as child, call `finalize_chunk`,
   connect `cell_changed` signal, notify `HexWorldState.on_chunk_loaded`).
2. Spawn up to `MAX_SPAWNS_PER_FRAME` (2) chunks from `_spawn_queue`.
3. Despawn up to `MAX_DESPAWNS_PER_FRAME` (3) chunks from `_despawn_queue`.
4. Check if player moved to a new chunk; if so, call `_update_chunks`.
5. Free any completed deferred-free chunks.

`MAX_CONCURRENT` (2) background generation jobs are allowed simultaneously. New jobs are
flushed from `_queue` by `_flush_queue` whenever a job completes.

### Spawn / despawn

On spawn: create `HexChunk`, set `terrain_manager`, add to `_loaded`, push to `_queue`,
call `_flush_queue`.

On despawn: erase from `_loaded`, remove from pending queues, disconnect `cell_changed`,
call `HexWorldState.on_chunk_unloaded`. If chunk is still generating, push to
`_deferred_free_queue`; otherwise `queue_free` immediately.

### _update_chunks

Computes the set of chunk coords within a hex-shaped `view_radius_chunks` ring. Adds
missing coords to `_spawn_queue` and coords no longer in range to `_despawn_queue`.
Spawn queue is sorted by Manhattan distance from current chunk centre (nearest first).

### Editor mode

`_editor_rebuild()` is the single editor entry point. It runs the full
`initialize → clear → update` cycle synchronously in the editor (no threads). Chunks are
generated and finalised immediately. Triggered by changes to the `config` export or by
the Generate tool button (currently commented out in favour of property-change trigger).

---

## HexPlantGenes (Resource)

Per-plant genetic data. Stored on deltas for hybrid plants; derived from `HexPlantDef.genes`
with noise perturbation for baseline plants.

### Key fields used by world system

| Field | Type | Notes |
|---|---|---|
| `cycle_speed` | float | Multiplier on all stage durations |
| `drought_resist` | float | Extends effective water duration |
| `pollen_yield_mult` | float | Multiplier on pollen output |
| `nectar_yield_mult` | float | Multiplier on nectar output |
| `pollen_radius` | int | Max cell distance for sprout from cross-pollination |
| `species_group` | StringName | Cross-pollination compatibility group |

Full genetics spec (all additive channels, categorical loci, variant rules, inheritance
model) is in `plant_genetics_spec.md` and `plant_variant_rules.md`.

### Key methods

```
perturbed(noise_val: float) -> HexPlantGenes  # returns a copy with minor noise-driven variation
static blend(a, b) -> HexPlantGenes           # used by attempt_cross_sprout for wild hybrids
pack_variants(stage) -> float                 # packs variant + stage into a float for shader
pack_flower_colors() -> float                 # packs flower colour channels for shader
pack_foliage_colors() -> float                # packs foliage colour channels for shader
```

---

## HexMeshLUT (RefCounted)

Precomputes terrain triangle index tables indexed by (skirt_mask, ramp_edge). Constructed
once per `HexTerrainManager` instance and shared across all chunks via `HexChunk._lut`.

Not specced further here; it is purely a mesh generation utility.

---

## Performance rules

- All noise sampling happens in `HexChunkGenCache.build` on the worker thread. No noise
  sampling on the main thread except for `get_terrain_context` calls from editor code.
- `HexWorldState.get_cell_ref` locks the mutex only long enough to check/write the cache.
  Simulation is done before the lock. Do not call `get_cell_ref` from worker threads.
- `_check_stale_plants` budget: logged if it exceeds 500 µs. It should rebuild only the
  plant multimeshes (`refresh_plants`), not full objects, unless an active plant scene
  changed.
- `_cell_states` on HexChunk is the chunk's local read-through cache. Prefer it over
  calling `HexWorldState.get_cell_ref` in tight loops within the chunk.
- Tree collision bodies are added/removed lazily (only within `COLLISION_RADIUS`) to
  avoid excessive `StaticBody3D` counts.
- Grass and static object multimeshes are built once at chunk generation. They are not
  updated per-tick. If a tree is felled or a new hive is placed, `refresh_objects` must
  be called.

---

## Threading rules

| Operation | Thread |
|---|---|
| `HexChunkGenCache.build` | Worker (WorkerThreadPool) |
| `HexChunk.generate_all_data` | Worker |
| `HexChunk.finalize_chunk` | Main (deferred) |
| `HexWorldState.get_cell_ref` | Main only |
| `HexWorldState._write_delta` | Main only |
| `HexWorldState.cell_changed` signal | Main only |
| `HexWorldDeltaStore.get_delta` | Main only (no lock needed; store is main-thread only) |
| `HexWorldBaseline` reads | Worker-safe (read-only after setup) |
| `HexTerrainConfig` reads | Worker-safe (read-only after apply_seed) |

---

## Extension points for future systems

The following hooks are already present or implied and will be used by later specs:

- `HexCellState.category` — used by Pawn system to determine valid interactions.
- `HexWorldState.set_cell` with `category = HIVE_ANCHOR` — how the Hive system
  registers a built hive onto the world.
- `HexCellDelta` fields `parent_a_cell`, `parent_b_cell` — lineage tracking for
  genetics system.
- `cell_changed` signal — listened to by: `HexChunk` (visual refresh), `TerritorySystem`
  (hive placement/removal), future systems as needed.
- `HexWorldState.current_world_time` — the single authoritative time source for all
  simulation systems.
- `HexGridObjectDef.Category` enum — add `HIVE_STRUCTURE`, `PAWN_SPAWN`, `TERRITORY_MARKER`
  as new categories when those systems are implemented.

---

## MVP scope notes

The following are explicitly out of scope for this system at MVP:

- Ocean floor / underwater cell traversal
- Per-cell territory influence fields (territory system is separate)
- Weather simulation modifying cell state
- Saving individual pawn positions in world state (pawn system owns that)
- Chunk-level LOD simulation for far colonies (full simulation is local to loaded chunks
  only; distant colonies are abstracted by the faction system)
