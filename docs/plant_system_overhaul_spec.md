# Plant System Overhaul Spec
## BeezWorx — Unified Plant Hierarchy, Health System, Damage Abilities, Grass Lifecycle, Soil Data

**Status:** Spec + data model complete. Implementation next session.
**Supersedes:** plant_system_overview.md, plant_lifecycle_spec.md (partially)
**Touches:** hex_grid_object_def, hex_plant_def, hex_plant_data, hex_cell_delta,
hex_cell_state, hex_biome, ability_def, role_def, hex_consts,
hex_chunk (rendering migration — next session)

---

## 1. Why This Overhaul

The original system had three separate inheritance branches for plant-like objects:
`HexPlantDef` (RESOURCE_PLANT), `HexTreeDef` (TREE), and raw `HexGridObjectDef`
instances for DEFENSIVE_PASSIVE and DEFENSIVE_ACTIVE. This fragmented lifecycle logic,
prevented health/damage from working uniformly, and made the grasshopper's eat ability
impossible to express cleanly through the ability def system.

The overhaul unifies everything under one hierarchy and one lifecycle model.

---

## 2. Category Model — Before and After

### Before

`HexGridObjectDef.Category`:
```
RESOURCE_PLANT, TREE, ROCK, PORTAL, DEFENSIVE_PASSIVE, DEFENSIVE_ACTIVE
```
`HexConsts.CellCategory` mirrored these numerically — a code smell. Colony systems
used the same integers as rendering routing.

### After

`HexGridObjectDef.Category` collapses to three physical-object types:
```
PLANT,   # any living plant — subcategory on HexPlantDef determines specifics
ROCK,    # impassable terrain object
PORTAL,  # reserved
```

`HexPlantDef.PlantSubcategory` carries the semantic distinction:
```
GRASS,            # ground cover; spreads; low nectar; pollen_basic only
RESOURCE,         # harvestable flowering plants (former RESOURCE_PLANT)
ACTIVE_DEFENSE,   # attacks pawns (former DEFENSIVE_ACTIVE)
PASSIVE_DEFENSE,  # blocks movement / damages on contact (former DEFENSIVE_PASSIVE)
TREE,             # structural; hive anchor; long lifecycle
```

`HexConsts.CellCategory` is now DECOUPLED from `HexGridObjectDef.Category`.
Colony systems (territory, jobs, bee interact) query `PlantSubcategory` directly
from the definition rather than relying on matching integer values. The
"must stay numerically identical" comment in hex_consts.gd is REMOVED.

### Migration pattern for existing category comparisons

Before:
```gdscript
if state.category == HexGridObjectDef.Category.RESOURCE_PLANT:
```
After:
```gdscript
if state.plant_subcategory == HexPlantDef.PlantSubcategory.RESOURCE:
```
`HexCellState` exposes a convenience field `plant_subcategory: int` (default -1 for
non-plants) so callers do not need to cast the definition.

---

## 3. Class Hierarchy

```
Resource
└── HexGridObjectDef          # base: id, category, placement, rendering
    └── HexPlantDef           # adds: plant_subcategory, max_health, toughness,
    │                         #       plant_data, genes, pollen_species_tag,
    │                         #       can_hybridize_across_species
    │   ├── GrassDef          # same structure, grass-tuned defaults
    │   └── HexTreeDef        # keeps all tree exports; gains lifecycle via plant_data
    └── (plain HexGridObjectDef for ROCK, PORTAL)
```

ACTIVE_DEFENSE and PASSIVE_DEFENSE plants use HexPlantDef directly with the
appropriate `plant_subcategory`. No new subclasses needed; the `scene` field
already handles per-species instantiation for active defense.

---

## 4. Plant Health System

### Storage: HexCellDelta

```
health_remaining: float = -1.0
# Sentinel -1.0 = full health. Written on first damage. Fits the existing
# mutation pattern alongside pollen_remaining and nectar_remaining.
```

### Damage flow

