# BeezWorx Implementation Roadmap

This document defines the phase-by-phase build order for BeezWorx MVP, targeting the
fastest path to a playable vertical slice. Each phase produces something runnable.
No phase is purely invisible infrastructure — if you cannot see or interact with the
result, the phase is wrong.

**Target vertical slice:** Queen exists in a hive. Foragers gather nectar autonomously.
Queen crafts honey, wax, and markers. Carpenter responds to a build marker and builds
a second hive. Territory projects from both hives. A snapvine guards the hive entrance.
A hornet raids the hive — the snapvine whips it, a soldier bee fights it, and the player
can possess the soldier and fight manually. Player can also possess a beetle. Game saves
and loads correctly. Every core mechanic is represented: management, automation, crafting,
expansion, territory, defense (plant + soldier), and possession diversity.

---

## On the existing terrain codebase

Do not scrap it. The `HexWorldState` baseline/delta/simulation stack, chunk streaming,
`HexChunkGenCache`, and cell state model all map directly onto the new spec. Three
surgical changes are needed before building on top of it:

1. **Migrate `current_world_time`** — remove from `HexWorldState`, create `TimeService`
   autoload, wire `HexTerrainManager._process` to call `TimeService.advance(delta * time_scale)`.
   Update all `get_cell` calls that default to `HexWorldState.current_world_time` to
   default to `TimeService.world_time` instead.

2. **Add `CellChangeMutationHint` to `cell_changed`** — change signal signature to
   `cell_changed(cell: Vector2i, hint: CellChangeMutationHint)`. Update `_write_delta`
   to select the appropriate hint. Update `HexChunk._on_cell_changed` to switch on hint.

3. **Expand `HexGridObjectDef.Category`** — add `HIVE_ANCHOR`, `TRAVERSABLE_STRUCTURE`,
   `RESOURCE_NODE`, `TERRITORY_MARKER`, `PAWN_SPAWN` to the enum. Existing `RESOURCE_PLANT`,
   `TREE`, `DEFENSIVE_ACTIVE` stay as-is.

These three changes take a day and unlock all subsequent phases.

---

## Phase 0 — Terrain migration (1–2 days)

**Goal:** Existing terrain running cleanly against the new spec. No new features.

Tasks:
- Create `TimeService` autoload with `TimeConfig` resource. Wire `HexTerrainManager`.
- Add `CellChangeMutationHint` enum and update `cell_changed` signal everywhere.
- Expand `CellCategory` enum.
- Add `EventBus` autoload — empty signal declarations for now; fill as phases need them.
- Update `architecture.md` in project files to match `architecture_spec.md`.

**Done when:** Terrain generates, chunks stream, plants tick through lifecycle stages,
world time advances via `TimeService`. No regressions from existing terrain behavior.

---

## Phase 1 — Autoload skeleton (2–3 days)

**Goal:** All autoloads exist as stubs. No logic yet — just class definitions, signal
declarations on EventBus, and the save/load contract stubs. This establishes the
dependency graph so all subsequent phases have a clean interface to build against.

Tasks:
- `HiveSystem` stub — `register_hive`, `get_hive`, `get_hives_for_colony` as empty/returns-null
- `TerritorySystem` stub — `is_in_territory`, `get_controlling_colony` return defaults
- `ColonyState` stub — `create_colony`, `get_colony`, `add_known_recipe`, `get_queen_id`
- `JobSystem` stub — `place_marker`, `post_job`, `get_claimable_jobs`, `claim_job`
- `PawnRegistry` stub — `register`, `deregister`, `get_state`, `get_pawns_for_colony`
- `SaveManager` stub — `save_game`, `load_game` do nothing yet
- All EventBus signals declared from `architecture_spec.md`

**Done when:** All autoloads load without errors. Godot project settings has them in
correct dependency order. No functionality yet.

---

## Phase 2 — Pawn base and possession (3–4 days)

**Goal:** A queen pawn exists in the world. The player can move her around. Basic
camera follows her. The pawn switch panel shows her name. HUD pawn card shows her
stats.

