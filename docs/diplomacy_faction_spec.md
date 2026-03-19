# BeezWorx MVP Spec: Diplomacy / Faction System

This document specifies faction definitions, the diplomacy interaction flow, preference
scoring, service contracts, alliance maintenance, the dialogue system as a discovery
mechanic, faction-specific behavior, and how diplomatic state connects to combat,
economy, and navigation. It is the authoritative reference for `FactionDef`,
`DiplomacyService`, and all interspecies relationship mechanics.

---

## Purpose and scope

Diplomacy is how the colony grows beyond its own biology. Bees alone can gather, craft,
and defend — but ant logistics, beetle earthmoving, bear protection, butterfly
pollination, and grasshopper grazing all require relationships. Those relationships are
built through understanding what each creature wants, producing it, and offering it
at the right time.

The core promise: diplomacy feels like natural interaction, not a quest menu. Creatures
talk about their lives. Players observe, experiment, and discover. The system rewards
curiosity and patience, not grinding.

This spec covers:
- FactionDef: static definition of each faction's identity and preferences
- Faction NPC: the pawn that represents a faction diplomatically
- The diplomacy interaction flow: approach, dialogue, offer, response
- Preference scoring: how well a gift matches faction needs
- Service contracts: what alliances unlock
- Alliance maintenance: decay, re-gifting, response to neglect
- Preference discovery: how the player learns what factions want
- Faction-specific dialogue behavior
- Multi-faction dynamics: factions that know each other
- EventBus integration and save/load

It does **not** cover: combat appeasement (Combat spec), territory influence from allied
factions (TerritorySystem), ant conveyor job mechanics (JobSystem spec), or loyalty
decay to the player colony (ColonyState spec).

---

## FactionDef (Resource)

One `.tres` per faction. Lives in `res://defs/factions/`.

```
class_name FactionDef
extends Resource

# Identity
@export var faction_id:           StringName
@export var display_name:         String
@export var species_id:           StringName    # which pawn species represents them
@export var home_biomes:          Array[StringName]  # biomes where this faction spawns
@export var is_unique:            bool = false  # true = one instance in world (bear, ant queen)
                                                # false = multiple instances possible

# Preferences — chemistry channel weights (0..1 each)
# These are HIDDEN from the player; discovered through dialogue
@export var pref_n_sweetness:     float = 0.0
@export var pref_n_heat:          float = 0.0
@export var pref_n_cool:          float = 0.0
@export var pref_n_vigor:         float = 0.0
@export var pref_n_calm:          float = 0.0
@export var pref_n_restore:       float = 0.0
@export var pref_n_fortify:       float = 0.0
@export var pref_n_toxicity:      float = 0.0
@export var pref_n_aroma:         float = 0.0
@export var pref_n_purity:        float = 0.0
@export var pref_p_protein:       float = 0.0
@export var pref_p_lipid:         float = 0.0
@export var pref_p_mineral:       float = 0.0
@export var pref_p_medicine:      float = 0.0
@export var pref_p_irritant:      float = 0.0
@export var pref_p_fertility:     float = 0.0

# Preferred product type (JOY = any honey; BREAD = bee_bread base; etc.)
@export var preferred_product_tag: StringName = &"honey"

# Diplomacy mechanics
@export var gift_sensitivity:      float = 1.0   # how much each gift moves the relation needle
@export var gift_interval_days:    int = 14      # days between required gifts to maintain alliance
@export var decay_rate_per_day:    float = 0.02  # relation drop per day past gift_interval
@export var min_match_for_effect:  float = 0.2   # minimum gift match to have any relation effect
@export var ally_threshold:        float = 0.5   # relation score to become allied
@export var hostile_threshold:     float = -0.3  # relation score to become hostile

# Service provided when allied
@export var service_type:          StringName    # see service types below
@export var service_description:   String

# Dialogue
@export var dialogue_set:          StringName    # id of DialogueDef collection for this faction
@export var greeting_line:         String        # first line when approached cold
@export var ally_greeting:         String        # line when already allied
@export var hostile_warning:       String        # line when relation is negative
```

---

## MVP faction roster

