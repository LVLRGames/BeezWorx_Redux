# BeezWorx

> *An organic colony automation game where you are the queen bee.*

BeezWorx is a colony-building simulation game built in Godot 4.6. You begin as a queen
bee managing a small hive and grow it into an expanding biological empire — not through
machines and conveyor belts, but through relationships, ecology, and living systems.
Bees gather, craft, and trade. Ants carry logistics. Bears protect hives. Plants defend
territory. Everything is alive and everything is connected.

---

## Core concept

Instead of building a factory, you build an ecosystem. The economic engine is:

**Bees → Honey → Trade → Services → Automation → Expansion**

You direct the colony by placing pheromone command markers crafted from wax and nectar.
Workers respond autonomously. You can also switch to direct control of any colony
member — or any allied creature — and play out their role yourself.

---

## Current status

**Pre-implementation — spec complete.**

All 17 MVP systems are fully specified. Implementation begins at Phase 0 (terrain
migration). See `docs/implementation_roadmap.md` for the full build order.

---

## Engine and platform

- **Engine:** Godot 4.6
- **Language:** GDScript (strongly typed)
- **Platform target:** PC (Windows / Linux / Mac)
- **Architecture:** Data-driven, component-based, deterministic modular

---

## Documentation

All design and architecture documentation lives in `docs/`. Read in this order if
you are new to the project:

### Start here
| File | Purpose |
|---|---|
| `docs/game_vision.md` | Player fantasy, target emotion, genre references, constraints |
| `docs/architecture_spec.md` | **Canonical architecture.** System map, autoload responsibilities, cell occupancy contract, inter-system call rules |
| `docs/mechanics.md` | Core mechanic definitions (possession, markers, crafting, territory) |

### System specs (full detail)
| File | System |
|---|---|
| `docs/world_hex_chunk_spec.md` | Hex grid, chunk streaming, cell state, baseline/delta/simulation |
| `docs/time_season_spec.md` | TimeService, day/night, seasons, calendar |
| `docs/pawn_system_spec.md` | Pawns, possession, ability system, AI structure, multiplayer |
| `docs/job_marker_spec.md` | Markers as crafted items, job lifecycle, task planning, ant trails |
| `docs/hive_slot_spec.md` | Hive construction, slot grid, crafting orders, nursery, upgrades |
| `docs/territory_spec.md` | Influence fields, hive radius, fade mechanics, plant allegiance |
| `docs/item_resource_spec.md` | ItemDef, RecipeDef, two-tier economy, recipe discovery, item gems |
| `docs/colony_lifecycle_spec.md` | Aging, egg laying, role determination, queen succession |
| `docs/colony_state_spec.md` | ColonyState, loyalty, morale, faction relations, influence score |
| `docs/ai_behavior_spec.md` | Utility AI, job execution, pathfinding, LOD simulation |
| `docs/combat_threat_spec.md` | Combat resolution, threat taxonomy, raid director, hive siege |
| `docs/active_defense_plant_spec.md` | Active plant behavior, targeting, allegiance, breeding |
| `docs/diplomacy_faction_spec.md` | Faction preferences, diplomacy flow, scoring, service contracts |
| `docs/rival_colony_spec.md` | AI colonies, simulation tiers, hive takeover, daughter colonies |
| `docs/exploration_discovery_spec.md` | Fog of war, soft boundaries, biome discovery, scout bees |
| `docs/ui_hud_spec.md` | All HUD elements, hive interior overlay, colony management screen |
| `docs/save_load_spec.md` | SaveManager, file format, versioning, autosave, migration |

### Reference documents
| File | Purpose |
|---|---|
| `docs/architecture.md` | Architecture summary (quick reference; full spec above) |
| `docs/economy_system.md` | Economy summary (quick reference) |
| `docs/combat_system.md` | Combat summary (quick reference) |
| `docs/genetics_system.md` | Genetics summary (quick reference) |
| `docs/plant_system_overview.md` | Plant simulation overview |
| `docs/plant_genetics_spec.md` | Full plant genome structure and inheritance |
| `docs/plant_chemistry_spec.md` | Nectar and pollen chemistry channels |
| `docs/plant_lifecycle_spec.md` | Eight-stage plant lifecycle FSM |
| `docs/plant_variant_rules.md` | Normal / Wild / Lush / Royal variant rules |
| `docs/plant_rendering_spec.md` | Mesh archetypes, atlas layers, LOD buckets |
| `docs/dialogue_hint_vocabulary.md` | Writer's reference — direct and inverse hint words per channel |
| `docs/findings.md` | Engine quirks, performance constraints, known scaling issues |
| `docs/progress_log.md` | Development log |
| `docs/gd_blast.md` | G.D.B.L.A.S.T. development protocol |
| `docs/game_system_template.md` | Template for writing new system specs |
| `docs/godot_architecture_rules.md` | Godot-specific architecture rules |