Tasks:
- `PawnState` RefCounted with all fields from pawn spec
- `PawnPersonality` generation from seed
- `SpeciesDef` resource for bee queen — movement speed, health, reveal radius
- `PawnBase` scene (CharacterBody3D, flying movement, basic collision)
- `PossessionService` — single player slot, possess/release, camera transition
- `PawnManager` — spawns one queen pawn at world origin on game start
- `PawnRegistry` — register/deregister, `get_state`
- Basic HUD: pawn card (portrait, health bar, name)
- Basic pawn switch panel: single entry, queen pinned at top
- Input actions: `action`, `alt_action`, `switch_pawn`, `cancel`

**Done when:** Player spawns as the queen, can fly around the hex world, HUD shows
her stats, pressing switch opens panel showing her name.

---

## Phase 3 — Hive placement and slots (4–5 days)

**Goal:** A pre-placed hive exists on a tree. Player can enter it. Slot grid renders.
Player can designate slots. No crafting yet — just the infrastructure.

Tasks:
- `HiveState` and `HiveSlot` RefCounted with all fields
- `HiveSystem.register_hive` — creates HiveState, registers in `_hives_by_cell`,
  sets cell category to `HIVE_ANCHOR` via `HexWorldState`
- `HiveSystem` deposit/withdraw API (item counts on slots)
- `ENTER_HIVE` ability on queen — transitions camera to interior view
- `HiveOverlay` UI — hex slot grid, slot selection, slot panel
- Slot designation selector (BED / STORAGE / CRAFTING / NURSERY / GENERAL)
- Pre-place one hive on a tree cell at game start (hardcoded for now)
- `ColonyState.create_colony(0)` at game start — player colony initialised

**Done when:** Player enters hive, sees slot grid, can change slot designations, exits hive.

---

## Phase 4 — Items, inventory, and item gems (3–4 days)

**Goal:** Items exist. The queen can carry them. Item gems appear in the world and can
be picked up. The hive can store items.

Tasks:
- `ItemDef` resources for MVP raw items: `nectar_basic`, `pollen_basic`, `water`,
  `plant_fiber`, `tree_resin`
- `PawnInventory` RefCounted — slots, add/remove, carry weight
- `ItemGemData` and `ItemGem` scene node (billboard sprite + Area3D)
- `ItemGemManager` — spatial index, spawn/despawn gems, pool management
- `GATHER_RESOURCE` ability effect — queen picks up item gem on action press
- `DROP_ITEM` ability effect — queen drops item from inventory
- `HiveSystem.deposit_item` / `withdraw_item` — move items to/from hive slots
- Inventory / context panel HUD (bottom-center) — shows carried items, target cell info
- Action button labels update from `InteractionDetector`

**Done when:** Queen walks up to a dropped nectar gem, presses action, gem disappears,
inventory shows nectar. Queen enters hive, deposits nectar into a storage slot.

---

## Phase 5 — Recipe discovery and crafting (3–4 days)

**Goal:** Queen can experiment with ingredients in a crafting slot and discover honey.
Crafting executes when recipe is known.

Tasks:
- `RecipeDef` resources: `honey_basic`, `beeswax`, `royal_wax`, `bee_jelly`,
  `bee_bread`, `marker_base` (always-known), plus a few discoverable ones
- `RecipeSystem` static class — `check_discovery`, `check_partial_match`
- `ColonyState.known_recipe_ids` — pre-populated with always-known set
- Crafting slot staging area in hive UI — queen places items, system checks for match
- `CraftOrder` — assigned to slot on discovery, tracks progress
- `EventBus.recipe_discovered` — triggers discovery notification
- Partial match glow in slot UI
- `ItemDef` resources for crafted items: `honey_basic`, `beeswax`, `royal_wax`
- Notification feed HUD (right edge) — recipe discovered, item crafted

**Done when:** Queen places nectar + pollen in crafting slot, honey recipe discovers,
craft begins, honey appears in slot. Queen can then craft beeswax (honey + honey),
then royal_wax, then marker_base.

---

## Phase 6 — Worker pawns and basic AI (4–5 days)

**Goal:** A forager bee exists alongside the queen. She autonomously gathers nectar
from plants and deposits it in the hive. Player can switch to her and control her.

