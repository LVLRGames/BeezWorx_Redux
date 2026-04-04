# time_panel.gd
# res://ui/hud/time_panel.gd
#
# Top-right panel showing season, day, and time of day.
# Pulses briefly on day/season change.
#
# SCENE STRUCTURE:
#   TimePanel (PanelContainer, this script)
#   └── HBoxContainer
#       ├── SeasonLabel (Label)   — season emoji + name
#       ├── DayLabel (Label)      — "Day 12"
#       └── TimeLabel (Label)     — "7:41 AM"

class_name TimePanel
extends PanelContainer

@onready var _season_label: Label = $HBoxContainer/SeasonLabel
@onready var _day_label:    Label = $HBoxContainer/DayLabel
@onready var _time_label:   Label = $HBoxContainer/TimeLabel

const SEASON_ICONS: Array[String] = ["🌸", "☀️", "🍂", "❄️"]

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	EventBus.day_changed.connect(func(_d): refresh())
	EventBus.season_changed.connect(func(_s): refresh())
	# Deferred so TimeService is initialized first
	call_deferred("refresh")

func _process(_delta: float) -> void:
	# Update time display every frame — time changes continuously
	if not TimeService.is_initialized:
		return
	_time_label.text = "🕒%s" % [TimeService.get_time_string()]



# ════════════════════════════════════════════════════════════════════════════ #
#  Public
# ════════════════════════════════════════════════════════════════════════════ #

func refresh() -> void:
	if not TimeService.is_initialized:
		return
	var season: int  = TimeService.current_season
	var day: int     = TimeService.day_of_current_season()
	var icon: String = SEASON_ICONS[clamp(season, 0, 3)]
	var sname: String = TimeService.get_current_season_name()
	_season_label.text = "%s %s" % [icon, sname]
	_day_label.text    = "%s Day %d" % ["☀️"if TimeService.is_daytime else"🌙",day]
	_time_label.text   = "🕒%s" % [TimeService.get_time_string()]

	_pulse()

func _pulse() -> void:
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate:a", 1.0, 0.0)
	tween.tween_property(self, "modulate:a", 0.6, 1.5)
