# BeezWorx MVP Spec: Territory System

This document specifies `TerritorySystem`, the per-cell influence model, hive radius
projection, territory fade after hive destruction, overlap rules, allegiance effects
on active plants, and the new-hive placement constraint. It is the authoritative
reference for all territory-related queries and mutations.

---

## Purpose and scope

Territory is the colony's claim on the world. It determines where markers stay alive,
where allied plants behave as allies, where rival colonies exert pressure, and how
far from existing infrastructure new hives may be placed.

This spec covers:
- The influence field model (per-cell, per-colony float values)
- Radius projection from hives
- Overlap rules (union of radii)
- Territory fade after hive destruction (unique vs overlapped cells)
- New hive placement constraint (must connect to existing territory)
- Allegiance: how territory level affects active plant behavior
- The query API used by all other systems
- EventBus integration and save/load

It does **not** cover: hive construction mechanics (HiveSystem), marker decay
(JobSystem), pawn loyalty decay from lost beds (ColonyState), or combat/raid spawning
(Combat spec). Those systems consume territory queries; this system only manages the
influence field.

---

## Influence model

### Per-cell influence

Each hex cell stores influence values per colony as a float in the range 0.0–1.0.

```
_influence: Dictionary[Vector2i, Dictionary[int, float]]
# cell → {colony_id: influence_value}
```

Influence of 1.0 means the cell is fully within that colony's territory. Influence of
0.0 means the colony has no claim. A cell can have non-zero influence from multiple
colonies simultaneously (contested cells).

**Influence is not a smooth gradient at MVP.** It is step-valued:

| Distance from nearest hive (hex cells) | Influence value |
|---|---|
| 0 to `territory_radius - 2` | 1.0 (core territory) |
| `territory_radius - 1` | 0.6 (border territory) |
| `territory_radius` | 0.3 (fringe territory) |
| > `territory_radius` | 0.0 (outside) |

The step values produce a visible soft edge at the territory boundary without the cost
of computing a true distance field. They are tunable constants on `TerritoryConfig`.

This model is intentionally simple. Post-MVP it can be replaced with a true signed
distance field or a pheromone diffusion simulation without changing the query API.

### Controlling colony

A cell's **controlling colony** is the colony with the highest influence at that cell.
Ties are broken by colony_id (lower id wins — player colony 0 always wins ties).

```
func get_controlling_colony(cell: Vector2i) -> int   # -1 if no colony has influence
func get_influence(cell: Vector2i, colony_id: int) -> float
func is_in_territory(cell: Vector2i, colony_id: int) -> bool  # influence > 0.0
func get_all_colonies_at(cell: Vector2i) -> Array[int]  # colonies with influence > 0
```

---

## Radius projection

When a hive is built, `TerritorySystem` receives `EventBus.hive_built` and projects
influence outward from the anchor cell using `HexWorldBaseline.hex_disk`.

```
func _project_hive_influence(hive_id: int) -> void:
    var hive: HiveState = HiveSystem.get_hive(hive_id)
    var radius: int = hive.territory_radius
    var colony_id: int = hive.colony_id

    for cell in HexWorldBaseline.hex_disk(hive.anchor_cell, radius):
        var dist: int = _hex_distance(hive.anchor_cell, cell)
        var influence: float = _influence_at_distance(dist, radius)
        _set_influence(cell, colony_id, influence, hive_id)
```

`_set_influence` sets the value only if it is **higher** than the current value for
that colony at that cell. This implements the union-of-radii rule: overlapping hive
radii reinforce rather than overwrite each other. A cell's influence for a colony is
always the maximum contributed by any of that colony's hives.

```
func _influence_at_distance(dist: int, radius: int) -> float:
    if dist <= radius - 2:   return 1.0
    elif dist == radius - 1: return 0.6
    elif dist == radius:     return 0.3
    else:                    return 0.0
```

### Per-cell hive contribution tracking

To support correct fade behavior, `TerritorySystem` tracks which hives contribute to
each cell:

```
_cell_contributors: Dictionary[Vector2i, Dictionary[int, float]]
# cell → {hive_id: influence_contributed}
```

This is the inverse of the influence field. When a hive is destroyed, we can quickly
find all cells it contributed to without scanning the entire influence dictionary.

```
_hive_cells: Dictionary[int, Array[Vector2i]]
# hive_id → [cells this hive contributes to]
```

Both structures are updated together in `_set_influence`.

---

## Territory fade after hive destruction

When `EventBus.hive_destroyed` is received:

```
func _on_hive_destroyed(hive_id: int, anchor_cell: Vector2i, colony_id: int) -> void:
    var cells: Array[Vector2i] = _hive_cells.get(hive_id, [])
    _register_fade(hive_id, colony_id, cells)
```

### Fade registration

```
class FadeRecord:
    var hive_id:    int
    var colony_id:  int
    var cells:      Array[Vector2i]   # cells this hive was contributing to
    var timer:      float             # seconds remaining; starts at FADE_DURATION

_active_fades: Dictionary[int, FadeRecord]   # hive_id → FadeRecord
```

`FADE_DURATION` is configurable (default: 120 seconds — 2 in-game minutes at normal
time scale).

