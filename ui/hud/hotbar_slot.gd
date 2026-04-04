# hotbar_slot.gd
# res://ui/hud/hotbar_slot.gd
#
# Controls a hotbar inventory slot — a small window into the pawn's inventory
# displayed as a HexGridContainer inside a ScrollContainer.
# The selected cell is always centered. Surrounding cells fade via vignette overlay.
#
# SCENE STRUCTURE:
#   HotbarSlot (Control, this script)
#   ├── ScrollContainer        — clips the hex grid, no scrollbars
#   │   └── HexGridContainer   — full inventory grid
#   └── VignetteOverlay        — ColorRect, same size, vignette shader on top
#       mouse_filter = IGNORE  — clicks pass through to grid below
#
# USAGE:
#   Call setup(pawn_id) to populate from inventory.
#   Call set_active(true/false) to open/close the expanded scroll view.
#   Navigate with navigate(dir: Vector2i) to move selection.
@tool
class_name HotbarSlot
extends Control

signal item_selected(item_id: StringName, count: int)
signal slot_closed()

const INVENTORY_CELL_SCENE := preload("res://ui/hud/inventory_cell.tscn")
const SCROLL_DURATION: float = 0.15

@onready var _scroll:      ScrollContainer  = $ScrollContainer
@onready var _grid:        HexGridContainer = $ScrollContainer/HexGridContainer
@onready var _vignette:    ColorRect        = $VignetteOverlay
@onready var _info_label:  RichTextLabel    = $InfoLabel
@export var preview_cell_count: int = 16:
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

@export var grow_direction: HexGridContainer.HexGrowDirection = HexGridContainer.HexGrowDirection.UP:
	set(v):
		grow_direction = v
		if _grid != null:
			_grid.grow_direction = v
			_scroll_to_selected(false)

@export var min_visible_slots: int = 1
@export var visibility_radius: int   = 3      # cells beyond this = invisible
@export var center_alpha:      float = 1.0
@export var falloff_curve: Curve   # optional — if null uses linear falloff


var _pawn_id:    int        = -1
var _items:      Array[StringName] = []   # item_ids in grid order
var _sel_col:    int        = 0
var _sel_row:    int        = 0
var _active:     bool       = false
var _scroll_tween: Tween    = null
var _label_tween:  Tween    = null

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.follow_focus = false

	if _vignette:
		_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_update_grid_padding()

	EventBus.pawn_inventory_changed.connect(_on_inventory_changed)
	EventBus.pawn_possessed.connect(_on_pawn_possessed)
	_refresh_info_label()
	_fade_info_label(true)

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_grid_padding()
		#size += Vector2(_grid.gap, _grid.gap) * 2

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("p1_toggle_inventory"):
		set_active(true)
		_refresh_info_label()
		_fade_info_label(true)

	if event.is_action_released("p1_toggle_inventory"):
		set_active(false)
		_fade_info_label(false)
	
	# Navigate while hotbar is held — respond to directional press events
	if _active and event.is_action_pressed("p1_move_left"):
		navigate(Vector2i(-1, 0))
	if _active and event.is_action_pressed("p1_move_right"):
		navigate(Vector2i(1, 0))
	if _active and event.is_action_pressed("p1_move_forward"):
		navigate(Vector2i(0, -1))
	if _active and event.is_action_pressed("p1_move_back"):
		navigate(Vector2i(0, 1))
	
	if _active and event.is_action_pressed("p1_action"):
		confirm_selection()
		get_viewport().set_input_as_handled()


# ════════════════════════════════════════════════════════════════════════════ #
#  Public API
# ════════════════════════════════════════════════════════════════════════════ #

func setup(pawn_id: int) -> void:
	_pawn_id = pawn_id
	_rebuild_grid()
	_update_grid_padding()
	await get_tree().process_frame
	await get_tree().process_frame  # two frames — layout needs to fully settle
	_update_grid_padding()
	_sel_col = 0
	_sel_row = 0
	_scroll_to_selected(false)
	_fade_cells(false)   

func set_active(active: bool) -> void:
	_active = active
	if active:
		_scroll_to_selected(true)
		_fade_cells(true)
	else:
		_fade_cells(false)
		emit_signal("slot_closed")


func is_active() -> bool:
	return _active

## Navigate selection by direction. dir is a Vector2i offset in col/row space.
func navigate(dir: Vector2i) -> void:
	if not _active:
		return

	var total: int  = _grid.get_child_count()
	var rows: int   = int(ceil(float(total) / float(_grid.columns)))
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


