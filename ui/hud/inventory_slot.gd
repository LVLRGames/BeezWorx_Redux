# inventory_slot.gd
# res://ui/hud/inventory_slot.gd
#
# HexPickerSlot subclass for pawn inventory.
# Populates cells from PawnInventory. Filters to specific item_id if set.
# Replaces the old HotbarSlot.

class_name InventorySlot
extends HexPickerSlot

signal item_selected(item_id: StringName, count: int)

const INVENTORY_CELL_SCENE := preload("res://ui/hud/inventory_cell.tscn")

var _pawn_id:     int         = -1
var _filter_item: StringName  = &""

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		EventBus.pawn_inventory_changed.connect(_on_inventory_changed)
		EventBus.pawn_possessed.connect(_on_pawn_possessed)

# ════════════════════════════════════════════════════════════════════════════ #
#  Public
# ════════════════════════════════════════════════════════════════════════════ #

func setup(pawn_id: int) -> void:
	_pawn_id = pawn_id
	_filter_item = &""
	refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	_sel_col = 0
	_sel_row = 0
	_scroll_to_selected(false)
	_fade_cells(false)

func filter_to_item(item_id: StringName) -> void:
	if _filter_item == item_id:
		return
	_filter_item = item_id
	refresh()
	# Jump to first matching cell
	var idx: int = _entries.find(item_id)
	if idx >= 0:
		flash(idx)

# ════════════════════════════════════════════════════════════════════════════ #
#  HexPickerSlot overrides
# ════════════════════════════════════════════════════════════════════════════ #

func _build_cells() -> void:
	super()   # clears grid and entries

	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	if state != null and state.inventory != null:
		for item_id: StringName in state.inventory.get_item_ids():
			if _filter_item != &"" and item_id != _filter_item:
				continue
			var count: int = state.inventory.get_count(item_id)
			if count <= 0:
				continue
			_entries.append(item_id)
			var cell: InventoryCell = INVENTORY_CELL_SCENE.instantiate()
			cell.modulate.a = 0.0
			cell.set_meta("item_id", item_id)
			_grid.add_child(cell)
			var icon: Texture2D = ItemRegistry.get_icon(item_id)
			cell.set_item(item_id, count, icon)

	# Pad to min slots with empty cells
	var current: int = _entries.size()
	for i in range(current, min_visible_slots):
		_entries.append(&"")
		var cell: InventoryCell = INVENTORY_CELL_SCENE.instantiate()
		cell.modulate.a = 0.0
		cell.set_meta("item_id", &"")
		_grid.add_child(cell)
		cell.set_empty()

func _get_entry_display_name(idx: int) -> String:
	if idx < 0 or idx >= _entries.size():
		return ""
	var item_id: StringName = _entries[idx]
	if item_id == &"":
		return ""
	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	var count: int = state.inventory.get_count(item_id) if state and state.inventory else 0
	return "%s  ×%d" % [ItemRegistry.get_display_name(item_id), count]

func _on_confirmed(idx: int) -> void:
	if idx < 0 or idx >= _entries.size():
		return
	var item_id: StringName = _entries[idx]
	if item_id == &"":
		return
	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	var count: int = state.inventory.get_count(item_id) if state and state.inventory else 0
	emit_signal("item_selected", item_id, count)

func _make_preview_cell(_index: int) -> Control:
	var cell: InventoryCell = INVENTORY_CELL_SCENE.instantiate()
	cell.modulate.a = 0.0
	cell.set_empty()
	return cell

# ════════════════════════════════════════════════════════════════════════════ #
#  EventBus
# ════════════════════════════════════════════════════════════════════════════ #

func _on_inventory_changed(pawn_id: int, item_id: StringName) -> void:
	if pawn_id != _pawn_id:
		return
	var prev_idx: int = get_selected_index()
	var prev_item: StringName = _entries[prev_idx] if prev_idx >= 0 \
		and prev_idx < _entries.size() else &""
	refresh()
	# Navigate to changed item
	var target: StringName = item_id if item_id != &"" else prev_item
	var idx: int = _entries.find(target)
	if idx >= 0:
		flash(idx)
	else:
		_fade_cells(false)

func _on_pawn_possessed(player_slot: int, pawn_id: int) -> void:
	if player_slot != 1:
		return
	setup(pawn_id)
