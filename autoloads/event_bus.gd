# FILE: res://autoloads/event_bus.gd
# Cross-system signal hub for decoupled communication.
# class_name EventBus
extends Node
@warning_ignore_start("unused_signal")

signal interaction_target_changed(pawn_id:int, target_info:Dictionary)


# World signals
signal cell_occupied(cell: Vector2i, category: int)
signal cell_cleared(cell: Vector2i)
signal cell_plant_stage_changed(cell: Vector2i, new_stage: int)
signal cell_plant_resources_changed(cell: Vector2i)
signal cell_revealed(cell: Vector2i)

# Plant signals
signal plant_stage_changed(cell: Vector2i, prev_stage: int, new_stage: int)
signal plant_sprouted(cell: Vector2i, plant_id: String, parent_cell: Vector2i)
signal plant_died(cell: Vector2i)

# Hive signals
signal hive_built(hive_id: int, anchor_cell: Vector2i, colony_id: int)
signal hive_destroyed(hive_id: int, anchor_cell: Vector2i, colony_id: int)
signal hive_integrity_changed(hive_id: int, new_integrity: float)
signal hive_slot_changed(hive_id: int, slot_index: int)
signal hive_upgraded(hive_id: int, upgrade_type_id: StringName)
signal hive_captured(hive_id: int, new_colony_id: int, old_colony_id: int)
signal egg_laid(hive_id: int, slot_index: int, queen_pawn_id: int)
signal egg_matured(hive_id: int, slot_index: int, role_tag: StringName, new_pawn_id: int)
signal egg_starved(hive_id: int, slot_index: int)

# Territory signals
signal territory_expanded(colony_id: int, cells: Array)
signal territory_faded(colony_id: int, cells: Array)

# Colony / pawn signals
signal player_pawn_ready(pawn: Node3D, player_slot: int)
signal pawn_registered(pawn_id: int, colony_id: int)
signal pawn_spawned(pawn_id: int, colony_id: int, cell: Vector2i)
signal pawn_died(pawn_id: int, colony_id: int, cause: StringName)
signal pawn_hit(attacker_id: int, target_id: int, damage: float, effects: Array)
signal pawn_loyalty_changed(pawn_id: int, new_loyalty: float)
signal pawn_aged(pawn_id: int, new_age_days: int)
signal pawn_possessed(player_slot: int, pawn_id: int)
signal pawn_inventory_changed(pawn_id: int)
signal pawn_action_context_changed(pawn_id: int)
signal queen_died(colony_id: int, had_heir: bool)
signal colony_founded(colony_id: int)
signal colony_dissolved(colony_id: int)
signal succession_contest_started(colony_id: int)
signal succession_contest_ended(colony_id: int, new_queen_id: int)
signal plant_discovered(colony_id: int, plant_id: StringName, cell: Vector2i)
signal biome_discovered(colony_id: int, biome_id: StringName, entry_cell: Vector2i)
signal faction_first_contact(colony_id: int, faction_id: StringName, cell: Vector2i)
signal item_discovered(colony_id: int, item_id: StringName)
signal item_collected(pawn_id: int, item_id: StringName, count: int)
signal item_used(pawn_id: int, item_id: StringName, count: int)
signal item_deposited(pawn_id: int, hive_id: int, item_id: StringName, count: int)

# Job signals
signal marker_placed(marker_id: int, marker_type_id: StringName, cell: Vector2i, colony_id: int)
signal marker_removed(marker_id: int, cell: Vector2i, reason: StringName)
signal job_posted(job_id: int, job_type_id: StringName, target_cell: Vector2i, colony_id: int, priority: int)
signal job_claimed(job_id: int, pawn_id: int)
signal job_completed(job_id: int, pawn_id: int)
signal job_failed(job_id: int, pawn_id: int)

# Recipe / diplomacy signals
signal recipe_discovered(colony_id: int, recipe_id: StringName)
signal faction_relation_changed(colony_id: int, faction_id: StringName, new_relation: float)
signal faction_preference_revealed(colony_id: int, faction_id: StringName)
signal trade_completed(colony_id: int, faction_id: StringName, item_id: StringName, match_score: float)
signal colony_influence_changed(colony_id: int, new_score: float)
signal colony_morale_changed(colony_id: int, new_morale: float)

# Time signals
signal day_changed(new_day: int)
signal day_started()
signal night_started()
signal season_changed(new_season: int)
signal year_changed(new_year: int)

# Threat signals
signal raid_started(raid_id: int, target_colony_id: int)
signal raid_ended(raid_id: int)
signal threat_spawned(pawn_id: int, threat_type: StringName, near_cell: Vector2i)
signal threat_deterred(pawn_id: int, threat_type: StringName)
signal plant_attack(cell: Vector2i, target_pawn_id: int, plant_type: StringName)

# Save signals
signal game_saved(slot_name: String)
signal game_loaded(slot_name: String)
signal autosave_completed()
signal save_failed(slot_name: String, error: String)
signal load_failed(slot_name: String, system: String, error: String)
signal game_over(colony_id: int)
