# BeezWorx MVP Spec: Exploration / Discovery System

This document specifies how the player discovers the world beyond their starting
territory — new biomes, new plant species, new faction encounters, and new recipe
ingredients. It defines the soft boundary system, exploration incentives, the fog
of war model, biome-specific discovery rewards, and how discovered content persists
in the colony's knowledge base.

---

## Purpose and scope

Exploration in BeezWorx is not about mapping a world — it is about finding things
worth bringing back. New plants with new chemistry. New creatures with new services.
New structural materials for new hive anchors. The world generates infinitely but the
player's colony is anchored to a territory. Exploration is the mechanism by which the
colony's knowledge and resources grow beyond what its home biome can provide.

This spec covers:
- What the player discovers through exploration
- The fog of war model (map reveal)
- Soft boundaries: how danger scales with distance from territory
- The queen as the primary explorer
- Scout bees: extending remote awareness
- Biome-specific discovery rewards
- How discoveries are recorded in ColonyState
- The plant discovery pipeline: find → bring sample → experiment
- Exploration incentives without mandatory requirements

It does **not** cover: the full world generation system (World/Hex/Chunk spec), biome
terrain generation (HexTerrainConfig), or faction encounter mechanics (Diplomacy spec).
Those systems define what exists to be found; this spec defines how finding it works.

---

## What exploration discovers

There are four categories of discoverable content:

### 1. Plant species

The most important discovery category. Different biomes have plants with different
chemistry channel profiles. A plant native to a cold biome produces high `N_cool`
nectar. A plant native to a dry rocky biome produces high `N_fortify` nectar. The
player cannot access these chemistry profiles without visiting those biomes.

Discovery happens by entering a biome cell where a plant species grows that is not
yet in `ColonyState.known_plants`. The queen's `InteractionDetector` triggers when
she passes within range of an unfamiliar plant:

```
func _on_new_plant_detected(cell: Vector2i, state: HexCellState) -> void:
    if ColonyState.knows_plant(0, state.object_id):
        return
    # Discovery notification fires
    EventBus.plant_discovered.emit(0, state.object_id, cell)
    ColonyState.add_known_plant(0, state.object_id)
```

**Discovery does not automatically unlock the plant for cultivation.** The queen knows
it exists and can see it. To use it she must gather its nectar or pollen and
experiment with it in a hive slot. The recipe discovery system handles the rest.

**Any pawn can discover plants** — foragers returning from a distant patch, gardeners
pollinating near the territory edge. But the queen gets a wider detection radius
(`discovery_radius` on SpeciesDef, larger for the queen) so she is the most efficient
explorer.

### 2. Faction NPCs

Finding a faction NPC for the first time triggers `EventBus.faction_first_contact`.
This records `first_contact_day` on `FactionRelation` and enables faction-specific
dialogue. The player does not need to interact — merely approaching within detection
range counts as first contact.

First contact with a faction unlocks their ambient dialogue in the world. Before first
contact, the faction NPC is present but silent (no speech bubbles, no interaction
prompt). After first contact, they speak and the interaction prompt appears.

### 3. Structural materials

Some hive anchor types (cacti, large mushrooms, specific rock formations) only appear
in specific biomes. The player discovers these as potential hive anchor sites by
entering the biome. Once discovered, the `BUILD_HIVE` marker can be placed on that
anchor type anywhere in range.

### 4. Recipe ingredients

Some items only drop in specific biomes:
- `mushroom_toxin` — fungal biome only
- `pollen_hearty` — savanna/grassland biome only
- `tree_resin` variants — specific tree species in specific biomes

The player discovers ingredient availability by finding the source plant or structure.
The item then appears as a known ingredient in the recipe discovery system.

---

## Fog of war model

### What is revealed

BeezWorx uses a **partial fog of war** — the terrain generates fully (visible from
above) but cell-level content (plants, structures, faction NPCs) is hidden until a
pawn has entered within `reveal_radius` of the cell.

```
# On HexCellState — runtime only, not saved to delta store:
var is_revealed: bool = false
```

Revealed state is stored per-cell in a `Dictionary[Vector2i, bool]` on a
`FogOfWarSystem` node (scene-owned, not autoload). It persists across sessions via
save/load.

### What fog looks like

Unrevealed cells show:
- Terrain mesh at full quality (the terrain is always visible — the shape of the
  world is not hidden)