## Confirm current selection — emits item_selected.
func confirm_selection() -> void:
	var idx: int = _grid.col_row_to_index(_sel_col, _sel_row)
	if idx < 0 or idx >= _items.size():
		return
	var item_id: StringName = _items[idx]
	var state: PawnState    = PawnRegistry.get_state(_pawn_id)
	var count: int          = state.inventory.get_count(item_id) if state and state.inventory else 0
	emit_signal("item_selected", item_id, count)
	set_active(false)

## Returns the currently selected item_id, or &"" if nothing selected.
func get_selected_item() -> StringName:
	var idx: int = _grid.col_row_to_index(_sel_col, _sel_row)
	if idx < 0 or idx >= _items.size():
		return &""
	return _items[idx]


func show_filtered_items(item_id: StringName) -> void:
	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	if state == null or state.inventory == null:
		return
 
	# Rebuild showing only matching items
	for child in _grid.get_children():
		child.queue_free()
	_items.clear()
 
	for id: StringName in state.inventory.get_item_ids():
		if item_id != &"" and id != item_id:
			continue
		var count: int = state.inventory.get_count(id)
		if count <= 0:
			continue
		_items.append(id)
		_make_item_cell(id, count)
 
	# Pad to min slots
	var current: int = _items.size()
	for i in range(current, min_visible_slots):
		var cell: InventoryCell = INVENTORY_CELL_SCENE.instantiate()
		cell.modulate.a = 0.0
		cell.set_meta("item_id", &"")
		_grid.add_child(cell)
		cell.set_empty()
 
	# Jump to first matching item
	if not _items.is_empty():
		var idx: int = 0
		var cr: Vector2i = _grid.index_to_col_row(idx)
		_sel_col = cr.x
		_sel_row = cr.y
 
	_update_selection_visuals()
	_scroll_to_selected(false)
	_fade_cells(false)



# ════════════════════════════════════════════════════════════════════════════ #
#  Grid population
# ════════════════════════════════════════════════════════════════════════════ #
func _rebuild_preview() -> void:
	if not is_node_ready():
		return
	for child in _grid.get_children():
		child.queue_free()
	_items.clear()
	for i in preview_cell_count:
		var cell: InventoryCell = INVENTORY_CELL_SCENE.instantiate()
		cell.set_meta("item_id", &"preview_%d" % i)
		_grid.add_child(cell)
		_items.append(&"preview_%d" % i)
	_update_selection_visuals()
	_scroll_to_selected(false)


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_items.clear()

	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	if state != null and state.inventory != null:
		for item_id: StringName in state.inventory.get_item_ids():
			var count: int = state.inventory.get_count(item_id)
			if count <= 0:
				continue
			_items.append(item_id)
			_make_item_cell(item_id, count)

	# Pad with empty cells up to min_visible_slots
	var current: int = _items.size()
	for i in range(current, min_visible_slots):
		var cell: InventoryCell = INVENTORY_CELL_SCENE.instantiate()
		cell.set_meta("item_id", &"")
		_grid.add_child(cell)
		cell.set_empty()

	# Clamp selection
	var total: int = maxi(_items.size(), min_visible_slots)
	if not _items.is_empty():
		_sel_col = clampi(_sel_col, 0, _grid.columns - 1)
		var rows: int = int(ceil(float(total) / float(_grid.columns)))
		_sel_row = clampi(_sel_row, 0, rows - 1)
	else:
		_sel_col = 0
		_sel_row = 0

	_update_selection_visuals()
	_scroll_to_selected(true)


func _make_item_cell(item_id: StringName, count: int) -> InventoryCell:
	var cell: InventoryCell = INVENTORY_CELL_SCENE.instantiate()
	cell.set_meta("item_id", item_id)
	_grid.add_child(cell)
	var icon: Texture2D = ItemRegistry.get_icon(item_id)
	cell.set_item(item_id, count, icon)
	return cell

func _update_selection_visuals() -> void:
	var sel_idx: int = _grid.col_row_to_index(_sel_col, _sel_row)
	var children     = _grid.get_children()
	for i: int in children.size():
		var cell: InventoryCell = children[i] as InventoryCell
		if cell == null:
			continue
		cell.set_selected(i == sel_idx)
	# Don't call _fade_cells here — caller decides



func _update_grid_padding():
	if _grid == null or _scroll == null:
		return

	var viewport_size: Vector2 = _scroll.size
	_grid.padding = Vector2(_grid.gap, _grid.gap)


func _fade_info_label(visible_target: bool) -> void:
	if _label_tween:
		_label_tween.kill()
	_label_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_label_tween.tween_property(_info_label, "modulate:a", 1.0 if visible_target else 0.0, 0.2)

