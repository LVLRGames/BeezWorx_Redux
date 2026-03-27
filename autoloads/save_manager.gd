# save_manager.gd
# res://autoloads/save_manager.gd
#
# Autoload. Orchestrates save/load across all systems in dependency order.
# Save files are JSON compressed with zstd, stored in user://saves/.
#
# SAVE ORDER (independent — all systems save, results collected):
#   TimeService, HexWorldState, HiveSystem, TerritorySystem,
#   ColonyState, JobSystem, PawnRegistry
#
# LOAD ORDER (dependency order):
#   1. TimeService       — no dependencies
#   2. HexWorldState     — no dependencies
#   3. HiveSystem        — depends on HexWorldState
#   4. TerritorySystem   — depends on HiveSystem
#   5. ColonyState       — depends on PawnRegistry IDs
#   6. JobSystem         — depends on ColonyState
#   7. PawnRegistry      — depends on HiveSystem (bed validation)
#   8. Post-load spawn   — chunk generation, pawn nodes

extends Node

const SAVE_DIR:          String = "user://saves/"
const SAVE_EXTENSION:    String = ".beez"
const AUTOSAVE_SLOT:     String = "autosave"
const MAX_SAVE_SLOTS:    int    = 10
const CURRENT_VERSION:   int    = 1

var _active_slot:        String = "default"
var _autosave_timer:     float  = 0.0
var _autosave_interval:  float  = 300.0   # 5 real minutes
var _is_saving:          bool   = false
var _is_loading:         bool   = false
var _total_play_time:    float  = 0.0

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	EventBus.day_changed.connect(_on_day_changed)

func _process(delta: float) -> void:
	if _is_saving or _is_loading:
		return
	_total_play_time  += delta
	_autosave_timer   += delta
	if _autosave_timer >= _autosave_interval:
		_autosave_timer = 0.0
		_trigger_autosave()

# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

## Save to slot_name. Uses active slot if slot_name is empty.
## Returns true on success.
func save_game(slot_name: String = "") -> bool:
	if _is_saving or _is_loading:
		return false

	var slot: String = slot_name if not slot_name.is_empty() else _active_slot
	if slot.is_empty():
		slot = _next_free_slot()

	_is_saving   = true
	_active_slot = slot

	var data: Dictionary = _collect_save_data(slot)
	var ok: bool         = _write_save_file(slot, data)

	_is_saving = false

	if ok:
		EventBus.game_saved.emit(slot)
		print("[SaveManager]: Game saved successfully. -- %s" % [slot])
	else:
		EventBus.save_failed.emit(slot, "write error")
		print("[SaveManager]: Game failed to save. -- %s" % [slot])

	
	return ok

## Load from slot_name. Returns true on success.
func load_game(slot_name: String) -> bool:
	if _is_saving or _is_loading:
		return false

	var path: String = SAVE_DIR + slot_name + SAVE_EXTENSION
	if not FileAccess.file_exists(path):
		push_error("SaveManager: save file not found: '%s'" % path)
		return false

	_is_loading = true

	var data: Dictionary = _read_save_file(path)
	if data.is_empty():
		_is_loading = false
		EventBus.load_failed.emit(slot_name, "SaveManager", "parse error")
		print("[SaveManager]: Game failed to load. -- %s" % [slot_name])
		return false
		
	# Version migration
	var file_version: int = data.get("version", 0)
	if file_version < CURRENT_VERSION:
		data = _migrate(data, file_version, CURRENT_VERSION)

	# Seed validation
	var saved_seed: int = data.get("world_seed", -1)
	if HexWorldState.cfg != null and saved_seed != HexWorldState.cfg.world_seed:
		push_warning("SaveManager: world seed mismatch — save may be from different config")

	_restore_save_data(data)

	_active_slot = slot_name
	_is_loading  = false
	EventBus.game_loaded.emit(slot_name)
	print("[SaveManager]: Game loaded successfully. -- %s" % [slot_name])
	return true

func delete_save(slot_name: String) -> bool:
	var path: String = SAVE_DIR + slot_name + SAVE_EXTENSION
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

func has_save(slot_name: String) -> bool:
	return FileAccess.file_exists(SAVE_DIR + slot_name + SAVE_EXTENSION)

func get_active_slot() -> String:
	return _active_slot

## Returns array of Dictionaries with slot metadata.
## Each entry: { slot_name, display_name, timestamp, play_time, world_seed }
func get_save_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(SAVE_EXTENSION):
			var slot: String = fname.trim_suffix(SAVE_EXTENSION)
			var meta: Dictionary = _read_save_meta(SAVE_DIR + fname)
			meta["slot_name"] = slot
			out.append(meta)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return a.get("timestamp", 0) > b.get("timestamp", 0))
	return out

# ════════════════════════════════════════════════════════════════════════════ #
#  Save orchestration
# ════════════════════════════════════════════════════════════════════════════ #

