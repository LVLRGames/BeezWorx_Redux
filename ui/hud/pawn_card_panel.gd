# pawn_card_panel.gd
# res://ui/hud/pawn_card_panel.gd
#
# Top-left HUD panel showing currently possessed pawn stats.
# Fades to 30% opacity after FADE_DELAY seconds of no change.
#
# SCENE STRUCTURE:
#   PawnCard (PanelContainer, this script)
#   └── VBoxContainer
#       ├── NameLabel (Label)
#       ├── HealthBar (ProgressBar)
#       ├── FatigueBar (ProgressBar)
#       └── RoleLabel (Label)

class_name PawnCardPanel
extends PanelContainer

const FADE_DELAY:   float = 4.0
const FADE_OPACITY: float = 0.3

@onready var _name_label:  Label       = $VBoxContainer/NameLabel
@onready var _health_bar:  ProgressBar = $VBoxContainer/HealthBar
@onready var _fatigue_bar: ProgressBar = $VBoxContainer/FatigueBar
@onready var _role_label:  Label       = $VBoxContainer/RoleLabel

var _pawn_id:    int       = -1
var _fade_timer: float     = 0.0
var _faded:      bool      = false
var _fade_tween: Tween     = null

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	modulate.a = 1.0
	visible    = false
	EventBus.pawn_hit.connect(_on_pawn_hit)

func _process(delta: float) -> void:
	if _pawn_id < 0:
		return
	_fade_timer -= delta
	if _fade_timer <= 0.0 and not _faded:
		_fade_to(FADE_OPACITY)
		_faded = true

# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

func set_pawn(pawn_id: int, state: PawnState) -> void:
	_pawn_id = pawn_id
	visible  = pawn_id >= 0
	if state == null:
		return
	_refresh_from_state(state)
	_wake_up()

# ════════════════════════════════════════════════════════════════════════════ #
#  Internal
# ════════════════════════════════════════════════════════════════════════════ #

func _refresh_from_state(state: PawnState) -> void:
	_name_label.text  = state.pawn_name
	_health_bar.value = (state.health / maxf(state.max_health, 1.0)) * 100.0
	_fatigue_bar.value = state.fatigue * 100.0
	_role_label.text  = str(state.role_id) if state.role_id != &"" else "Queen"

func _on_pawn_hit(attacker_id: int, target_id: int, _damage: float, _effects: Array) -> void:
	if target_id != _pawn_id:
		return
	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	if state:
		_refresh_from_state(state)
	_wake_up()

func _wake_up() -> void:
	_fade_timer = FADE_DELAY
	if _faded:
		_fade_to(1.0)
		_faded = false

func _fade_to(alpha: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_fade_tween.tween_property(self, "modulate:a", alpha, 0.5)