Tasks:
- `RoleDef` for forager — utility behaviors with correct weights and conditions
- `UtilityBehaviorDef` resources for: SEEK_SLEEP, DEPOSIT_ITEMS, GATHER_NECTAR
- `PawnAI` node — tick loop, utility scoring, job polling, subtask execution
- `PawnAbilityExecutor` node — shared execution, cooldowns, target resolution
- `InteractionDetector` Area3D — detects plants, hive entrance, item gems
- `GATHER_NECTAR` job type in `PawnAI` subtask builder
- `JobSystem.post_job` — basic job posting (no markers yet, just hive-slot-derived)
- `JobSystem.get_claimable_jobs` — role filter + distance filter
- Flying pawn movement (steering behavior, separation force)
- LOD tick intervals (distance-based)
- Pawn switch panel — forager appears as second entry
- `PawnManager` — spawn forager at game start alongside queen

**Done when:** Forager flies to a flowering plant, gathers nectar into inventory, flies
to hive, deposits into storage slot. Player can possess forager and manually gather.
Player can switch back to queen. AI resumes when possession released.

---

## Phase 7 — Job markers and carpenter (4–5 days)

**Goal:** Queen crafts a build hive marker, places it on a tree, carpenter responds
and builds a second hive.

Tasks:
- `MarkerDef` for `BUILD_HIVE` — generates BUILD_HIVE job
- `MarkerData` runtime — created by `JobSystem.place_marker`
- `PLACE_MARKER` ability effect — consumes marker item, creates MarkerData
- `JobTemplateDef` for BUILD_HIVE — required items: plant_fiber, bee_glue
- `ItemDef` for `marker_build_hive`, `bee_glue`, `plant_fiber`
- `RecipeDef` for `bee_glue` (tree_resin + beeswax), `marker_build_hive` (marker_base + plant_fiber)
- `RoleDef` for carpenter — utility behaviors including BUILD_HIVE, GATHER_PLANT_FIBER
- Task planner in `JobSystem.claim_job` — evaluates fetch vs harvest for materials
- `BUILD_HIVE` subtask sequence in `PawnAI`
- `HiveSystem.register_hive` called on job completion
- Territory projection: `TerritorySystem._project_hive_influence` on `hive_built`
- `PawnManager` — spawn carpenter at game start
- Territory visual: shader parameter on terrain for colony influence

**Done when:** Queen places build marker on tree. Carpenter gathers materials (or
fetches from hive), navigates to marker, consumes materials over time, second hive
appears. Territory expands visually.

---

## Phase 8 — Territory system and fading (2–3 days)

**Goal:** Territory renders correctly. Destroying the second hive causes its unique
cells to fade. Active plant allegiance responds to territory state.

Tasks:
- `TerritorySystem` full implementation — influence field, cell contributor tracking,
  `get_plant_allegiance`, fade records, `_fade_tick`
- `TerritorySystem._recompute_from_hives` — called on load
- Territory overlay shader on terrain (influence visualisation)
- `EventBus.territory_faded` / `territory_expanded` emissions
- `HiveSystem._destroy_hive` — triggers fade, displaces bed assignments
- Loyalty decay on `ColonyState` from lost beds (basic — just the hook, not full morale)
- `CellChangeMutationHint.STRUCTURAL` correctly triggers territory re-query in active plants

**Done when:** Player destroys (or lets be destroyed) the second hive. Territory
shrinks. Fading is visible. Active plant in the fading zone changes allegiance.

---

## Phase 9 — Beetle possession and ground pawn movement (2–3 days)

**Goal:** A beetle exists in the world. Player can switch to and possess it. Beetle has
two working abilities: carry a heavy item and dig a hole. Ground pawn movement feels
distinct from flying pawn movement.

Tasks:
- `SpeciesDef` for beetle — ground movement, 90-day lifespan, slow carry speed
- `RoleDef` for beetle — utility behaviors: CARRY_ITEM, IDLE_WANDER
- `AbilityDef` for carry (action) and dig (alt-action)
- Ground pawn movement in `PawnBase` — `NavigationAgent3D`, gravity, slope handling
- Navigation mesh generation per chunk (baked during `finalize_chunk`)
- `CARRY_ITEM` ability: beetle picks up nearest heavy item gem, carries it, drops on
  alt-action. Carry weight modifies move speed via `carry_weight_speed_curve`.
- `DIG_HOLE` ability: beetle digs on target cell (visual only at this stage — full
  planting mechanic is post-milestone)