### Implementation
| File | Purpose |
|---|---|
| `docs/implementation_roadmap.md` | Phase-by-phase build order, milestones, first coding session |

---

## Project structure

```
res://
  autoloads/          # EventBus, TimeService, HexWorldState, HiveSystem,
                      # TerritorySystem, ColonyState, JobSystem, PawnRegistry, SaveManager
  world/              # HexTerrainManager, HexChunk, HexWorldBaseline, HexWorldSimulation,
                      # HexWorldDeltaStore, HexMeshLUT, HexConsts
  colony/
    hive/             # HiveState, HiveSlot, CraftOrder, EggState
    territory/        # TerritorySystem (also autoload)
    colony_data.gd
  pawns/
    pawn_base.gd      # CharacterBody3D base scene
    pawn_state.gd
    pawn_ai.gd
    possession_service.gd
    roles/            # RoleDef resources and role-specific scripts
    species/          # SpeciesDef resources and species-specific scripts
  jobs/
    job_data.gd
    marker_data.gd
    trail_data.gd
  defs/
    items/            # ItemDef .tres files
    recipes/          # RecipeDef .tres files
    plants/           # HexPlantDef .tres files
    species/          # SpeciesDef .tres files
    roles/            # RoleDef .tres files
    abilities/        # AbilityDef .tres files
    hives/            # HiveDef .tres files
    factions/         # FactionDef .tres files
    threats/          # ThreatDef .tres files
    markers/          # MarkerDef .tres files
    biomes/           # HexBiome .tres files
    time_config.tres  # TimeConfig resource
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
  docs/               # All documentation listed above
```

---

## Key design principles

**Organic, not industrial.** Logistics, production, and defense feel ecological rather
than mechanical. Ants carry items. Bears guard hives. Plants defend territory.

**Leadership through service.** The queen is the most capable bee but there is only
one of her. Early game she does everything. Late game she delegates and explores.

**Possession as choice, not requirement.** Workers run autonomously and competently.
The player can jump in, do it better, and jump back out. The game rewards intervention
without requiring it.

**Diegetic information.** The world communicates state without HUD interruption where
possible. Thirsty plants desaturate. Elder bees grey at the wing joints. Feral defense
plants turn red-tinged. The HUD fills gaps the world cannot cover.

**Diplomacy through observation.** Faction preferences are never shown in a tooltip.
Creatures describe their needs through natural dialogue. The player experiments, gets
partial responses, adjusts, and eventually discovers the perfect recipe. Chemistry
channels map to plain-language hint words defined in `docs/dialogue_hint_vocabulary.md`.

---

## Vertical slice milestone

The first playable milestone is:

- Queen exists in a starting hive on a tree
- Foragers gather nectar from plants autonomously
- Queen crafts honey → wax → markers
- Queen places a build hive marker on a second tree
- Carpenter responds, sources materials, builds the second hive
- Territory projects from both hives and is visible on the terrain
- A snapvine guards the hive entrance — active during FLOWERING/FRUITING/IDLE stages
- A hornet raids the hive — snapvine whips it, soldier fights it
- Player can possess the soldier and fight the hornet manually
- Player can switch to and possess a beetle — ground-level movement, carry/dig abilities
- Game saves and loads correctly

---

## Contributing

Solo project. See `docs/implementation_roadmap.md` for the current phase and
`docs/progress_log.md` for what has been done and what is next.

When working with AI coding assistants:
1. Share the relevant spec before asking for code
2. Generate class scaffolds (typed fields + method stubs) before logic
3. One system at a time
4. Test each phase before starting the next
5. Log any engine quirks immediately in `docs/findings.md`