1. Player/AI executes `DAMAGE_PLANT` ability on a cell.
2. `PawnAbilityExecutor` calls `HexWorldState.damage_plant(cell, ability.damage, pawn_id)`.
3. `HexWorldState.damage_plant`:
   a. Resolves target: `get_cell_ref(cell)` — must be PLANT category.
   b. Validates subcategory against `ability.valid_plant_subcategories` — no-op if mismatch.
   c. Resolves current health: `delta.health_remaining` if ≥ 0, else `def.max_health`.
   d. Computes effective damage: `ability.damage / maxf(def.toughness, 0.01)`.
   e. Subtracts effective damage. If health ≤ 0: `_kill_plant(cell)`.
   f. Else: `mutate_cell(cell, {"health_remaining": new_health})`.
4. `_kill_plant(cell)`:
   a. `clear_cell(cell)` — writes CLEARED delta, fires cell_changed.
   b. Calls `ItemGemManager.spawn_gem(item_id, world_pos)` if available (stubbed).
   c. Emits `EventBus.plant_killed(cell, pawn_id)` (new signal — add to EventBus).

### On HexPlantDef

```gdscript
@export var max_health: float = 100.0
@export var toughness:  float = 1.0
# effective_damage = raw_damage / toughness
# toughness = 1.0 = normal. 2.0 = half damage. 0.5 = double damage.
```

### Toughness reference values

| Plant type           | max_health | toughness | Hits at 25 dmg |
|----------------------|------------|-----------|----------------|
| Thin grass           | 50         | 0.6       | 3-4            |
| Resource plant       | 100        | 1.0       | 4              |
| Passive defense      | 150        | 2.0       | 12             |
| Active defense       | 200        | 2.5       | 20             |
| Young tree           | 400        | 4.0       | 64             |
| Mature tree          | 800        | 8.0       | 128            |

### Health reset rules

- On `PLANTED` or `SPROUT_SPAWNED` delta: `health_remaining` is NOT written (sentinel
  -1 = full health). No need to write full health explicitly.
- On `stage_override` to WILT or DEAD: health is irrelevant; plant is dying naturally.
- On `clear_cell`: delta is replaced with CLEARED; old health record is gone.
- Health does NOT reset between lifecycle stages. A damaged plant that cycles through
  IDLE → FLOWERING stays damaged. Regeneration is a future mechanic.

---

## 5. Damage Ability System

### CORRECTION — AbilityDef is @abstract, not enum-based

The initial spec proposed an EffectType enum on AbilityDef. The actual codebase uses
a **subclass-per-type** pattern. AbilityDef is `@abstract`; each ability type is a
concrete subclass (CollectAbilityDef, DepositAbilityDef, etc.). This is the correct
pattern and must be followed.

The new concrete subclass for plant damage is:

```gdscript
# damage_plant_ability_def.gd
class_name DamagePlantAbilityDef
extends AbilityDef

@export var damage:                    float       = 25.0
# HexPlantDef.PlantSubcategory ints. Empty = any subcategory.
@export var valid_plant_subcategories: Array[int]  = []
# Plant stages during which damage is allowed. Empty = any stage.
@export var valid_stages:              Array[int]  = []
# Override item drop on kill. Empty = use plant def's drop_item_id.
@export var drop_item_override:        StringName  = &""
```

Implements `can_use`, `resolve_target`, `execute` — same virtual interface as
CollectAbilityDef.

### RoleDef pattern (actual)

RoleDef does NOT have ability slot exports. Abilities are assigned on `PawnBase`
directly via `@export var action_abilities: Array[AbilityDef]` — a prioritized list
where the first `can_use()` winner fires on action button press.

RoleDef.harvest_restrictions (Array[StringName]) is a separate role-level filter
that may be used by the AI to further restrict which resources a role pursues.
It does NOT gate DamagePlantAbilityDef execution — the ability's own
`valid_plant_subcategories` is the authority.

Two species sharing the same `eat_grass.tres` AbilityDef automatically share the same
targeting rules. Different targets → different .tres file.

### Authored ability resources (create as .tres files)

**`res://abilities/defs/eat_grass.tres`** (DamagePlantAbilityDef)
```
damage                    = 25.0
valid_plant_subcategories = [PlantSubcategory.GRASS, PlantSubcategory.RESOURCE]
display_name              = "Eat"
cooldown                  = 0.3
```

