# BeezWorx Architecture

> This document is a summary reference. The full authoritative spec is in
> `architecture_spec.md` (outputs folder). When they conflict, the full spec wins.

---

## 1. Scene Organisation

```
WorldRoot
├── HexTerrainManager     — chunk streaming, mesh generation, advances TimeService
├── PawnManager           — spawns/despawns pawn nodes, routes possession input
│   └── PossessionService — tracks which player slot controls which pawn
├── RivalColonySimulator  — AI colony simulation (near = full, far = abstract)
├── ThreatDirector        — schedules and spawns threat raids
├── ItemGemManager        — world-dropped item node pooling
├── FogOfWarSystem        — revealed cell tracking
└── UIRoot                — all HUD, overlays, and management screens
```

---

## 2. Global Autoloads (Singletons)

Loaded in dependency order:

- `EventBus` — typed signal hub; no state
- `TimeService` — world_time, day/night phase, seasons
- `HexWorldState` — terrain substrate, cell occupancy, baseline/delta/simulation
- `HiveSystem` — hive state, slot contents, hive integrity, colony inventory queries
- `TerritorySystem` — per-cell influence fields, fade timers, plant allegiance
- `ColonyState` — queen identity/history, heirs, known recipes, loyalty, faction relations
- `JobSystem` — markers (as placed physical items), trails, jobs, task planning
- `PawnRegistry` — lightweight index of all live pawns by id and cell
- `SaveManager` — orchestrates save/load across all systems

---

## 3. Data Models (Resources)

All static definitions are authored as `.tres` files:

- `HexTerrainConfig` — all terrain generation parameters and noise layers
- `ItemDef` — item identity, chemistry channels, stack size, tags, nursing role
- `RecipeDef` — inputs, outputs, craft time, role requirements, channel output map
- `RoleDef` — pawn role identity, utility behaviors, harvest restrictions
- `SpeciesDef` — base stats, lifespan, reveal radius, possession boost values
- `AbilityDef` — action/alt-action definition, targeting mode, range, effects
- `HiveDef` — base slot count, upgrade definitions
- `FactionDef` — faction identity, hidden preference channels, service type
- `MarkerDef` — marker category (JOB/NAV/INFO), placement rules, job templates
- `ThreatDef` — threat type, spawn conditions, scaling, appeasement faction
- `HexBiome` — terrain parameters, grass settings, biome discovery reward
- `PlantDef` / `HexPlantDef` — lifecycle data, base genes, plant category
- `TimeConfig` — day length, days per season, day/night split

---

## 4. Entity Hierarchy

### Pawns (CharacterBody3D)

Composition pattern. Each pawn has:
- `PawnState` (RefCounted) — canonical runtime data; owned by pawn node, referenced by PawnRegistry
- `PawnAI` (Node child) — utility AI + job polling; disabled when player-possessed
- `PawnAbilityExecutor` (Node child) — shared execution engine for action/alt-action
- `InteractionDetector` (Area3D child) — detects nearby interactable targets
- `DialogueDetector` (Area3D child) — detects nearby pawns for ambient dialogue

Two movement types: `GROUND` (CharacterBody3D with gravity) and `FLYING` (gravity disabled).

### Hives

`HiveState` (RefCounted) owned by `HiveSystem`. Not a scene node — data only.
Contains slot array (`Array[HiveSlot]`), integrity, upgrades, territory radius.
Scene representation is the hive interior UI overlay, not a persistent 3D node.

### Active Plants

Individual scene nodes (not multimesh) instantiated per `DEFENSIVE_ACTIVE` cell.
Pooled at `HexTerrainManager` level. Not pawns — no PawnRegistry entry, no AI, no possession.

---

## 5. Cell Occupancy Contract

```
enum CellCategory {
    EMPTY, RESOURCE_PLANT, TREE, DEFENSIVE_ACTIVE,
    HIVE_ANCHOR, TRAVERSABLE_STRUCTURE, RESOURCE_NODE,
    TERRITORY_MARKER, PAWN_SPAWN
}
```

Coexistence rules (per cell):
- RESOURCE_PLANT: up to 6, coexists with TREE/HIVE_ANCHOR/TERRITORY_MARKER
- TREE: 1, becomes HIVE_ANCHOR when hive is built on it (tree data preserved)
- DEFENSIVE_ACTIVE: 1, coexists with RESOURCE_PLANT
- HIVE_ANCHOR: 1, coexists with RESOURCE_PLANT
- All others: 1, coexist only with TERRITORY_MARKER
- Pawns: not cell occupants; tracked by PawnRegistry position, not cell state

---

## 6. Event Architecture

All cross-system communication through `EventBus` typed signals. No direct node
references between unrelated systems. No scene node holds canonical simulation state.

Key architectural rules:
- Autoloads own simulation state; scene nodes own presentation and input
- `HexWorldState` is a substrate — it does not call domain autoloads
- `HexChunk` is the only node subscribed to `HexWorldState.cell_changed`; it forwards
  semantic events onward to `EventBus` for domain systems
- `cell_changed` carries a `CellChangeMutationHint` enum so chunks select the correct
  refresh path (STRUCTURAL / STAGE_CHANGE / RESOURCE_CHANGE / MARKER_CHANGE)

---

## 7. Marker System Note

Markers are **not** a separate system. They are part of `JobSystem`. Markers are
physical craftable items placed in the world by the queen. Three categories exist:
JOB markers (generate worker jobs), NAV markers (ant conveyors, patrol routes —
modify navigation weights), and INFO markers (world labels). All share the same
`MarkerDef` / `MarkerData` pipeline.
