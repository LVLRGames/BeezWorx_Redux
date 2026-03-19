# BeezWorx MVP Spec: UI / HUD System

This document specifies every player-facing interface element, its data sources,
interaction model, visibility rules, and layout position. It is the authoritative
reference for `UIRoot` and all HUD, overlay, and management screen components.

---

## Purpose and scope

BeezWorx UI has one guiding principle: diegetic minimalism. Information appears in
the world when possible. When it must appear in a HUD element, it fades when not
needed and never overwhelms the ecological scene the player is inhabiting.

The UI must support: possessing and switching between pawns, managing hive slots,
monitoring colony health, navigating the world, reading active markers, and accessing
colony strategy — all without breaking the feeling of being a small creature in a
large living world.

This spec covers:
- UI philosophy and diegetic information principles
- HUD elements: layout, data sources, visibility rules
- Hive interior overlay: slot grid, slot panel, craft order UI
- Pawn switch panel
- Colony management screen
- Minimap and compass
- Interaction prompts and contextual button labels
- Notification system
- Visual style guidelines
- Input model

It does **not** cover: rendering of terrain, plants, or pawns (those are scene/shader
concerns), or the save/load menu (SaveManager spec).

---

## UI philosophy

### Diegetic first

Before adding a HUD element, ask: can the world communicate this instead?

Examples of diegetic information already specced:
- Plant thirst: desaturation shader on plant mesh (`thirst` value in HexCellState)
- Pawn age: greying of dark body segments on elder bees
- Territory fade: colour shift on ground cells as influence drops
- Active plant allegiance: subtle red tint on feral plants
- Faction mood: ambient dialogue lines shift tone before alliance breaks

HUD elements exist for information that cannot reasonably be communicated in-world:
inventory contents, slot designations, health numbers, navigation markers.

### Fade when idle

Every HUD element that is not actively in use fades to low opacity or hides entirely
after `UI_FADE_DELAY` seconds (default: 4 seconds of no relevant input or state change).
It reappears immediately on relevant input or state change.

This keeps the screen clear during normal movement and exploration while ensuring
information is always available when needed.

### Hexagonal shapes where possible

The UI uses hex-shaped panels, hex grid layouts, and hex-derived geometry wherever
it does not compromise readability. This is a visual identity decision — the game is
built on hex geometry and the UI should feel like it belongs to that world.

---

## HUD layout

```
┌─────────────────────────────────────────────────────┐
│  [PAWN CARD]        [COMPASS]          [SEASON/TIME] │
│                                                      │
│                                                      │
│                    WORLD VIEW                        │
│                                                      │
│                                                      │
│  [PAWN SWITCH]  [INVENTORY / CONTEXT]  [MARKER INFO] │
└─────────────────────────────────────────────────────┘
```

---

## HUD elements

### 1. Pawn card (top-left)

Displays the currently possessed pawn's core stats.

**Contents:**
- Portrait (species icon + role icon overlay)
- Name
- Health bar (hex-segmented; segments go dark as health drops)
- Fatigue indicator (small secondary bar or fill pattern on portrait border)
- Elder icon (if in warning window)
- Role tag
- Loyalty indicator (subtle — 5 small hex pips, filled by loyalty level)

**Visibility:** Always visible when possessing a pawn. Fades to 30% opacity during
extended stillness. Returns to full opacity on any input or stat change.

**Data source:** `PawnRegistry.get_state(possessed_pawn_id)`

**Update trigger:** Subscribes to `EventBus.pawn_hit`, fatigue changes (polled at
1Hz), `EventBus.pawn_loyalty_changed`

---

### 2. Compass (top-center)

Skyrim-style horizontal compass strip showing directional markers visible to the
current pawn.

**Contents:**
- Cardinal directions (N/S/E/W)
- Colony hives within detection range (hive icon, colour-coded by status)
- Active job markers the current pawn can claim (marker type icon)
- Faction NPCs within range (faction icon)
- Queen position if not currently possessing the queen (crown icon)
- Threat indicators if combat is nearby (red spike icon)

**Visibility:** Always visible. Fades when no markers are in range and no threats
are active.

**Data source:**
- `HiveSystem.get_hives_for_colony(colony_id)` — position and status
- `JobSystem.get_markers_for_colony(colony_id)` — visible markers
- `PawnRegistry.get_state(queen_pawn_id).last_known_cell` — queen location
- `ThreatDirector._active_threats` — threat positions

**Marker visibility rule:** A marker appears on the compass only if the current pawn's
role can claim jobs derived from it, or if it is a colony-wide marker (DEFEND, INFO).
A forager does not see BUILD_HIVE markers. This keeps the compass relevant rather than
noisy.

