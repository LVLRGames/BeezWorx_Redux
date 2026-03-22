# World Boundary Contract
## BeezWorx — Phase 0 State Ownership Document

This document defines which systems own which state.
**If you are about to write a field or method that doesn't fit its system's
charter below, stop. Either the field belongs in a different system, or a
new system needs to be created. Do not blur these boundaries.**

Last updated: Phase 0

---

## The Two State Domains

```
┌─────────────────────────────────────┐   ┌─────────────────────────────────────┐
│         WORLD LAYER                 │   │         COLONY LAYER                │
│         HexWorldState               │   │         ColonyState + subsystems    │
│                                     │   │                                     │
│  Owns the deterministic simulation  │   │  Owns everything the player's       │
│  of the physical world. Knows       │   │  actions produce. Knows nothing     │
│  nothing about bees, colonies,      │   │  about terrain noise, biomes,       │
│  economy, or diplomacy.             │   │  or baseline generation.            │
└─────────────────────────────────────┘   └─────────────────────────────────────┘
```

---

## HexWorldState — Owns

### Data
- `current_world_time: float` — the master simulation clock. All time in the
  game is expressed as seconds of world time. This is the only clock.
- `cfg: HexTerrainConfig` — terrain generation parameters.
- `registry: HexDefinitionRegistry` — all object/plant/tree definitions.
- `baseline: HexWorldBaseline` — procedural cell generation (read-only queries).
- `delta_store: HexWorldDeltaStore` — mutations that deviate from baseline.
- `simulation: HexWorldSimulation` — cell resolution combining baseline + deltas.
- `_cell_cache: Dictionary[Vector2i, HexCellState]` — hot query cache.

### What it knows about a cell
- Is the cell occupied, and by what definition (`object_id`, `HexGridObjectDef`).
- What `HexGridObjectDef.Category` the occupant is.
- For plants: stage, genes, thirst, pollen/nectar amounts, birth time.
- Whether a delta exists (player-placed, cleared, mutated).

### What it does NOT know
- Which colony owns this cell or any object in it.
- Whether a hive is built here.
- Pawn IDs, job IDs, marker IDs.
- Loyalty, morale, diplomacy values.
- Anything about the economy.

### Signals emitted
```gdscript
signal cell_changed(cell: Vector2i)
```
`cell_changed` is a low-level invalidation signal. It fires whenever a delta
is written. It does NOT carry a `CellChangeMutationHint` in the current
implementation — **Phase 1 task:** update signature to:
```gdscript
signal cell_changed(cell: Vector2i, hint: HexConsts.CellChangeMutationHint)
```
Until then, all listeners do a full re-query on any `cell_changed`.

### Write API (the only legal ways to mutate world state)
```gdscript
HexWorldState.set_cell(cell, object_id, overrides)    # place an object
HexWorldState.clear_cell(cell)                         # remove an object
HexWorldState.mutate_cell(cell, overrides)             # change plant state
HexWorldState.water_plant(cell)
HexWorldState.consume_pollen(cell, amount)
HexWorldState.consume_nectar(cell, amount)
HexWorldState.apply_pollen(source_cell, target_cell)
HexWorldState.set_plant_stage(cell, stage)
HexWorldState.attempt_cross_sprout(ca, cb, ga, gb)
```
**No other system may write directly to `delta_store` or `_cell_cache`.**

---

## ColonyState — Owns

### Data
- Colony identity, queen lineage, heir list, succession state.
- Known recipes, known plants, known items, discovered biomes.
- Loyalty cache per pawn.
- Morale value and active morale modifiers per colony.
- Faction relation scores and trade history.
- Colony influence score.

### HiveSystem — Owns
- All `HiveState` objects (slots, integrity, upgrades, territory radius).
- Which cell is a hive anchor (tracks `_hives_by_cell`).
- Inventory counts per hive slot.
- Egg states and craft orders in slots.
- Sleep slot reservations.

### TerritorySystem — Owns
- Which cells are in which colony's territory.
- Influence values per (cell, colony) pair.
- Active fade timers after hive destruction.
- Plant allegiance derived from territory overlap.

### JobSystem — Owns
- All `MarkerData` objects (queen-placed scent markers).
- All `JobData` objects (executable work items derived from markers).
- Trail networks.
- Job claim state (which pawn has claimed which job).

