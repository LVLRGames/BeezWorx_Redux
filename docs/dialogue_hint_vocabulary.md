# BeezWorx Design Doc: Dialogue Hint Vocabulary

This document defines the natural-language vocabulary used in creature dialogue to hint
at chemistry channel preferences and product type preferences. It is a shared reference
for writers, systems designers, and anyone authoring `DialogueDef` resources.

The goal is a vocabulary that is learnable without being a lookup table. Players should
be able to decode dialogue through observation and experimentation, not by reading a
guide. Words should feel like how a creature would actually talk about food and comfort,
not like a game system describing itself.

---

## How the system works

Each creature or faction has hidden preference channel values on their `FactionDef` or
`SpeciesDef`. When the player offers a product, the game compares the product's chemistry
profile against the creature's preference profile and scores the match. A perfect match
is a full ally. A partial match gives partial benefit. The player learns the preference
profile through dialogue — but only indirectly, through the creature's natural speech.

Writers use this vocabulary to embed preference hints in dialogue lines. The same channel
can appear in many different dialogue lines through many different words. Consistency
across the vocabulary is more important than consistency within a single line.

---

## Nectar channel vocabulary (`N_` channels)

These describe flavour, sensation, and effect as a creature would experience them.
Use 1–3 of these words per relevant dialogue line. Do not use the channel name itself.

### `N_sweetness` — energy, palatability, basic appeal
> Core attractiveness. Every creature responds to sweetness to some degree.

**Hint words:** sweet, sugary, rich, tasty, delicious, satisfying, yummy

*Example dialogue use:* "Something sweet to keep me going through the afternoon."
*Example dialogue use:* "I don't ask for much, just something rich and satisfying."

---

### `N_heat` — warmth, spice, fire
> Warming effect. Creatures in cold climates or those that run cold crave this.

**Hint words:** warm, hot, spicy, fiery, burning, toasty, cozy

*Example dialogue use:* "My joints get stiff in the cold. I need something that warms me from the inside."
*Example dialogue use:* "Give me something with a little kick to it. Something spicy."

---

### `N_cool` — cooling, soothing, fresh
> Cooling effect. Creatures that overheat, feel anxious, or live near water lean toward this.

**Hint words:** cool, fresh, crisp, soothing, refreshing, calm, clear, clean

*Example dialogue use:* "Something cool and fresh, like a drink from the river."
*Example dialogue use:* "I've been overheating all day. I need something that cools me down."

---

### `N_vigor` — energy, stimulation, strength boost
> Stimulating effect. Creatures that work hard, need a pick-me-up, or love to party.

**Hint words:** energising, stimulating, lively, zingy, buzzing, invigorating, bracing, electric

*Example dialogue use:* "Something that gets me going. I've got a long day ahead."
*Example dialogue use:* "I like things with a little buzz to them. Really gets the legs moving."

---

### `N_calm` — settling, ordering, peace
> Sedative effect. Anxious creatures, those in pain, creatures that need sleep or order.

**Hint words:** calming, settling, soothing, peaceful, gentle, mellow, quiet, still

*Example dialogue use:* "My stomach's been restless all morning. I need something to settle it."
*Example dialogue use:* "Something gentle. Nothing too wild. I just need to think clearly."

*Note:* `N_cool` and `N_calm` can overlap in feel. `N_cool` is physical (temperature, sensation).
`N_calm` is psychological (mood, anxiety, mental clarity). A river-smell hint points to `N_cool`.
A "settle my nerves" hint points to `N_calm`.

---

### `N_restore` — healing, recovery, repair
> Restorative effect. Injured or sick creatures, those recovering from effort.

**Hint words:** healing, restorative, mending, reviving, nourishing, wholesome, fortifying

*Example dialogue use:* "I took a knock yesterday. Could use something to help me heal up."
*Example dialogue use:* "Something nourishing. My body's been through a lot lately."

*Note:* `N_restore` and `N_fortify` can both sound like "strength." `N_restore` is recovery
(fixing damage). `N_fortify` is resilience (resisting future damage). "Help me heal" → restore.
"Help me take a hit" → fortify.

---

### `N_fortify` — toughening, hardening, endurance
> Defensive reinforcement. Creatures that face threats, work in harsh conditions, or want
> to feel unbreakable.