- Beetle pawn scene — distinct mesh from bee, ground-level camera when possessed
- `PawnManager` — spawn one beetle near hive at game start
- Pawn switch panel — beetle appears as third entry below forager

**Done when:** Player opens pawn switch panel, selects beetle, camera drops to ground
level. Beetle crawls toward a dropped item gem, picks it up with action, moves
noticeably slower. Player presses alt-action, beetle sets it down. Player switches back
to queen — beetle AI resumes wandering. The two movement types (flying queen, crawling
beetle) feel meaningfully different.

---

## Phase 10 — Plant lifecycle, snapvine, soldier, and hornet (5–6 days)

**Goal:** Plant lifecycle is visually ticking. A snapvine guards the hive. A hornet
raids. The snapvine whips it. A soldier bee can fight it. Player can possess the soldier.
This is the defense layer of the vertical slice.

**Plant lifecycle (2 days):**
- `_check_stale_plants` already exists in `HexChunk` — ensure stage transitions fire
  correctly and `DEFENSIVE_ACTIVE` category plants respond to their stage
- `ActivePlantPool` on `HexTerrainManager` — checkout/return node pool
- Snapvine scene (`ActivePlant` subclass or configured instance):
  - `TriggerArea` (Area3D) detects flying AND ground pawns in range
  - Stage gate: active during FLOWERING / FRUITING / IDLE; dormant in GROWTH / WILTING
  - `_should_attack` queries `TerritorySystem.get_plant_allegiance` — ALLIED attacks
    enemies only, FERAL attacks everything
  - Attack animation + `CombatSystem.resolve_hit` via virtual pawn id
  - `A_range` and `A_regeneration` channels read from genes at spawn
  - `feral_tint` shader parameter driven by allegiance state
- Place one snapvine on a cell adjacent to the starting hive anchor at game start

**CombatSystem (1 day):**
- `resolve_hit(attacker_id, target_id, ability, is_player_controlled)` — damage, defence
  multipliers, hit effects (poison from `poison_stinger`)
- `_apply_damage` — decrement `PawnState.health`, call `_kill_pawn` at 0
- `_kill_pawn` — set `is_alive = false`, emit `EventBus.pawn_died`, queue_free node
- `_tick_effects` — tick poison/paralysis/stun durations each frame
- `EventBus.pawn_hit` emission

**Soldier bee (1 day):**
- `SpeciesDef` for soldier — slightly higher health, same flying movement
- `RoleDef` for soldier — utility behaviors: ATTACK_THREAT (high weight when
  threat_nearby), PATROL (fallback idle), SEEK_SLEEP
- `AbilityDef` for attack (action: use poison stinger) and gather thorn (alt-action)
- `PawnAI` threat detection — `_check_threats()`, `_decide_threat_response()`
- Alert propagation — soldier receiving alert switches to ATTACK_THREAT
- `PawnManager` — spawn one soldier at game start

**Hornet and minimal ThreatDirector (1 day):**
- `SpeciesDef` for hornet — flying, hostile (colony_id = -1)
- Hornet AI: single utility behavior — FLY_TO_HIVE, attack anything in range
- `ThreatDirector` minimal — spawn one hornet every 120 real seconds on a timer,
  targeting the nearest hive. No `ThreatDef` resource needed yet — hardcoded for milestone.
- Hornet pawn scene — visually distinct from bee

**Done when:** Hornet spawns, flies toward hive. Snapvine detects it, whips it (stun
+ damage). Soldier detects it, flies to intercept, attacks. Player can possess soldier
and manually target the hornet. Hornet dies — `EventBus.pawn_died` fires, notification
shows. If territory around snapvine fades (debug: destroy the hive manually), snapvine
turns red-tinged and whips the forager flying past instead.

---

## Phase 11 — Polish and vertical slice completion (3–4 days)

**Goal:** All milestone systems connected and feeling good. The core loop is completable
without crashes.

Tasks:
- Full compass HUD — hive indicators, marker icons, queen position, threat indicators
- Season/time indicator HUD
- Notification feed — recipe discovered, pawn died, hive attacked
- `FogOfWarSystem` — reveal cells as queen moves, plants hidden in unrevealed cells
- `SaveManager` full implementation — save/load all systems in dependency order,
  autosave on day change