---

### 3. Season / time indicator (top-right)

A small compact display showing the current in-game time context.

**Contents:**
- Season icon (leaf for fall, snowflake for winter, flower for spring, sun for summer)
- Day of season (e.g. "Day 12 of 91")
- Day/night icon (sun or moon)
- Approximate time of day (visual only — a small arc indicator, not a clock number)

**Visibility:** Always visible at low opacity. Pulses briefly on day change and season
change.

**Data source:** `TimeService` directly

---

### 4. Pawn switch panel (left side)

A vertical list of colony members that appears when the player holds the pawn switch
input. Releases to hide.

**Trigger:** Hold `prev_pawn` or `next_pawn` input. Appears instantly on hold.
Disappears 0.5 seconds after release.

**Contents:**
- Scrollable vertical list of all living, awake, eligible-to-possess colony pawns
- Each entry: portrait icon, name, role icon, health bar (compact), elder icon if applicable
- Currently possessed pawn is highlighted
- Pawns currently possessed by another player (multiplayer) are greyed out with player
  icon overlay
- Pawns in unloaded chunks are shown with a "distant" indicator — selectable but camera
  transition will be slow
- Queen entry is always pinned at top of list regardless of scroll position

**Interaction:** While panel is open, directional input scrolls the list. Releasing
on a highlighted entry possesses that pawn. Pressing cancel closes without switching.

**Data source:** `PawnRegistry.get_pawns_for_colony(colony_id)` filtered to alive +
awake + eligible. Sorted: queen first, then by role group, then alphabetically.

**Elder indicator:** Pawns in warning window show a greyed-portrait overlay and a small
grey-segment icon beside their name. Not alarming — just visible.

---

### 5. Inventory / context panel (bottom-center)

Two-part panel showing what the current pawn carries and what the cell in front of
them contains.

**Left half — Pawn inventory:**
- Grid of inventory slots (capacity from `SpeciesDef`)
- Each slot: item icon, count, weight indicator
- Liquids show fill-level visual rather than count
- Empty slots shown as faint hex outlines
- Total carry weight bar beneath the grid

**Right half — Cell context:**
- If InteractionDetector has a valid target: shows target info
- For a plant cell: species name, current stage, nectar/pollen amount (bars), thirst level
- For a hive: hive name, integrity bar, slot count / occupied count
- For a faction NPC: faction name, relation indicator (5 pips), last gift info
- For an item gem: item name, count, "pick up" prompt
- For another pawn: name, role, health

**Visibility:** Inventory half is always visible when carrying items. Context half
appears when InteractionDetector has a valid target. Both fade when empty/no target.

**Action button labels:** Below the context panel, the current pawn's action and
alt-action labels update dynamically based on `InteractionDetector` results.
Examples: "Gather Nectar" / "Pollinate", "Talk to Bear" / "Offer Item",
"Enter Hive" / "Place Marker"

---

### 6. Marker info strip (bottom-right)

Shows active job markers that have been placed and their status.

**Contents:**
- List of up to 5 most recently placed markers by this colony
- Each entry: marker type icon, target cell indicator, job status (posted / claimed /
  executing), claimant name if claimed

**Visibility:** Only visible when markers exist. Fades when no markers are active.
Full marker list accessible through colony management screen.

---

### 7. Notification feed (right edge, below marker strip)

Transient notifications that appear and fade. Not a log — only the most recent 3
notifications are visible at once.

**Notification types and format:**

| Event | Notification text | Duration |
|---|---|---|
| Recipe discovered | "Recipe found: [Name]" | 4s |
| New plant discovered | "New plant: [Name]" | 3s |
| Alliance formed | "[Faction] is now allied" | 5s |
| Alliance breaking | "[Faction] is restless" | 6s |
| Hive under attack | "Hive attacked!" | Until resolved |
| Pawn died | "[Name] has died" | 4s |
| Elder pawn | "[Name] is getting old" | 3s |
| Queen in danger | "The queen is exposed!" | Until safe |
| Egg hatched | "[Role] has emerged" | 3s |

**Visual style:** Notifications slide in from the right, remain briefly, then fade out.
Critical notifications (Hive attacked, Queen in danger) have a distinct border colour
and do not auto-fade until acknowledged or resolved.

**No notification spam:** If the same notification type fires multiple times within
10 seconds, it updates the existing notification rather than creating a new one.
"Pawn died" shows the most recent death name but a count if multiple died.

---

## Hive interior overlay