### Fade tick

`TerritorySystem._process` runs a fade pass once per second:

```
func _fade_tick(delta: float) -> void:
    for hive_id in _active_fades:
        var rec: FadeRecord = _active_fades[hive_id]
        rec.timer -= delta

        if rec.timer <= 0.0:
            _apply_fade(rec)
            _active_fades.erase(hive_id)
```

### Fade application (the overlap rule)

`_apply_fade` is where the "overlapped cells stay, unique cells fade" rule is enforced:

```
func _apply_fade(rec: FadeRecord) -> void:
    var faded_cells: Array[Vector2i] = []

    for cell in rec.cells:
        # Remove this hive's contribution from the cell
        if _cell_contributors.has(cell):
            _cell_contributors[cell].erase(rec.hive_id)

        # Recompute influence for this colony at this cell from remaining contributors
        var new_influence: float = 0.0
        if _cell_contributors.has(cell):
            for other_hive_id in _cell_contributors[cell]:
                if HiveSystem.get_hive(other_hive_id).colony_id == rec.colony_id:
                    new_influence = maxf(new_influence, _cell_contributors[cell][other_hive_id])

        var old_influence: float = _influence.get(cell, {}).get(rec.colony_id, 0.0)
        _set_raw_influence(cell, rec.colony_id, new_influence)

        if new_influence < old_influence:
            faded_cells.append(cell)

    # Clean up hive tracking
    _hive_cells.erase(rec.hive_id)

    if not faded_cells.is_empty():
        EventBus.territory_faded.emit(rec.colony_id, faded_cells)
```

The result: cells that had overlap from other living hives retain their influence level.
Only cells whose sole contributor was the destroyed hive drop to zero (or to whatever
the remaining contributors provide).

### Partial fade (gradual visual effect)

For visual feedback during the fade timer countdown, `TerritorySystem` emits influence
reduction signals at intermediate steps (50% through timer → fringe cells drop to 0,
75% through → border cells drop, 100% → full application). This gives the player visible
warning that territory is collapsing before it fully fades.

```
func _update_fade_visuals(rec: FadeRecord, progress: float) -> void:
    # progress 0..1 through FADE_DURATION
    # At 0.5: set fringe cells (distance == radius) to 0 for this hive's colony
    # At 0.75: set border cells (distance == radius-1) to 0
    # At 1.0: full _apply_fade()
```

Visual territory rendering reads from the influence field directly; the intermediate
reduction triggers a re-render of the territory overlay without permanently altering the
influence until full fade.

---

## New hive placement constraint

A new hive can only be built as part of the colony network. The BUILD_HIVE marker
placement validation (in `JobSystem.place_marker`) calls:

```
TerritorySystem.is_valid_expansion_cell(cell: Vector2i, colony_id: int) -> bool
```

```
func is_valid_expansion_cell(cell: Vector2i, colony_id: int) -> bool:
    # Rule: the cell must be within EXPANSION_REACH hex cells of any cell
    # that currently has influence >= 0.3 for this colony.
    # EXPANSION_REACH default: 3 hex cells beyond the current fringe.
    var reach: int = EXPANSION_REACH
    for neighbor in HexWorldBaseline.hex_disk(cell, reach):
        if get_influence(neighbor, colony_id) >= 0.3:
            return true
    return false
```

`EXPANSION_REACH` (default: 3) is the gap the player can bridge when placing a new hive.
This allows the player to deliberately extend a chain outward — each new hive expands
the reachable area for the next one — without allowing arbitrary teleport placement.

A cell that fails `is_valid_expansion_cell` will still accept the BUILD_HIVE marker
(the queen can place the physical marker anywhere she can reach), but the marker
immediately enters the territory decay countdown and the job will expire before a
carpenter can complete it unless the colony's territory expands to reach it first.
This creates interesting tension: the player can speculatively place markers to claim
future territory, but must expand to reach them before they decay.

---

## Allegiance and active plant behavior

Active defense plants (flytraps, whip vines, briars, etc.) check territory allegiance
to determine targeting. `TerritorySystem` exposes:

```
func get_plant_allegiance(cell: Vector2i, plant_colony_id: int) -> PlantAllegiance
```

```
enum PlantAllegiance {
    ALLIED,      # controlling colony matches plant's colony; attacks enemies only
    NEUTRAL,     # no colony controls this cell; attacks anything that triggers it
    HOSTILE,     # a rival colony controls this cell; may attack friendlies
    FERAL,       # plant's colony has fading/zero influence; erratic targeting
}
```

Allegiance determination:

```
func get_plant_allegiance(cell: Vector2i, plant_colony_id: int) -> PlantAllegiance:
    var influence: float = get_influence(cell, plant_colony_id)
    var controller: int = get_controlling_colony(cell)

    if influence <= 0.0:
        return PlantAllegiance.FERAL      # colony has no claim here at all

    if controller == plant_colony_id:
        if influence >= 0.6:
            return PlantAllegiance.ALLIED
        else:
            return PlantAllegiance.NEUTRAL  # fringe territory: plant is uncertain
    else:
        return PlantAllegiance.HOSTILE     # rival controls this cell
```