**Hint words:** tough, hardening, strengthening, durable, armoured, resilient, steadfast, ironclad

*Example dialogue use:* "I need something that'll help me shrug off the next hit."
*Example dialogue use:* "Something that toughens you up. Makes you feel like nothing can touch you."

---

### `N_toxicity` — bite, danger, edge
> Poisonous or caustic. Creatures that appreciate danger, use toxins themselves, or
> have high toxin tolerance. At low values, adds "edge" or "bite." High values are
> actively harmful to most creatures.

**Hint words:** bitter, sharp, dangerous, venomous, biting, tangy, edgy, fierce, potent

*Example dialogue use:* "I like things with a little danger in them. Something with real bite."
*Example dialogue use:* "Something sharp. None of that sweet soft stuff."

*Note:* At low toxicity this reads as "edgy flavour preference." Only creatures with high
toxin tolerance (spiders, wasps, certain beetles) respond positively to high toxicity.
Writers should use milder words (bitter, sharp, tangy) for low-preference creatures and
stronger words (venomous, fierce, dangerous) for high-tolerance ones.

---

### `N_aroma` — scent, smell, fragrance, communication
> Pheromonal and scent properties. Highly social creatures, insects that communicate
> via scent, or any creature that navigates by smell.

**Hint words:** fragrant, aromatic, perfumed, scented, sweet-smelling, floral, pungent, musky

*Example dialogue use:* "There's something about the smell of it. Like wildflowers after rain."
*Example dialogue use:* "It should smell right. My kind notices the smell before the taste."

---

### `N_purity` — cleanness, clarity, quality
> Grade/purity. Creatures that are discerning, value quality, or react badly to impurities.

**Hint words:** pure, clean, clear, refined, quality, proper, unadulterated, fine

*Example dialogue use:* "Nothing crude. I can tell when it's been done sloppily."
*Example dialogue use:* "It should be clean. Pure. Made with care."

---

## Pollen channel vocabulary (`P_` channels)

Pollen channels are primarily relevant for food products (bread, jelly, nursing items)
and for products targeting creatures with dietary preferences. They're less commonly
hinted at than nectar channels but important for diplomatic food products.

### `P_protein` — strength, muscle, growth, fullness
**Hint words:** protein, hearty, filling, meaty, substantial, beefy, nourishing, dense

*Example dialogue use:* "Something hearty. A real meal, not just a snack."
*Example dialogue use:* "Without a protein-rich meal I just don't have the strength for it."

---

### `P_lipid` — endurance, lasting energy, richness
**Hint words:** rich, fatty, long-lasting, sustained, creamy, heavy, full-bodied

*Example dialogue use:* "Something that keeps me going all day, not just for an hour."
*Example dialogue use:* "Rich and heavy. Something that sticks with you."

---

### `P_mineral` — hardness, structure, resilience
**Hint words:** mineral, earthy, gritty, rocky, solid, structured, dense

*Example dialogue use:* "Something earthy. Reminds me of the soil after rain."
*Example dialogue use:* "Something solid. Not airy. Something with substance."

---

### `P_medicine` — healing, immunity, wellness
**Hint words:** medicinal, healthy, curative, cleansing, immune-boosting, wellness

*Example dialogue use:* "Something that keeps the sickness away. You know, something healthy."
*Example dialogue use:* "Medicinal. It needs to actually do something for the body."

---

### `P_irritant` — aggression, edge, defensiveness
> At low values, adds "spunk" or "edge" to a food. At high values, actively unpleasant
> for most creatures. Creatures with defensive builds or aggressive personalities may
> enjoy this.

**Hint words:** irritating, peppery, aggravating, prickly, sharp, rough, scratchy

*Example dialogue use:* "Something with a bit of a scratch to it. I like food that fights back."

---

### `P_fertility` — vitality, life, growth
> Primarily relevant for nursing products and creatures focused on reproduction or growth.

**Hint words:** vital, life-giving, fertile, blooming, lush, vibrant, growing

*Example dialogue use:* "Something that feels alive. Full of life."
*Example dialogue use:* "Something lush. Like spring in a bite."

---