func _refresh_info_label() -> void:
	var item_id: StringName = get_selected_item()
	if item_id == &"":
		_info_label.text = ""
		return
	var display: String = ItemRegistry.get_display_name(item_id)
	var count: int = 0
	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	if state and state.inventory:
		count = state.inventory.get_count(item_id)
	_info_label.text = "[center]%s  ×%d[/center]" % [display, count]

func _fade_cells(show_all: bool) -> void:
	var sel_idx: int   = _grid.col_row_to_index(_sel_col, _sel_row)
	var sel_cr: Vector2i = Vector2i(_sel_col, _sel_row)
	var children       = _grid.get_children()

	for i: int in children.size():
		var cell: Control = children[i] as Control
		if cell == null:
			continue

		var target_alpha: float
		if not show_all:
			# Inactive — only selected cell visible
			target_alpha = 1.0 if i == sel_idx else 0.0
		else:
			var cr: Vector2i   = _grid.index_to_col_row(i)
			var dist: int      = _hex_grid_dist(sel_cr, cr)
			if dist > visibility_radius:
				target_alpha = 0.0
			elif falloff_curve != null:
				var t: float = float(dist) / float(visibility_radius)
				target_alpha = falloff_curve.sample(1.0 - t)
			else:
				# Linear falloff
				target_alpha = 1.0 - (float(dist) / float(visibility_radius + 1))

		var tween := cell.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(cell, "modulate:a", target_alpha, 1.5)

static func _hex_grid_dist(a: Vector2i, b: Vector2i) -> int:
	# Offset grid distance — accounts for odd row shift
	# Convert offset coords to axial, then use axial distance
	var a_axial: Vector2i = _offset_to_axial(a)
	var b_axial: Vector2i = _offset_to_axial(b)
	var dq: int = b_axial.x - a_axial.x
	var dr: int = b_axial.y - a_axial.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2

static func _offset_to_axial(cr: Vector2i) -> Vector2i:
	# Odd-row-right offset → axial
	var q: int = cr.x - (cr.y - (cr.y & 1)) / 2
	var r: int = cr.y
	return Vector2i(q, r)


# ════════════════════════════════════════════════════════════════════════════ #
#  Scroll
# ════════════════════════════════════════════════════════════════════════════ #



func _scroll_to_selected(animated: bool) -> void:
	if not is_node_ready():
		return

	await get_tree().process_frame

	var center: Vector2 = _grid.get_cell_center(_sel_col, _sel_row)
	var viewport_size: Vector2 = _scroll.size
	var grid_size: Vector2 = _grid.get_minimum_size()

	var max_h: float = maxf(0.0, grid_size.x - viewport_size.x)
	var max_v: float = maxf(0.0, grid_size.y - viewport_size.y)

	var target_h: int = int(round(clampf(
		center.x - viewport_size.x * 0.5,
		0.0,
		max_h
	)))
	var target_v: int = int(round(clampf(
		center.y - viewport_size.y * 0.5,
		0.0,
		max_v
	)))

	if not animated or Engine.is_editor_hint():
		_scroll.scroll_horizontal = target_h
		_scroll.scroll_vertical = target_v
		return

	if _scroll_tween:
		_scroll_tween.kill()

	_scroll_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_scroll_tween.tween_property(_scroll, "scroll_horizontal", target_h, SCROLL_DURATION)
	_scroll_tween.parallel().tween_property(_scroll, "scroll_vertical", target_v, SCROLL_DURATION)

# ════════════════════════════════════════════════════════════════════════════ #
#  EventBus
# ════════════════════════════════════════════════════════════════════════════ #

func _on_inventory_changed(pawn_id: int, item_id: StringName) -> void:
	if pawn_id != _pawn_id:
		return
	
	var prev_item: StringName = get_selected_item()
	_rebuild_grid()
	await get_tree().process_frame
	_fade_cells(true)
	
	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	if state == null or state.inventory == null:
		_fade_cells(false)
		return
	
	var item_ids: Array[StringName] = state.inventory.get_item_ids()
	if item_ids.is_empty():
		_fade_cells(false)
		return
	
	# Navigate to changed item
	var target_item: StringName = prev_item if item_id.is_empty() else item_id
	if target_item == &"" or not state.inventory.has_item(target_item):
		target_item = item_ids[0]
	
	var idx: int = _items.find(target_item)
	if idx >= 0:
		var cr: Vector2i = _grid.index_to_col_row(idx)
		_sel_col = cr.x
		_sel_row = cr.y
	
	_update_selection_visuals()
	_scroll_to_selected(true)
	_refresh_info_label()
	await get_tree().create_timer(1.5).timeout
	_fade_cells(false)   # ← always end inactive — only selected visible


func _on_pawn_possessed(player_slot: int, pawn_id: int) -> void:
	if player_slot != 1:
		return
	setup(pawn_id)