### Ant Colony (Queen Ant)
```
faction_id: "ant_colony"
species_id: "ant_queen"
preferred_product_tag: "jelly"
pref_n_aroma: 0.8, pref_n_calm: 0.6, pref_p_protein: 0.5
gift_interval_days: 7      # ants need regular supply for their workforce
decay_rate_per_day: 0.04   # faster decay — ants are demanding
service_type: "logistics"  # unlocks ant conveyor trail markers
is_unique: true
```

**Discovery path:** Player meets ant queen near a large ant colony. She mentions her
workers' constant need for order and nourishment. "They march so far each day. I need
something that keeps them calm and fed." → `n_calm` + `jelly` base. Aroma component
revealed on second dialogue encounter or after first partial match gift.

**Service detail:** Alliance unlocks the `ANT_CONVEYOR_NODE` marker recipe and enables
ants from this colony to respond to placed ant trail markers within the colony's
territory.

---

### Bear
```
faction_id: "bear"
species_id: "bear"
preferred_product_tag: "honey"
pref_n_cool: 0.7, pref_n_calm: 0.6, pref_n_aroma: 0.5, pref_p_lipid: 0.4
gift_interval_days: 21     # bears are patient; gift every 3 weeks
decay_rate_per_day: 0.015  # slow decay — bears hold grudges less than ants
service_type: "guardian"   # allied bear defends colony against other large animals
is_unique: false            # multiple bears in world; each a separate FactionRelation
```

**Discovery path:** Bear found near river or forest edge. Often has a physical ailment
or complaint. "My stomach's been restless lately. I keep coming to the river just to
feel the cool air off the water. There's something about that smell — fresh, clean."
→ `n_cool` + `n_calm` + `n_aroma`. Lipid component: "I just feel like nothing fills
me up for long." → `p_lipid`.

**Service detail:** An allied bear will intercept bear raiders and fight them. Player
can also possess the bear for direct combat (strong melee, great for threatening
badgers). Bear has historical memory of queen lineage — queries `queen_history` for
generational dialogue.

---

### Beetle
```
faction_id: "beetle"
species_id: "dung_beetle"
preferred_product_tag: "bread"
pref_p_protein: 0.8, pref_n_vigor: 0.6, pref_p_mineral: 0.4
gift_interval_days: 14
decay_rate_per_day: 0.025
service_type: "earthmoving"  # beetles dig holes, move rocks, transplant plants
is_unique: false
```

**Discovery path:** Found struggling to move a heavy object. "Without that protein-rich
meal I just don't have it in me today." → `p_protein` + `bread` base. Vigor ("gets me
going, legs moving") and mineral ("something solid, earthy") revealed through repeat
encounters or after partial success.

**Service detail:** Allied beetles respond to earthmoving markers — digging planting
holes for seeds, moving rocks off paths, transplanting living plants to new cells (the
mechanic that allows intentional garden redesign without waiting for natural seeds).

---

### Butterfly Swarm
```
faction_id: "butterfly_swarm"
species_id: "butterfly"
preferred_product_tag: "nectar"   # raw nectar, not processed honey
pref_n_sweetness: 0.7, pref_p_fertility: 0.8, pref_n_aroma: 0.5
gift_interval_days: 10
decay_rate_per_day: 0.03
service_type: "pollination"  # butterflies actively pollinate player's resource plants
is_unique: false              # swarms appear seasonally; separate relation per swarm
```

**Discovery path:** Butterflies encountered in meadows or near flower fields. Dialogue
is ephemeral and poetic — they talk about flowers, migration, seasons. "We follow the
sweetest blooms. Something worth coming back to." → `n_sweetness` + `n_aroma`. Fertility
component: "Where we go, things grow." → `p_fertility`.

**Service detail:** Allied butterfly swarm actively pollinates resource plants in
territory each day, increasing breeding speed and seed set. Particularly valuable for
accelerating hybrid plant development. Butterflies are naturally non-hostile — their
neutral behavior is already harmless, but alliance means they actively help rather than
just passing through.

---