When the player enters a hive (via `ENTER_HIVE` ability), the camera transitions to
a closer top-down view of the hive interior. The world is still visible in the
background but dimmed. The slot grid appears as an overlay.

### Slot grid

A 2D hex grid of slot nodes arranged in a honeycomb pattern.

**Layout:** Slots are arranged in concentric hex rings from a center point. The grid
expands as more capacity is added. If `slot_count` exceeds the visible area, the grid
is scrollable — the view pans to keep the selected slot centered.

**Each slot node shows:**
- Designation icon (bed, storage, crafting, nursery, general)
- Contents icon (item stack or egg or sleeping pawn icon)
- Contents count or status
- Assignment indicator (tiny pawn portrait if assigned to a specific pawn)
- Craft progress bar (if CRAFTING slot has an active order)

**Slot selection:** Mouse/cursor selects a slot. Gamepad uses directional input to
navigate between adjacent slots. Selected slot is highlighted with a hex outline glow.

### Slot panel

Opening a selected slot (confirm input) opens a panel beside the grid:

**For GENERAL / STORAGE slots:**
- Designation selector (change to bed / storage / crafting / nursery)
- Item lock selector (for STORAGE: restrict to item type; dropdown of known items)
- Contents list with remove/deposit options
- Assign pawn button (for BED slots)

