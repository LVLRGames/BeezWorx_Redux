# BeezWorx Scaffold Generation Prompt

Paste this prompt to a fresh AI coding session (Claude, GPT-4, etc.) to generate the
full project skeleton. Run it before Phase 0 of the implementation roadmap. The scaffold
produces compilable GDScript stubs — typed fields and method signatures with TODO bodies.
No logic yet. The phases fill in the logic one system at a time.

Split into two passes if the response is too long for one context window: Pass A covers
autoloads and data classes; Pass B covers scene nodes and UI.

---

## PROMPT — Pass A (Autoloads and Data Classes)

```
You are a senior Godot 4.6 engineer generating a compilable GDScript scaffold for a
game called BeezWorx. Produce actual GDScript files — not pseudocode. Every file must
compile without errors in Godot 4.6. Use strongly typed GDScript throughout.

Rules:
- class_name declarations on every file
- snake_case filenames, PascalCase class names
- All fields typed with correct GDScript 4 syntax (e.g. var foo: int = 0)
- All method signatures typed with return types
- Method bodies contain only: pass, return null, return 0, return false, return [],
  return {}, or a single TODO comment — NO logic
- Short header comment on each file explaining its role
- Array types use Array[Type] syntax
- Dictionary types use Dictionary[KeyType, ValueType] syntax where supported
- Use @export on all Resource fields intended for editor authoring
- Signals declared with typed parameters

Generate the following files in order. After each file, output a divider: ---FILE---

═══════════════════════════════════════════════════════════════
AUTOLOADS (res://autoloads/)
═══════════════════════════════════════════════════════════════

1. event_bus.gd
Owns no state. Declares all cross-system signals as typed signals.
Include ALL of these signals with correct typed parameters:

World signals:
  cell_occupied(cell: Vector2i, category: int)
  cell_cleared(cell: Vector2i)
  cell_plant_stage_changed(cell: Vector2i, new_stage: int)
  cell_plant_resources_changed(cell: Vector2i)
  cell_revealed(cell: Vector2i)

Hive signals:
  hive_built(hive_id: int, anchor_cell: Vector2i, colony_id: int)
  hive_destroyed(hive_id: int, anchor_cell: Vector2i, colony_id: int)
  hive_integrity_changed(hive_id: int, new_integrity: float)
  hive_slot_changed(hive_id: int, slot_index: int)
  hive_upgraded(hive_id: int, upgrade_type_id: StringName)
  hive_captured(hive_id: int, new_colony_id: int, old_colony_id: int)
  egg_laid(hive_id: int, slot_index: int, queen_pawn_id: int)
  egg_matured(hive_id: int, slot_index: int, role_tag: StringName, new_pawn_id: int)
  egg_starved(hive_id: int, slot_index: int)

Territory signals:
  territory_expanded(colony_id: int, cells: Array)
  territory_faded(colony_id: int, cells: Array)

Colony / pawn signals:
  pawn_spawned(pawn_id: int, colony_id: int, cell: Vector2i)
  pawn_died(pawn_id: int, colony_id: int, cause: StringName)
  pawn_hit(attacker_id: int, target_id: int, damage: float, effects: Array)
  pawn_loyalty_changed(pawn_id: int, new_loyalty: float)
  pawn_aged(pawn_id: int, new_age_days: int)
  queen_died(colony_id: int, had_heir: bool)
  colony_founded(colony_id: int)
  colony_dissolved(colony_id: int)
  succession_contest_started(colony_id: int)
  succession_contest_ended(colony_id: int, new_queen_id: int)
  plant_discovered(colony_id: int, plant_id: StringName, cell: Vector2i)
  biome_discovered(colony_id: int, biome_id: StringName, entry_cell: Vector2i)
  faction_first_contact(colony_id: int, faction_id: StringName, cell: Vector2i)
  item_discovered(colony_id: int, item_id: StringName)

Job signals:
  marker_placed(marker_id: int, marker_type_id: StringName, cell: Vector2i, colony_id: int)
  marker_removed(marker_id: int, cell: Vector2i, reason: StringName)
  job_posted(job_id: int, job_type_id: StringName, target_cell: Vector2i, colony_id: int, priority: int)
  job_claimed(job_id: int, pawn_id: int)
  job_completed(job_id: int, pawn_id: int)
  job_failed(job_id: int, pawn_id: int)

Recipe / diplomacy signals:
  recipe_discovered(colony_id: int, recipe_id: StringName)
  faction_relation_changed(colony_id: int, faction_id: StringName, new_relation: float)
  faction_preference_revealed(colony_id: int, faction_id: StringName)
  trade_completed(colony_id: int, faction_id: StringName, item_id: StringName, match_score: float)
  colony_influence_changed(colony_id: int, new_score: float)
  colony_morale_changed(colony_id: int, new_morale: float)

Time signals:
  day_changed(new_day: int)
  day_started()
  night_started()
  season_changed(new_season: int)
  year_changed(new_year: int)

Threat signals:
  raid_started(raid_id: int, target_colony_id: int)
  raid_ended(raid_id: int)
  threat_spawned(pawn_id: int, threat_type: StringName, near_cell: Vector2i)
  threat_deterred(pawn_id: int, threat_type: StringName)
  plant_attack(cell: Vector2i, target_pawn_id: int, plant_type: StringName)

Save signals:
  game_saved(slot_name: String)
  game_loaded(slot_name: String)
  autosave_completed()
  save_failed(slot_name: String, error: String)
  load_failed(slot_name: String, system: String, error: String)
  game_over(colony_id: int)
  autosave_completed()

2. time_service.gd
Autoload. Owns world clock. Fields: config (TimeConfig), world_time: float,
current_day: int, day_phase: float, is_daytime: bool, day_of_year: int,
current_season: int, current_year: int, and _prev_ fields for transition detection.
Constants: SPRING=0, SUMMER=1, FALL=2, WINTER=3.
Methods: initialize(config), advance(delta), get_day_phase(), is_night(), 
time_until_dawn(), time_until_dusk(), get_current_season_name(), is_season(season),
day_of_current_season(), fraction_through_season(), world_time_for_day(day),
elapsed_days(), save_state(), load_state(data).

3. hive_system.gd
Autoload. Fields: _hives: Dictionary[int, HiveState], _hives_by_cell: Dictionary[Vector2i, int],
_next_hive_id: int, _colony_inventory_cache: Dictionary, _colony_inventory_dirty: Dictionary.
Methods: register_hive(anchor_cell, colony_id, builder_pawn_id), get_hive(hive_id),
get_hives_for_colony(colony_id), get_capital_hive(colony_id), set_queen_bed(hive_id, slot_index, queen_pawn_id),
get_all_living_hives(), get_colony_inventory_count(colony_id, item_id),
find_nearest_hive_with_item(colony_id, item_id, min_count, near_cell),
find_nearest_hive_with_storage(colony_id, item_id, near_cell),
withdraw_item(hive_id, item_id, count), deposit_item(hive_id, item_id, count),
find_sleep_slot(pawn_id, colony_id, near_cell), reserve_sleep_slot(hive_id, slot_index, pawn_id),
release_sleep_slot(hive_id, slot_index, pawn_id), apply_damage(hive_id, amount, attacker_id),
repair_hive(hive_id, amount, repairer_pawn_id), apply_upgrade(hive_id, upgrade_type_id),
get_slot(hive_id, slot_index), get_slots_by_designation(hive_id, designation),
get_all_craft_orders(hive_id), get_nursery_eggs(colony_id), emit_slot_changed(hive_id, slot_index),
save_state(), load_state(data).

4. territory_system.gd
Autoload. Fields: _influence: Dictionary, _cell_contributors: Dictionary,
_hive_cells: Dictionary[int, Array], _active_fades: Dictionary, _recently_changed: Dictionary.
Constants: FADE_DURATION=120.0, EXPANSION_REACH=3.
Methods: get_influence(cell, colony_id), is_in_territory(cell, colony_id),
get_controlling_colony(cell), get_all_colonies_at(cell), get_cell_count_for_colony(colony_id),
get_contested_cell_count(colony_id), is_valid_expansion_cell(cell, colony_id),
get_plant_allegiance(cell, plant_colony_id), get_render_influence(cell, colony_id),
get_all_influence(cell), get_changed_cells_since(world_time),
expand_hive_radius(hive_id, new_radius), _recompute_from_hives(),
save_state(), load_state(data).

5. colony_state.gd
Autoload. Fields: _colonies: Dictionary[int, ColonyData], _next_colony_id: int.
Methods: create_colony(), get_colony(colony_id), get_player_colony(),
set_queen(colony_id, pawn_id), get_queen_id(colony_id), record_queen_death(colony_id, cause),
add_heir(colony_id, pawn_id), remove_heir(colony_id, pawn_id), get_heirs(colony_id),
add_known_recipe(colony_id, recipe_id), knows_recipe(colony_id, recipe_id),
get_known_recipes(colony_id), add_known_plant(colony_id, plant_id), knows_plant(colony_id, plant_id),
get_loyalty(pawn_id), modify_loyalty(pawn_id, delta, cause),
get_morale(colony_id), get_morale_modifiers(colony_id),
get_relation(colony_id, faction_id), modify_relation(colony_id, faction_id, delta, cause),
get_alliance_level(colony_id, faction_id), resolve_gift(colony_id, faction_id, item_id, count),
get_influence_score(colony_id), recompute_influence(colony_id),
save_state(), load_state(data).

6. job_system.gd
Autoload. Fields: _markers: Dictionary[int, MarkerData], _jobs: Dictionary[int, JobData],
_markers_by_cell: Dictionary[Vector2i, Array], _jobs_by_colony: Dictionary[int, Array],
_jobs_by_type: Dictionary[StringName, Array], _claimed_by_pawn: Dictionary[int, int],
_trails: Dictionary[int, TrailData], _next_marker_id: int, _next_job_id: int,
_next_trail_id: int.
Constants: MARKER_DECAY_DURATION=30.0.
Methods: place_marker(cell, marker_type_id, colony_id, placer_id, trail_id),
remove_marker(marker_id, reason), post_job(job_type_id, target_cell, colony_id, priority,
required_role_tags, source_marker_id, max_claimants, expires_after),
get_claimable_jobs(pawn_id, colony_id, role_tags, near_cell, search_radius),
claim_job(job_id, pawn_id), release_job(job_id, pawn_id),
complete_job(job_id, pawn_id), fail_job(job_id, pawn_id),
update_job_progress(job_id, progress_delta),
create_trail(colony_id, species_tags, item_filter, is_loop),
append_trail_node(trail_id, marker_id), close_trail(trail_id), dissolve_trail(trail_id),
get_markers_for_colony(colony_id), get_jobs_for_marker(marker_id),
get_job_claimed_by(pawn_id), get_markers_at_cell(cell),
save_state(), load_state(data).

7. pawn_registry.gd
Autoload. Fields: _states: Dictionary[int, PawnState], _nodes: Dictionary[int, WeakRef],
_by_colony: Dictionary[int, Array], _by_cell: Dictionary[Vector2i, Array], _next_id: int.
Methods: register(pawn_id, state, node), deregister(pawn_id),
get_state(pawn_id), get_node(pawn_id), get_ai(pawn_id),
get_pawns_for_colony(colony_id), get_all_pawn_ids(), get_pawns_near_cell(cell, radius),
get_pawns_in_hive(hive_id), next_id(), update_cell(pawn_id, new_cell),
save_state(), load_state(data).

8. save_manager.gd
Autoload. Fields: _active_slot: String, _autosave_timer: float, _autosave_interval: float,
_is_saving: bool, _is_loading: bool, _total_play_time: float.
Constants: SAVE_DIR, SAVE_EXTENSION, AUTOSAVE_SLOT, MAX_SAVE_SLOTS, CURRENT_VERSION.
Methods: save_game(slot_name), load_game(slot_name), delete_save(slot_name),
get_save_slots(), has_save(slot_name), get_active_slot(), start_new_game(config).

═══════════════════════════════════════════════════════════════
DATA CLASSES (res://world/, res://colony/, res://jobs/, res://pawns/)
═══════════════════════════════════════════════════════════════

9. res://world/hex_consts.gd
Static class (no class_name needed, or class_name HexConsts). All constants and static
utility functions: HEX_SIZE, SQRT3, CHUNK_SIZE, MAX_HEIGHT, HEIGHT_STEP, TERRAIN_TILE_U,
TERRAIN_TILE_V. Static methods: AXIAL_TO_WORLD(q, r) -> Vector2, WORLD_TO_AXIAL(x, z) -> Vector2i.
Enum: CellCategory { EMPTY, RESOURCE_PLANT, TREE, DEFENSIVE_ACTIVE, HIVE_ANCHOR,
TRAVERSABLE_STRUCTURE, RESOURCE_NODE, TERRITORY_MARKER, PAWN_SPAWN }.
Enum: CellChangeMutationHint { STRUCTURAL, STAGE_CHANGE, RESOURCE_CHANGE, MARKER_CHANGE }.

10. res://colony/hive/hive_state.gd
class_name HiveState extends RefCounted. All fields from hive spec: hive_id, colony_id,
anchor_cell, anchor_type, slots: Array[HiveSlot], slot_count, max_integrity, integrity,
is_destroyed, breach_timer, territory_radius, fade_timer, applied_upgrades: Array[StringName],
specialisation: StringName, is_capital.
Methods: to_dict() -> Dictionary, static from_dict(data) -> HiveState.

11. res://colony/hive/hive_slot.gd
class_name HiveSlot extends RefCounted.
Enum: SlotDesignation { GENERAL, BED, STORAGE, CRAFTING, NURSERY }.
Fields: slot_index, hive_id, designation, locked_item_id, assigned_pawn_id,
stored_items: Dictionary[StringName, int], capacity_units, craft_order: CraftOrder,
egg_state: EggState, sleeper_id.
Methods: to_dict(), static from_dict(data).

12. res://colony/hive/craft_order.gd
class_name CraftOrder extends RefCounted.
Fields: recipe_id, target_count, produced_count, is_repeating, crafter_pawn_id, progress.
Methods: to_dict(), static from_dict(data).

13. res://colony/hive/egg_state.gd
class_name EggState extends RefCounted.
Inner class FeedEntry: item_id: StringName, fed_at: float, fed_by: int.
Fields: laid_at, laid_by, maturation_day, feed_log: Array, is_starved, emerging_role: StringName.
Methods: to_dict(), static from_dict(data).

14. res://colony/colony_data.gd
class_name ColonyData extends RefCounted.
Inner class QueenRecord: pawn_name: String, pawn_id: int, reign_start: int, reign_end: int, cause: StringName.
Inner class MoraleModifier: source_id: StringName, value: float, expires_day: int, description: String.
Fields: colony_id, display_name, queen_pawn_id, heir_ids: Array[int], contest_active, contest_day,
queen_history: Array, known_recipe_ids: Array[StringName], known_plants: Array[StringName],
known_items: Array[StringName], discovered_biomes: Array[StringName], known_anchor_types: Array[StringName],
_loyalty_cache: Dictionary[int, float], _morale_cache: float, _morale_dirty: bool,
_morale_modifiers: Array, faction_relations: Dictionary[StringName, FactionRelation],
_influence_score: float, _influence_dirty: bool.
Methods: to_dict(), static from_dict(data).

15. res://colony/colony_data.gd (append — FactionRelation)
class_name FactionRelation extends RefCounted.
Inner class TradeRecord: day: int, item_id: StringName, item_count: int, match_score: float, relation_delta: float.
Fields: faction_id, relation_score, is_allied, is_hostile, trade_history: Array,
first_contact_day, last_gift_day, preference_revealed.
Methods: to_dict(), static from_dict(data).

(Note: FactionRelation can be a separate file res://colony/faction_relation.gd if preferred.)

16. res://jobs/job_data.gd
class_name JobData extends RefCounted.
Inner class JobMaterialReq: item_id: StringName, count: int, per_colony: bool.
Enum: JobStatus { POSTED, CLAIMED, EXECUTING, COMPLETED, FAILED, EXPIRED, CANCELLED }.
Fields: job_id, job_type_id, source_marker_id, colony_id, target_cell, target_pawn_id,
target_hive_id, required_role_tags: Array[StringName], required_items: Array,
priority, max_claimants, expires_at, status, claimant_ids: Array[int],
posted_at, claimed_at, completed_at, fail_count, max_fails, progress, task_plan.
Methods: to_dict(), static from_dict(data).

17. res://jobs/marker_data.gd
class_name MarkerData extends RefCounted.
Enum: MarkerCategory { JOB, NAV, INFO }.
Fields: marker_id, marker_type_id, marker_category, def, cell, placer_id, colony_id,
placed_at, decay_timer, job_ids: Array[int], job_progress, trail_id, trail_next_id, trail_prev_id.
Methods: to_dict(), static from_dict(data).

18. res://jobs/trail_data.gd
class_name TrailData extends RefCounted.
Fields: trail_id, colony_id, species_tags: Array[StringName], item_filter: Array[StringName],
node_ids: Array[int], is_loop.
Methods: to_dict(), static from_dict(data).

19. res://pawns/pawn_state.gd
class_name PawnState extends RefCounted.
Fields: pawn_id, pawn_name, species_id, role_id, colony_id, movement_type,
health, max_health, fatigue, age_days, max_age_days, is_alive, is_awake,
loyalty, inventory: PawnInventory, personality: PawnPersonality,
possessor_id, player_boost_active, ai_resume_state: Dictionary,
last_known_cell, active_buffs: Dictionary[StringName, float],
active_effects: Dictionary[StringName, EffectInstance].
Inner class EffectInstance: effect_id: StringName, duration: float, magnitude: float, source_id: int.
Methods: to_dict(), static from_dict(data).

20. res://pawns/pawn_inventory.gd
class_name PawnInventory extends RefCounted.
Inner class PawnInventorySlot: item_id: StringName, count: int.
Fields: capacity, slots: Array.
Methods: add_item(item_id, count) -> int, remove_item(item_id, count) -> bool,
get_count(item_id) -> int, is_full() -> bool, get_carried_weight() -> float,
get_item_tags() -> Array[StringName], to_dict(), static from_dict(data).

21. res://pawns/pawn_personality.gd
class_name PawnPersonality extends RefCounted.
Fields: seed, curiosity, boldness, diligence, chattiness, stubbornness,
dialogue_tags: Array[StringName].
Methods: generate(p_seed: int) -> void, to_dict(), static from_dict(data).

═══════════════════════════════════════════════════════════════
RESOURCE DEFINITIONS (res://defs/) — just the class declarations
═══════════════════════════════════════════════════════════════

Generate stub class files for each resource type. Just the class declaration,
@export fields with correct types, and no methods beyond _init if needed.

22. res://defs/items/item_def.gd — class_name ItemDef extends Resource
All @export fields: item_id, display_name, description, icon, mesh, stack_size,
carry_weight, is_liquid, tags: Array[StringName], nutrition_value, nursing_role_tag,
perishable, spoil_time, all chem_ floats (sweetness, heat, cool, vigor, calm,
restore, fortify, toxicity, aroma, purity), all pollen_ floats (protein, lipid,
mineral, medicine, irritant, fertility), quality_grade, diplomacy_value,
preferred_by_factions: Array[StringName].

23. res://defs/recipes/recipe_def.gd — class_name RecipeDef extends Resource
Inner class RecipeIngredient: item_id: StringName, tag_filter: StringName, count: int.
@export fields: recipe_id, display_name, ingredients: Array[RecipeIngredient],
output_item_id, output_count, output_quality, required_role_tags: Array[StringName],
craft_time, requires_hive_slot, required_station_tags: Array[StringName],
is_discoverable, discovery_hint, channel_output_map: Dictionary.

24. res://defs/species/species_def.gd — class_name SpeciesDef extends Resource
@export fields: species_id, display_name, movement_type (int), move_speed, max_health,
base_defence_mult, base_lifespan_days, lifespan_variance_days, min_lifespan_days,
stubbornness_lifespan_bonus, fatigue_rate, rest_rate, carry_capacity, reveal_radius,
alert_radius, possession_speed_boost, possession_action_boost, carry_weight_speed_curve,
water_capacity, lay_egg_cost, hive_destruction_survival_chance.

25. res://defs/roles/role_def.gd — class_name RoleDef extends Resource
@export fields: role_id, display_name, utility_behaviors: Array[Resource],
harvest_restrictions: Array[StringName], craft_wait_interval, fallback_behavior_id.

26. res://defs/abilities/ability_def.gd — class_name AbilityDef extends Resource
Enums: TargetingMode { SELF, WORLD_CELL, NEARBY_ITEM, NEARBY_PAWN, INVENTORY_ITEM,
CONTEXTUAL, HIVE_SLOT }, ExecutionMode { INSTANT, CHANNEL, TOGGLE },
AbilityEffectType { GATHER_RESOURCE, DROP_ITEM, PLACE_MARKER, REMOVE_MARKER, ATTACK,
CRAFT, POLLINATE, WATER_PLANT, BUILD_STRUCTURE, ENTER_HIVE, OFFER_TRADE,
LAY_EGG, POSSESS_PAWN, INTERACT_GENERIC }.
@export fields: ability_id, display_name, description, icon, targeting_mode,
range, requires_xz_alignment, valid_categories: Array[int], valid_item_tags: Array[StringName],
valid_pawn_tags: Array[StringName], execution_mode, channel_duration, cooldown, stamina_cost,
effect_type, item_id, item_count, job_marker_type, damage, diplomacy_item_id,
animation_hint, vfx_id, sfx_id, ai_use_conditions: Array[StringName], ai_priority.

27. res://defs/factions/faction_def.gd — class_name FactionDef extends Resource
@export fields: faction_id, display_name, species_id, home_biomes: Array[StringName],
is_unique, all pref_n_ and pref_p_ floats, preferred_product_tag, gift_sensitivity,
gift_interval_days, decay_rate_per_day, min_match_for_effect, ally_threshold,
hostile_threshold, service_type, service_description, dialogue_set,
greeting_line, ally_greeting, hostile_warning, will_approach_colony,
patrol_territory, relocates_seasonally, reaction_to_raid_nearby, gift_memory_days.

28. res://defs/markers/marker_def.gd — class_name MarkerDef extends Resource
Inner class JobTemplateDef (Resource): job_type_id, required_role_tags: Array[StringName],
required_items: Array, priority, max_claimants, expires_after, consumption_rate, progress_on_completion.
@export fields: marker_type_id, marker_category (int), display_name, icon, color,
crafted_from_item_id, requires_xz_alignment, valid_cell_categories: Array[int],
max_per_cell, can_place_outside_territory, is_trail_node, trail_species_tags: Array[StringName],
trail_item_filter: Array[StringName], generates_jobs: Array[JobTemplateDef],
repost_on_complete, repost_condition, is_persistent, decay_outside_territory,
manual_remove_only, return_item_on_remove, return_item_cost.

29. res://defs/threats/threat_def.gd — class_name ThreatDef extends Resource
@export fields: threat_id, threat_category (int), species_id, spawn_count_range,
spawn_distance_range, base_spawn_chance, influence_scale, honey_scale,
seasonal_multipliers: Array[float], raid_cooldown_days, can_be_appeased,
appeasement_faction: StringName.

30. res://defs/time_config.gd — class_name TimeConfig extends Resource
@export fields: day_length_seconds (default 600.0), days_per_season (default 91),
day_night_split (default 0.6), time_scale (default 1.0).

═══════════════════════════════════════════════════════════════
OUTPUT FORMAT
═══════════════════════════════════════════════════════════════

For each file output:
1. A comment line: # FILE: res://path/to/filename.gd
2. The complete GDScript file content
3. A divider: ---FILE---

After all files, output a complete file tree showing every file generated.
```

