# item_gem_manager.gd
# res://world/items/item_gem_manager.gd
#
# Manages spawning of collectible item gems when plants are killed.
# Found by HexWorldState._try_spawn_gem() via group "item_gem_manager".
#
# SETUP:
#   1. Add an ItemGemManager node as a child of WorldRoot (or any persistent scene node).
#   2. In the Inspector, add it to the "item_gem_manager" group.
#      (Or call add_to_group("item_gem_manager") in _ready — handled here.)
#   3. No further configuration needed.
#
# API:
#   spawn_gem(item_id, world_pos)  — spawns one gem at world_pos
#   spawn_gems(item_id, count, world_pos) — spawns count gems, slightly scattered
#   clear_all() — removes all active gems (e.g. on scene reset)

class_name ItemGemManager
extends Node3D

## Maximum gems allowed in the world simultaneously. Oldest removed when exceeded.
@export var max_gems: int = 256

## Scatter radius when spawning multiple gems for the same drop.
@export var scatter_radius: float = HexConsts.HEX_SIZE * 0.5

## Height above world_pos.y at which gems spawn.
@export var spawn_height_offset: float = 1.0

var _gems: Array[ItemGem] = []


func _ready() -> void:
	add_to_group("item_gem_manager")


# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

## Spawn one gem. Called by HexWorldState._try_spawn_gem() per item in the drop.
func spawn_gem(item_id: StringName, world_pos: Vector3) -> void:
	_enforce_cap()

	var gem := ItemGem.new()
	gem.name = "ItemGem_%s" % item_id

	# Random scatter offset so stacked drops don't overlap.
	var scatter := Vector3(
		randf_range(-scatter_radius, scatter_radius),
		spawn_height_offset,
		randf_range(-scatter_radius, scatter_radius)
	)
	# Bob phase offset so simultaneously spawned gems pulse out of sync.
	var bob_phase: float = randf() * TAU

	gem.setup(item_id, 1, bob_phase)
	add_child(gem)
	gem.global_position = world_pos + scatter

	_gems.append(gem)


## Spawn multiple gems for a single drop at the same location.
func spawn_gems(item_id: StringName, count: int, world_pos: Vector3) -> void:
	for _i: int in count:
		spawn_gem(item_id, world_pos)


## Remove all gems — e.g. on level reset or save-load.
func clear_all() -> void:
	for gem: ItemGem in _gems:
		if is_instance_valid(gem):
			gem.queue_free()
	_gems.clear()


# ════════════════════════════════════════════════════════════════════════════ #
#  Internal
# ════════════════════════════════════════════════════════════════════════════ #

## Prune freed gems and enforce the cap by removing oldest.
func _enforce_cap() -> void:
	# Prune already-freed entries.
	_gems = _gems.filter(func(g): return is_instance_valid(g))
	# Remove oldest if over cap.
	while _gems.size() >= max_gems:
		var oldest: ItemGem = _gems.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