### Grasshopper (Non-diplomatic — lured)
```
faction_id: "grasshopper"
species_id: "grasshopper"
preferred_product_tag: "honey"
pref_n_toxicity: 0.5, pref_n_vigor: 0.7   # they like things with a little buzz
gift_interval_days: N/A    # grasshoppers aren't formally allied; they're lured
service_type: "grazing"    # eats plants near dropped honey
```

**Grasshoppers are not diplomatic partners.** They cannot be allied in the traditional
sense. Instead, the player uses the `GRAZE` marker (which drops honey bait on target
cells) to attract grasshoppers to specific areas for controlled grazing. This uses
the lure mechanic rather than the formal diplomacy flow.

**Discovery path:** Player finds grasshoppers eating unwanted grass near the colony.
"We just wanna eat and party, yeah? Give us something good and we'll go wherever the
party is." → lured by honey with vigor/toxicity channels (hopperwine). The recipe
for hopperwine is `honey_basic + nectar_toxic` — a honey with a mild intoxicating
effect that grasshoppers find irresistible.

**Implementation:** Grasshoppers respond to dropped item gems with the `honey` tag
near their current location. No formal `FactionRelation` record needed — the GRAZE
marker handles the interaction through the job system. Grasshoppers that eat near a
GRAZE marker are still wild creatures following a lure, not colony allies.

---

## Faction NPC

Each unique faction (ant queen, bear) has a specific NPC pawn in the world that the
player must find and approach. Non-unique factions (beetles, butterflies) have any
instance of their species serve as the diplomatic representative.

Faction NPCs are spawned by `ThreatDirector` or a `FactionSpawner` (simple node that
reads `FactionDef.home_biomes` and places NPCs during world generation). They are
standard pawn entities with `colony_id = -1` (neutral) and a special `is_faction_npc`
flag on `PawnState`.

Faction NPCs do not age or die at MVP — they are persistent world anchors. Post-MVP,
NPC death creates faction succession (new ant queen, new alpha bear) with its own
dialogue arc.

---

## The diplomacy interaction flow

### Step 1: Approach and greeting

When the player (as queen) enters `InteractionDetector` range of a faction NPC, the
contextual interact prompt fires: "Talk to [Faction Name]".

Pressing interact calls `DiplomacyService.begin_interaction(queen_pawn_id, npc_pawn_id)`.

The NPC delivers their greeting line based on current relation state:
- First encounter → `FactionDef.greeting_line`
- Known but not allied → ambient dialogue from `dialogue_set`
- Allied → `FactionDef.ally_greeting`
- Hostile → `FactionDef.hostile_warning` (player cannot offer gifts while hostile)

### Step 2: Dialogue and hint delivery

After greeting, the NPC delivers 1–3 ambient dialogue lines selected from their
`dialogue_set`. Lines are selected by matching the NPC's `dialogue_tags` (personality)
and current world context tags (season, time of day, current relation level, whether
preference has been revealed).

Lines include preference hints using the vocabulary from `dialogue_hint_vocabulary.md`.
The system does not tell the player which lines contain hints — all dialogue looks the
same. Players learn to pay attention.

```
func _select_dialogue_lines(npc: PawnState, context: DialogueContext) -> Array[String]:
    var eligible: Array[DialogueLine] = []
    for line in dialogue_def.lines:
        if _line_matches_context(line, npc, context):
            eligible.append(line)
    # Weight by personality match
    eligible.sort_custom(func(a, b):
        return _personality_weight(a, npc) > _personality_weight(b, npc)
    )
    # Return top 1-3 with randomness
    return eligible.slice(0, randi_range(1, 3))
```

### Step 3: Offer

After dialogue, if the relation is not hostile, the player can offer an item from their
inventory. The HUD presents the offer UI: current inventory items the queen is carrying,
with the option to select one stack to offer.

The player does NOT see any match score or hint about which item to offer. They offer
based on their understanding of the dialogue hints.

```
func offer_item(colony_id: int, faction_id: StringName, item_id: StringName, count: int) -> void:
    ColonyState.resolve_gift(colony_id, faction_id, item_id, count)
    var relation: FactionRelation = ColonyState.get_relation(colony_id, faction_id)
    var match_score: float = relation.trade_history.back().match_score
    _deliver_response_dialogue(faction_id, match_score, relation.relation_score)
```

