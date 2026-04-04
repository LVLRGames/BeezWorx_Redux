# time_service.gd
# res://autoloads/time_service.gd
#
# Autoload. Authoritative game clock for BeezWorx.
# Converts world_time (elapsed in-game seconds) into structured concepts:
# time of day, day index, season, year.
# Emits transition signals through EventBus.
#
# ADVANCEMENT:
#   TimeService advances itself in _process(). Nothing else writes world_time.
#
# RELATIONSHIP TO HexWorldState:
#   HexWorldState.current_world_time no longer exists.
#   All systems that need world time read TimeService.world_time directly.
#   HexWorldState.get_cell() reads TimeService.world_time internally when
#   the caller omits the world_time parameter.
extends Node

enum TimeOfDay { DAWN, DAY, DUSK, NIGHT }

# ── Season constants ──────────────────────────────────────────────────────────
const SPRING: int = 0
const SUMMER: int = 1
const FALL:   int = 2
const WINTER: int = 3

const SEASON_NAMES: Array[String] = ["Spring", "Summer", "Fall", "Winter"]

# ── Config ────────────────────────────────────────────────────────────────────
var config: Resource = null   # TimeConfig — set via initialize()

# ── Core clock ────────────────────────────────────────────────────────────────
## Total elapsed in-game seconds. The only value saved to disk.
## Never write this from outside TimeService.
var world_time: float = 0.0

# ── Cached derived values ─────────────────────────────────────────────────────
var current_day:    int   = 0
var day_phase:      float = 0.0   # 0..1 through current day
var is_daytime:     bool  = true
var day_of_year:    int   = 0     # 0 .. days_per_year - 1
var current_season: int   = SPRING
var current_year:   int   = 0

# ── Previous-frame values for transition detection ────────────────────────────
var _prev_day:        int  = -1
var _prev_season:     int  = -1
var _prev_year:       int  = -1
var _prev_is_daytime: bool = true
var is_initialized:   bool = false

# ── Defaults used before config is assigned ───────────────────────────────────
const _DEFAULT_DAY_LENGTH:    float = 600.0
const _DEFAULT_DAYS_PER_SEASON: int = 7
const _DEFAULT_DAY_NIGHT_SPLIT: float = 0.6
const _DEFAULT_TIME_SCALE:    float = 1.0


const DAWN_THRESHOLD: float = 0.15   # fraction of daytime
const DUSK_THRESHOLD: float = 0.85   # fraction of daytime

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _process(delta: float) -> void:
	if config == null:
		return
	var scale: float = config.get("time_scale") if config else _DEFAULT_TIME_SCALE
	world_time += delta * scale
	_update_derived()
	_emit_transitions()
	RenderingServer.global_shader_parameter_set(
	   &"engine_time",
	   float(Time.get_ticks_usec()) / 1000000.0
   )

# ════════════════════════════════════════════════════════════════════════════ #
#  Initialisation
# ════════════════════════════════════════════════════════════════════════════ #

## Called by WorldRoot after HexWorldState.initialize().
## On new game: world_time is 0.
## On load: restore world_time first via load_state(), then call initialize().
func initialize(p_config: Resource) -> void:
	config = p_config
	_update_derived()
	# Sync prev values so no spurious signals fire on the first frame
	_prev_day        = current_day
	_prev_season     = current_season
	_prev_year       = current_year
	_prev_is_daytime = is_daytime
	
	is_initialized = true

# ════════════════════════════════════════════════════════════════════════════ #
#  Derived value computation
# ════════════════════════════════════════════════════════════════════════════ #

func _update_derived() -> void:
	var dl:  float = _day_length()
	var dps: int   = _days_per_season()

	current_day    = int(world_time / dl)
	day_phase      = fmod(world_time, dl) / dl
	is_daytime     = day_phase < _day_night_split()
	day_of_year    = current_day % (dps * 4)
	current_season = day_of_year / dps
	current_year   = current_day / (dps * 4)

# ════════════════════════════════════════════════════════════════════════════ #
#  Transition signals
# ════════════════════════════════════════════════════════════════════════════ #

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

