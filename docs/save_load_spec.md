# BeezWorx MVP Spec: Save / Load System

This document specifies `SaveManager`, the save file format, versioning and migration,
the save/load orchestration order, autosave behavior, and the error handling model.
It is the authoritative reference for all persistence in BeezWorx.

---

## Purpose and scope

BeezWorx is a simulation game with a living world. The player's colony must persist
faithfully across sessions — every pawn, every hive slot, every discovered recipe,
every diplomatic relationship, every revealed cell. At the same time the save system
must be compact, fast, and resilient to version changes as the game evolves.

The core strategy: save only what differs from the deterministic baseline. The world
generates identically from the same seed every time. Only player-driven changes
(placed objects, mutations, discovered knowledge, pawn states, hive contents) are
stored as deltas. This keeps save files small regardless of how much of the world
the player has explored.

This spec covers:
- SaveManager: the orchestration autoload
- Save file format and structure
- System save/load contracts (what each system saves)
- Save order and dependency ordering
- Autosave behavior
- Version numbering and migration
- Error handling and corruption recovery
- Multiple save slots

It does **not** cover: the in-game save menu UI (UI spec), world generation
(World/Hex/Chunk spec), or individual system state structures (those are each
system's spec). Those systems define what to save; this spec defines how saving works.

---

## SaveManager (autoload)

```
class_name SaveManager
extends Node

const SAVE_DIR:         String = "user://saves/"
const SAVE_EXTENSION:   String = ".beez"
const AUTOSAVE_SLOT:    String = "autosave"
const MAX_SAVE_SLOTS:   int    = 10
const CURRENT_VERSION:  int    = 1

var _active_slot:       String = ""
var _autosave_timer:    float  = 0.0
var _autosave_interval: float  = 300.0  # 5 real minutes between autosaves
var _is_saving:         bool   = false
var _is_loading:        bool   = false
```

### Public API

```
func save_game(slot_name: String = "") -> bool
func load_game(slot_name: String) -> bool
func delete_save(slot_name: String) -> bool
func get_save_slots() -> Array[SaveSlotInfo]
func has_save(slot_name: String) -> bool
func get_active_slot() -> String
```

`save_game` with no argument saves to the active slot. If no active slot exists,
it saves to a new numbered slot.

---

## Save file format

Each save is a single `.beez` file — a JSON document compressed with Godot's
`FileAccess` zstd compression.

### Top-level structure

```json
{
    "version": 1,
    "timestamp": 1234567890,
    "play_time_seconds": 3600,
    "world_seed": 1337,
    "slot_name": "My Colony",
    "preview": {
        "queen_name": "Aurellia",
        "colony_name": "The Heatherbee Colony",
        "current_day": 142,
        "current_season": "Summer",
        "hive_count": 7,
        "population": 43
    },
    "systems": {
        "time_service":          { ... },
        "hex_world_state":       { ... },
        "hive_system":           { ... },
        "territory_system":      { ... },
        "colony_state":          { ... },
        "job_system":            { ... },
        "pawn_registry":         { ... },
        "fog_of_war":            { ... },
        "rival_colony_simulator": { ... },
        "threat_director":       { ... }
    }
}
```

The `preview` block is read without decompressing the full file — it is stored at a
known byte offset for fast save slot display in the menu. It contains just enough
to show the player which save is which.

`world_seed` is stored at the top level so `HexWorldState` can validate on load that
the generated world matches the save. If seeds differ (e.g. a save from a different
version or a corrupted seed), a warning is shown.

---

## System save contracts

Each autoload and scene-owned system implements:

```
func save_state() -> Dictionary   # returns serialisable dict
func load_state(data: Dictionary) -> void  # restores from dict
```

The full contract per system, referencing what each system spec defines:

### TimeService
```
Saves: world_time (float)
Does not save: derived values (all recomputed from world_time on load)
```

### HexWorldState (via HexWorldDeltaStore)
```
Saves: all HexCellDelta records (placed objects, mutations, sprouts, cleared cells,
       ground item gems in unloaded chunks)
Does not save: terrain baseline (fully deterministic from seed),
              cell cache (rebuilt on demand)
Format: array of delta records keyed by cell [q, r]
```

### HiveSystem
```
Saves: all HiveState records including slot arrays, craft orders, egg states,
       integrity, upgrades, hive names, fade timers
Does not save: inventory cache (rebuilt from slot contents on load)
```

### TerritorySystem
```
Saves: active fade records (hive_id, colony_id, timer)
Does not save: influence field (recomputed from living hives on load),
              cell contributor map (recomputed from hives on load)
```

### ColonyState
```
Saves: per colony — queen_pawn_id, heir_ids, contest state, queen_history,
       known_recipe_ids, known_plants, known_items, discovered_biomes,
       known_anchor_types, loyalty cache, morale modifiers, faction_relations
       (including trade history and preference_revealed), influence score
Does not save: derived morale value (recomputed on first query)
```

### JobSystem
```
Saves: all MarkerData records, all TrailData records, persistent JobData records
       (POSTED and EXECUTING jobs from markers and hive slots; not reactive private jobs)
Does not save: reactive/private jobs (colony_id < 0), task plans (recomputed on claim)
Note: CLAIMED and EXECUTING jobs restore as POSTED; pawns re-claim on first AI tick
```

### PawnRegistry
```
Saves: all PawnState records for all living pawns (player colony, rival colonies,
       neutral faction NPCs)
Saves per pawn: pawn_id, pawn_name, species_id, role_id, colony_id, health,
               max_health, fatigue, age_days, max_age_days, loyalty, inventory,
               personality (seed + all trait floats), ai_resume_state,
               last_known_cell, is_alive, is_awake, active_effects
Does not save: node references (nodes are re-spawned on load),
              PawnAI runtime state beyond ai_resume_state
```

### FogOfWarSystem
```
Saves: all revealed cell coordinates as [q, r] pairs
Does not save: nothing else
Note: this is the largest save component for heavily explored worlds; compressed well
```

### RivalColonySimulator
```
Saves: RivalColonyState for all ABSTRACT-tier colonies,
       simulation tier assignments
Does not save: FULL-tier colony pawn states (those are in PawnRegistry),
              terrain (deterministic)
```

### ThreatDirector
```
Saves: raid cooldown timestamps, active raid group records
Does not save: threat pawn states (those are in PawnRegistry with colony_id = -1)
```

---

## Save orchestration order

Save and load must happen in dependency order. Systems that depend on others must
load after their dependencies.

### Save order

Order does not matter for saving — all systems save independently, results are
collected into the top-level `systems` dictionary.

```
func _collect_save_data() -> Dictionary:
    return {
        "time_service":           TimeService.save_state(),
        "hex_world_state":        HexWorldState.save_state(),
        "hive_system":            HiveSystem.save_state(),
        "territory_system":       TerritorySystem.save_state(),
        "colony_state":           ColonyState.save_state(),
        "job_system":             JobSystem.save_state(),
        "pawn_registry":          PawnRegistry.save_state(),
        "fog_of_war":             FogOfWarSystem.save_state(),
        "rival_colony_simulator": RivalColonySimulator.save_state(),
        "threat_director":        ThreatDirector.save_state(),
    }
```

### Load order

Order matters. Dependencies load first.

```
func _restore_save_data(data: Dictionary) -> void:
    var s: Dictionary = data["systems"]

    # 1. Time first — world_time is needed by almost everything
    TimeService.load_state(s["time_service"])

    # 2. World substrate — delta store must exist before hives/pawns reference cells
    HexWorldState.load_state(s["hex_world_state"])

    # 3. Hive infrastructure — territory needs hive positions
    HiveSystem.load_state(s["hive_system"])

    # 4. Territory — recomputes from hives; fade records restore on top
    TerritorySystem.load_state(s["territory_system"])

    # 5. Colony state — faction relations, recipes, known plants
    ColonyState.load_state(s["colony_state"])

    # 6. Jobs and markers — depend on colony state for filtering
    JobSystem.load_state(s["job_system"])

    # 7. Pawns — depend on hive system for bed assignment validation
    PawnRegistry.load_state(s["pawn_registry"])

    # 8. Fog of war — independent, can load any time after world
    FogOfWarSystem.load_state(s["fog_of_war"])

    # 9. Rival colonies — depend on colony state and pawn registry
    RivalColonySimulator.load_state(s["rival_colony_simulator"])

    # 10. Threat director — depends on hive positions for targeting
    ThreatDirector.load_state(s["threat_director"])

    # 11. Post-load: spawn scene nodes for loaded pawns and hive objects
    _spawn_world_nodes()
```

### Post-load node spawning

After all state is restored, `_spawn_world_nodes` asks scene managers to create nodes:

```
func _spawn_world_nodes() -> void:
    # Trigger chunk generation around player position
    HexTerrainManager.update_chunks_immediate()

    # Spawn pawn nodes for pawns in loaded chunks
    PawnManager.spawn_pawns_for_loaded_chunks()

    # Active plant pool nodes created by HexChunk on finalize
    # (handled by chunk generation above)

    # Item gem nodes created by ItemGemManager during chunk finalize
    # (handled by chunk generation above)
```

Node spawning is deferred to after chunk generation completes, not during
`load_state`. This avoids trying to add nodes before the scene tree is ready.

---

## Autosave

```
func _process(delta: float) -> void:
    if _is_saving or _is_loading:
        return
    _autosave_timer += delta
    if _autosave_timer >= _autosave_interval:
        _autosave_timer = 0.0
        _trigger_autosave()

func _trigger_autosave() -> void:
    # Do not autosave during combat or hive interior view
    if ThreatDirector.has_active_raids():
        return
    if UIRoot.is_hive_overlay_open():
        return
    save_game(AUTOSAVE_SLOT)
    EventBus.autosave_completed.emit()
```

**Autosave is silent** — no interruption, no UI, just a brief autosave icon in the
corner for 2 seconds. The player is never blocked by a save operation.

**Autosave slot is separate** from named save slots. It always overwrites the same
`autosave.beez` file. On new game start, the autosave is cleared.

**When autosave is suppressed:**
- During active raids (saving mid-combat would allow reload-exploit of raid outcomes)
- While the hive interior overlay is open (slot state may be mid-transaction)
- During the queen death/game-over sequence

**Day-change autosave:** Additionally, the game autosaves once per in-game day at the
moment `day_changed` fires. This ensures the player always has a recent save even if
they play for long sessions without triggering the 5-minute timer.

---

## Save file writing

```
func save_game(slot_name: String) -> bool:
    if _is_saving:
        return false
    _is_saving = true

    var data: Dictionary = _collect_save_data()
    data["version"]          = CURRENT_VERSION
    data["timestamp"]        = Time.get_unix_time_from_system()
    data["play_time_seconds"] = _total_play_time
    data["world_seed"]       = HexWorldState.cfg.world_seed
    data["slot_name"]        = slot_name
    data["preview"]          = _build_preview()

    var json_str: String = JSON.stringify(data)
    var path: String = SAVE_DIR + slot_name + SAVE_EXTENSION

    DirAccess.make_dir_recursive_absolute(SAVE_DIR)
    var file := FileAccess.open_compressed(
        path,
        FileAccess.WRITE,
        FileAccess.COMPRESSION_ZSTD
    )
    if file == null:
        push_error("SaveManager: failed to open '%s' for writing" % path)
        _is_saving = false
        return false

    file.store_string(json_str)
    file.close()

    _active_slot = slot_name
    _is_saving = false
    EventBus.game_saved.emit(slot_name)
    return true
```

**Atomic write:** To prevent corruption from interrupted saves, write to a temp file
first, then rename:

```
var temp_path: String = path + ".tmp"
# ... write to temp_path ...
DirAccess.rename_absolute(temp_path, path)
```

If the process is interrupted before rename, the old save file is untouched. The
`.tmp` file is cleaned up on next launch.

---

## Save file loading

```
func load_game(slot_name: String) -> bool:
    if _is_loading:
        return false
    var path: String = SAVE_DIR + slot_name + SAVE_EXTENSION

    if not FileAccess.file_exists(path):
        push_error("SaveManager: save file not found: '%s'" % path)
        return false

    _is_loading = true
    var file := FileAccess.open_compressed(
        path,
        FileAccess.READ,
        FileAccess.COMPRESSION_ZSTD
    )
    if file == null:
        push_error("SaveManager: failed to open '%s' for reading" % path)
        _is_loading = false
        return false

    var json_str: String = file.get_as_text()
    file.close()

    var parsed = JSON.parse_string(json_str)
    if parsed == null:
        push_error("SaveManager: JSON parse failed for '%s'" % path)
        _is_loading = false
        return false

    var data: Dictionary = parsed

    # Version check and migration
    var file_version: int = data.get("version", 0)
    if file_version < CURRENT_VERSION:
        data = _migrate(data, file_version, CURRENT_VERSION)

    # Seed validation
    var saved_seed: int = data.get("world_seed", -1)
    if saved_seed != HexWorldState.cfg.world_seed:
        push_warning("SaveManager: world seed mismatch. Save may be from different config.")

    _restore_save_data(data)
    _active_slot = slot_name
    _is_loading = false
    EventBus.game_loaded.emit(slot_name)
    return true
```

---

## Versioning and migration

### Version numbering

`CURRENT_VERSION` is an integer, incremented whenever the save format changes in a
breaking way. Non-breaking additions (new optional fields) do not require a version bump.

Breaking changes that require a bump:
- Removing a field that old saves will have
- Changing the meaning of an existing field
- Changing the save/load contract of a system in a way that makes old data invalid

### Migration

```
func _migrate(data: Dictionary, from_version: int, to_version: int) -> Dictionary:
    var d: Dictionary = data.duplicate(true)
    for v in range(from_version, to_version):
        d = _migrate_step(d, v, v + 1)
    return d

func _migrate_step(data: Dictionary, from_v: int, to_v: int) -> Dictionary:
    match [from_v, to_v]:
        [0, 1]:
            # Version 0 → 1: initial release, no migration needed
            data["version"] = 1
            return data
        _:
            push_warning("SaveManager: no migration path from v%d to v%d" % [from_v, to_v])
            return data
```

Migration steps are additive — each step migrates one version increment. This means
a save from version 1 can migrate to version 5 by running steps 1→2, 2→3, 3→4, 4→5
in sequence. Never skip steps.

### Forward compatibility

The JSON format means fields the current code does not recognise are silently ignored.
A save created with a newer version of the game can be opened by an older version —
the new fields are simply ignored. This is safe as long as older versions do not corrupt
data they do not understand.

---

## Error handling and corruption recovery

### On save failure
- Log the error to Godot's error console
- Emit `EventBus.save_failed(slot_name, error_message)`
- Show a brief UI notification: "Save failed. Check disk space."
- Do not crash; the game continues running

### On load failure
- If the file cannot be parsed: offer to start a new game or choose a different slot
- If a system's `load_state` throws an error: catch it, log it, emit
  `EventBus.load_failed(slot_name, system_name, error_message)`, and attempt to
  continue with that system in its default state
- Partial load is better than no load — a colony with missing pawn data is recoverable;
  a crash is not

### Corruption detection

On load, validate:
- `version` field exists and is a non-negative integer
- `world_seed` matches current config (warn if not, do not block)
- `systems` dictionary contains all expected keys (warn if a system key is missing;
  load that system in default state)
- `preview.current_day` is a positive integer (basic sanity check)

If validation fails at the top level (version missing, systems missing), treat as
corrupted and offer the player a recovery dialog.

### Backup save

Before overwriting an existing save slot, copy the current file to `slot_name.backup.beez`.
The backup is one generation deep — only the previous version. On corruption, the player
can load the backup via the save slot menu.

---

## Multiple save slots

```
class SaveSlotInfo:
    var slot_name:      String
    var display_name:   String    # queen_name + colony_name
    var timestamp:      int       # unix timestamp
    var play_time:      float     # seconds
    var current_day:    int
    var current_season: String
    var hive_count:     int
    var population:     int
    var is_autosave:    bool
```

`get_save_slots()` reads only the preview block of each `.beez` file without
decompressing the full content:

```
func get_save_slots() -> Array[SaveSlotInfo]:
    var slots: Array[SaveSlotInfo] = []
    var dir := DirAccess.open(SAVE_DIR)
    if dir == null:
        return slots
    dir.list_dir_begin()
    var fname: String = dir.get_next()
    while fname != "":
        if fname.ends_with(SAVE_EXTENSION) and not fname.ends_with(".tmp"):
            var info := _read_preview(SAVE_DIR + fname)
            if info != null:
                slots.append(info)
        fname = dir.get_next()
    slots.sort_custom(func(a, b): return a.timestamp > b.timestamp)
    return slots
```

Preview reading opens the file, reads the first N bytes (enough to cover the preview
block), and parses just that portion. Full decompression only happens on actual load.

---

## EventBus integration

```
# Emitted by SaveManager:
EventBus.game_saved(slot_name: String)
EventBus.game_loaded(slot_name: String)
EventBus.autosave_completed()
EventBus.save_failed(slot_name: String, error: String)
EventBus.load_failed(slot_name: String, system: String, error: String)

# Consumed by SaveManager:
EventBus.day_changed    → trigger day-change autosave
EventBus.game_over      → suppress autosave; offer manual save before game-over screen
```

---

## New game initialisation

When starting a new game rather than loading:

```
func start_new_game(config: NewGameConfig) -> void:
    # Apply seed from config
    HexWorldState.cfg.world_seed = config.world_seed

    # Initialise all systems to default state
    TimeService.initialize(config.time_config)
    HexWorldState.initialize(HexWorldState.cfg)
    HiveSystem.initialize()
    TerritorySystem.initialize()
    ColonyState.initialize()
    JobSystem.initialize()
    PawnRegistry.initialize()
    FogOfWarSystem.initialize()
    RivalColonySimulator.initialize()
    ThreatDirector.initialize()

    # Place starting hive and pawns
    _place_starting_colony(config)

    _active_slot = ""   # no active slot until player saves manually
    _autosave_timer = 0.0
```

`_place_starting_colony` creates the starting hive on the pre-determined anchor cell,
spawns the queen and starting workers with correct roles, and sets up the starting
`ColonyData` with always-known recipes. This is the tutorial setup — the world the
player sees when they first start a new game.

---

## Performance considerations

- Serialisation runs on the main thread. For small saves this is fast enough. If save
  size grows (large explored worlds with many revealed cells), consider moving JSON
  serialisation to a worker thread with `WorkerThreadPool.add_task`.
- The fog of war revealed cells array is the largest component for heavily explored
  worlds. At 50,000 explored cells it serialises to roughly 500KB uncompressed;
  zstd compression typically reduces this by 60–70%, so ~150–200KB. Acceptable.
- `_collect_save_data()` calls every system's `save_state()`. This is synchronous and
  happens in one frame. If any system has expensive serialisation, profile it early.

---

## MVP scope notes

Deferred past MVP:

- Cloud save (Steam Cloud or similar) — the file format is portable and ready for it
- Save file encryption (anti-cheat for competitive multiplayer)
- Export / import save files via UI
- Save file size analytics tooling
- Branching save trees (multiple named saves within a single run for experimentation)
- Mod support hooks in save format (reserved key in systems dictionary for mod data)