### Step 4: Response dialogue

The NPC responds to the gift with dialogue calibrated to the match score:

| Match score | Response tone | Example |
|---|---|---|
| 0.0 – 0.2 | Polite rejection / confusion | "That's... not really what I had in mind." |
| 0.2 – 0.4 | Mild positive / partial interest | "Hmm. That's not bad. Something's almost right." |
| 0.4 – 0.6 | Genuine interest | "Now that's getting somewhere. You're close." |
| 0.6 – 0.8 | Strong positive | "That's almost exactly it. Just a little off." |
| 0.8 – 0.95 | Near-perfect | "That's nearly perfect. I can work with this." |
| 0.95 – 1.0 | Perfect match | "Yes. That's exactly what I needed." |

**On first gift with match_score ≥ 0.3:** `preference_revealed = true` fires
`EventBus.faction_preference_revealed`. The NPC delivers a special response that
confirms the player is on the right track and adds one more specific hint about what
would make it even better. This is the reward for the first successful experiment —
not a full reveal, but enough to narrow the search.

**On alliance threshold crossed** (relation_score ≥ `ally_threshold`): NPC delivers
alliance dialogue ("I think we understand each other now. My people are yours.") and
`EventBus.faction_relation_changed` fires with the new allied state. Service unlocks
immediately.

### Step 5: Service activation

`DiplomacyService` listens to `EventBus.faction_relation_changed`. When a faction
transitions to allied:

```
func _on_faction_allied(colony_id: int, faction_id: StringName) -> void:
    var def: FactionDef = Registry.get_faction(faction_id)
    match def.service_type:
        &"logistics":
            # Unlock ant trail marker recipe in ColonyState.known_recipes
            ColonyState.add_known_recipe(colony_id, &"marker_ant_trail")
            # Reveal ant trail recipe ingredients through NPC dialogue hint
            _trigger_recipe_hint_dialogue(faction_id, &"marker_ant_trail")
        &"guardian":
            # Register bear as a defensive guardian for this colony
            _register_guardian(colony_id, faction_id)
        &"earthmoving":
            # Unlock beetle earthmoving markers
            ColonyState.add_known_recipe(colony_id, &"marker_beetle_dig")
        &"pollination":
            # Register butterfly swarm as active pollinator in territory
            _register_pollinator(colony_id, faction_id)
```

**Recipe reveal through dialogue:** When a service unlocks a recipe (ant trail marker),
the NPC delivers a dialogue line that hints at the ingredients — not states them
outright. "My workers respond to something that smells like home and feels like order.
You'll figure it out." → `n_aroma` + `n_calm` in marker_base + a calm/ordered nectar.
This keeps the experimentation loop alive even after alliance.

---

## Preference scoring detail

`DiplomacyService._score_gift` computes the match between an offered item and a
faction's preference profile:

```
func _score_gift(item_id: StringName, count: int, def: FactionDef) -> float:
    var item: ItemDef = Registry.get_item(item_id)
    if item == null:
        return 0.0

    # Product type match: does this item have the preferred product tag?
    var type_match: float = 1.0 if item.tags.has(def.preferred_product_tag) else 0.5
    # Wrong product type is not zero — it's just less effective

    # Chemistry channel match: dot product of item channels vs preference weights
    var channel_score: float = (
        item.chem_sweetness  * def.pref_n_sweetness  +
        item.chem_heat       * def.pref_n_heat        +
        item.chem_cool       * def.pref_n_cool        +
        item.chem_vigor      * def.pref_n_vigor       +
        item.chem_calm       * def.pref_n_calm        +
        item.chem_restore    * def.pref_n_restore     +
        item.chem_fortify    * def.pref_n_fortify     +
        item.chem_toxicity   * def.pref_n_toxicity    +
        item.chem_aroma      * def.pref_n_aroma       +
        item.chem_purity     * def.pref_n_purity
    )

    # Pollen channels (relevant for bread, jelly products)
    var pollen_score: float = (
        item.pollen_protein  * def.pref_p_protein    +
        item.pollen_lipid    * def.pref_p_lipid      +
        item.pollen_mineral  * def.pref_p_mineral    +
        item.pollen_medicine * def.pref_p_medicine   +
        item.pollen_irritant * def.pref_p_irritant   +
        item.pollen_fertility * def.pref_p_fertility
    )

    # Normalise: sum of preference weights is the maximum possible score
    var max_score: float = _sum_preference_weights(def)
    if max_score <= 0.0:
        return type_match

    var normalised: float = (channel_score + pollen_score) / max_score
    var quality_bonus: float = (item.quality_grade - 1) * 0.05  # 0..0.2 bonus for quality

    return clampf(type_match * normalised + quality_bonus, 0.0, 1.0)
```