**`res://abilities/defs/chomp_tree.tres`** (DamagePlantAbilityDef, future — bear)
```
damage                    = 80.0
valid_plant_subcategories = [PlantSubcategory.TREE, PlantSubcategory.ACTIVE_DEFENSE,
                             PlantSubcategory.PASSIVE_DEFENSE]
```

### Grasshopper landscaper kit

```
Grasshopper.tscn (PawnBase / PawnHopper)
  action_abilities = [eat_grass.tres]   ← first can_use() winner fires

res://defs/roles/landscaper.tres (RoleDef)
  role_id           = &"landscaper"
  utility_behaviors = [CLEAR_GRASS, IDLE_HOP]
  harvest_restrictions = []
```

---

## 6. Grass Lifecycle

Grass uses the same Stage enum: SEED → SPROUT → GROWTH → FLOWERING → FRUITING → IDLE → WILT → DEAD

GrassDef's attached HexPlantData uses very different values:

| Parameter              | Resource plant | Grass          | Notes |
|------------------------|----------------|----------------|-------|
| `wilt_without_water`   | true           | **false**      | No water timer |
| `soil_wilt_enabled`    | false          | **true**       | Soil conditions CAN kill it |
| `max_fruit_cycles`     | 3              | **99**         | Effectively permanent cycle |
| `nectar_per_fruit`     | 5.0            | **0.1**        | Nearly nothing |
| `base_nectar_yield`    | 1.0            | **0.05**       | Trace amounts only |
| `can_produce_pollen`   | true           | **true**       | pollen_basic tag |
| `sprout_chance`        | 0.25           | **0.45**       | Spreads readily |
| `sprout_radius`        | 3              | **2**          | Close spread |
| `max_health` (on def)  | 100.0          | **50.0**       | Soft |
| `toughness` (on def)   | 1.0            | **0.6**        | Easy to eat |

Stage durations for grass (all values in world-seconds):
```
SEED:       0.0       # not used; grass doesn't grow from seed in baseline
SPROUT:     300.0     # slow establishing
GROWTH:     600.0     # main green phase
FLOWERING:  900.0     # rare bloom event; mostly visual
FRUITING:   300.0     # short seed window
IDLE:       1800.0    # long dormant rest before next cycle
WILT:       3600.0    # extremely slow die-off under soil stress
DEAD:       60.0      # fast clear after death
```

### Grass wilt — soil conditions only

New fields on HexPlantData:
```gdscript
@export var soil_wilt_enabled:  bool  = false
@export var wilt_wetness_min:   float = 0.05   # only bone-dry soil wilts
@export var wilt_toxicity_max:  float = 0.85   # only extreme toxicity kills
```

Wilt is forced when:
```
(soil_wilt_enabled) AND (soil_wetness < wilt_wetness_min OR soil_toxicity > wilt_toxicity_max)
```
This check runs in `HexWorldSimulation.get_cell` AFTER the water wilt check.
Both paths independently write `stage_override = WILT`.

### Grass pollen isolation

New fields on HexPlantDef:
```gdscript
@export var pollen_species_tag:          StringName = &""
@export var can_hybridize_across_species: bool       = true
```

GrassDef authoring:
```
pollen_species_tag          = &"grass"
can_hybridize_across_species = false
```

`attempt_cross_sprout` rejects hybridization if either parent has
`can_hybridize_across_species = false` AND the two parents have different
`pollen_species_tag` values. Grass × grass = allowed. Grass × flower = blocked.

### Grass spreading

Same `attempt_cross_sprout` path as resource plants. Grass spreads naturally without
bee involvement — this is intentional. It creates ambient colonial busywork for the
landscaper role and makes clearing feel satisfying and purposeful.

---

## 7. Soil Data

### SoilData Resource (new)