### `P_mutation` — wildness, unpredictability, chaos
> Creatures that enjoy novelty, risk, or the unusual. Grasshoppers are a good candidate.

**Hint words:** wild, unpredictable, strange, chaotic, surprising, unusual, exotic, weird

*Example dialogue use:* "Something different every time. I hate the same thing twice."
*Example dialogue use:* "Something a little wild. You know, surprising."

---

### `P_stability` — reliability, consistency, comfort
> Creatures that are conservative, prefer routine, or value dependability.

**Hint words:** reliable, consistent, familiar, comforting, steady, dependable, traditional

*Example dialogue use:* "Just something I know. Something I can count on."
*Example dialogue use:* "Nothing fancy. Something dependable."

---

### `P_purity` — quality, cleanliness (pollen)
Same vocabulary as `N_purity`. See above.

---

## Base product type vocabulary

These words hint at which product type a creature wants before the player knows the
specific chemistry. A creature that says "something to drink" is probably asking for
honey or nectar-based product (liquid). One that says "a proper meal" is pointing at
bread. Writers use these to set the product category before the chemistry hints narrow
it further.

**Honey** is the default assumption. If no product type is hinted, the player should
try honey first. Do not use specific words for honey — its absence is its hint.

---

### `bread` — solid food, protein-based products
**Hint words:** meal, dinner, supper, food, hearty bite, something to eat, proper food, breakfast, snack

*Example:* "What I really want is a proper meal." → bee_bread base
*Example:* "Something I can really sink my teeth into." → bee_bread base

---

### `jelly` — soft, medicinal, restorative products
**Hint words:** salve, remedy, something soft, something smooth, paste, gel, spread, balm

*Example:* "Something smooth. Easy on the stomach." → bee_jelly base
*Example:* "A salve of some kind. For the aches." → bee_jelly base + N_restore

---

### `serum` — concentrated effect products, brews, elixirs
**Hint words:** brew, elixir, tonic, draught, effect, potion, concentrate, dose, drop

*Example:* "A little elixir. Something with a real effect." → serum_base
*Example:* "Just a drop of something potent." → serum_base

---

### `venom` — weapons, traps, offensive products
**Hint words:** weapon, sting, bite, something nasty, poison, trap ingredient

*Note:* Creatures don't usually ask for venom directly. Venom-based products appear
in crafting contexts (poison_stinger, paralyzer_stinger) rather than diplomacy.
Soldiers may discuss venom in the context of combat preparation. Not a diplomacy product.

---

### `glue / construction material` — structural products
**Hint words:** glue, adhesive, binding, construction, material, paste, cement, fixer

*Note:* Primarily a carpenter/construction context. Beetles and other earthmoving
creatures may ask about it tangentially when discussing construction jobs.

---

## Quality grade vocabulary

Use these when a creature cares about the quality of what they receive, not just the
chemistry. A creature that uses quality words is probably a discerning ally who gives
better service for higher-grade products.

| Grade | Hint words |
|---|---|
| Crude | rough, basic, whatever, anything'll do, doesn't matter |
| Common | normal, regular, standard, decent, ordinary |
| Fine | good, proper, well-made, careful, quality |
| Lush | exceptional, remarkable, really good, impressive |
| Royal | perfect, extraordinary, the best, nothing less |

---

## Conflict channel pairs (writer's reference)

When writing dialogue that expresses a strong dislike, the opposite channel vocabulary
is appropriate. A creature that hates heat will use cool vocabulary and express aversion
to warmth.

| Channel | Conflicts with |
|---|---|
| `N_heat` | `N_cool` |
| `N_vigor` | `N_calm` |
| `N_restore` (recovery focus) | `N_fortify` (prevention focus) — mild conflict |
| `P_mutation` | `P_stability` |

*Example of aversion dialogue:* "Nothing hot. I can't stand it. Something cool and fresh."
→ creature has high `N_cool` preference and low `N_heat` tolerance.

---

## Inverse hint vocabulary

Inverse hints describe what the creature is *experiencing* or *lacking* — the problem,
not the solution. The player must recognise that the remedy is the opposite of the
symptom. This is the most natural form of dialogue hint and should be used at least as
often as direct hints.