# ════════════════════════════════════════════════════════════════════════════ #
#  Public query API
# ════════════════════════════════════════════════════════════════════════════ #

func get_day_phase() -> float:
	return day_phase

func is_night() -> bool:
	return not is_daytime

func time_until_dawn() -> float:
	if is_daytime:
		# Already daytime — next dawn is after tonight's night
		var night_len: float = _day_length() * (1.0 - _day_night_split())
		return time_until_dusk() + night_len
	# Currently night — dawn is at day_night_split of current day
	var dl: float = _day_length()
	var time_in_day: float = fmod(world_time, dl)
	return dl - time_in_day   # seconds until end of night (= dawn)

func time_until_dusk() -> float:
	if not is_daytime:
		# Already night — next dusk is after tomorrow's day
		var day_len: float = _day_length() * _day_night_split()
		return time_until_dawn() + day_len
	var dl: float = _day_length()
	var time_in_day: float = fmod(world_time, dl)
	var dusk_time: float   = dl * _day_night_split()
	return dusk_time - time_in_day

func get_current_season_name() -> String:
	return SEASON_NAMES[current_season]

func get_time_of_day() -> int:
	if not is_daytime:
		return TimeOfDay.NIGHT
	var split: float = _day_night_split()
	var day_t: float = day_phase / split
	if day_t < DAWN_THRESHOLD:
		return TimeOfDay.DAWN
	elif day_t > DUSK_THRESHOLD:
		return TimeOfDay.DUSK
	return TimeOfDay.DAY

func get_time_of_day_name() -> String:
	match get_time_of_day():
		TimeOfDay.DAWN:  return "Dawn"
		TimeOfDay.DUSK:  return "Dusk"
		TimeOfDay.NIGHT: return "Night"
		_:               return "Day"


func get_time_string() -> String:
	var day_len: float = _day_length()
	var time_in_day: float = fmod(world_time, day_len)
	var raw_minutes: int = int((time_in_day / day_len) * 1440)
	# Offset so dawn (phase 0.0) = 6:00 AM
	var total_minutes: int = (raw_minutes + 288) % 1440
	var hours: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	var suffix: String = "AM" if hours < 12 else "PM"
	var display_hour: int = hours % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minutes, suffix]

func days_until_season(season: int) -> int:
	if current_season == season:
		return 0
	var dps: int = _days_per_season()
	var target_day_of_year: int = season * dps
	var cur: int = day_of_year
	if target_day_of_year > cur:
		return target_day_of_year - cur
	return (_days_per_season() * 4) - cur + target_day_of_year

func is_season(season: int) -> bool:
	return current_season == season

func day_of_current_season() -> int:
	return day_of_year % _days_per_season()

func fraction_through_season() -> float:
	return float(day_of_current_season()) / float(_days_per_season())

func world_time_for_day(day: int) -> float:
	return float(day) * _day_length()

func elapsed_days() -> int:
	return current_day

# ════════════════════════════════════════════════════════════════════════════ #
#  Save / Load
# ════════════════════════════════════════════════════════════════════════════ #

func save_state() -> Dictionary:
	return {
		"world_time":     world_time,
		"schema_version": 1,
	}

func load_state(data: Dictionary) -> void:
	world_time = data.get("world_time", 0.0)
	if config != null:
		_update_derived()
		_prev_day        = current_day
		_prev_season     = current_season
		_prev_year       = current_year
		_prev_is_daytime = is_daytime

# ════════════════════════════════════════════════════════════════════════════ #
#  Config helpers (safe defaults if config not yet assigned)
# ════════════════════════════════════════════════════════════════════════════ #

func _day_length() -> float:
	return config.get("day_length_seconds") if config else _DEFAULT_DAY_LENGTH

func _days_per_season() -> int:
	return config.get("days_per_season") if config else _DEFAULT_DAYS_PER_SEASON

func _day_night_split() -> float:
	return config.get("day_night_split") if config else _DEFAULT_DAY_NIGHT_SPLIT