**For CRAFTING slots:**
- Recipe selector (dropdown of known recipes filtered by slot's role context)
- Quantity input (how many to produce)
- Repeating toggle
- Current order status and progress
- Cancel order button

**For NURSERY slots:**
- Egg status (if occupied): days remaining, current role trajectory, last feed time
- Feed button (opens item selector for feeding; queen only)
- Role indicator (shows which role the current feed log is pointing toward)

**For BED slots:**
- Assigned pawn name (or "Unassigned")
- Re-assign button
- Current occupant status (sleeping / empty)

### Hive header

Above the slot grid, a persistent header shows:
- Hive name (editable — player can name their hives)
- Integrity bar
- Territory radius
- Applied upgrades list (compact icons)
- "Set as Capital" button (if this hive does not currently contain the queen's bed)
- Upgrade button (opens upgrade panel)

---

## Colony management screen

Accessible only from inside the capital hive. Opens as a full overlay replacing the
slot grid.

### Tabs

**Population tab:**
- Total population count
- Population by role (pie chart or hex grid of role icons)
- Elderly % indicator
- Heir count and egg status summary
- List of all pawns with name, role, age, loyalty, and health — sortable by column

**Production tab:**
- Per-hive production summary: honey output rate, wax, glue — all estimated from
  current orders and pawn counts
- Known recipe list with current stock levels
- Colony inventory aggregate (total of all items across all hives)

**Territory tab:**
- Minimap view of all hive locations and territory radii
- Contested cells highlighted
- Rival colony territory shown if within scouted range
- Hive integrity summary per hive

**Diplomacy tab:**
- All known factions with relation score, alliance status, days since last gift
- Gift interval warning indicator (how many days until decay begins)
- Trade history summary per faction

**Markers tab:**
- All active markers with type, cell, claimant, job status
- Cancel marker button per entry
- Remote command slots (scout bee count determines available slots)

---

## Minimap

A small hex-shaped minimap in the corner of the colony management screen (and
optionally accessible as a persistent small HUD element via toggle).

**Contents:**
- Revealed terrain (greyscale elevation map)
- Colony territory (soft colour overlay in colony hue)
- Rival territory (rival hue, only in revealed cells)
- Hive locations (dot per hive, colour by status: intact / damaged / destroyed-fading)
- Active markers (tiny icons)
- Queen position (crown icon, always shown even outside revealed area)
- Player's current position (pawn icon)
- Faction NPC locations (faction icon, only in revealed cells)

**Scale:** Minimap scale is adjustable (scroll to zoom). Default shows a 60-cell radius
around the colony center.

**Not a full world map at MVP.** The minimap shows explored areas only. A full world
map with strategic overlay is post-MVP.

---

## Interaction prompts

When `InteractionDetector` has a valid target:

A prompt appears near the target object in world space (a small floating UI element
anchored to the target) showing:
- Action button label (what pressing action does)
- Alt-action button label (what pressing alt-action does)

The prompt fades if the player does not move toward the target for 3 seconds, and
reappears on movement. It tracks with the target object in world space.

For the queen, these labels change dynamically based on context resolution. For other
pawns, they are fixed to the pawn's role abilities.

**Button labels use plain language, not ability IDs:**
- ✅ "Gather Nectar"
- ✅ "Pollinate"
- ✅ "Talk"
- ✅ "Offer Item"
- ❌ "USE_ABILITY_GATHER_NECTAR"

---

## Visual style guidelines

**Colour palette:**
- Primary: warm amber / golden tones (honey, wax, warmth)
- Secondary: deep forest greens and earth browns
- Accent: pale sky blue (daylight, clarity, clean information)
- Warning: desaturated orange (not alarm red — this is nature, not war)
- Critical: deep red, used sparingly (queen in danger, hive destroyed)

**Typography:**
- UI font: rounded, organic sans-serif — not mechanical or industrial
- All caps avoided except for section headers
- Numbers in bold; labels in regular weight

**Transparency:**
- All panels use semi-transparent backgrounds (60–75% opacity)
- Borders are thin and use the amber/golden palette
- No sharp corners — rounded or hex-edged panels throughout

**Hex shapes:**
- Health bars are hex-segmented (6 segments per pip)
- Portrait frames are hex-shaped
- Slot grid is honeycomb hex
- Panel borders have subtle hex chamfer

**Scale and density:**
- UI elements are comfortably sized for mouse and gamepad
- No information is ever smaller than 14pt equivalent
- Touch targets are never smaller than 44px

---

## Input model

### Keyboard / mouse
- `Tab` or `E`: interact / confirm
- `Q`: alt-action
- `Shift + Tab`: open pawn switch panel (hold)
- `Escape`: close current panel / cancel
- `M`: toggle minimap
- `C`: toggle colony management (only inside capital hive)
- Mouse: navigate slot grid, click to select, scroll to zoom minimap

### Gamepad
- `A` / `Cross`: interact / confirm
- `X` / `Square`: alt-action
- `LB` / `L1`: hold to open pawn switch panel
- `B` / `Circle`: cancel / back
- `Y` / `Triangle`: toggle minimap
- `Start`: colony management (only inside capital hive)
- Left stick: move / navigate panels
- Right stick: camera / compass pan

### Input abstraction

All input goes through an `InputManager` singleton (autoload) that maps raw device
input to semantic actions (`action`, `alt_action`, `switch_pawn`, `cancel`, etc.).
UI components subscribe to semantic actions, not raw key codes. This is the standard
Godot InputMap approach applied consistently.

---

## UIRoot scene structure

```
UIRoot (CanvasLayer)
├── HUD (Control)
│   ├── PawnCard (Control)              — top-left
│   ├── CompassStrip (Control)          — top-center
│   ├── SeasonTimeIndicator (Control)   — top-right
│   ├── PawnSwitchPanel (Control)       — left side, hidden by default
│   ├── InventoryContextPanel (Control) — bottom-center
│   ├── MarkerInfoStrip (Control)       — bottom-right
│   └── NotificationFeed (Control)      — right edge
│
├── HiveOverlay (Control)               — hidden; shown on ENTER_HIVE
│   ├── HiveHeader (Control)
│   ├── SlotGrid (Control)
│   └── SlotPanel (Control)             — hidden; shown on slot select
│
├── ColonyManagementScreen (Control)    — hidden; shown in capital hive
│   ├── TabBar (Control)
│   ├── PopulationTab (Control)
│   ├── ProductionTab (Control)
│   ├── TerritoryTab (Control)
│   ├── DiplomacyTab (Control)
│   └── MarkersTab (Control)
│
└── InteractionPrompt (Control)         — world-anchored, follows target
```

All panels are implemented as Godot `Control` nodes with `CanvasLayer` at the root.
They read from autoloads directly — they never mutate autoload state. All mutations
go through ability calls or dedicated service methods.

---

## Save / load

UI state is mostly transient and not saved. What is saved:

- Hive names (custom names set by player) — saved as part of `HiveSystem.save_state()`
- Minimap scale preference — saved in a `UserPreferences` resource
- Which tab was last open in colony management — not saved (always opens to Population)

The `FogOfWarSystem` (part of exploration spec) saves revealed cell state, which is
what the minimap renders from.

---

## MVP scope notes

Deferred past MVP:

- Full world map (strategic overlay showing all explored territory at any zoom level)
- In-game tutorial overlays (contextual popups for first-time mechanics)
- Accessibility options (colorblind modes, text size scaling, high-contrast mode)
- Controller haptic feedback profiles
- Animated pawn portraits in pawn card (currently static icon)
- Drag-and-drop item management in hive slots
- Multi-hive management view (seeing all hives' slot grids simultaneously)
- Colony management screen accessible remotely via scout bees (the data is available;
  the UI restriction is intentional at MVP to keep the player physically present)