- No plant meshes or object meshes
- No faction NPCs
- A subtle desaturation/greying of the terrain color to distinguish from revealed cells

The player can see the shape of the world from above — they know there is a forest
over there, a mountain range in that direction. They cannot see what lives in it until
they go there.

This is intentional: the player can make strategic decisions about where to explore
(heading toward the forest biome they can see) without being blind to the world's
shape. It rewards exploration without punishing navigation.

### Reveal radius

Each pawn reveals cells within their `reveal_radius` as they move:

```
# On SpeciesDef:
@export var reveal_radius: int = 3   # hex cells revealed as pawn moves through world
```

The queen has `reveal_radius = 5` — she is a better explorer than workers. Scout bees
(see below) have `reveal_radius = 8`.

Revealed cells are never re-hidden — once seen, always seen.

---

## Soft boundaries: danger scaling with distance

The world does not have hard edges. It has escalating danger that makes very distant
exploration increasingly costly without making it impossible.

### Distance tiers from territory

```
# Distance is measured from the nearest cell with colony influence > 0
enum ExplorationZone {
    TERRITORY,      # within own territory: safe
    FRONTIER,       # 1-10 cells beyond territory edge: slightly elevated threat
    WILDERNESS,     # 11-30 cells beyond: meaningful threat; escort recommended
    DEEP_WILDERNESS, # 31-60 cells beyond: serious threat; solo queen is risky
    UNKNOWN,        # 61+ cells beyond: extreme threat; likely death without preparation
}
```

### Threat scaling per zone

`ThreatDirector` uses the pawn's current zone when computing random hostile encounter
chance:

| Zone | Hostile encounter chance | Group size | Pawn types |
|---|---|---|---|
| TERRITORY | 0% | — | — |
| FRONTIER | 5%/min | 1–2 | insects only |
| WILDERNESS | 15%/min | 2–4 | insects + small predators |
| DEEP_WILDERNESS | 30%/min | 3–6 | any type including large animals |
| UNKNOWN | 50%/min | 4–8 | apex threats; birds more aggressive |

These are per-minute probabilities for any pawn in that zone. The queen exploring
alone in DEEP_WILDERNESS faces a 30% chance of encountering a hostile group every
real minute. This is designed to feel dangerous — not impossible — and to strongly
encourage the player to bring escort soldiers or allies on long expeditions.

### Bird zone and altitude

Altitude danger does not scale with distance from territory. Birds are always present
above the canopy threshold regardless of location. However, birds in distant zones are
slightly more aggressive (lower detection threshold by -20% in DEEP_WILDERNESS and
UNKNOWN zones) — the wilder the territory, the less tolerance wildlife has for intruders.

### Climate hazards as soft limits

Cold biomes, hot biomes, and extreme elevation biomes function as natural soft barriers
that require specific preparations:
- Cold biome: queen needs `spicy_jelly` buff active before entering
- Hot biome: queen needs `cool_jelly` buff before entering
- Extreme elevation: wind speed increases fatigue rate; no direct counter at MVP

These hazards are not instant death — they are manageable with preparation. The player
who discovers a cold biome by scouting and returns prepared (having crafted appropriate
jelly) gets to explore it fully. The player who stumbles in unprepared learns the lesson
the hard way.

---

## The queen as primary explorer

The queen is the best explorer in the colony for several reasons:

- Largest `reveal_radius` (5 cells) of any bee pawn
- Largest `alert_radius` (6 cells) — spots threats earlier
- Highest `max_health` — can survive encounters workers cannot
- Contextual abilities allow her to interact with anything she discovers
- Only she can perform first-contact diplomacy with new factions

But she is also the most important pawn to keep alive. This tension — queen is the
best explorer but also the one who cannot die — is intentional. The player must choose:
send the queen to explore (best results, highest risk) or send workers/scouts (slower
discovery, lower risk).

### Queen safety during exploration

If the player possesses a different pawn while the queen is outside a hive:
- Queen AI posts `NAVIGATE_HOME` immediately (see Pawn spec)
- Queen travels to and enters the nearest hive
- She stays inside until the player switches back to her

If the player is controlling the queen and switches to another pawn while the queen
is in a dangerous zone:
- The queen AI still navigates home
- But the transition takes time — the queen is vulnerable during the journey
- Players who switch away carelessly in hostile territory may find their queen took
  damage or died during the uncontrolled trek home