### PawnRegistry — Owns
- All `PawnState` objects (health, fatigue, loyalty, inventory, personality).
- Node references to live `PawnBase` instances.
- Cell → pawn index (which pawns are in which cells).

### TimeService — Owns
- Day/night cycle phase.
- Current day, season, year.
- Transition detection (day_changed, season_changed, etc.).
- **Does NOT own `world_time`.** It reads `HexWorldState.current_world_time`
  and derives calendar values from it. It does not advance the clock itself —
  `HexTerrainManager._process()` advances `HexWorldState.current_world_time`.

---

## The occupant_data Bridge

`HexCellState` carries a single nullable field:
```gdscript
var occupant_data: CellOccupantData = null
```

This is the only sanctioned crossing point between the two domains.

**Rules:**
1. The world layer **never reads** `occupant_data`. It only allocates the slot.
2. Colony systems write a typed subclass (`HiveAnchorOccupant`, `MarkerOccupant`,
   `PawnOccupant`) into this field via `HexWorldState.set_occupant_data()`.
   That method (Phase 1 task) writes the data and invalidates the cell cache.
3. `occupant_data` is a shallow reference. The owning colony system (e.g.
   `HiveSystem`) holds the canonical copy. `HexCellState` holds only a ref.
4. `occupant_data` is **not** serialised by `HexWorldDeltaStore`. Colony systems
   serialise their own data via `SaveManager`. On load, colony systems re-populate
   `occupant_data` refs after world state is restored.
5. `HexCellState.category` stays as the `HexGridObjectDef.Category` int for
   baseline/delta objects. For colony-placed objects (hives, markers), the
   category is set by the colony system when it calls `set_occupant_data()`.

---

## Legal Cross-Domain Calls

| Caller | May call | May NOT call |
|--------|----------|--------------|
| HiveSystem | `HexWorldState.get_cell()` (read) | `delta_store` directly |
| TerritorySystem | `HexWorldState.get_cell()` (read) | Anything on ColonyState |
| JobSystem | `HexWorldState.get_cell()` (read) | HiveSystem internals |
| PawnAI | `HexWorldState.get_cell()` (read) | `_cell_cache` directly |
| HexChunk | `HexWorldState.get_cell_ref()` | Any colony system |
| CombatSystem | `HexWorldState.get_cell()`, `HiveSystem.apply_damage()` | `delta_store` directly |
| SaveManager | `save_state()` on all systems | N/A |
| EventBus | (signal only — owns no state) | N/A |

---

## Signal Contract

All cross-system communication goes through `EventBus` signals.
Direct method calls between colony subsystems are permitted only within
the colony layer (e.g. `HiveSystem` calling `TerritorySystem` is fine;
`HexChunk` calling `HiveSystem` is not).

**World → Colony (HexWorldState emits, colony systems listen):**
```
cell_changed(cell, hint)   →   HiveSystem, TerritorySystem, PawnRegistry
```

**Colony → World (colony systems call HexWorldState write API directly):**
```
HiveSystem          → HexWorldState.set_cell() when placing hive anchor mesh
TerritorySystem     → HexWorldState.set_cell() when placing territory marker object
PawnRegistry        → (no world writes — pawns are scene nodes, not cell occupants
                        except via occupant_data)
```

**Colony → Colony (via EventBus):**
```
EventBus.hive_built         → TerritorySystem, ColonyState
EventBus.hive_destroyed     → TerritorySystem, ColonyState, JobSystem
EventBus.pawn_died          → ColonyState, HiveSystem (release sleep slot)
EventBus.marker_placed      → JobSystem (generate jobs from marker def)
EventBus.territory_faded    → ColonyState (morale penalty), PawnAI (re-evaluate loyalty)
```

---

## What This Prevents

Without this contract, the failure modes are:

- **HexChunk imports HiveSystem** — chunk generation runs on a worker thread;
  HiveSystem is main-thread only. Deadlock.
- **HexWorldState stores colony_id per cell** — world deltas would serialize
  colony ownership, making save files colony-dependent and breaking determinism.
- **TerritorySystem calls HexWorldBaseline** — territory logic would re-run
  procedural generation, coupling fade timers to noise values.
- **PawnAI writes delta_store directly** — bypasses cache invalidation,
  produces stale HexCellState reads in other systems.

---

*This document is updated before any code change that affects system boundaries.*
*If a planned feature requires crossing a boundary not listed here, update this*
*document first and get a second opinion before writing the code.*