The pattern is: creature describes a negative state → player infers the positive channel
that would resolve it.

### `N_sweetness` — inverse hints (creature is hungry, lacking energy)
**Inverse words:** bland, tasteless, dull, unsatisfying, empty, hollow, flavorless

*Example:* "Everything I've eaten today has been so bland. Nothing has any taste to it."
→ wants `N_sweetness`

---

### `N_heat` — inverse hints (creature is cold, stiff, sluggish from cold)
**Inverse words:** cold, freezing, stiff, numb, chilled, shivering, icy, rigid

*Example:* "My joints get so stiff in the morning. The cold just gets into everything."
→ wants `N_heat`

---

### `N_cool` — inverse hints (creature is overheating, feverish, agitated by heat)
**Inverse words:** overheating, feverish, flushed, scorching, burning up, restless from heat, sweating, parched

*Example:* "I've been out in the sun all day. I'm absolutely parched and burning up."
→ wants `N_cool`

---

### `N_vigor` — inverse hints (creature is tired, sluggish, lacking motivation)
**Inverse words:** tired, sluggish, exhausted, drained, lethargic, slow, heavy-limbed, unmotivated

*Example:* "I barely had the energy to get up this morning. Everything feels so heavy."
→ wants `N_vigor`

---

### `N_calm` — inverse hints (creature is anxious, restless, unsettled, racing thoughts)
**Inverse words:** restless, anxious, unsettled, jittery, on edge, can't focus, scattered, wound up, frantic

*Example:* "My stomach won't settle. I've been so restless all morning, can't seem to focus."
→ wants `N_calm`

*This is the bear's "restless stomach" example. Restless is the inverse hint; calm is
the channel being pointed at.*

---

### `N_restore` — inverse hints (creature is injured, worn down, sick)
**Inverse words:** hurt, wounded, worn out, broken down, aching, sore, sick, suffering, battered

*Example:* "I took a bad hit yesterday. Everything aches and I can't seem to shake it."
→ wants `N_restore`

---

### `N_fortify` — inverse hints (creature feels vulnerable, fragile, exposed)
**Inverse words:** vulnerable, fragile, exposed, brittle, unprotected, soft, easily hurt, thin-skinned

*Example:* "I feel so exposed out here lately. Like anything could knock me down."
→ wants `N_fortify`

---

### `N_toxicity` — inverse hints (creature finds things too safe, too mild, boring)
**Inverse words:** mild, boring, safe, tame, dull, harmless, weak, pedestrian, toothless

*Example:* "Everything's so tame around here. Nothing has any edge to it anymore."
→ wants `N_toxicity` (low-to-mid; for edge-seeking creatures)

---

### `N_aroma` — inverse hints (creature notices absence of scent, finds things odourless)
**Inverse words:** odourless, scentless, flat, unscented, bland-smelling, nose-blind, sterile

*Example:* "It just has no smell to it. My kind relies on scent. If it doesn't smell like anything, it means nothing to us."
→ wants `N_aroma`

---

### `N_purity` — inverse hints (creature finds things impure, adulterated, sloppy)
**Inverse words:** impure, contaminated, sloppy, crude, rough, mixed-up, adulterated, unrefined

*Example:* "It tastes like something was mixed in that shouldn't be there. I can always tell."
→ wants `N_purity`

---

### `P_protein` — inverse hints (creature is weak, hasn't eaten a real meal)
**Inverse words:** weak, skinny, underfed, malnourished, skipped a meal, running on empty, no strength

*Example:* "I skipped breakfast today and without that protein-rich meal I just don't have it in me."
→ wants `P_protein`

