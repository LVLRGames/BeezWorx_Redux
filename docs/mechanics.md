# BeezWorx Mechanics

> This document is a summary reference using the standard mechanic format.
> Full authoritative specs are in the outputs folder.

---

## Core 30-Second Loop

1. Possess a pawn (queen or worker)
2. Gather resources or pollinate plants
3. Craft products back at the hive
4. Trade with creatures or place job markers
5. Expand the colony

---

## Mechanic: Possession

**Player Action:** Hold pawn switch input to open the pawn switch panel. Select an
eligible colony member. Release to possess them.

**Eligibility:** Target must be alive, awake, in the player's colony, and not already
possessed by another player.

**Game Response:** `PawnAI` suspends and saves `ai_resume_state`. Player input routes
to the new pawn via `PossessionService`. Camera transitions to new pawn. HUD updates
to reflect new pawn's role and abilities.

**Possession boost:** Possessed pawn gains ~8% movement speed and ~5% action speed.
Targeting is player-precise rather than AI-nearest. Never displayed to the player.

**Failure Conditions:** Cannot possess enemy pawns. Cannot possess a pawn currently
possessed by another player. Queen can only be possessed by player slot 0 (host).

**Queen safety:** If player switches away from queen while she is outside a hive,
queen AI posts `NAVIGATE_HOME` immediately and enters the nearest hive.

**System Interactions:** `PossessionService`, `PawnAI`, `PawnAbilityExecutor`, `CameraRig`

---

## Mechanic: Command Markers (Pheromone Markers)

**Player Action:** Queen crafts a marker item (e.g. `marker_build_hive` from
`marker_base + plant_fiber`), then uses the `PLACE_MARKER` ability on a valid cell
within interaction range.

**Game Response:** Marker item is consumed from inventory. A world-visible marker node
spawns at the target cell. `JobSystem` registers the marker and generates appropriate
jobs. Workers with matching role tags can claim those jobs.

**Marker categories:**
- JOB markers generate worker jobs (build, gather, defend, graze)
- NAV markers modify navigation for specific species (ant conveyors, patrol routes)
- INFO markers are world labels — no job generated

**Failure Conditions:** Marker item not in inventory. Target cell doesn't match
`MarkerDef.valid_cell_categories`. `max_per_cell` already reached. Queen must be
within the target cell's XZ boundary for placement (or within 1–2 units for most
other marker types). Markers placed outside territory begin immediate decay.

**Speculative placement:** Markers can be placed beyond territory but will decay after
`MARKER_DECAY_DURATION` seconds (default 30s) unless territory expands to cover them.
This enables strategic forward planning.

**System Interactions:** `JobSystem`, `PawnAbilityExecutor`, `TerritorySystem`,
`ItemGemManager` (consumes marker item from inventory)

---

## Mechanic: Storage and Crafting Slots (Hive)

**Player Action:** Enter a hive via `ENTER_HIVE` ability. Hive interior overlay opens.
Select a slot. Assign designation, set craft order, or manage items.

**Game Response:** Slot designation changes take effect immediately. Craft orders post
a `CRAFT_ITEM` job to `JobSystem`. The crafter (or queen) who claims the job navigates
to the hive, sources materials via task planner, and crafts the item.

**Crafting does not happen automatically** — a crafter pawn or the queen must
physically work the slot. Crafters check hive slot orders during their fallback idle
behavior. The queen crafts faster than workers at discovering recipes but slower at
bulk production (longer craft times).

**Feedback:** Slot progress bar fills during crafting. Completed items appear in the
slot. Colony management Production tab shows estimated output rates.

**Failure Conditions:** No crafter pawn available or accessible. Required ingredients
not in colony inventory and no viable local source. Recipe not yet discovered.
Nursery slots only valid for princess eggs in capital hive.

**System Interactions:** `HiveSystem`, `JobSystem`, `ColonyState` (recipe validation),
`PawnAI` (crafter job claiming)

---

## Mechanic: Territory Fading

**Player Action:** Build new hives to expand territory, or fail to protect existing ones.

**Game Response:** Each hive projects a territory radius. Colony territory = union of
all hive radii. When a hive is destroyed, only cells with no overlap from living hives
fade — overlapped cells remain secure. Fade takes 120 seconds, giving visible warning.

**Feedback:**
- Ground cell colour shifts toward desaturated/grey as influence drops
- Active plants show red tint (`feral_tint` shader parameter) when going feral
- Notification: "Hive attacked!" / "Territory is fading"
- Markers placed in fading zone begin decay

**Failure Conditions (consequences of fade):**
- Active plants become NEUTRAL (fringe influence) then FERAL (zero influence) —
  attacking allied ants, bees, and player pawns indiscriminately
- Displaced bees lose bed slots → loyalty decay → possible abandonment
- Allied factions supplied through that hive's territory may lose loyalty
- Markers in the fading zone begin territory decay countdown

**System Interactions:** `TerritorySystem`, `HiveSystem` (via EventBus.hive_destroyed),
`JobSystem` (marker decay), `ColonyState` (loyalty/morale modifiers),
active plant nodes (allegiance re-query on `EventBus.territory_faded`)