This creates a realistic consequence without locking the player into possessing the
queen during exploration.

---

## Scout bees

Scout bees are a specialist role (`role_id = "scout"`) that extend the colony's
awareness without requiring the queen.

### Scout abilities

- `reveal_radius = 8` — best of any pawn
- `alert_radius = 10` — spots threats very early
- Low `carry_weight` capacity — scouts travel light; they are not gatherers
- **Remote command support:** each living scout bee enables one remote marker command
  from the colony management menu (see Job/Marker spec)

### Scout AI behavior

Scout AI fallback (when no job): fly outward from territory edge, following the
`curiosity` personality trait direction bias. Curious scouts range further; stubborn
scouts patrol closer to familiar territory. Scouts automatically reveal cells and
log any new plant species they encounter back to `ColonyState.known_plants`.

Scouts do not gather. If they encounter a new plant, they note it (`EventBus.plant_discovered`)
and continue. The queen or a forager must follow up to actually collect from the plant.

### Scout limits at MVP

At MVP, scouts are not a dedicated egg-fed role — they are a specialisation path.
A forager can be assigned the "scout" role tag by the player via the hive slot
assignment UI, which modifies their AI behavior profile but does not change their
physical capabilities. Post-MVP, a distinct scout caste with unique morphology is
planned.

---

## Biome-specific discovery rewards

Each biome has a discovery reward profile — what the player gains from being the
first to send a pawn into it. Rewards are logged in `ColonyState.discovered_biomes`.

```
# On HexBiome resource:
@export var discovery_reward:    BiomeDiscoveryReward

class BiomeDiscoveryReward:
    var unique_plants:       Array[StringName]  # plant ids that only grow here
    var unique_materials:    Array[StringName]  # item ids that drop here
    var faction_encounters:  Array[StringName]  # faction_ids found here
    var hive_anchor_types:   Array[StringName]  # anchor categories available
    var narrator_line:       String             # documentary narrator line on discovery
```

The `narrator_line` is delivered as an ambient audio/subtitle line when the queen first
enters a new biome type. Quiet, rare, atmospheric. This is the documentary feel
described in the original game vision.

Examples:

**Forest biome (starting biome):** No narrator line — the player starts here.

**Wetlands biome:** "Beyond the treeline, the ground softens. New flowers grow where
standing water meets light." → `N_cool` and `P_medicine` plants. Sundew finds ideal
conditions here. Frog faction encounter (post-MVP).

**Rocky highlands biome:** "The stone here is old. Plants that survive do so through
stubbornness, not abundance." → `N_fortify` plants, `P_mineral` pollen, large rock
pile hive anchor opportunities.

**Fungal grove biome:** "The mycelium network runs deep. What grows here has learned
to take rather than give." → `mushroom_toxin`, `toxin_spore` in abundance, exotic
active plant variants with high toxicity.

**Arid scrubland biome:** "Dry air, sparse blooms, long distances between water. Only
the most vigorous plants survive." → `N_vigor` nectar, `pollen_hearty` from tough grasses.
Beetle faction more likely here.

---

## The plant discovery pipeline

Finding a plant is the beginning, not the end. The full pipeline:

```
1. Queen (or scout) enters biome → new plant detected → ColonyState.add_known_plant
2. Queen (or forager with marker) gathers nectar/pollen from the new plant
3. Items land in hive storage: new nectar_[biome_variant] or pollen_[biome_variant]
4. Queen experiments in crafting slot → discovers new honey variant recipe
5. New honey → possible new diplomatic ingredient → new faction relations
6. Player breeds new plant into territory → permanent access without long expeditions
```

Step 6 (breeding into territory) is the long-term payoff of exploration. A plant
found in the fungal grove can be propagated near the hive over multiple generations
until a stable local line exists. The colony no longer needs to send expeditions for
`mushroom_toxin` — it grows next door.

This pipeline gives exploration a clear long-term return: not just "I saw a cool place"
but "I now have access to chemistry that changes what I can produce permanently."

---

## Exploration incentives without mandatory requirements

The player is never forced to explore. The starting biome provides enough resources
to build a functional colony. But exploration provides:

- Access to chemistry profiles impossible in the starting biome
- Diplomatic contacts that unlock logistics, defense, and earthmoving
- Structural anchor types that expand where hives can be built
- Recipe ingredients that enable Tier 2 crafting beyond starting materials
- Map knowledge for strategic planning (seeing rival colony locations)

These are all meaningful improvements that compound over time. A player who never
explores can survive. A player who explores gains substantial advantages. The game
rewards curiosity without punishing players who prefer to consolidate.

### The pull toward exploration

Several systems create natural pull without requiring exploration:

- Alliance decay on key factions (bear, ant queen) requires regular gifts; if the
  starting biome cannot produce the right chemistry, the player must either explore
  or lose the alliance
- Worker aging creates periodic demand for new roles; some roles (soldiers) need
  specific ingredients (`mushroom_toxin` for paralyzer stingers) that require
  expeditions
- Rival colony expansion means eventually a rival pushes toward the player's territory;
  understanding the world layout helps strategic response
- The queen's personal curiosity (modelled through the "explorer" documentary feel)
  creates narrative motivation even when mechanical motivation is absent

---

## ColonyState discovery tracking

```
# On ColonyData:
var known_plants:     Array[StringName]   # plant object_ids the colony has encountered
var known_items:      Array[StringName]   # item_ids the colony has held at least once
var discovered_biomes: Array[StringName]  # biome_ids the colony has entered
var known_anchor_types: Array[StringName] # anchor categories the colony has built on

# Discovery events:
EventBus.plant_discovered(colony_id, plant_id, cell)
EventBus.biome_discovered(colony_id, biome_id, entry_cell)
EventBus.faction_first_contact(colony_id, faction_id, cell)
EventBus.item_discovered(colony_id, item_id)   # fires when item first enters colony inventory
```

Discovery records are saved as part of `ColonyState.save_state()`.

---

## FogOfWarSystem

Scene-owned node. Owns the per-cell revealed state and updates it as pawns move.

```
class_name FogOfWarSystem
extends Node

var _revealed:    Dictionary[Vector2i, bool]   # cell → revealed

func reveal_around(cell: Vector2i, radius: int) -> void:
    for c in HexWorldBaseline.hex_disk(cell, radius):
        if not _revealed.get(c, false):
            _revealed[c] = true
            EventBus.cell_revealed.emit(c)

func is_revealed(cell: Vector2i) -> bool:
    return _revealed.get(cell, false)
```

`EventBus.cell_revealed` is consumed by `HexChunk` to enable plant/object mesh
rendering for that cell. Before revelation, plant multimesh instances at that cell
have their visibility disabled via instance custom data (a shader-readable flag).

### Performance

`FogOfWarSystem.reveal_around` runs every time a pawn moves to a new cell. With 150
pawns, that is at most 150 calls per second, each iterating at most `π × radius²` ≈ 78
cells (radius 5). Most of those cells are already revealed after the early game. The
check is a dictionary lookup — fast.

The `_revealed` dictionary grows over time as the player explores. With cells being
Vector2i, each entry costs ~40 bytes. At 10,000 explored cells (a large explored area)
that is 400KB — negligible.

---

## Save / load

`FogOfWarSystem` saves and loads `_revealed`:

```
func save_state() -> Dictionary:
    var cells = []
    for cell in _revealed:
        cells.append([cell.x, cell.y])
    return {"revealed_cells": cells, "schema_version": 1}

func load_state(data: Dictionary) -> void:
    _revealed.clear()
    for pair in data["revealed_cells"]:
        _revealed[Vector2i(pair[0], pair[1])] = true
```

On load, all revealed cells are registered immediately. `HexChunk` reads `FogOfWarSystem.is_revealed`
during `finalize_chunk` to determine which plant instances to show. No per-frame fog
computation needed after load.

---

## MVP scope notes

Deferred past MVP:

- Scout caste as a distinct egg-fed role with unique morphology.
- Expedition system: player formally dispatches a scout group on a multi-day
  autonomous expedition with a target biome; receives report on return.
- Landmark discovery: unique named locations (ancient abandoned hive, giant lone
  tree, crystal cave) with specific rewards and narrative lines.
- Dynamic fog: fog partially returns to areas abandoned for a long season (plants
  change, new creatures move in). At MVP revealed is permanent.
- Multiplayer fog sharing: all players share the same revealed map.