```gdscript
# res://defs/world/soil_data.gd
class_name SoilData
extends Resource

enum SoilType {
    LOAM,         # balanced; good for most plants
    CLAY,         # retains water well; slow drainage
    SAND,         # poor water retention; drains fast
    GRAVEL,       # very low retention; harsh
    VOLCANIC,     # nutrient-rich but elevated base toxicity
    CONTAMINATED, # event-driven; high toxicity; most plants die
}

@export var soil_type:      SoilType = SoilType.LOAM
@export var base_wetness:   float    = 0.5   # 0.0 = bone dry, 1.0 = waterlogged
@export var base_toxicity:  float    = 0.0   # 0.0 = clean, 1.0 = fully toxic
# drainage_rate: how fast wetness_override decays toward base_wetness per day.
# Stubbed for now — no weather. Will be driven by weather events.
@export var drainage_rate:  float    = 0.1
```

### Where soil state lives

| Layer              | What it holds |
|--------------------|---------------|
| `HexBiome`         | `soil_profile: SoilData` — baseline soil for this biome |
| `HexCellDelta`     | `wetness_override: float = -1.0` and `toxicity_override: float = -1.0` |
| `HexCellState`     | `soil_type`, `soil_wetness`, `soil_toxicity` — fully resolved |

### HexBiome addition

```gdscript
@export var soil_profile: SoilData = null
```

When null: simulation falls back to SoilType.LOAM with base_wetness = 0.5.

---

## 8. File Change Summary

### Modified files

| File | Change |
|------|--------|
| `hex_grid_object_def.gd` | Category enum → PLANT, ROCK, PORTAL only |
| `hex_plant_def.gd` | PlantSubcategory enum; max_health, toughness, pollen_species_tag, can_hybridize_across_species |
| `hex_plant_data.gd` | soil_wilt_enabled, wilt_wetness_min, wilt_toxicity_max |
| `hex_cell_delta.gd` | health_remaining, wetness_override, toxicity_override; to_dict/from_dict |
| `hex_cell_state.gd` | plant_subcategory, health_remaining, soil_wetness, soil_toxicity, soil_type; duplicate_state |
| `hex_biome.gd` | soil_profile: SoilData |
| `hex_consts.gd` | Remove numeric-sync guarantee; update CellCategory comment |
| `ability_def.gd` | EffectType enum, damage, valid_plant_subcategories, drop_item_override |

### New files

| File | Purpose |
|------|---------|
| `grass_def.gd` | GrassDef extends HexPlantDef |
| `soil_data.gd` | SoilData Resource |

### Deferred to implementation session

| File | Work |
|------|------|
| `hex_world_state.gd` | `damage_plant()` API; `plant_killed` signal emission |
| `hex_world_simulation.gd` | health_remaining resolution; soil wilt check; plant_subcategory population |
| `hex_chunk.gd` | Rendering: switch on plant_subcategory |
| `grasshopper.gd` | Replace manual `_bite_plant` with AbilityDef executor call |
| `pawn_ability_executor.gd` | DAMAGE_PLANT effect handler |

---

## 9. Rendering Migration Notes (next session)

`HexChunk._generate_objects()` currently switches on `category`. After the overhaul,
all plant-category objects hit `PLANT` and the inner switch goes on `plant_subcategory`:

```gdscript
if def.category == HexGridObjectDef.Category.PLANT:
    var pd := def as HexPlantDef
    match pd.plant_subcategory:
        HexPlantDef.PlantSubcategory.GRASS:           # stays as grass multimesh system
        HexPlantDef.PlantSubcategory.RESOURCE:        # sprout/bush MM (unchanged)
        HexPlantDef.PlantSubcategory.TREE:            # tree MM batch (unchanged)
        HexPlantDef.PlantSubcategory.ACTIVE_DEFENSE:  # scene instantiation (unchanged)
        HexPlantDef.PlantSubcategory.PASSIVE_DEFENSE: # MM per def.id (unchanged)
```

No rendering behavior changes — only the routing condition changes.

---

## 10. Open Questions (resolve before implementation)

