# BeezWorx Architecture: Combat & Defense

> This document is a summary reference. The full authoritative spec is in
> `combat_threat_spec.md` (outputs folder).

---

## Purpose

Defines how threats interact with the player colony and how the colony defends itself
through soldier bees, active defense plants, and diplomatic alliances.

---

## Combat Resolution

All hits go through `CombatSystem.resolve_hit(attacker_id, target_id, ability)`.
Damage = `ability.damage × attack_multiplier × defence_multiplier`. Hit effects
(poison, paralysis, knockback, stun) are stored on `PawnState.active_effects` and
ticked by `CombatSystem` each frame.

Hive damage is separate: `CombatSystem.apply_hive_damage(hive_id, amount, attacker_id)`
calls through to `HiveSystem.apply_damage`. Hives have integrity; at 0 they are
destroyed. Below breach threshold (30% integrity), invaders can enter.

Player-controlled pawns deal 10% bonus damage (precision advantage, not raw stats).

---

## Threat Taxonomy

**Category 1 — Insects:** Hornets, rival bee swarms, caterpillars, grasshoppers, wasps.
Full pawn entities spawned by `ThreatDirector`. Can be killed by soldiers.

**Category 2 — Large animals:** Bear (targets hive for honey), Badger (digs at base).
Cannot be killed by bees. Stopped by deterrence accumulation from active plants and
allied animals. Bear requires ~4–7 unimpeded hits to destroy a hive. Deterrence from
briar/thistle/whip vine damage accumulates; at threshold the animal retreats.

**Category 3 — Aerial boundary:** Birds patrol above canopy threshold. Instant kill
on contact (workers), 60% health damage (queen — survivable once). Not spawned by
ThreatDirector — always present as altitude triggerzones.

**Category 4 — Environmental:** Cold zones (`N_heat` jelly counter), hot zones
(`N_cool` jelly counter). Applied by `CombatSystem._tick_hazards` per second.

---

## Territory and Defense Layers

**Territory overlap rule:** Colony border = union of all hive radii. When a hive is
destroyed, only cells with no overlap from living hives fade. Fade is gradual over
120 seconds, giving visible warning before full collapse.

**Fade consequences:**
- Active plants lose allegiance and begin friendly fire (see active_defense_plant_spec.md)
- Pawns with beds in the destroyed hive lose their housing → loyalty decay
- Allied faction supply lines through that hive's territory may weaken

**Defense layers in order of engagement:**
1. Briar/thistle fields — outer ring, slows and damages large animals on approach
2. Whip vines — mid-range, intercepts flying insects
3. Flytraps/sundews — close range, catches crawling insects near entrance
4. Soldier bees — active combat, patrol-based when no explicit markers placed
5. Allied animals — bear fights bear raiders; ant colony defends against rival ants

---

## Diplomatic Threat Resolution

Threats with `can_be_appeased = true` on their `ThreatDef` are suppressed when the
player has alliance with the `appeasement_faction` (relation ≥ 0.5). This means:
- Allied bear → bear raids suppressed
- Allied ant colony → rival ant swarm raids suppressed
Alliance decay means this protection is not permanent (see diplomacy_faction_spec.md).

---

## Raid Director

`ThreatDirector` (scene-owned node) checks spawn conditions every 60 real seconds.
Spawn chance scales with colony influence, honey stock, season, and time of day.
High honey → attracts bears and badgers. High influence → attracts rival bee swarms
and hornets. Winter suppresses most insect threats.

Raid cooldowns prevent the same threat type spawning too frequently. All cooldown
timestamps are saved and restored — players cannot exploit reloads to reset raids.

---

## Hive Takeover

Player can capture a rival hive instead of destroying it:
1. Reduce integrity below 30% (breach threshold)
2. Queen enters rival hive via forced `ENTER_HIVE`
3. Queen uses `PLACE_COLONY_MARKER` ability → stamps colony pheromone
4. Worker morale resolution: loyal workers resist (eliminated), moderately loyal flee,
   low loyalty workers defect to player colony with starting loyalty 0.3

Captured hive retains 50% integrity and all slot infrastructure.

---

## Queen Mortality

The colony must always have a queen. Queen death = game over unless a princess is
currently maturing in a nursery slot. Succession is natural (no timer) — the player
is simply blocked from queen-exclusive actions until the princess matures and the
player performs `BECOME_QUEEN`. Multiple simultaneous heirs trigger a 1-day contest;
eldest wins, others exile and potentially found daughter colonies.

See `colony_lifecycle_spec.md` for full succession rules.
