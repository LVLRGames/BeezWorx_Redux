# hex_picker_slot.gd
# res://ui/hud/hex_picker_slot.gd
#
# Generic scrollable hex grid picker. Base class for InventorySlot and AbilitySlot.
# Shows a HexGridContainer inside a ScrollContainer — one cell always centered.
# Cells fade by distance from selected when active.
#
# Subclasses override:
#   _build_cells()       — populate _grid with cells, fill _entries
#   _on_confirmed(idx)   — called when player confirms selection
#   _make_cell(entry)    — instantiate and return a configured cell node
#
# SCENE STRUCTURE (same for all subclasses):
#   HexPickerSlot (Control, this script or subclass)
#   ├── ScrollContainer
#   │   └── HexGridContainer
#   ├── VignetteOverlay (ColorRect, mouse_filter=IGNORE)
#   └── InfoLabel (RichTextLabel)

@tool
class_name HexPickerSlot
extends Control

signal entry_confirmed(index: int)
signal picker_closed()

const SCROLL_DURATION:           float = 0.15
const ITEM_DISPLAY_TIME:         float = 2.0

@onready var _scroll:      ScrollContainer  = $ScrollContainer
@onready var _grid:        HexGridContainer = $ScrollContainer/HexGridContainer
@onready var _vignette:    ColorRect        = $VignetteOverlay
@onready var _info_label:  RichTextLabel    = $InfoLabel

# ── Exports ───────────────────────────────────────────────────────────────────
@export var min_visible_slots:  int   = 9
@export var visibility_radius:  int   = 3
@export var center_alpha:       float = 1.0
@export var falloff_curve:      Curve = null

@export var preview_cell_count: int = 9:
	set(v):
		preview_cell_count = v
		if Engine.is_editor_hint() and is_node_ready() and _grid != null:
			_rebuild_preview()

@export var selected_cell_index: int = 0:
	set(v):
		selected_cell_index = clamp(v, 0, max(0, preview_cell_count - 1))
		if Engine.is_editor_hint() and is_node_ready() and _grid != null:
			_sel_col = selected_cell_index % _grid.columns
			_sel_row = selected_cell_index / _grid.columns
			_update_selection_visuals()
			_scroll_to_selected(false)

@export var grow_direction: HexGridContainer.HexGrowDirection = \
		HexGridContainer.HexGrowDirection.UP:
	set(v):
		grow_direction = v
		if _grid != null:
			_grid.grow_direction = v
			_scroll_to_selected(false)

# ── Runtime state ─────────────────────────────────────────────────────────────
## Subclass fills this array — each element is whatever the subclass tracks
## (StringName item_id, AbilityDef, etc.)
var _entries:       Array          = []
var _sel_col:       int            = 0
var _sel_row:       int            = 0
var _active:        bool           = false
var _scroll_tween:  Tween          = null
var _label_tween:   Tween          = null
var _pickup_timer:  float          = 0.0
var _ft:            Tween          = null  

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	if not Engine.is_editor_hint():
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_scroll.follow_focus            = false
		_grid.size_flags_horizontal     = Control.SIZE_SHRINK_BEGIN
		_grid.size_flags_vertical       = Control.SIZE_SHRINK_BEGIN
		if _vignette:
			_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _info_label:
			_info_label.modulate.a = 0.0

func _process(delta: float) -> void:
	if _pickup_timer > 0.0:
		_pickup_timer -= delta
		if _pickup_timer <= 0.0 and not _active:
			_fade_cells(false)

# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

func refresh() -> void:
	_build_cells()
	_clamp_selection()
	_update_selection_visuals()

func set_active(active: bool) -> void:
	_active = active
	if active:
		_pickup_timer = 0.0
		_scroll_to_selected(true)
		_fade_cells(true)
	else:
		_pickup_timer = 0.0
		_fade_cells(false)
		emit_signal("picker_closed")

func is_active() -> bool:
	return _active

func navigate(dir: Vector2i) -> void:
	if not _active:
		return
	var total: int  = _grid.get_child_count()
	if total == 0:
		return
	var rows: int    = int(ceil(float(total) / float(_grid.columns)))
	var new_col: int = _sel_col + dir.x
	var new_row: int = _sel_row + dir.y
	new_row = clampi(new_row, 0, rows - 1)
	var max_col: int = mini(_grid.columns - 1, total - 1 - new_row * _grid.columns)
	new_col = clampi(new_col, 0, max_col)
	if new_col == _sel_col and new_row == _sel_row:
		return
	_sel_col = new_col
	_sel_row = new_row
	_update_selection_visuals()
	_scroll_to_selected(true)
	_refresh_info_label()

func confirm_selection() -> void:
	var idx: int = _grid.col_row_to_index(_sel_col, _sel_row)
	if idx < 0 or idx >= _entries.size():
		return
	_on_confirmed(idx)
	emit_signal("entry_confirmed", idx)
	set_active(false)

func get_selected_index() -> int:
	return _grid.col_row_to_index(_sel_col, _sel_row)

## Flash the picker open briefly (e.g. on item pickup) then auto-close
func flash(target_index: int = -1) -> void:
	if target_index >= 0:
		var cr: Vector2i = _grid.index_to_col_row(target_index)
		_sel_col = cr.x
		_sel_row = cr.y
		_update_selection_visuals()
		_scroll_to_selected(false)
	_fade_cells(true)
	_refresh_info_label()
	_fade_info_label(true)
	_pickup_timer = ITEM_DISPLAY_TIME


func show_selected_only() -> void:
	_fade_cells(false)

func show_with_falloff() -> void:
	_fade_cells(true)


# ════════════════════════════════════════════════════════════════════════════ #
#  Overridable by subclasses
# ════════════════════════════════════════════════════════════════════════════ #

