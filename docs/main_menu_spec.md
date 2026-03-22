# BeezWorx MVP Spec: Main Menu, Game Over, and Credits

This document specifies all screens outside of active gameplay: the LVLR splash,
the animated main menu, the colonies carousel, the options screen, the game over
postmortem overlay, and the credits screen. It is the authoritative reference for
`MainMenuRoot` and all non-gameplay UI flows.

---

## Purpose and scope

The main menu is the player's first impression of BeezWorx. It must communicate the
game's ecological identity immediately — a living world is visible behind everything,
and the UI feels organic and deliberate rather than sterile and mechanical.

This spec covers:
- LVLR Games splash screen
- Animated title screen with fly-through world background
- Animated sidebar navigation (Play / Options / Quit)
- Colonies carousel with save slot cards
- New colony setup
- Multiplayer join card
- Per-colony options
- Game options screen
- Game over sequence: camera lock, vignette, desaturation, postmortem stats
- Credits screen

It does **not** cover: in-game HUD or hive overlay (UI/HUD spec), save file format
(Save/Load spec), or world generation parameters (World/Hex/Chunk spec).

---

## Screen flow

```
App launch
  └── LVLR Splash (2–3 seconds)
        └── Title Screen (fly-through background + title art + "press any key")
              └── [any input]
                    ├── Main Menu (sidebar flies in)
                    │     ├── PLAY (default focused)
                    │     │     └── Colonies Panel (carousel flies in from right)
                    │     │           ├── [select world card] → Enter Colony / Edit Colony
                    │     │           ├── [+ card] → New Colony Setup
                    │     │           └── [join card] → Multiplayer Join
                    │     ├── OPTIONS → Options Screen (sidebar flies out, options flies in)
                    │     └── QUIT → Confirm Modal → exit
                    └── [from options] Back → Main Menu returns
```

---

## LVLR Games splash screen

A full-screen splash showing the LVLR Games logo and studio name. Duration: 2.5 seconds.

- Fade in from black over 0.5 seconds
- Logo holds for 1.5 seconds
- Fade out to black over 0.5 seconds
- Can be skipped by any input (press any key/button)
- Transitions directly to Title Screen

The LVLR logo and wordmark are static assets. No animation required beyond the fades.
A subtle ambient sound or short sting plays during the splash (silent is also acceptable
for MVP — placeholder until audio is produced).

---

## Title screen

### Background: world fly-through

The background is a live Godot viewport rendering the hex world with a slow cinematic
camera path. The camera drifts through the starting biome — past flowering plants,
hovering bees, gently waving grass. This is the world the player is about to enter.