func _collect_save_data(slot: String) -> Dictionary:
	var systems: Dictionary = {}

	# Collect from each system — order doesn't matter for saving
	systems["time_service"]       = TimeService.save_state()
	systems["hex_world_state"]    = HexWorldState.save_state()
	systems["hive_system"]        = HiveSystem.save_state()
	systems["territory_system"]   = TerritorySystem.save_state()
	systems["colony_state"]       = ColonyState.save_state()
	systems["job_system"]         = JobSystem.save_state()
	systems["pawn_registry"]      = PawnRegistry.save_state()

	return {
		"version":      CURRENT_VERSION,
		"slot_name":    slot,
		"timestamp":    Time.get_unix_time_from_system(),
		"play_time":    _total_play_time,
		"world_seed":   HexWorldState.cfg.world_seed if HexWorldState.cfg else -1,
		"systems":      systems,
	}

# ════════════════════════════════════════════════════════════════════════════ #
#  Load orchestration
# ════════════════════════════════════════════════════════════════════════════ #

func _restore_save_data(data: Dictionary) -> void:
	var s: Dictionary = data.get("systems", {})
	_total_play_time  = data.get("play_time", 0.0)

	# Load in dependency order
	if s.has("time_service"):
		TimeService.load_state(s["time_service"])

	if s.has("hex_world_state"):
		HexWorldState.load_state(s["hex_world_state"])

	if s.has("hive_system"):
		HiveSystem.load_state(s["hive_system"])

	if s.has("territory_system"):
		TerritorySystem.load_state(s["territory_system"])

	if s.has("colony_state"):
		ColonyState.load_state(s["colony_state"])

	if s.has("job_system"):
		JobSystem.load_state(s["job_system"])

	if s.has("pawn_registry"):
		PawnRegistry.load_state(s["pawn_registry"])

	# Post-load: spawn world nodes after all state is restored
	#call_deferred("_spawn_world_nodes")




# ════════════════════════════════════════════════════════════════════════════ #
#  File I/O
# ════════════════════════════════════════════════════════════════════════════ #

func _write_save_file(slot: String, data: Dictionary) -> bool:
	var path:    String = SAVE_DIR + slot + SAVE_EXTENSION
	var tmp:     String = path + ".tmp"
	var json:    String = JSON.stringify(data)

	# Write to .tmp first — prevents corruption if write is interrupted
	var file := FileAccess.open_compressed(
		tmp,
		FileAccess.WRITE,
		FileAccess.COMPRESSION_ZSTD
	)
	if file == null:
		push_error("SaveManager: failed to open '%s' for writing" % tmp)
		return false

	file.store_string(json)
	file.close()

	# Atomic rename: remove old save, rename .tmp to final path
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err: Error = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("SaveManager: rename failed (%d) for '%s'" % [err, path])
		return false
	#print("SaveManager: save file written. -- %s ")
	return true

func _read_save_file(path: String) -> Dictionary:
	var file := FileAccess.open_compressed(
		path,
		FileAccess.READ,
		FileAccess.COMPRESSION_ZSTD
	)
	if file == null:
		push_error("SaveManager: failed to open '%s' for reading" % path)
		return {}

	var json_str: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_str)
	if parsed == null or not parsed is Dictionary:
		push_error("SaveManager: JSON parse failed for '%s'" % path)
		return {}

	return parsed

func _read_save_meta(path: String) -> Dictionary:
	# Read only top-level metadata without parsing full systems block
	var data: Dictionary = _read_save_file(path)
	return {
		"timestamp":  data.get("timestamp",  0),
		"play_time":  data.get("play_time",  0.0),
		"world_seed": data.get("world_seed", -1),
	}

# ════════════════════════════════════════════════════════════════════════════ #
#  Autosave
# ════════════════════════════════════════════════════════════════════════════ #

func _trigger_autosave() -> void:
	# Suppress during raids or while hive overlay is open
	if _hive_overlay_open():
		return
	save_game(AUTOSAVE_SLOT)
	EventBus.autosave_completed.emit()

func _on_day_changed(_new_day: int) -> void:
	# Day-change autosave
	if not _is_saving and not _is_loading:
		_trigger_autosave()

func _hive_overlay_open() -> bool:
	var overlay: Node = get_tree().get_first_node_in_group("hive_overlay")
	if overlay == null:
		return false
	return overlay.visible

# ════════════════════════════════════════════════════════════════════════════ #
#  Versioning and migration
# ════════════════════════════════════════════════════════════════════════════ #

func _migrate(data: Dictionary, from_version: int, to_version: int) -> Dictionary:
	var d: Dictionary = data.duplicate(true)
	for v: int in range(from_version, to_version):
		d = _migrate_step(d, v, v + 1)
	return d

func _migrate_step(data: Dictionary, from_v: int, to_v: int) -> Dictionary:
	match [from_v, to_v]:
		[0, 1]:
			data["version"] = 1
			return data
		_:
			push_warning("SaveManager: no migration path from v%d to v%d" % [from_v, to_v])
			return data

# ════════════════════════════════════════════════════════════════════════════ #
#  Helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _next_free_slot() -> String:
	for i: int in MAX_SAVE_SLOTS:
		var candidate: String = "save_%02d" % i
		if not has_save(candidate):
			return candidate
	# All slots full — overwrite oldest
	var slots: Array[Dictionary] = get_save_slots()
	if not slots.is_empty():
		return slots.back().get("slot_name", "save_00")
	return "save_00"