**Quality grade matters:** A Royal-grade honey with perfect channel match scores up to
0.2 higher than a Common-grade honey with the same channels. This rewards the player
for breeding Lush and Royal variant plants — the chemistry is the same but the grade
amplifies it.

**Wrong product type penalty:** Offering bee_bread to a faction that prefers honey
gets a 0.5 multiplier on the channel score. It is not zero because some channel
overlap still registers — a bread with high sweetness offered to a honey-preferring
faction is partially effective. This prevents the system from being a pure binary
check.

---

## Alliance maintenance

### The gift clock

When an alliance is formed, `FactionRelation.last_gift_day` is set to the current day.
`ColonyState._on_day_changed` checks all allied factions:

```
func _check_alliance_decay(colony_id: int) -> void:
    for faction_id in _colonies[colony_id].faction_relations:
        var rel: FactionRelation = _colonies[colony_id].faction_relations[faction_id]
        if not rel.is_allied:
            continue
        var def: FactionDef = Registry.get_faction(faction_id)
        var days_since_gift: int = TimeService.current_day - rel.last_gift_day
        if days_since_gift > def.gift_interval_days:
            var excess_days: int = days_since_gift - def.gift_interval_days
            modify_relation(colony_id, faction_id, -def.decay_rate_per_day, &"neglect")
```

### Warning dialogue

Before an alliance breaks, the faction NPC shifts to warning-tone ambient dialogue:

At 75% through the decay window: "I haven't heard from you in a while."
At 90%: "My patience is not infinite."
At alliance threshold crossed downward: Full break dialogue + service revocation.

This warning gives the player time to act before losing the alliance. The player who
is paying attention to NPC dialogue will never be blindsided by a lost alliance.

### Re-establishing a broken alliance

If relation drops below `ally_threshold` but stays above `hostile_threshold`:
- Services are revoked immediately.
- Player can re-gift to rebuild the relation score.
- No cooldown on re-gifting — the player can immediately begin repairing.

If relation drops below `hostile_threshold`:
- NPC becomes hostile — won't accept gifts.
- For large animals (bears), this may trigger them becoming a raid threat.
- To reset from hostile requires a specific "peace offering" — an item the faction
  values highly (match_score ≥ 0.7), offered by walking into dialogue range despite
  the hostile warning. High risk, but it opens the door.

---

## Faction-specific behavior quirks

These are behavioral properties on `FactionDef` that make each faction feel distinct
beyond their preference profile.

```
@export var will_approach_colony:    bool = false  # does the NPC come to the player, or wait to be found?
@export var patrol_territory:        bool = false  # does the NPC move around or stay in one area?
@export var relocates_seasonally:    bool = false  # does the NPC move in different seasons?
@export var reaction_to_raid_nearby: StringName    # "ignore", "flee", "help" if a raid occurs near them
@export var gift_memory_days:        int = 90      # how long they remember past gifts in dialogue
```

| Faction | Approaches | Patrols | Seasonal | Raid reaction |
|---|---|---|---|---|
| Ant queen | No — found in ant mound | No — stays in mound area | No | help (defends against ground threats) |
| Bear | No — found near river/cave | Yes — patrols territory | Yes — hibernates in winter | help (fights rival bears) |
| Beetle | No — found near rocks | Yes — slow patrol near rock formations | No | flee |
| Butterfly | No — seasonal migration | Yes — follows flower blooms | Yes — only spring/summer | flee |