**Q1: Tree lifecycle.** Trees are currently `is_permanent = true`. Adding a lifecycle
via `HexPlantData` means trees can theoretically die of old age. Is that intended?
Recommendation: `is_permanent` on `HexGridObjectDef` suppresses WILT/DEAD stage checks.
Trees only die by combat (bear) or explicit event. Their lifecycle runs SPROUT → GROWTH
→ FLOWERING (seasonal blossoms) → FRUITING (seeds/fruit drops) → IDLE infinitely,
never advancing to WILT unless is_permanent is false.

**Q2: Active defense plant death.** When a snapvine reaches 0 health, does it:
(a) clear permanently and drop a gem, or (b) enter WILT/DEAD stage and respawn at
SPROUT after DEAD duration? Recommendation: add `respawn_on_death: bool` to
HexPlantData. Active defense plants default `respawn_on_death = true`.

**Q3: Grass rendering granularity.** Individual grass "plants" (one per cell) are a
logical layer. Visually, should damaged/dead grass cells show differently in the grass
multimesh, or is that overkill for this stage? Recommendation: pass `health_remaining`
as a shader parameter (like thirst), desaturating/browning the grass tile as it takes
damage. Dead grass cells (stage == DEAD) suppress grass rendering entirely.

---

## 11. Open Question Resolutions

### Q1 — Tree permanence

`is_permanent` stays on `HexGridObjectDef` (already there). Meaning: the object
cannot die or be destroyed by any means — not combat, not events, not lifecycle.
Currently `HexTreeDef._init()` hardcodes it to `true`. Remove that hardcoded default.

**New authoring rule:**
- Regular trees: `is_permanent = false`, `max_fruit_cycles = 999`
  → Near-infinite lifecycle; can be felled by a bear ability in the future.
- Giant royal trees: `is_permanent = true`
  → Cannot be destroyed under any circumstances.

`HexWorldSimulation._apply_wilt_rule` already checks nothing when `is_permanent` is
true (existing path). No logic change needed — just remove the hardcoded `true` in
`HexTreeDef._init()` and update the authored `.tres` files.

---

### Q2 — Active defense plant death / seed respawn

No `respawn_on_death`. Instead, add to `HexPlantData`:

```gdscript
## If > 0, when this plant dies while it has produced seeds (reached FRUITING
## at least once this lifecycle), roll this chance to place a SPROUT in the
## same slot instead of clearing. 0.0 = no chance. Active defense plants
## default ~0.25 so they can persist without undermining breeding.
@export var seed_respawn_chance: float = 0.0
```

The check in `HexWorldState._kill_plant(slot_key)`:
```
if pd.seed_respawn_chance > 0.0 and state.fruit_cycles_done > 0:
    if randf() < pd.seed_respawn_chance:
        _spawn_sprout_in_slot(slot_key, def.id, null, slot_key.xy, slot_key.xy)
        return   # no gem drop — the plant "seeded itself"
# else: clear_slot, try item gem drop
```

This preserves the farming tension: you must actively collect/store seeds to guarantee
a defense plant's survival. The seed_respawn_chance is a safety net, not a guarantee.

---

## 12. Cell Slot System

### Overview

Every hex cell is divided into **6 triangular plant slots** (numbered 0–5). Each slot
is the triangle formed between the cell centre and one edge of the hex. Plants — grass
included — occupy one slot. Trees occupy all six. Rocks occupy 1–4 depending on size.

This replaces the current system where:
- Plants = one occupant per cell (origin + multi-cell footprint)
- Grass = separate decorative multimesh, no logical representation

After this change: every visible plant is a logical entity with health, lifecycle,
genes, and a slot address. The grass multimesh is retired. Grass renders via the
existing plant shader with a grass-specific material.

---

### Slot geometry

Following the NDIRS convention already used by HexChunk:

```
NDIRS = [(1,0), (0,1), (-1,1), (-1,0), (0,-1), (1,-1)]
```

Slot K corresponds to the triangular region between the hex centre and the edge facing
NDIRS[K]. The visual centroid of slot K (used as the base offset for plant placement):