---

## PROMPT — Pass B (Scene Nodes and UI Stubs)

```
You are a senior Godot 4.6 engineer generating GDScript scene node stubs for BeezWorx.
These are the scene-owned nodes (not autoloads). Same rules as Pass A — typed fields,
method signatures, TODO bodies only. All files must compile.

Generate the following files:

1. res://pawns/pawn_base.gd — class_name PawnBase extends CharacterBody3D
Fields: @onready state: PawnState, @onready ai: PawnAI, @onready executor: PawnAbilityExecutor,
@onready interaction_detector: Area3D, @onready dialogue_detector: Area3D.
@export fields: species_def: SpeciesDef, role_def: RoleDef, action_ability: AbilityDef,
alt_ability: AbilityDef, interact_ability: AbilityDef.
Methods: get_pawn_id() -> int, _physics_process(delta), _on_interaction_targets_changed(targets),
_on_body_entered_dialogue(body), navigate_to(world_pos: Vector3),
_get_effective_move_speed() -> float, _get_effective_action_speed() -> float.

2. res://pawns/pawn_ai.gd — class_name PawnAI extends Node
Fields: pawn: PawnBase, ai_active: bool, current_job: JobData, current_subtask_index: int,
_tick_timer: float, _nearest_threat_id: int, _current_nav_target: Vector3, _cached_path: PackedVector3Array.
Constants: AI_TICK_INTERVAL = 0.25, ALERT_PROPAGATION_RADIUS = 8.
Methods: _process(delta), _evaluate(), _score_behavior(behavior, state) -> float,
_evaluate_condition(state, condition_id) -> bool, _try_claim_job(behavior, state) -> bool,
_tick_current_job(delta), _execute_subtask(subtask, delta) -> bool,
_build_subtask_sequence(job) -> Array, _check_threats(),
_decide_threat_response() -> StringName, _compute_flee_threshold() -> float,
_alert_colony(), receive_alert(from_cell: Vector2i, threat_id: int),
_get_tick_interval() -> float, _chunks_from_player() -> int.

3. res://pawns/pawn_ability_executor.gd — class_name PawnAbilityExecutor extends Node
Fields: pawn: PawnBase, cooldowns: Dictionary[StringName, float].
Methods: try_action() -> bool, try_alt_action() -> bool, try_interact() -> bool,
can_use(ability: AbilityDef) -> bool, resolve_target(ability: AbilityDef) -> Variant,
execute(ability: AbilityDef, target: Variant) -> void,
_tick_cooldowns(delta: float) -> void, _on_interact_generic(target: Variant) -> void.

4. res://pawns/possession_service.gd — class_name PossessionService extends RefCounted
Fields: possessed_pawns: Dictionary[int, int], max_players: int.
Methods: request_possess(player_slot, pawn_id) -> bool,
request_release(player_slot) -> void, get_possessed_pawn(player_slot) -> Node,
is_possessed(pawn_id) -> bool, get_possessor(pawn_id) -> int,
_can_possess(player_slot, pawn_id) -> bool.

5. res://world/hex_terrain_manager.gd — existing file, add these methods/fields:
Fields to add: _active_plant_pool: Dictionary[StringName, Array].
Methods to add: checkout_active_plant(type_id: StringName) -> Node3D,
return_active_plant(type_id: StringName, node: Node3D) -> void,
update_chunks_immediate() -> void.

6. res://colony/active_plant.gd — class_name ActivePlant extends Node3D
Fields: current_cell: Vector2i, colony_id: int, genes: HexPlantGenes, stage: int,
_plant_virtual_pawn_id: int, _cooldown_timer: float, _current_target_id: int.
Methods: initialize(cell: Vector2i, col_id: int, p_genes: HexPlantGenes, p_stage: int),
_process(delta), _check_for_targets(), _on_body_entered(body: Node3D),
_should_attack(pawn_id: int, allegiance: int) -> bool,
_begin_attack(target_pawn_id: int), _execute_attack(target_pawn_id: int),
_start_cooldown(), _play_attack_animation(), _update_trigger_radius(),
_is_valid_target_type(state: PawnState) -> bool.

7. res://autoloads/combat_system.gd — class_name CombatSystem extends Node (autoload)
Fields: none persistent.
Methods: resolve_hit(attacker_id, target_id, ability, is_player_controlled) -> float,
apply_hive_damage(hive_id, amount, attacker_id) -> void,
_apply_damage(pawn_id, damage, source_id) -> void,
_apply_hit_effects(pawn_id, ability) -> void,
_get_attack_multiplier(state) -> float, _get_defence_multiplier(state) -> float,
_tick_effects(delta) -> void, _tick_hazards(delta) -> void,
_tick_boundary_threats(delta) -> void, _trigger_bird_strike(pawn_id) -> void,
_kill_pawn(pawn_id, cause) -> void,
resolve_instant_kill(pawn_id, cause) -> void.

8. res://world/fog_of_war_system.gd — class_name FogOfWarSystem extends Node (scene-owned)
Fields: _revealed: Dictionary[Vector2i, bool].
Methods: reveal_around(cell: Vector2i, radius: int) -> void,
is_revealed(cell: Vector2i) -> bool,
save_state() -> Dictionary, load_state(data: Dictionary) -> void.

9. res://ui/ui_root.gd — class_name UIRoot extends CanvasLayer
Fields: @onready pawn_card: Control, @onready compass_strip: Control,
@onready season_time_indicator: Control, @onready pawn_switch_panel: Control,
@onready inventory_context_panel: Control, @onready marker_info_strip: Control,
@onready notification_feed: Control, @onready hive_overlay: Control,
@onready colony_management_screen: Control, @onready interaction_prompt: Control.
Methods: show_hive_overlay(hive_id: int) -> void, hide_hive_overlay() -> void,
is_hive_overlay_open() -> bool, show_notification(text: String, duration: float, is_critical: bool) -> void,
update_pawn_card(state: PawnState) -> void, open_colony_management() -> void,
close_colony_management() -> void, update_interaction_prompt(action_label: String, alt_label: String) -> void.

10. res://colony/lifecycle_system.gd — class_name LifecycleSystem extends Node (scene-owned)
Methods: _on_day_changed(new_day: int) -> void,
_check_natural_death(state: PawnState) -> void,
_roll_lifespan(species_def: SpeciesDef, personality: PawnPersonality) -> int,
_mature_egg(hive_id: int, slot_index: int) -> void,
_determine_role(feed_log: Array) -> StringName,
_create_pawn(egg: EggState, role_tag: StringName, birth_hive_id: int) -> int,
_crown_queen(colony_id: int, princess_id: int) -> void,
_exile_princess(origin_colony_id: int, princess_id: int) -> void,
_trigger_game_over(colony_id: int) -> void,
_recruit_retinue(colony_id: int, min_count: int, max_count: int) -> Array[int].

Output each file with # FILE: header and ---FILE--- divider.
After all files, output the complete updated file tree.
```

---

## After running the scaffold

Once both passes are complete:

1. **Verify the project opens** in Godot 4.6 without parse errors. Fix any typing
   issues (Godot 4.6 is strict about Array[Type] and Dictionary[K, V] syntax).

2. **Register autoloads** in Project Settings → Autoloads in this order:
   EventBus, TimeService, HexWorldState, HiveSystem, TerritorySystem,
   ColonyState, JobSystem, PawnRegistry, SaveManager, CombatSystem.

3. **Create minimal .tres resources** for testing:
   - `res://defs/time_config.tres` (TimeConfig with defaults)
   - One `ItemDef` for `nectar_basic`
   - One `SpeciesDef` for `bee_queen`

4. **Begin Phase 0** of the implementation roadmap — terrain migration. The scaffold
   gives you the class interfaces; the phases fill in the logic.