*This is the beetle example verbatim — it uses both a direct hint (protein-rich) and an
inverse hint (skipped a meal, don't have it in me) in the same line.*

---

### `P_lipid` — inverse hints (creature runs out of energy too quickly, can't sustain effort)
**Inverse words:** running out of steam, burning through it, can't keep it up, fading fast, short-lived

*Example:* "I start strong but I fade so fast. I need something that actually lasts."
→ wants `P_lipid`

---

### `P_mineral` — inverse hints (creature feels structurally weak, crumbling, soft)
**Inverse words:** crumbling, soft, brittle shell, weak structure, hollow, falling apart

*Example:* "My shell's been getting softer lately. Something's missing from my diet."
→ wants `P_mineral`

---

### `P_medicine` — inverse hints (creature is sick, fighting off something, run-down)
**Inverse words:** sick, ill, coming down with something, fighting it off, under the weather, infected, rundown

*Example:* "There's something going around in the burrow. Half of us are under the weather."
→ wants `P_medicine`

---

### `P_mutation` — inverse hints (creature is bored, stuck in routine, wants change)
**Inverse words:** bored, stuck, predictable, same old, routine, monotonous, stale

*Example:* "Same thing every day. I'm so bored I could scream. I need something different."
→ wants `P_mutation`

---

### `P_stability` — inverse hints (creature is uncertain, unreliable, inconsistent)
**Inverse words:** all over the place, inconsistent, unpredictable, chaotic, unreliable, scattered

*Example:* "I just need something I can count on. Everything's been so all over the place lately."
→ wants `P_stability`

---

## Combined hint example (direct + inverse in same line)

The most natural dialogue mixes direct and inverse hints in a single speech act.

> "I skipped breakfast and without that protein-rich meal I just don't have the strength for it today."

Breaking it down:
- "skipped breakfast" → inverse of `P_protein` (absence of meal = lacking protein)
- "protein-rich meal" → direct hint for `P_protein`
- "don't have the strength" → inverse of `N_vigor` (lacking strength = wants vigor)

Three hints in one line, none of them feeling like a game instruction. This is the
target register for all creature preference dialogue.

---

## Writer's checklist

When writing a dialogue line that should hint at a recipe or preference:

1. **Pick the dominant channel(s)** the creature prefers (1–2 channels usually).
2. **Choose hint words** from the channel vocabulary above — not the channel name itself.
3. **Choose a product type word** if the creature has a product type preference beyond honey.
4. **Embed naturally** — the creature is talking about themselves, not issuing a quest.
5. **Avoid double-hinting** — one strong hint per line is better than two weak ones.
6. **Leave room for experimentation** — a 50% match should get a partial response, so
   hints don't need to be complete. A creature can mention two separate preferences in
   two separate conversations.
7. **Grade hints are optional** — only use them for creatures that genuinely care about
   quality. Most basic creature allies are happy with common grade.

---

## Example: Full creature preference decode

**Bear NPC — preference profile:** `N_cool (0.7), N_calm (0.6), N_aroma (0.5), P_lipid (0.4)`
**Target product:** a honey made from cool + calm nectar with aromatic notes, rich pollen

**Dialogue line 1 (first encounter):**
> "My stomach's been restless lately. I keep coming to the river just to feel the cool air
> off the water. There's something about that smell — fresh, clean. Reminds me of better days."

Decoded: restless stomach → `N_calm`. Cool air off water → `N_cool`. Fresh clean smell → `N_aroma`.

**Dialogue line 2 (second encounter, after partial product offered):**
> "That was... almost right. A little closer to what I need. Something richer though.
> Fuller. Like it should really stay with you."

Decoded: richer, fuller, stays with you → `P_lipid`.

**Resulting recipe hunt:** player looks for a cool + calm + aromatic nectar plant near
water, and a lipid-rich pollen source. Crafts honey from that nectar and pollen. Gives
to bear. Match score high enough for ally status.

---

## Notes for systems designers

- Chemistry channel values on `FactionDef` are the preference thresholds. A match score
  is the dot product of (product channels × preference weights), normalised 0..1.
- A match score ≥ 0.9 = full ally. 0.6–0.89 = partial ally (reduced service quality
  or shorter alliance duration). 0.3–0.59 = neutral reaction ("nice, but not quite").
  < 0.3 = no effect or mild insult if toxicity is high for a low-tolerance creature.
- Alliance duration (if not permanent) is proportional to match score and quantity.
  Better product = longer alliance before re-gifting is needed.
- The player never sees match scores. They infer quality from the creature's response
  dialogue. Response dialogue uses the same vocabulary: "That's almost perfect" vs
  "That's exactly what I needed" vs "Hmm, close, but something's missing."
- Dialogue lines should never say "you need more N_cool." They say "it's almost there
  but it needs to be a little fresher."