```gdscript
static func slot_centroid_offset(slot: int) -> Vector2:
	# Returns XZ offset from cell centre, in world units.
	# Each triangle's centroid = (centre + edge_midpoint) / 2
    # edge_midpoint is at HEX_SIZE * 0.5 * flat_direction(slot)
    const SLOT_DIRS: Array[Vector2] = [
        Vector2( 0.866,  0.0  ),   # slot 0  → +q direction
        Vector2( 0.433,  0.75 ),   # slot 1
        Vector2(-0.433,  0.75 ),   # slot 2
        Vector2(-0.866,  0.0  ),   # slot 3
        Vector2(-0.433, -0.75 ),   # slot 4
        Vector2( 0.433, -0.75 ),   # slot 5
    ]
    return SLOT_DIRS[slot] * HexConsts.HEX_SIZE * 0.38
    # 0.38 ≈ centroid distance from centre for a regular hexagon triangle
```

A plant placed in slot K has its world position jittered within a radius of ~0.25 *
HEX_SIZE around its slot centroid, staying inside the triangle boundaries.

---

### Vector3i slot addressing

`HexWorldDeltaStore` changes its primary key from `Vector2i` to `Vector3i`:

```
Vector3i(q, r, slot)   where slot = 0..5
```

**Single-slot plants (grass, resource, defense):**
Stored at `Vector3i(q, r, K)` where K is their assigned slot.

**Multi-slot objects (trees: 6, large rocks: 2–4):**
Stored once at `Vector3i(q, r, 0)` — the "anchor slot."
`HexGridObjectDef.slots_occupied: int` declares how many contiguous slots (starting
from 0) this object blocks. Trees have `slots_occupied = 6`.
The query layer treats slots 1..slots_occupied-1 as occupied by the anchor.

**Multi-cell footprints (trees spanning more than one cell):**
The anchor slot `Vector3i(origin_q, origin_r, 0)` holds the full delta.
Satellite cells: occupancy dict maps `Vector3i(sat_q, sat_r, K)` → anchor slot key,
for all K in 0..5. Satellite cells have no delta of their own.

**Serialization key:** `"%d,%d,%d"` instead of `"%d,%d"`.

---

### HexWorldDeltaStore migration

```gdscript
# BEFORE:
var deltas:    Dictionary = {}   # Vector2i  → HexCellDelta
var occupancy: Dictionary = {}   # Vector2i  → Vector2i (sat → origin)

# AFTER:
var deltas:    Dictionary = {}   # Vector3i  → HexCellDelta
var occupancy: Dictionary = {}   # Vector3i  → Vector3i  (sat_slot → anchor_slot)
```

Key methods change signature:
```
get_delta(Vector2i)              → get_delta(Vector3i)
set_delta(Vector2i, delta)       → set_delta(Vector3i, delta)
has_delta(Vector2i)              → has_delta(Vector3i)
get_origin_for_cell(Vector2i)    → get_anchor_for_slot(Vector3i) → Vector3i
set_occupancy(origin, footprint) → set_occupancy(anchor_slot, cell_footprint, slots_occupied)
```

---

### HexWorldState API additions

```gdscript
# Get one slot's occupant.
get_slot(cell: Vector2i, slot: int) -> HexCellState

# Get all slot occupants for a cell (up to 6, nulls for empty slots).
get_cell_occupants(cell: Vector2i) -> Array[HexCellState]  # always length 6

# Legacy compatibility — returns the first occupied slot (slot 0 preferred).
# Existing callers (Bee.interact etc.) continue to work via this path during migration.
get_cell(cell: Vector2i) -> HexCellState   # kept; internally calls get_slot(cell, 0)
										   # for multi-slot objects, or first occupied
```

`HexCellState` gains `slot_index: int = -1` so callers know which slot they got.

---

### HexGridObjectDef additions

```gdscript
## Number of contiguous slots (starting from slot 0) this object occupies.
## 1 = single plant. 6 = full cell (tree). 2-4 = various rock sizes.
## Plants in PlantSubcategory.GRASS/RESOURCE/ACTIVE_DEFENSE/PASSIVE_DEFENSE = 1.
## HexTreeDef overrides this in _init() to 6.
@export var slots_occupied: int = 1
```

---

### Spreading and pollen priority

Both systems gain a same-cell-first preference:

**Spreading (`_find_sprout_slot`):**
1. Check all 6 slots in the parent's own cell — pick a random empty one if available.
2. If cell is full, fall through to adjacent cells (existing `_find_sprout_cell` logic).

**Pollen (`attempt_cross_sprout`):**
1. Check plants in the same cell for cross-pollination first.
2. Fall through to `base_pollen_radius` ring search if no compatible same-cell partner.

---

### Grass rendering migration

The decorative grass multimesh (`_generate_grass()` in HexChunk) is **retired**.

Grass is now rendered exactly like resource plants:
- GrassDef has `plant_subcategory = GRASS`
- Grass plants share the resource plant MultiMesh pipeline
- A grass-specific `Material` overrides the shader's atlas parameters for the grass
  quad/blade mesh (simple single-quad geometry, not the complex flower/stem/fruit atlas)
- `HexBiome.has_grass` and `grass_density_threshold` now drive the BASELINE GENERATION
  of GrassDef plants into cell slots, not the multimesh system

**Visual parity with old system:**
Up to 6 grass blades per cell = up to 6 GrassDef plants per cell (one per slot).
The "density" concept moves from visual multimesh count to logical slot fill rate.

---

### Damage visual feedback (for next session)

Two visual responses to plant damage:

**1. Bounce animation on hit:**
The existing `trigger_plant_bounce(cell)` in HexChunk writes a timestamp to
`custom_data.a` which the shader reads as a wobble time. This already works for
resource plants. Extend to grass by:
- Using the same custom_data.a channel in the grass-as-plant pipeline
- `HexWorldState.damage_plant()` calls `trigger_plant_bounce(cell)` after writing the delta

**2. Damage browning:**
Pass `health_fraction` (from `HexCellState.get_health_fraction()`) as a shader COLOR.r
channel (currently used for `thirst`). Two options:
- Share the `thirst` channel (browning = damaged OR thirsty — same visual)
- Add a second channel (COLOR.g = damage browning, COLOR.r stays as thirst)
Recommend: separate channels. Thirst desaturates; damage browns/reddens. Distinct reads.

**3. Color flash on hit:**
Add `custom_data.b` as a "last hit time" channel, separate from bounce (custom_data.a).
Shader lerps toward a `hit_color` (configurable per-material, e.g., red for damage,
white for freeze) based on `exp(-k * (engine_time - last_hit_time))`.
This works for all plants including grass with zero per-plant overhead.

---

### Baseline generation changes (deferred to implementation session)

`HexWorldBaseline._generate_cell` currently assigns one object per cell.
After the slot migration:
1. Generate large objects first (trees, rocks) — they claim all/multiple slots.
2. Fill remaining slots with resource plants per biome definition.
3. Fill any remaining empty slots with GrassDef instances per `grass_density_threshold`.

This means `HexTerrainConfig` needs a way to declare "slot fill order" per biome —
probably a simple priority list of object defs with their fill chance.

---

### Files affected by slot migration (implementation session)

| File | Change |
|------|--------|
| `hex_world_delta_store.gd` | All keys Vector2i → Vector3i; serialization format update |
| `hex_world_simulation.gd` | `get_cell` → `get_slot`; multi-slot query logic |
| `hex_world_state.gd` | New `get_slot`, `get_cell_occupants`; `damage_plant` uses slot key |
| `hex_world_baseline.gd` | Slot-aware cell generation; grass into slots |
| `hex_chunk.gd` | Retire `_generate_grass()`; render all plants through single pipeline; slot-aware `_plant_instance_map` |
| `hex_cell_state.gd` | Add `slot_index: int` (data model — already in outputs) |
| `hex_grid_object_def.gd` | Add `slots_occupied: int` (data model — already in outputs) |
| `hex_tree_def.gd` | `_init()` sets `slots_occupied = 6`, removes `is_permanent = true` |
| `collect_ability_def.gd` | `valid_categories` → `valid_plant_subcategories` |
| `bee.gd` | `interact()` — `state.category == RESOURCE_PLANT` → `plant_subcategory == RESOURCE` |
| `grasshopper.gd` | Remove manual `_bite_plant`; use `DamagePlantAbilityDef` executor |