**FERAL behavior** (influence == 0, territory fully faded): plant attacks any creature
that enters its trigger radius regardless of species or colony. Flytraps snap up allied
ants. Whip vines swat passing bees. This is the ecological instability consequence of
losing territory.

**HOSTILE behavior** (rival controls cell): plant preferentially attacks the colony that
originally placed/cultivated it. This is the most dangerous state — your own defenses
become weapons against you.

**NEUTRAL behavior** (fringe territory, influence == 0.3): plant behaves like a wild
plant — attacks based on trigger mechanics only, no colony discrimination.

Active plant nodes query allegiance on their AI tick (same cadence as `_check_stale_plants`
in `HexChunk`). They cache the result and only re-query when `EventBus.territory_faded`
or `EventBus.territory_expanded` fires for their cell.

---

## Allied creature supply-line loyalty

When territory fades, allies that were being supplied through hives in that territory
may lose loyalty. `TerritorySystem` emits `EventBus.territory_faded(colony_id, cells)`
and `ColonyState` listens to check if any allied faction's supply hive was in those cells.
Full loyalty decay rules are in the ColonyState spec — `TerritorySystem` only emits the
event; it does not own faction loyalty.

---

## Territory visualisation hooks

`TerritorySystem` does not directly drive any visual rendering. It exposes a query API
that the terrain shader and UI minimap read from:

```
# Returns the influence value for rendering territory overlay on a cell
func get_render_influence(cell: Vector2i, colony_id: int) -> float

# Returns all influence entries for a cell (for multi-colony contested rendering)
func get_all_influence(cell: Vector2i) -> Dictionary[int, float]

# Returns cells within a radius that changed influence since last_check_time
# Used by the territory overlay renderer to do incremental updates
func get_changed_cells_since(world_time: float) -> Array[Vector2i]
```

`get_changed_cells_since` is backed by a `_recently_changed: Dictionary[Vector2i, float]`
(cell → world_time of last change). The renderer calls this each frame and only redraws
changed cells rather than the full visible territory.

---

## Territory upgrade integration

When `HiveSystem.apply_upgrade` applies a `TERRITORY_BEACON` upgrade, it calls:

```
TerritorySystem.expand_hive_radius(hive_id: int, new_radius: int) -> void
```

This re-projects influence with the new radius. Cells that gain influence emit
`EventBus.territory_expanded(colony_id, new_cells)`. Cells that were already covered
at a lower influence level get upgraded to the appropriate step value.

---

## EventBus integration

```
# Consumed by TerritorySystem:
EventBus.hive_built(hive_id, anchor_cell, colony_id)
    → _project_hive_influence(hive_id)
    → emit territory_expanded for newly covered cells

EventBus.hive_destroyed(hive_id, anchor_cell, colony_id)
    → _register_fade(hive_id, colony_id, cells)

EventBus.hive_upgraded(hive_id, upgrade_type_id)
    → if upgrade affects territory_radius: expand_hive_radius(hive_id, new_radius)

# Emitted by TerritorySystem:
EventBus.territory_expanded(colony_id, cells)   # cells that gained influence
EventBus.territory_faded(colony_id, cells)      # cells that lost influence
```

---

## Save / load

Territory influence is **not fully saved**. On load, it is recomputed from the hive
network. This keeps save files small and avoids stale influence data.

```
func save_state() -> Dictionary:
    # Save only active fade records (partially-faded territory in progress)
    var fades = []
    for hive_id in _active_fades:
        var rec: FadeRecord = _active_fades[hive_id]
        fades.append({
            "hive_id":   rec.hive_id,
            "colony_id": rec.colony_id,
            "timer":     rec.timer,
            # cells are not saved — recomputed from _hive_cells on load
        })
    return {"active_fades": fades, "schema_version": 1}

func load_state(data: Dictionary) -> void:
    # Step 1: full recompute from all living hives
    _recompute_from_hives()
    # Step 2: restore in-progress fades
    for f in data["active_fades"]:
        var hive_id: int = f["hive_id"]
        if _hive_cells.has(hive_id):   # hive was destroyed, cells still tracked
            var rec := FadeRecord.new()
            rec.hive_id   = hive_id
            rec.colony_id = f["colony_id"]
            rec.cells     = _hive_cells[hive_id]
            rec.timer     = f["timer"]
            _active_fades[hive_id] = rec

func _recompute_from_hives() -> void:
    _influence.clear()
    _cell_contributors.clear()
    _hive_cells.clear()
    for hive in HiveSystem.get_all_living_hives():
        _project_hive_influence(hive.hive_id)
```

---

## MVP scope notes

Deferred past MVP:

- True smooth influence gradient (distance field or pheromone diffusion). Current
  step model is intentionally simple and visually readable.
- Multi-colony contested territory UI (showing rival influence overlay distinctly).
- Territory pressure mechanics (high rival influence triggering passive effects on
  player colony morale before overt conflict).
- Neutral zone creatures responding to territory boundaries (animals that avoid high-
  influence territory, wild plants that behave differently at territory edges).
- Underground or vertical territory layers (canopy vs ground level distinction).