Implementation:
- A `TitleWorldViewport` (SubViewport) runs a lightweight instance of the terrain
  with a pre-seeded demonstration world (fixed seed, not the player's save)
- Camera follows a spline path defined in the scene — slow, looping, never jarring
- The world runs at reduced simulation fidelity (plants tick, bees fly, no AI jobs)
- Viewport renders at a slight downscale for performance, upscaled to fill screen
- A very subtle darkening vignette overlay (10–15% dark) prevents the world from
  competing with the title UI

### Title art

The BeezWorx title art (a stylised logo/wordmark) flies in from slightly off-center-top
on a slow ease-out curve. It settles in the vertical center of the screen, horizontally
centered or slightly left of center.

Below the title art, after a 0.8-second delay, the prompt text fades in:
**"Press any key to begin"** (gamepad: any button)

The prompt text pulses with a slow opacity oscillation (0.6 → 1.0 → 0.6, period ~2s)
to draw the eye without being distracting.

No other UI elements are visible on this screen.

---

## Main menu (sidebar)

### Transition from title screen

On any input from the title screen:

1. The "Press any key" text fades out immediately.
2. The title art animates from its centered position to the **upper-left corner** of
   the screen, scaling down to approximately 60% of its title-screen size.
   Ease: `ease_in_out`, duration 0.4 seconds.
3. Simultaneously, a **black sidebar panel** slides in from the left edge of the screen.
   Width: ~280px. Height: full screen. Ease: `ease_out`, duration 0.35 seconds.
4. After the sidebar reaches its final position (or at 0.2s into its animation),
   three buttons slide in from the left **over** the sidebar, staggered:
   - **PLAY** — slides in first, 0ms delay
   - **OPTIONS** — slides in second, 80ms delay
   - **QUIT** — slides in third, 160ms delay
   Each button slides from off-screen-left to its final position.
   Ease: `ease_out_back` (slight overshoot for organic feel).

5. **PLAY is auto-focused** when the sidebar finishes animating. The Colonies panel
   begins its fly-in from the right simultaneously (see below).

### Sidebar visual style

- Background: solid black, slight transparency acceptable (90–95% opacity)
- Left edge: flush with screen edge
- Right edge: subtle amber/golden border line (1–2px, colony palette)
- Title art in upper-left: amber/honey colour
- Buttons: full-width within sidebar, left-aligned text with hex-bullet prefix
- Focused button: slightly brighter text + left accent bar in amber
- Hover (mouse): same as focused

### Button behavior

**PLAY:** focuses the Colonies panel. Colonies panel flies in from the right if not
already visible. Always the default focused state.

**OPTIONS:** Sidebar flies out to the left. Options screen flies in from the left
in its place. Back button in options reverses the animation.

**QUIT:** Opens a centered confirm modal ("Are you sure you want to quit?", Yes / No).
Yes exits the application. No dismisses the modal, focus returns to sidebar.

---

## Colonies panel

Flies in from the right edge of the screen when PLAY is focused. Width fills the
remaining screen space to the right of the sidebar. Has its own header.

### Header

- Panel title: **"Colonies"** (or **"Empires"** — TBD; recommend "Colonies" for
  consistency with in-game language, but "Empires" has more weight)
- Displayed in the top area of the panel, amber/honey colour, large font

### Save slot carousel

A horizontally scrollable carousel of **colony cards**. Cards are arranged left to
right, sorted by last-played date descending (most recent first).

Scrolling: mouse wheel, swipe gesture, or left/right directional input.
One card is always "active" (centered or slightly left of center), larger than flanking
cards (parallax card stack effect — active card at 100% scale, adjacent at 85%,
further at 70%).

### Colony card content

Each card displays:

- **Colony emblem / flag** (top portion — procedurally generated or player-set)
- **Colony name** (e.g. "The Heatherbee Colony")
- **Queen name** (current reigning queen)
- **Last played date** (formatted as in-game day + real date: "Day 142, Summer — 2 days ago")
- **Hive count** and **population count** (icon + number)
- **Play time** (total hours)
- **Local / Multiplayer indicator** — icon in corner:
  - Local: a single bee silhouette icon
  - Multiplayer: two bee silhouettes
  - Additionally: local cards have a warm amber border; multiplayer cards have a cool
    blue border

Snapshot: each card has a small rendered snapshot of the world at the hive location
(captured at last save, stored as a PNG thumbnail in the save folder alongside the
`.beez` file).

### Special cards

**New Colony card** (always second-to-last):
- Outline style (dashed amber border, semi-transparent fill)
- Large **"+"** symbol in the center
- Label: "Start New Colony"
- Clicking opens the New Colony Setup flow

**Join Colony card** (always last):
- Outline style with blue tint (multiplayer colour)
- Two bee silhouettes icon
- Label: "Join a Friend's Colony"
- Contains: friend code input field or browse button
- Clicking opens the multiplayer join flow (post-MVP for online; local co-op
  connect flow at MVP)

### Card selection and actions

Clicking a colony card (or pressing confirm on a focused card) **selects** it:
- Card animates to fully centered
- Two buttons fade in below the carousel:
  - **Enter Colony** (primary, auto-focused) — loads the save, enters the world
  - **Edit Colony** — opens per-colony options overlay

**Enter Colony:** calls `SaveManager.load_game(slot_name)`. Loading screen fades in
over the main menu while the world loads, then fades out into gameplay.

### Per-colony options (Edit Colony)

A modal overlay that slides up from the bottom of the colonies panel. Contains:

- Rename colony (text input)
- Change colony emblem (emblem picker — a small grid of pre-authored emblems)
- Delete colony (dangerous — requires typing the colony name to confirm)
- Save / Cancel buttons (bottom right)

---

## New colony setup

Triggered by the "+" card. A panel slides up from the bottom of the colonies panel
(or replaces it with a fly animation). Contains:

- **Colony name** text input (required; placeholder: "Name your colony")
- **World seed** input (optional; leave blank for random; shows generated seed value
  once focus leaves the field so player can note it)
- **Difficulty** selector (3 options for MVP: Relaxed / Standard / Unforgiving —
  affects threat frequency and resource abundance)
- **Start Colony** button (primary, bottom right)
- **Back** button (bottom left, returns to carousel)

"Start Colony" calls `SaveManager.start_new_game(config)` and transitions to gameplay
via the loading screen.

---

## Options screen

Triggered by the OPTIONS button. The sidebar flies out left; the options panel flies in
from the left in its place, full-screen width.

### Layout

Two-column layout: category tabs on the left (~200px), settings on the right.

**Category tabs:**
- Video
- Audio
- Controls
- Accessibility
- Credits ← (navigates to Credits screen)

### Video settings

- Resolution (dropdown)
- Window mode (Windowed / Borderless / Fullscreen)
- VSync (On / Off)
- Frame rate cap (30 / 60 / 120 / Unlimited)
- Render scale (50% / 75% / 100% / 125%) — affects SubViewport resolution
- Shadow quality (Low / Medium / High)
- Grass density (Low / Medium / High / Ultra) — maps to `HexTerrainConfig.max_grass_per_hex`
- Terrain detail distance (slider — affects chunk `view_radius_chunks`)
- UI scale (slider 80%–150%)

### Audio settings

- Master volume (slider)
- Music volume (slider)
- SFX volume (slider)
- Ambient volume (slider)
- Narrator volume (slider) — the documentary narrator biome discovery lines

### Controls settings

- Key binding remapper — lists all semantic actions from InputManager, allows rebind
- Controller layout selector (Standard / Southpaw)
- Mouse sensitivity (slider)
- Camera invert X / Y (toggles)
- Hold vs toggle for pawn switch panel (toggle)

### Accessibility settings

- Colorblind mode (None / Deuteranopia / Protanopia / Tritanopia)
- High contrast UI (toggle)
- Text size (Small / Normal / Large)
- Reduce motion (toggle — disables UI fly-in animations, uses fades instead)
- Subtitles for narrator lines (toggle)

### Options behavior

- Changes apply immediately (no "apply" button needed for most settings)
- Resolution and window mode changes have a 10-second confirm timeout ("Revert in 8s")
  with Keep / Revert buttons
- A "Restore Defaults" button is available at the bottom of each category
- **Back** button (or Escape/B) flies options panel out and returns to main menu sidebar

---

## Loading screen

Shown during `SaveManager.load_game` and `start_new_game`. A full-screen overlay that
fades in over the main menu and fades out when the world is ready.

Contents:
- The BeezWorx title art (smaller, centered)
- A subtle animated hex grid pattern (slow, organic movement)
- A loading hint — one of a rotating set of short gameplay tips or lore lines, changed
  every 3 seconds
- A small loading indicator (not a progress bar — a looping hex spinner)

The loading screen does not show a percentage. Load time for a saved world is expected
to be short enough that a spinner is sufficient.

---

## Game over sequence

### Trigger

`EventBus.game_over(colony_id)` fires when the queen dies with no living heirs.
`PossessionService` immediately forces the player to possess the queen pawn (or locks
the camera to her last known position if she is already dead and has no node).

### Sequence

**Step 1 — World desaturation (0–1.5 seconds):**
A full-screen shader overlay fades in that:
- Applies heavy vignette (dark oval border closing in toward center)
- Progressively desaturates everything except the queen pawn (she retains full colour)
- Applies a soft gaussian blur to everything except the queen
Effect: the world fades to greyscale around a still-vibrant queen. The contrast draws
the eye to her even as chaos implies itself around the edges.

**Step 2 — Game over text (1.5–2.5 seconds):**
The words **"The Colony Has Fallen"** fade in centered above the queen, using the game's
title font in white. No dramatic sting — quiet is more impactful. A single low ambient
tone fades in under the scene.

**Step 3 — Postmortem modal (2.5 seconds onward):**
A dark semi-transparent modal slides up from the bottom of the screen. Title:
**"A Queen's Legacy"**

Modal contents:
- **Queen name and portrait**
- **Reign duration** (days ruled, seasons survived)
- **Colony name**
- **Peak population** reached
- **Hives built** (lifetime)
- **Alliances formed** (faction names)
- **Recipes discovered** (count + list of notable ones)
- **Threats defeated** (lifetime raid count survived)
- **Cause of death** (old age / combat / unknown)
- **Succession:** "No heir was named. The colony dissolved."
- If queen_history has multiple entries: "She was the [N]th queen of [Colony Name]"

At the bottom of the modal, two buttons:
- **Return to Menu** — fades out to main menu, colony card shows as "Dissolved"
- **View Credits** — transitions to Credits screen

### Dissolved colony card

After a game over, the colony's save card in the carousel displays a "Dissolved" state:
- Greyscale card
- A subtle broken-hex icon overlay
- The colony remains in the carousel so the player can see its history
- "Enter Colony" is replaced with "View Legacy" (read-only postmortem stats, no play)
- The player can delete it from Edit Colony

---

## Credits screen

Accessible from: game over postmortem ("View Credits") and Options screen ("Credits" tab).

### Visual style

- Full dark background (near-black, very subtle hex pattern texture at low opacity)
- Vertically scrolling credits text, centered
- A few hand-placed decorative bee sprites float slowly across the background at
  varying depths (parallax, slow drift — not distracting, just alive)
- One or two flowering plant sprites in the lower corners, gently swaying

### Content structure (scrolling top to bottom)

```
[BeezWorx logo — large]

A game by
[Your name / studio name]

[Section: Design & Development]
[Your name]

[Section: Tools & Engine]
Godot Engine 4.6
[any libraries used]

[Section: Music]
[composer / placeholder]

[Section: Sound]
[sfx source / placeholder]

[Section: Special Thanks]
[anyone you want to thank]

[Section: Built With]
LVLR G.D.B.L.A.S.T. Pipeline

[BeezWorx logo — small, bottom]
"Thank you for playing."
```

### Behavior

- Scroll speed: slow and steady (readable at a glance)
- Player can hold a button to fast-scroll
- Player can press Back / Escape at any time to exit
- If reached from game over: Back returns to postmortem modal
- If reached from options: Back returns to options screen
- After credits finish scrolling, they loop rather than stopping

---

## Scene structure

```
MainMenuRoot (Node — scene root, not CanvasLayer)
├── TitleWorldViewport (SubViewport)   — fly-through world render
├── MainMenuUI (CanvasLayer)
│   ├── SplashScreen (Control)         — LVLR logo, fades in/out
│   ├── TitleScreen (Control)          — title art + press any key
│   ├── Sidebar (Control)              — black panel + Play/Options/Quit
│   ├── ColoniesPanel (Control)        — carousel + cards
│   │   ├── ColonyCard (x N)
│   │   ├── NewColonyCard
│   │   └── JoinColonyCard
│   ├── NewColonySetup (Control)       — name/seed/difficulty form
│   ├── OptionsScreen (Control)        — tabbed settings panel
│   ├── ConfirmModal (Control)         — quit confirm
│   └── LoadingScreen (Control)        — full-screen load overlay
│
└── GameOverLayer (CanvasLayer)        — separate layer; active during gameplay
    ├── VignetteDesatOverlay (Control) — full-screen shader overlay
    ├── GameOverText (Control)         — "The Colony Has Fallen"
    ├── PostmortemModal (Control)      — legacy stats
    └── CreditsScreen (Control)        — scrolling credits
```

`GameOverLayer` is a separate `CanvasLayer` that lives in the main scene tree (not
in `MainMenuRoot`) so it can overlay active gameplay without requiring a scene
transition to the main menu first.

---

## Animation constants

All UI animations use these defaults (adjustable in a `UIAnimationConfig` resource):

```
SPLASH_FADE_IN:      0.5s
SPLASH_HOLD:         1.5s
SPLASH_FADE_OUT:     0.5s
TITLE_FLY_IN:        0.6s  ease_out_back
SIDEBAR_SLIDE_IN:    0.35s ease_out
BUTTON_STAGGER:      0.08s per button
BUTTON_SLIDE_IN:     0.3s  ease_out_back
COLONIES_FLY_IN:     0.4s  ease_out
CARD_SCALE_ACTIVE:   1.0
CARD_SCALE_ADJACENT: 0.85
CARD_SCALE_FAR:      0.70
MODAL_SLIDE_UP:      0.35s ease_out
VIGNETTE_FADE_IN:    1.5s
GAMEOVER_TEXT_IN:    0.6s
POSTMORTEM_SLIDE_UP: 0.4s

REDUCE_MOTION_FALLBACK: all animations become 0.15s cross-fades when
                        reduce_motion accessibility option is enabled
```

---

## Save slot thumbnail capture

When `SaveManager.save_game` is called, capture a thumbnail of the current viewport:

```
func _capture_thumbnail(slot_name: String) -> void:
    var img: Image = get_viewport().get_texture().get_image()
    img.resize(320, 180, Image.INTERPOLATE_BILINEAR)
    img.save_png(SaveManager.SAVE_DIR + slot_name + "_thumb.png")
```

The thumbnail is saved alongside the `.beez` file. It is loaded by the colony card
and displayed as the card's background image. If no thumbnail exists (new save, or
thumbnail file missing), the card shows a procedurally generated hex pattern using
the world seed as the colour source.

---

## MVP scope notes

Deferred past MVP:

- Online multiplayer join flow (join card exists in UI; network layer is post-MVP)
- Colony emblem editor (emblem picker uses pre-authored set at MVP)
- Animated colony emblem (static image at MVP)
- Achievement display on colony card
- Sorting and filtering options for the colony carousel (sort by name, hive count, etc.)
- Animated background for credits (bee sprites are placeholder; full art pass post-MVP)
- Localisation / language selection in options
