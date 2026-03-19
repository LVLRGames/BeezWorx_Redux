# BeezWorx Architecture: Economy System

> This document is a summary reference. Full authoritative specs are in
> `item_resource_spec.md`, `hive_slot_spec.md`, and `diplomacy_faction_spec.md`
> (outputs folder).

---

## Purpose

Manages the flow of biological resources from the procedural hex world into the
colony's hive network, driven by queen command markers and autonomous worker behaviors.

---

## Core Loop

1. **Explore** — Queen finds new plant species in new biomes; discovers new chemistry
2. **Discover** — Queen experiments with ingredients in hive crafting slots to unlock recipes
3. **Automate** — Once recipes are known, crafter bees handle production; workers gather
4. **Expand** — Queen crafts build markers and places them on valid anchor cells

---

## Two-Tier Crafting Economy

**Tier 1 — Base products** (from gathered ingredients):
- `honey` = nectar (any) + pollen
- `beeswax` = honey + honey (worker bees)
- `royal_wax` = honey + honey (queen only — her wax is always royal)
- `bee_jelly` = water + pollen
- `bee_bread` = honey + pollen
- `bee_glue` = tree_resin + beeswax
- `marker_base` = royal_wax + nectar_aromatic (queen only)
- `serum_base` = nectar + nectar
- `venom_base` = nectar_toxic + nectar

**Tier 2 — Derived products** (base + specialising ingredient):
- `royal_jelly` = bee_jelly + royal_wax (queen only)
- `royal_ant_jelly` = royal_jelly + nectar_aromatic (queen only — diplomatic bribe)
- `poison_stinger` = venom_base + thorn (soldier)
- `beetle_bread` = bee_bread + pollen_hearty (diplomatic food for beetles)
- `zippyzap_serum` = serum_base + nectar_stimulating
- etc.

**Honey variants** emerge from the channel output map on `RecipeDef`. Same recipe,
different nectar chemistry → different honey variant. High `N_heat` nectar → spicy
honey. High `N_cool` → cooling honey. The player discovers these through experiment.

**Royal tag rule:** Any item with "royal" in its name (`royal_wax`, `royal_jelly`,
`royal_ant_jelly`) can only be crafted by the queen. Enforced by `required_role_tags`
on `RecipeDef`. Workers cannot craft them even if ingredients are available.

---

## Markers as Crafted Items

Markers are not abstract commands — they are physical items the queen crafts and
places. All markers are Tier 2 products following the pattern:
`marker_base + [job-relevant ingredient]`

Examples:
- `marker_build_hive` = marker_base + plant_fiber
- `marker_defend` = marker_base + thorn
- `marker_ant_trail` = marker_base + royal_ant_jelly (requires ant alliance first)
- `marker_patrol` = marker_base + poison_stinger

Three marker categories: JOB (generates worker jobs), NAV (ant conveyors, patrol
routes), INFO (world labels). All handled by `JobSystem`.

---

## Hive Slot System

Inside a hive, a 2D hex grid of slots. Slot designations:
- `GENERAL` — flexible; holds items, can be used as bed, accepts craft orders
- `BED` — sleep slot; assigned to specific pawn; unassigned beds open to any pawn
- `STORAGE` — holds items; optional item type lock
- `CRAFTING` — holds a `CraftOrder`; crafter or queen works it
- `NURSERY` — holds an egg; nurse or queen feeds it; determines emerging bee's role

**Bed requirement:** Every bee needs a bed slot. Failure to find one → loyalty decay
→ abandonment. Bed shortages are the primary colony management pressure.

**Capital hive:** The hive containing the queen's bed slot. Only place where:
- Colony management screen is accessible
- Princess (royal_jelly-fed) eggs can be raised
- The NURSERY specialisation upgrade can be applied

**Specialisation upgrades:** INN (all beds → +25% rest rate), FACTORY (all crafting/
storage → −20% craft time), GRANARY (all storage → +50% capacity), NURSERY (all
nursery → −25% gestation), BARRACKS (beds + crafting → soldiers spawn pre-armed).

---

## Recipe Discovery

Queen places ingredients in a CRAFTING slot staging area. `RecipeSystem` checks each
combination against all known and discoverable recipes. On match with undiscovered
recipe: recipe unlocks colony-wide, crafting begins automatically. On near-match:
subtle "you're onto something" glow — no text hint. All workers with the right role
tags can craft discovered recipes from then on.

Always-known recipes (given at game start): `honey_basic`, `beeswax`, `royal_wax`,
`bee_jelly`, `bee_bread`, `marker_base`.

---

## Honey Economy and Diplomacy

Diplomatic relationships are built through offering the right product with the right
chemistry to each faction. Faction preferences are hidden — the player discovers them
through creature dialogue using the hint vocabulary in `dialogue_hint_vocabulary.md`.

- **Bear:** `N_cool` + `N_calm` + `N_aroma` honey with `P_lipid` pollen → guardian ally
- **Ant queen:** `N_aroma` + `N_calm` jelly → logistics ally (unlocks conveyor trails)
- **Beetle:** `P_protein` + `N_vigor` bread → earthmoving ally
- **Butterfly:** `N_sweetness` + `P_fertility` nectar → pollination ally
- **Grasshopper:** not formally allied — lured with `hopperwine` (honey_toxic + nectar_vigor)

Match score (0..1 dot product of item chemistry vs faction preference weights) determines
relation delta. Quality grade (crude → royal) adds up to 0.2 bonus to match score.
Alliances decay if not maintained with regular gifts; decay rate varies per faction.

---

## Roles and Possession

Every creature uses the universal grammar:
- `action` = collect (gather resource, pick up item)
- `alt_action` = use (deposit, craft, place marker, attack)

The queen's action/alt are contextual — `InteractionDetector` resolves the best target
in range and updates button labels dynamically. All other pawns have fixed ability slots
set on their scene configuration.

Player-controlled pawns receive subtle possession boosts: ~8% movement speed, ~5%
action speed, and precise targeting (aim at the threat nearest the hive, not nearest
to self). Never displayed to the player — felt, not announced.