- Basic game-over sequence — queen dies with no heir, colony chaos, game-over screen
- `LifecycleSystem` minimal — day-change aging, natural death, elder indicator on pawn card
- `ColonyState` loyalty basics — bed shortage decay, abandonment at 0.0
- Narrator biome discovery line for at least one non-starting biome
- Bug fixing pass across all phases

**Done when:** The full vertical slice milestone is completable: queen → gather → craft
honey → craft markers → carpenter builds hive → territory expands → hornet raids →
snapvine whips it → soldier fights it → player possesses soldier → player possesses
beetle and feels ground-level movement → game saves and loads correctly.

---

## Phase order rationale

The phases build in a strict dependency order:

```
Terrain (0) → Autoload skeleton (1) → Pawn + possession (2) → Hive + slots (3)
→ Items + gems (4) → Recipes + crafting (5) → Worker AI (6) → Markers + carpenter (7)
→ Territory (8) → Beetle possession (9) → Plant lifecycle + snapvine + soldier + hornet (10)
→ Polish (11)
```

Each phase is playable or at least runnable before the next begins. You should be
able to show someone the game after Phase 6 (forager autonomously gathering) and have
them understand what the game is about. Phases 7–10 add the strategic and ecological
depth that make it compelling.

---

## Estimated total timeline

Solo development with AI coding assistance:

| Phase | Days estimated | Cumulative |
|---|---|---|
| 0 — Terrain migration | 1–2 | 2 |
| 1 — Autoload skeleton | 2–3 | 5 |
| 2 — Pawn + possession | 3–4 | 9 |
| 3 — Hive + slots | 4–5 | 14 |
| 4 — Items + gems | 3–4 | 18 |
| 5 — Recipes + crafting | 3–4 | 22 |
| 6 — Worker AI | 4–5 | 27 |
| 7 — Markers + carpenter | 4–5 | 32 |
| 8 — Territory | 2–3 | 35 |
| 9 — Beetle possession | 2–3 | 38 |
| 10 — Plant lifecycle + snapvine + soldier + hornet | 5–6 | 44 |
| 11 — Polish + slice | 3–4 | 48 |

**Target: 7–8 weeks to vertical slice** at a steady pace with daily sessions.
These are coding days, not calendar days. Expect the real number to be higher —
bugs, design pivots, and life happen. But the milestone is achievable.

---

## How to use AI coding assistance effectively

Each phase should be broken into focused coding sessions. The pattern that works best:

1. **Start each session by sharing the relevant spec** — paste the spec section you
   are implementing so the AI has the exact field names, signal names, and contracts.
2. **One system at a time** — do not ask for multiple systems in one generation pass.
   Ask for `HiveState` and `HiveSlot` first, validate them, then ask for `HiveSystem`
   autoload methods.
3. **Generate scaffolds first, logic second** — ask for class definitions with typed
   fields and method stubs first. Then ask to implement each method individually.
   This produces cleaner code than asking for complete implementations in one shot.
4. **Test each phase before starting the next** — a bug carried into the next phase
   becomes two bugs. The phases are designed to be testable at each boundary.
5. **Update findings.md when you hit engine quirks** — the findings doc is your
   institutional memory. Anything surprising about Godot 4.6 behavior goes there
   immediately so future sessions don't repeat the discovery.

---

## First coding session (Phase 0, Day 1)

Concrete first steps:

1. Create `res://autoloads/time_service.gd` — `TimeConfig` resource + `TimeService`
   node with `advance(delta)`, `current_day`, `day_phase`, `current_season`,
   `is_daytime`. Register as autoload.
2. Add `TimeConfig` resource at `res://defs/time_config.tres` — `day_length = 600.0`,
   `days_per_season = 91`, `day_night_split = 0.6`.
3. In `HexTerrainManager._process`: replace `HexWorldState.current_world_time +=
   delta * world_time_scale` with `TimeService.advance(delta * world_time_scale)`.
4. In `HexWorldState`: replace all reads of `current_world_time` with
   `TimeService.world_time`. Remove the field.
5. Add `CellChangeMutationHint` enum to a new `res://world/hex_consts.gd` or inline
   in `HexWorldState`. Update `cell_changed` signal signature.
6. Run the project. Terrain should generate identically to before. World time advances.

That is a complete, testable first session. Everything after it builds on a clean base.
