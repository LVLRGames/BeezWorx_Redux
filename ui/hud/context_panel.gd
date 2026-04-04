# context_panel.gd
# res://ui/hud/context_panel.gd
#
# Bottom-center-right panel showing info about the current interaction target.
# Content changes based on target type: plant, hive, pawn, item_gem.
# Fades out when no target.
#
# SCENE STRUCTURE:
#   ContextPanel (PanelContainer, this script)
#   └── VBoxContainer
#       ├── TargetName (Label)
#       ├── TargetDetail (Label)       — stage name / integrity / role etc
#       ├── NectarBar (ProgressBar)    — plants only
#       └── PollenBar (ProgressBar)    — plants only

class_name ContextPanel
extends PanelContainer

const FADE_DURATION: float = 0.3
const STAGE_NAMES: Array[String] = [
	"Seed", "Sprout", "Growing", "Flowering", "Fruiting", "Idle", "Wilting", "Dead"
]

@onready var _target_name:   Label       = $VBoxContainer/TargetName
@onready var _target_detail: Label       = $VBoxContainer/TargetDetail
@onready var _nectar_bar:    ProgressBar = $VBoxContainer/NectarBar
@onready var _pollen_bar:    ProgressBar = $VBoxContainer/PollenBar

var _ft: Tween = null
 



# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	modulate.a = 0.0
	_nectar_bar.visible = false
	_pollen_bar.visible = false

# ════════════════════════════════════════════════════════════════════════════ #
#  Public
# ════════════════════════════════════════════════════════════════════════════ #

func set_target(target_info: Dictionary) -> void:
	if target_info.is_empty():
		fade_out()
		return

	match target_info.get("type", &"none"):
		&"plant": _show_plant(target_info)
		&"hive":  _show_hive(target_info)
		&"pawn":  _show_pawn(target_info)
		_:        fade_out()

# ════════════════════════════════════════════════════════════════════════════ #
#  Target displays
# ════════════════════════════════════════════════════════════════════════════ #

func _show_plant(info: Dictionary) -> void:
	_target_name.text   = info.get("display_name", "Plant")
	var stage: int      = info.get("stage", 0)
	_target_detail.text = STAGE_NAMES[clamp(stage, 0, STAGE_NAMES.size() - 1)]

	var nectar: float   = info.get("nectar", 0.0)
	var pollen: float   = info.get("pollen", 0.0)

	_nectar_bar.visible = true
	_pollen_bar.visible = true
	_nectar_bar.value   = nectar * 100.0
	_pollen_bar.value   = pollen * 100.0

	fade_in()

func _show_hive(info: Dictionary) -> void:
	_target_name.text   = info.get("display_name", "Hive")
	var hive_id: int    = info.get("hive_id", -1)
	var hs: HiveState   = HiveSystem.get_hive(hive_id) if hive_id >= 0 else null

	if hs:
		_target_detail.text = "Integrity: %d%%" % int((hs.integrity / hs.max_integrity) * 100.0)
	else:
		_target_detail.text = ""

	_nectar_bar.visible = false
	_pollen_bar.visible = false
	fade_in()

func _show_pawn(info: Dictionary) -> void:
	_target_name.text   = info.get("display_name", "Pawn")
	var pawn_id: int    = info.get("pawn_id", -1)
	var state: PawnState = PawnRegistry.get_state(pawn_id) if pawn_id >= 0 else null

	if state:
		_target_detail.text = "%s — HP: %d%%" % [
			str(state.role_id),
			int((state.health / maxf(state.max_health, 1.0)) * 100.0)
		]
	else:
		_target_detail.text = ""

	_nectar_bar.visible = false
	_pollen_bar.visible = false
	fade_in()

# ════════════════════════════════════════════════════════════════════════════ #
#  Fade
# ════════════════════════════════════════════════════════════════════════════ #

func fade_in() -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", 1.0, 0.25)
 
func fade_out() -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", 0.0, 0.25)
