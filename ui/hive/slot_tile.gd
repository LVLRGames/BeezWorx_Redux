# slot_tile.gd
# res://ui/hive/slot_tile.gd
#
# Scene tile placed in the hive TileMapLayer.
#
# SCENE STRUCTURE:
#   SlotTile (Node2D, this script)
#   ├── Background      (Sprite2D) — hex tile atlas, 6 frames, color-modulated by designation
#   ├── SlotProgress    (TextureProgressBar) — fill/radial based on designation type
#   ├── DesignationIcon (Sprite2D) — icon atlas 8x4, 16x16 per frame
#   ├── ItemIcon        (Sprite2D) — contextual item/status icon
#   └── Label           (Label)   — item count or status text
#
# ICON ATLAS: 128x64px, 8 cols x 4 rows, 16x16 per frame
#   Cols: 0=locked 1=general 2=bed 3=storage 4=crafting 5=nursery 6=spare 7=spare
#   Rows: 0=default 1=variant1 2=variant2 3=royal
#
# BACKGROUND ATLAS: 6 frames horizontal
#   0=partial 1=opaque 2=outline 3=blacked 4=disabled 5=border

class_name SlotTile
extends Node2D

const FRAME_PARTIAL:  int = 0
const FRAME_OPAQUE:   int = 1
const FRAME_OUTLINE:  int = 2
const FRAME_BLACKED:  int = 3
const FRAME_DISABLED: int = 4
const FRAME_BORDER:   int = 5

const ICON_COLS: int = 8
const ICON_ROWS: int = 4

const BOUNCE_SCALE:    float = 1.16
const BOUNCE_DURATION: float = 0.5

@onready var _background:  Sprite2D            = $Background
@onready var _progress:    TextureProgressBar  = $SlotProgress
@onready var _desig_icon:  Sprite2D            = $DesignationIcon
@onready var _item_icon:   Sprite2D            = $ItemIcon
@onready var _label:       Label               = $Label

var _designation: int  = HiveSlot.SlotDesignation.GENERAL
var _subtype:     int  = HiveSlot.SlotSubtype.DEFAULT
var _selected:    bool = false
var _bounce_tween: Tween = null
var _def: SlotDesignationDef = null

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	_refresh_def()
	_update_visuals()

# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

func set_designation(desig_id: int, subtype_id: int = 0) -> void:
	_designation = desig_id
	_subtype     = subtype_id
	_refresh_def()
	_update_visuals()

func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_update_background_frame()
	if selected:
		_start_bounce()
	else:
		_stop_bounce()

func set_contents(items: Dictionary, sleeper_id: int) -> void:
	if _label == null:
		return
	if items.is_empty() and sleeper_id < 0:
		_label.text = ""
		_update_progress(0.0)
		return

	var total: int = 0
	for v in items.values():
		total += v
	_label.text = str(total) if total > 0 else ""

	# Update progress bar for storage fill
	if _def and _def.progress_type == SlotDesignationDef.PROGRESS_LINEAR:
		var cap: float = float(_def.progress_max) if _def.progress_max > 0 else 10.0
		_update_progress(float(total) / cap)
	elif sleeper_id >= 0:
		_label.text = "💤"

func set_progress(value: float) -> void:
	_update_progress(value)

func set_item_icon_frame(frame: int) -> void:
	if _item_icon:
		_item_icon.visible = frame >= 0
		if frame >= 0:
			_item_icon.frame = frame

func set_locked(locked: bool) -> void:
	if locked:
		set_designation(HiveSlot.SlotDesignation.LOCKED)

# ════════════════════════════════════════════════════════════════════════════ #
#  Internal
# ════════════════════════════════════════════════════════════════════════════ #

func _refresh_def() -> void:
	if Engine.is_editor_hint():
		return
	_def = SlotDesignationRegistry.get_def(_designation)

func _update_visuals() -> void:
	_update_background_color()
	_update_background_frame()
	_update_designation_icon()
	_update_progress(0.0)
	if _item_icon:
		_item_icon.visible = false

func _update_background_color() -> void:
	if _background == null or _def == null:
		return
	_background.modulate = _def.color

func _update_background_frame() -> void:
	if _background == null:
		return
	if _designation == HiveSlot.SlotDesignation.LOCKED:
		_background.frame = FRAME_DISABLED
		return
	_background.frame = FRAME_OUTLINE if _selected else FRAME_PARTIAL

func _update_designation_icon() -> void:
	if _desig_icon == null:
		return
	# frame = col + row * ICON_COLS
	var col: int   = _def.icon_col if _def else 1
	var row: int   = _subtype
	_desig_icon.frame = col + row * ICON_COLS
	_desig_icon.visible = true

func _update_progress(fill: float) -> void:
	if _progress == null or _def == null:
		_progress.visible = false
		return
	if _def.progress_type == SlotDesignationDef.PROGRESS_NONE:
		_progress.visible = false
		return
	_progress.visible = true
	_progress.value   = clampf(fill, 0.0, 1.0) * 100.0
	# Radial vs linear handled by TextureProgressBar.fill_mode in Inspector
	# PROGRESS_RADIAL: set fill_mode=FILL_CLOCKWISE in scene
	# PROGRESS_LINEAR: set fill_mode=FILL_BOTTOM_TO_TOP in scene

# ════════════════════════════════════════════════════════════════════════════ #
#  Scale bounce
# ════════════════════════════════════════════════════════════════════════════ #

func _start_bounce() -> void:
	if _bounce_tween:
		_bounce_tween.kill()
	scale = Vector2.ONE
	_bounce_tween = create_tween() \
		.set_loops() \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_SINE)
	_bounce_tween.tween_property(self, "scale", Vector2(BOUNCE_SCALE, BOUNCE_SCALE), BOUNCE_DURATION)
	_bounce_tween.tween_property(self, "scale", Vector2.ONE, BOUNCE_DURATION)

func _stop_bounce() -> void:
	if _bounce_tween:
		_bounce_tween.kill()
		_bounce_tween = null
	self.scale = Vector2.ONE