**Bear hibernation:** During winter, the bear NPC enters `is_hibernating = true` state.
The player cannot interact with them. Any active bear alliance persists through winter —
the bear remembers the relationship even if the gift clock pauses during hibernation.
`last_gift_day` does not advance during hibernation, so the gift interval effectively
pauses. This is fair to the player — you cannot gift a sleeping bear, so you shouldn't
lose the alliance because of it.

---

## Multi-faction dynamics

At MVP, diplomacy is strictly bilateral (player ↔ faction). Post-MVP, factions can
know each other and the player's reputation can affect multiple relations at once.

However, one multi-faction rule exists at MVP: **hostile factions don't trade with
each other's allies.** If the player is allied with an ant colony and a rival ant
colony exists in the same territory, the rival ants may become hostile to the player
by default. This is handled by `ThreatDirector` treating rival ant colony members as
hostile when the player has a competing ant alliance.

This is the only implemented faction-to-faction dynamic at MVP. It is sufficient to
create emergent conflict without requiring a full faction relationship graph.

---

## DiplomacyService

`DiplomacyService` is not an autoload — it is a stateless helper class (static methods
only) that orchestrates the diplomacy flow. State lives on `ColonyState`. This keeps
the service lightweight and avoids another autoload dependency.

```
class_name DiplomacyService

static func begin_interaction(queen_id: int, npc_id: int) -> void
static func offer_item(colony_id: int, faction_id: StringName, item_id: StringName, count: int) -> void
static func can_offer(colony_id: int, faction_id: StringName) -> bool
static func get_response_dialogue(faction_id: StringName, match_score: float, relation: float) -> String
static func _score_gift(item_id: StringName, count: int, def: FactionDef) -> float
static func _trigger_recipe_hint_dialogue(faction_id: StringName, recipe_id: StringName) -> void
```

---

## EventBus integration

```
# Emitted (via ColonyState or DiplomacyService):
EventBus.faction_relation_changed(colony_id, faction_id, new_score, new_state)
EventBus.faction_preference_revealed(colony_id, faction_id)
EventBus.trade_completed(colony_id, faction_id, item_id, match_score)

# Consumed by DiplomacyService / ColonyState:
EventBus.day_changed            → check alliance decay for all colonies
EventBus.season_changed         → update faction patrol and availability states
EventBus.pawn_died              → if faction NPC died, mark faction as temporarily unavailable
EventBus.queen_died             → all faction relations gain "instability" modifier
                                   (relations decay faster during succession period)
```

**Queen death and faction relations:** When the queen dies, all faction allies
experience an instability modifier on their relation score — small daily decay for
the period until a new queen is crowned. This represents the factions feeling uncertain
about the colony's future. The decay stops when a new queen performs `BECOME_QUEEN`.
A fast succession minimises relation damage; a long interregnum can break weaker
alliances. One more reason to plan succession well.

---

## Save / load

Faction relation state is saved as part of `ColonyState.save_state()`:

```
# Per faction relation:
{
    "faction_id":            rel.faction_id,
    "relation_score":        rel.relation_score,
    "is_allied":             rel.is_allied,
    "is_hostile":            rel.is_hostile,
    "first_contact_day":     rel.first_contact_day,
    "last_gift_day":         rel.last_gift_day,
    "preference_revealed":   rel.preference_revealed,
    "trade_history":         rel.trade_history.map(func(r): return r.to_dict()),
}
```

`FactionDef` resources are not saved — they are static definitions. Only the runtime
relation state is persisted.

---

## MVP scope notes

Deferred past MVP:

- Faction-to-faction relationship graph (factions knowing each other, reputation
  spillover between factions).
- Faction NPC death and succession (new ant queen, alpha bear replacement).
- Player-named diplomatic agreements (formal treaties with terms).
- Faction territorial claims (factions defending their own territory as well as
  the colony's).
- Gift market pricing (offering too much at once causes diminishing returns — markets
  become saturated). At MVP, more is always better within a session.
- Faction-specific questlines (bear asking the player to clear a rival bear from
  his territory before allying). The dialogue system supports this but the quest
  tracking layer is post-MVP.
- Human faction (the most complex diplomatic challenge — asymmetric power, smoke
  mechanics, harvesting threat).
