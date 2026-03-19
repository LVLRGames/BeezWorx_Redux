# BeezWorx Architecture: Genetics System

> This document is a summary reference. Full authoritative specs are in
> `plant_genetics_spec.md`, `plant_chemistry_system.md`, `plant_variant_rules.md`,
> and `plant_lifecycle_spec.md` (project files) and `active_defense_plant_spec.md`
> (outputs folder).

---

## Purpose

Allow the player to manipulate the ecosystem organically — breeding plant lines with
specific chemistry profiles to unlock new honey variants, defense capabilities, and
diplomatic ingredients. The player does not interact with gene values directly; they
manage pollen ratios and observe results over generations.

---

## Genome Structure

Each plant has a `PlantGenome` (or `HexPlantGenes` in codebase) containing:

**Categorical loci** — discrete features (stem type, leaf type, flower type, posture).
Expressed via dominance/codominance rules. Drive visual appearance.

**Additive trait channels** — continuous floats (0..1). Cover:
- Growth: `growth_speed`, `cycle_speed`, `lifespan`, `drought_resist`, `fertility`
- Yield: `nectar_volume`, `pollen_amount`, `flower_density`, `cycle_repeat_count`
- Chemistry (nectar): `N_sweetness`, `N_heat`, `N_cool`, `N_vigor`, `N_calm`,
  `N_restore`, `N_fortify`, `N_toxicity`, `N_aroma`, `N_purity`
- Chemistry (pollen): `P_protein`, `P_lipid`, `P_mineral`, `P_medicine`,
  `P_irritant`, `P_fertility`, `P_mutation`, `P_stability`, `P_purity`
- Active plant: `A_trigger_speed`, `A_grasp_strength`, `A_range`,
  `A_regeneration`, `A_discrimination`, `A_toxin_potency`
- Structural: `leaf_density`, `branch_spread`, `thorniness`, `vine_tendency`

**Hidden lineage traits** — affect variant scoring: `wildness_bias`, `lush_affinity`,
`royal_affinity`, `purity_retention`, `hybrid_fertility`.

---

## Inheritance Model

Offspring inherit additive channels as:
```
offspring_value = species_baseline + (parentA_contrib + parentB_contrib) / 2 + random_mutation
```
Mutation magnitude scales with parent `mutation_bias` and `P_mutation` channels.
Categorical loci follow dominance rules defined per locus. All values clamped 0..1.

---

## Pollination Mechanics

**Natural spreading:** Pollinated plants at FRUITING stage drop seeds on their own cell
(up to 6 plants per hex). No player intervention needed — fields stay alive naturally.

**Cross-pollination:** `HexWorldState.attempt_cross_sprout(ca, cb, ga, gb)` is called
when a bee applies pollen from cell A to cell B. If species groups are compatible, a
hybrid sprout spawns on a free cell near B. If an authored cross exists for this pair,
the authored `HexPlantDef` is used; otherwise a `wild_plant` with blended genes spawns.

**Explicit transplanting:** Ant carries seed + beetle digs hole = plant to new cell.
Crafting is hive-only; gardeners carry pollen to hive but compression is done by crafters.

---

## Variant System

Plants express one of four variants based on accumulated scores:

| Variant | Trigger | Key effects |
|---|---|---|
| NORMAL | Default | Baseline stats |
| WILD | Stress events, uncontrolled pollination, low stability | Fertility +25%, stability −30%, chemistry volatility |
| LUSH | Ideal conditions, full care, high vigor genes | Yield +40%, wider coverage, visual fullness |
| ROYAL | Isolated breeding, purity-only pollen, perfect care | Highest grade, stability +50%, consistent potency |

Variants are not permanent — conditions can shift a plant between states across
fruiting cycles. The `A_discrimination` channel on active plants determines how well
they resist feral reversion when territory fades (high discrimination = holds allegiance
longer into the fade).

---

## Chemistry and Product Outcomes

Chemistry channels on nectar/pollen items carry through into crafted products.
The `channel_output_map` on `RecipeDef` maps dominant channels to output item variants:
- High `N_heat` nectar → `honey_spicy`
- High `N_cool` nectar → `honey_cool`
- High `N_restore` → `honey_healing`

Conflict rules: opposing channels cancel (heat vs cool, vigor vs calm).
Synergy rules: certain combinations grant bonuses (heat + fortify → enhanced cold
resistance on the product).

Quality grade of output is determined by the lowest grade among inputs, with a
possible +1 step if the average input grade is significantly higher than the minimum.

---

## Ecological Instability

When a hive's territory fades, plants in the affected cells lose colony pheromone
influence. The consequence escalates in tiers:

1. **Fringe influence (0.3):** Plant becomes NEUTRAL — wild behavior, no colony
   discrimination. Allied ants and bees passing through are safe but the plant
   no longer actively defends the colony.

2. **Zero influence:** Plant becomes FERAL — attacks all creatures regardless of
   colony. Allied ants, foragers, the player's ground pawns are all vulnerable.
   Plants with high `A_discrimination` (bred specifically for loyalty) resist full
   feral longer than wild or unbreed lines.

3. **Visual cue:** FERAL plants have a desaturated, red-tinged shader state
   (`feral_tint` parameter). Players who notice get early warning.

**Genetic drift:** Plants in zero-influence areas continue naturally cross-pollinating
without colony guidance, producing unpredictable wild hybrids the player has not
yet discovered. These can be valuable or hazardous.

---

## Breeding for Defense

Active defense plants (flytraps, whip vines, briars, thistles, sundews) use the same
genetics as resource plants but their `A_*` specialisation channels determine combat
effectiveness. Key breeding targets:

- **Flytrap:** `A_grasp_strength` (hold time), `A_toxin_potency` (damage while held),
  `A_discrimination` (resist friendly fire)
- **Whip vine:** `A_range` (intercept distance), `A_trigger_speed` (reaction time),
  `bloom_density` (number of vine heads = rate of fire)
- **Briar:** `A_grasp_strength` (stronger slow), `branch_spread` (wider coverage)
- **All:** `A_discrimination` (holds allegiance during territorial stress)

Chemistry also affects active plants: high `N_toxicity` adds poison effect to attacks;
high `N_aroma` attracts targets toward the plant (lure mechanic for pest redirection).