## Subclass: clear and repopulate _grid and _entries
func _build_cells() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_entries.clear()

## Subclass: return display name for info label
func _get_entry_display_name(_idx: int) -> String:
	return ""

## Subclass: called on confirm
func _on_confirmed(_idx: int) -> void:
	pass

## Subclass: build preview cells for editor
func _rebuild_preview() -> void:
	if not is_node_ready():
		return
	for child in _grid.get_children():
		child.queue_free()
	_entries.clear()
	for i in preview_cell_count:
		var cell: Control = _make_preview_cell(i)
		if cell:
			_grid.add_child(cell)
		_entries.append(null)
	_update_selection_visuals()
	_scroll_to_selected(false)

## Subclass: make a preview cell for editor display
func _make_preview_cell(_index: int) -> Control:
	return null

# ════════════════════════════════════════════════════════════════════════════ #
#  Selection + scroll
# ════════════════════════════════════════════════════════════════════════════ #

func _clamp_selection() -> void:
	var total: int = maxi(_entries.size(), min_visible_slots)
	if total > 0:
		_sel_col = clampi(_sel_col, 0, _grid.columns - 1)
		var rows: int = int(ceil(float(total) / float(_grid.columns)))
		_sel_row = clampi(_sel_row, 0, rows - 1)
	else:
		_sel_col = 0
		_sel_row = 0

func _update_selection_visuals() -> void:
	var sel_idx: int = _grid.col_row_to_index(_sel_col, _sel_row)
	var children     = _grid.get_children()
	for i: int in children.size():
		var cell: Control = children[i] as Control
		if cell == null:
			continue
		if cell.has_method("set_selected"):
			cell.set_selected(i == sel_idx)
	_info_label.text = _get_entry_display_name(sel_idx)


func _scroll_to_selected(animated: bool) -> void:
	if not is_node_ready():
		return
	if not Engine.is_editor_hint():
		await get_tree().process_frame
	var center: Vector2        = _grid.get_cell_center(_sel_col, _sel_row)
	var viewport_size: Vector2 = _scroll.size
	var grid_size: Vector2     = _grid.get_minimum_size()
	var max_h: float = maxf(0.0, grid_size.x - viewport_size.x)
	var max_v: float = maxf(0.0, grid_size.y - viewport_size.y)
	var target_h: int = int(round(clampf(center.x - viewport_size.x * 0.5, 0.0, max_h)))
	var target_v: int = int(round(clampf(center.y - viewport_size.y * 0.5, 0.0, max_v)))
	if not animated or Engine.is_editor_hint():
		_scroll.scroll_horizontal = target_h
		_scroll.scroll_vertical   = target_v
		return
	if _scroll_tween:
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_scroll_tween.tween_property(_scroll, "scroll_horizontal", target_h, SCROLL_DURATION)
	_scroll_tween.parallel().tween_property(_scroll, "scroll_vertical", target_v, SCROLL_DURATION)

# ════════════════════════════════════════════════════════════════════════════ #
#  Cell fading
# ════════════════════════════════════════════════════════════════════════════ #

func fade_in() -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", 1.0, 0.2)
 
func fade_out(hide_after: bool = false) -> void:
	if _ft: _ft.kill()
	_ft = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_ft.tween_property(self, "modulate:a", 0.0, 0.2)
	if hide_after:
		_ft.tween_callback(func(): visible = false)
 
func _fade_cells(show_all: bool) -> void:
	var sel_idx: int     = _grid.col_row_to_index(_sel_col, _sel_row)
	var sel_cr: Vector2i = Vector2i(_sel_col, _sel_row)
	var children         = _grid.get_children()
	for i: int in children.size():
		var cell: Control = children[i] as Control
		if cell == null:
			continue
		var target_alpha: float
		if not show_all:
			target_alpha = 1.0 if i == sel_idx else 0.0
		else:
			var cr: Vector2i = _grid.index_to_col_row(i)
			var dist: int    = _hex_grid_dist(sel_cr, cr)
			if dist == 0:
				target_alpha = center_alpha
			elif dist > visibility_radius:
				target_alpha = 0.0
			elif falloff_curve != null:
				var t: float = float(dist) / float(visibility_radius)
				target_alpha = falloff_curve.sample(1.0 - t)
			else:
				target_alpha = 1.0 - (float(dist) / float(visibility_radius + 1))
		if cell.has_method("fade_to"):
			cell.fade_to(target_alpha)
		else:
			cell.modulate.a = target_alpha



# ════════════════════════════════════════════════════════════════════════════ #
#  Info label
# ════════════════════════════════════════════════════════════════════════════ #

func _refresh_info_label() -> void:
	if _info_label == null:
		return
	var idx: int = get_selected_index()
	var display: String = _get_entry_display_name(idx)
	if display.is_empty():
		_info_label.text = ""
	else:
		_info_label.text = "[center]%s[/center]" % display

func _fade_info_label(show: bool) -> void:
	if _info_label == null:
		return
	if _label_tween:
		_label_tween.kill()
	_label_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_label_tween.tween_property(_info_label, "modulate:a", 1.0 if show else 0.0, 0.2)

# ════════════════════════════════════════════════════════════════════════════ #
#  Hex distance helpers
# ════════════════════════════════════════════════════════════════════════════ #

static func _hex_grid_dist(a: Vector2i, b: Vector2i) -> int:
	var a_axial: Vector2i = _offset_to_axial(a)
	var b_axial: Vector2i = _offset_to_axial(b)
	var dq: int = b_axial.x - a_axial.x
	var dr: int = b_axial.y - a_axial.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2

static func _offset_to_axial(cr: Vector2i) -> Vector2i:
	var q: int = cr.x - (cr.y - (cr.y & 1)) / 2
	var r: int = cr.y
	return Vector2i(q, r)
