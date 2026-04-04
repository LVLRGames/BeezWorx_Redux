# inventory_panel.gd
# res://ui/hud/inventory_panel.gd
class_name InventoryPanel
extends PanelContainer

const FADE_DELAY:   float = 4.0
const FADE_OPACITY: float = 0.15

@onready var _hotbar: InventorySlot = $VBoxContainer/InventorySlot
@onready var _weight: ProgressBar   = $VBoxContainer/WeightBar

var _pawn_id:    int   = -1
var _ft:         Tween = null
var _fade_timer: float = 0.0
var _faded:      bool  = false

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	modulate.a = FADE_OPACITY
	visible    = true

func _process(delta: float) -> void:
	if _hotbar.is_active():
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
	_hotbar.setup(pawn_id)
	_refresh_weight(state)

func refresh(state: PawnState = null) -> void:
	if state == null:
		state = PawnRegistry.get_state(_pawn_id)
	_refresh_weight(state)

func filter_to_item(item_id: StringName) -> void:
	_hotbar.filter_to_item(item_id)
	_wake_up()

func fade_in() -> void:
	_wake_up()

func fade_out() -> void:
	_fade_to(FADE_OPACITY)
	_faded = true

# ════════════════════════════════════════════════════════════════════════════ #
#  Internal
# ════════════════════════════════════════════════════════════════════════════ #

func _refresh_weight(state: PawnState) -> void:
	if state == null or state.inventory == null:
		return
	_weight.value = minf(state.inventory.get_carried_weight() / 5.0, 1.0) * 100.0

func _wake_up() -> void:
	_fade_timer = FADE_DELAY
	if _faded:
		_fade_to(1.0)
		_faded = false

func _fade_to(alpha: float) -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", alpha, 0.5)
