# BeezWorx MVP Spec: Time Service

This document specifies `TimeService`, the global authoritative clock for BeezWorx.
All time-dependent systems (plant lifecycle, seasonal behavior, day/night creature
activity, raid scheduling, bee aging, diplomacy timers) read exclusively from this
autoload. No other system owns or advances time.

---

## Purpose

`TimeService` converts a single monotonically advancing float (`world_time`) into
structured game-time concepts: time of day, day index, season, and year. It emits
signals at each transition so dependent systems can respond without polling.

---

## Configuration

Time behavior is driven by a `TimeConfig` resource assigned to `TimeService` at startup.
This resource is authored in the editor and lives in `res://defs/time_config.tres`.

```
class_name TimeConfig
extends Resource

@export var day_length_seconds: float = 600.0  # real seconds per in-game day
@export var days_per_season: int      = 7       # in-game days per season
@export var day_night_split: float    = 0.6     # fraction of day that is daytime (0..1)
@export var time_scale: float         = 1.0     # global multiplier (1.0 = normal speed)
```

`seasons_per_year` is fixed at `4` (spring, summer, fall, winter). It is not configurable
because seasonal gameplay content (bear hibernation, plant bloom windows, winter survival
mechanics) is authored against exactly four seasons.

Derived constants (computed once from config, not stored):

```
days_per_year  = days_per_season * 4
year_length    = day_length_seconds * days_per_year
season_length  = day_length_seconds * days_per_season
```

---

## Runtime state

```
class_name TimeService
extends Node

# ── Config ────────────────────────────────────────────────────────────
var config: TimeConfig

# ── Core clock ────────────────────────────────────────────────────────
var world_time: float = 0.0        # total elapsed in-game seconds; never set externally

# ── Cached derived values (updated each advance()) ────────────────────
var current_day:    int   = 0      # total days elapsed since world start
var day_phase:      float = 0.0    # 0..1 position within current day
var is_daytime:     bool  = true
var day_of_year:    int   = 0      # 0 .. days_per_year - 1
var current_season: int   = 0      # 0=spring 1=summer 2=fall 3=winter
var current_year:   int   = 0

# ── Previous frame values for transition detection ────────────────────
var _prev_day:    int = -1
var _prev_season: int = -1
var _prev_year:   int = -1
var _prev_is_daytime: bool = true
```

`world_time` is the single value that gets saved and restored. All other fields are
recomputed from it.

---

## Advancing the clock

`HexTerrainManager` calls `TimeService.advance(delta)` once per `_process` frame:

```
func advance(delta: float) -> void:
    world_time += delta * config.time_scale
    _update_derived()
    _emit_transitions()
```

Nothing else calls `advance`. Nothing else writes `world_time`.

---

## Derived value computation

`_update_derived()` recomputes all cached fields from `world_time`:

```
func _update_derived() -> void:
    var dl: float = config.day_length_seconds
    var dps: int  = config.days_per_season

    current_day    = int(world_time / dl)
    day_phase      = fmod(world_time, dl) / dl
    is_daytime     = day_phase < config.day_night_split
    day_of_year    = current_day % (dps * 4)
    current_season = day_of_year / dps          # integer division
    current_year   = current_day / (dps * 4)    # integer division
```

These are cheap integer and float operations. No signals are emitted here — that is
handled separately.

---

## Transition signals

`_emit_transitions()` checks whether any boundary was crossed since the previous frame
and emits the appropriate signals. Signals are emitted through `EventBus` so all
subscribers receive them via the standard channel.

```
func _emit_transitions() -> void:
    if is_daytime != _prev_is_daytime:
        if is_daytime:
            EventBus.day_started.emit()
        else:
            EventBus.night_started.emit()
        _prev_is_daytime = is_daytime

    if current_day != _prev_day:
        EventBus.day_changed.emit(current_day)
        _prev_day = current_day

    if current_season != _prev_season:
        EventBus.season_changed.emit(current_season)
        _prev_season = current_season

    if current_year != _prev_year:
        EventBus.year_changed.emit(current_year)
        _prev_year = current_year
```

Signals fire at most once per frame. If multiple days pass in one frame (e.g. on load
or extreme time skip), only the current values are emitted — intermediate days are
skipped. Systems that need to process skipped time (e.g. aging) should query
`current_day` directly after load.

---

## Season definitions

Seasons are referenced as integers throughout the codebase. The canonical mapping:

```
const SPRING = 0
const SUMMER = 1
const FALL   = 2
const WINTER = 3
```

These constants live on `TimeService` as static consts so any script can write
`TimeService.WINTER` without magic numbers.

### Seasonal effects on other systems (summary)

Each system's full seasonal behavior is specced in its own document. This table
summarises the contracts that `TimeService` enables:

| System | Uses TimeService for |
|---|---|
| Plant lifecycle | `current_season` checked against `bloom_seasons: Array[int]` on `HexPlantDef`. If current season is not in bloom window, FLOWERING stage is skipped (GROWTH → FRUITING directly) or IDLE is extended. Trees check season for annual cycle repeat. |
| Creature AI | `current_season == WINTER` suppresses bear raids. Night bloom plants check `is_daytime`. Nocturnal creatures activate on `night_started`. |
| Threat / Raid director | Season-weighted spawn tables. Winter reduces insect raids, increases cold-adapted threats. |
| Bee aging | One `day_changed` signal = one aging tick per bee. Full rules in lifecycle spec. |
| Diplomacy timers | Alliance decay and tribute deadlines measured in `current_day`. |
| Hive upgrade bonuses | Some efficiency bonuses are season-specific (e.g. "Summer Harvest" hive upgrade). |
| Weather (post-MVP) | Season determines valid weather event pool. |

---

## Public query API

Other systems should use these helpers rather than computing time math themselves:

```
# Time of day
func get_day_phase() -> float               # 0..1
func is_night() -> bool                     # not is_daytime
func time_until_dawn() -> float             # world_time seconds until next day_started
func time_until_dusk() -> float             # world_time seconds until next night_started

# Day / season / year
func get_current_season_name() -> String    # "Spring" / "Summer" / "Fall" / "Winter"
func days_until_season(season: int) -> int  # how many days until target season starts
func is_season(season: int) -> bool         # current_season == season
func day_of_current_season() -> int         # 0 .. days_per_season - 1
func fraction_through_season() -> float     # 0..1 through current season

# World time
func world_time_for_day(day: int) -> float  # world_time at start of that day
func elapsed_days() -> int                  # alias for current_day; clearer at callsites
```

---

## Initialisation

```
func initialize(p_config: TimeConfig) -> void:
    config = p_config
    _update_derived()
    # Initialise _prev_ values to current so no spurious signals on first frame
    _prev_day        = current_day
    _prev_season     = current_season
    _prev_year       = current_year
    _prev_is_daytime = is_daytime
```

Called by `HexTerrainManager._ready()` (or `WorldRoot._ready()`) before any other system
that depends on time. On save load, `world_time` is restored first, then `initialize` is
called again to recompute all derived values without emitting transition signals.

---

## Save / load

`TimeService` implements the standard save/load contract:

```
func save_state() -> Dictionary:
    return {
        "world_time": world_time,
        "schema_version": 1
    }

func load_state(data: Dictionary) -> void:
    world_time = data.get("world_time", 0.0)
    _update_derived()
    # Sync _prev_ values to suppress spurious transitions on first post-load frame
    _prev_day        = current_day
    _prev_season     = current_season
    _prev_year       = current_year
    _prev_is_daytime = is_daytime
```

Only `world_time` is saved. All derived values are recomputed on load.

---

## Time scale and pausing

`config.time_scale` is a runtime-mutable multiplier. Setting it to `0.0` effectively
pauses simulation time without stopping `_process`. This is the intended pause mechanism.

`HexTerrainManager` passes raw `delta` to `TimeService.advance(delta)`. The time scale
multiplication happens inside `advance`. This means physics and rendering continue at
normal speed while in-game time is paused or slowed — correct behavior for a management
game.

For a future "fast-forward" feature (e.g. skipping to next season), set `time_scale` to
a high value for a duration, then restore it. Transition signals will fire normally.

---

## Relationship to HexWorldState

`HexWorldState.current_world_time` **no longer exists** as a field on `HexWorldState`.
Any code that previously read or wrote `HexWorldState.current_world_time` must be updated
to use `TimeService.world_time`.

`HexWorldSimulation.get_cell` and `HexWorldBaseline` methods that accept a `world_time`
parameter continue to accept it as a parameter — they do not read from `TimeService`
directly. The caller (always on the main thread) passes `TimeService.world_time` at the
call site. This keeps the simulation layer stateless and testable.

```
# Correct call pattern:
var state = HexWorldState.get_cell(cell, TimeService.world_time)

# Also acceptable (default parameter uses TimeService internally):
var state = HexWorldState.get_cell(cell)
```

When the default parameter path is used, `HexWorldState.get_cell` reads
`TimeService.world_time` internally. This is the only place `HexWorldState` is permitted
to reference `TimeService`.

---

## MVP scope notes

The following are explicitly deferred past MVP:

- Variable time scale per-biome (e.g. time moves faster in the spirit realm).
- Per-season day length variation (longer summer days).
- Player-visible in-game calendar UI. The data is available; the UI widget is post-MVP.
- Weather simulation driven by season. Season affects threat tables and plant behavior
  at MVP; weather events are post-MVP.
