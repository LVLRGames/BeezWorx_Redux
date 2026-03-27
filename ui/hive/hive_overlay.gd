# hive_overlay.gd
# res://ui/hive/hive_overlay.gd

class_name HiveOverlay
extends CanvasLayer

const HIVE_TILESET        := preload("res://ui/hive/hive_slot_tileset.tres")
const SLOT_TILE_SCENE     := preload("res://ui/hive/slot_tile.tscn")
const SLOT_TEXTURE        := preload("res://ui/hive/slot.png")
const SLOT_ALPHA:          float = 0.82
const CAM_TWEEN_DURATION:  float = 0.15
const TILE_PX:             int   = 40
const TILE_FRAMES:         int   = 6
const PANEL_SLIDE_DURATION: float = 0.2
const PANEL_WIDTH:         float = 300.0
const NAV_REPEAT_DELAY:    float = 0.15

enum FocusArea { GRID, PANEL }

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var _hive_name:        LineEdit       = $MainContainer/VBoxContainer/HiveHeader/HiveHeaderContent/HiveName
@onready var _integrity_bar:    ProgressBar    = $MainContainer/VBoxContainer/HiveHeader/HiveHeaderContent/IntegrityBar
@onready var _territory_label:  Label          = $MainContainer/VBoxContainer/HiveHeader/HiveHeaderContent/TerritoryLabel
@onready var _exit_button:      Button         = $MainContainer/VBoxContainer/HiveHeader/HiveHeaderContent/ExitButton
@onready var _viewport:         SubViewport    = $MainContainer/VBoxContainer/ContentRow/SubViewportContainer/SubViewport
@onready var _camera:           Camera2D       = $MainContainer/VBoxContainer/ContentRow/SubViewportContainer/SubViewport/Camera2D
@onready var _slot_layer:       TileMapLayer   = $MainContainer/VBoxContainer/ContentRow/SubViewportContainer/SubViewport/SlotLayer
@onready var _select_layer:     TileMapLayer   = $MainContainer/VBoxContainer/ContentRow/SubViewportContainer/SubViewport/SelectLayer
@onready var _slot_panel:       PanelContainer = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel
@onready var _slot_title:       Label          = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/SlotTitle
@onready var _designation_box:  VBoxContainer  = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/DesignationOptions
@onready var _contents_label:   Label          = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/ContentsLabel
@onready var _contents_grid:    GridContainer  = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/ContentsGrid
@onready var _deposit_section:  VBoxContainer  = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/DepositSection
@onready var _item_selector:    OptionButton   = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/DepositSection/ItemSelector
@onready var _quantity_input:   SpinBox        = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/DepositSection/QuantityInput
@onready var _deposit_button:   Button         = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/DepositSection/DepositButton
@onready var _withdraw_section: VBoxContainer  = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/WithdrawSection
@onready var _withdraw_item:    OptionButton   = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/WithdrawSection/WithdrawItemSelector
@onready var _withdraw_qty:     SpinBox        = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/WithdrawSection/WithdrawQuantityInput
@onready var _withdraw_button:  Button         = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/WithdrawSection/WithdrawButton
@onready var _storage_lock_section:   VBoxContainer = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/StorageLockSection
@onready var _storage_lock_selector:  OptionButton  = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/StorageLockSection/StorageLockSelector
@onready var _storage_lock_button:    Button        = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/StorageLockSection/StorageLockButton
@onready var _storage_clear_button:   Button        = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/StorageLockSection/StorageClearButton
@onready var _crafting_recipe_section: VBoxContainer = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/CraftingRecipeSection
@onready var _recipe_selector:        OptionButton  = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/CraftingRecipeSection/RecipeSelector
@onready var _recipe_set_button:      Button        = $MainContainer/VBoxContainer/ContentRow/PanelAnchor/SlotPanel/SlotPanelScroll/SlotPanelContent/CraftingRecipeSection/RecipeSetButton

# ── State ─────────────────────────────────────────────────────────────────────
var _hive_id:        int                            = -1
var _controller:     HiveController                 = null
var _selected_cell:  Vector2i                       = Vector2i.ZERO
var _cell_to_slot:   Dictionary[Vector2i, int]      = {}
var _slot_to_cell:   Dictionary[int, Vector2i]      = {}
var _cam_tween:      Tween                          = null
var _tileset_built:  bool                           = false
var _tile_instances: Dictionary[Vector2i, SlotTile] = {}
var _focus_area:     FocusArea                      = FocusArea.GRID
var _panel_tween:    Tween                          = null
var _px:             String                         = "p1_"
var _nav_cooldown:   float                          = 0.0

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	add_to_group("hive_overlay")
	visible = false
	_slot_panel.visible = false
	_exit_button.pressed.connect(_on_exit_pressed)
	_hive_name.text_submitted.connect(_on_name_submitted)
	_deposit_button.pressed.connect(_on_deposit_pressed)
	_withdraw_button.pressed.connect(_on_withdraw_pressed)
	_storage_lock_button.pressed.connect(_on_storage_lock_pressed)
	_storage_clear_button.pressed.connect(_on_storage_clear_pressed)
	_recipe_set_button.pressed.connect(_on_recipe_set_pressed)

func _process(delta: float) -> void:
	if _nav_cooldown > 0.0:
		_nav_cooldown -= delta

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(_px + "cancel"):
		match _focus_area:
			FocusArea.PANEL:
				_focus_area = FocusArea.GRID
				_hide_panel()
				get_viewport().set_input_as_handled()
				return
			FocusArea.GRID:
				var focused: Control = get_viewport().gui_get_focus_owner()
				if focused == _exit_button:
					_on_exit_pressed()
				else:
					_exit_button.grab_focus()
				get_viewport().set_input_as_handled()
				return

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed(_px + "confirm"):
		if _focus_area == FocusArea.PANEL:
			var focused: Control = get_viewport().gui_get_focus_owner()
			if focused is Button:
				(focused as Button).emit_signal("pressed")
				get_viewport().set_input_as_handled()
				return
		else:
			var slot_index: int = _cell_to_slot.get(_selected_cell, -2)
			if slot_index >= 0:   # real slot only — not locked (-1) or missing (-2)
				_focus_panel()
			get_viewport().set_input_as_handled()
			return

	if _focus_area == FocusArea.GRID:
		var moved := false
		if _nav_cooldown <= 0.0:
			if event.is_action_pressed(_px + "move_right") or event.is_action_pressed("ui_right"):
				moved = _navigate_to_neighbor(Vector2(1.0, 0.0))
			elif event.is_action_pressed(_px + "move_left") or event.is_action_pressed("ui_left"):
				moved = _navigate_to_neighbor(Vector2(-1.0, 0.0))
			elif event.is_action_pressed(_px + "move_forward") or event.is_action_pressed("ui_up"):
				moved = _navigate_to_neighbor(Vector2(0.0, -1.0))
			elif event.is_action_pressed(_px + "move_back") or event.is_action_pressed("ui_down"):
				moved = _navigate_to_neighbor(Vector2(0.0, 1.0))
		if moved:
			_nav_cooldown = NAV_REPEAT_DELAY
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed:
		_handle_viewport_click(event.position)

# ════════════════════════════════════════════════════════════════════════════ #
#  Open / Close
# ════════════════════════════════════════════════════════════════════════════ #

func open_hive(hive_id: int, controller: HiveController, player_slot: int = 1) -> void:
	_hive_id    = hive_id
	_controller = controller
	_px         = "p%d_" % player_slot
	visible     = true
	await get_tree().process_frame
	_rebuild_ui()
	_focus_area = FocusArea.GRID

func close_hive() -> void:
	_slot_panel.visible = false
	visible             = false
	_hive_id            = -1
	_controller         = null
	_selected_cell      = Vector2i.ZERO
	_cell_to_slot.clear()
	_slot_to_cell.clear()
	_tile_instances.clear()

func _on_exit_pressed() -> void:
	if _controller:
		_controller.request_exit()
	else:
		close_hive()

# ════════════════════════════════════════════════════════════════════════════ #
#  Panel show / hide
# ════════════════════════════════════════════════════════════════════════════ #

func _show_panel() -> void:
	if _panel_tween:
		_panel_tween.kill()
	_slot_panel.visible    = true
	_slot_panel.modulate.a = 1.0
	_slot_panel.position.x = PANEL_WIDTH
	_panel_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_panel_tween.tween_property(_slot_panel, "position:x", 0.0, PANEL_SLIDE_DURATION)

func _hide_panel() -> void:
	if not _slot_panel.visible:
		return
	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_panel_tween.parallel().tween_property(_slot_panel, "position:x",  PANEL_WIDTH, PANEL_SLIDE_DURATION)
	_panel_tween.parallel().tween_property(_slot_panel, "modulate:a",  0.0,         PANEL_SLIDE_DURATION)
	_panel_tween.tween_callback(func(): _slot_panel.visible = false)

func _focus_panel() -> void:
	_focus_area = FocusArea.PANEL
	_show_panel()
	if _deposit_section.visible and _item_selector.item_count > 0:
		_item_selector.grab_focus()
		return
	if _designation_box.visible and _designation_box.get_child_count() > 0:
		(_designation_box.get_child(0) as Button).grab_focus()


func _refocus_panel() -> void:
	# Keep panel open, refocus first interactive element
	if _deposit_section.visible and _item_selector.item_count > 0:
		_item_selector.grab_focus()
	elif _withdraw_section.visible and _withdraw_item.item_count > 0:
		_withdraw_item.grab_focus()
	elif _designation_box.visible and _designation_box.get_child_count() > 0:
		(_designation_box.get_child(0) as Button).grab_focus()

# ════════════════════════════════════════════════════════════════════════════ #
#  UI build
# ════════════════════════════════════════════════════════════════════════════ #

func _rebuild_ui() -> void:
	var hs: HiveState = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	_rebuild_header(hs)
	_ensure_tileset()
	_rebuild_tilemap(hs)

func _rebuild_header(hs: HiveState) -> void:
	_hive_name.text          = hs.hive_name if not hs.hive_name.is_empty() else "Hive %d" % _hive_id
	_integrity_bar.max_value = hs.max_integrity
	_integrity_bar.value     = hs.integrity
	_territory_label.text    = "Territory: %d cells" % TerritorySystem.get_cell_count_for_colony(hs.colony_id)

# ════════════════════════════════════════════════════════════════════════════ #
#  TileSet
# ════════════════════════════════════════════════════════════════════════════ #

func _ensure_tileset() -> void:
	if _tileset_built:
		return
	_tileset_built = true
	_slot_layer.tile_set  = HIVE_TILESET
	_select_layer.tile_set = HIVE_TILESET

# ════════════════════════════════════════════════════════════════════════════ #
#  Tilemap build
# ════════════════════════════════════════════════════════════════════════════ #

func _rebuild_tilemap(hs: HiveState) -> void:
	_slot_layer.clear()
	_select_layer.clear()
	_cell_to_slot.clear()
	_slot_to_cell.clear()
	_tile_instances.clear()

	fill_centered_area(_slot_layer, Vector2i.ZERO, 32, 0, Vector2i(4, 0))

	var cells: Array[Vector2i] = _hex_spiral_cells(hs.slot_count)
	for i: int in cells.size():
		var cell: Vector2i = cells[i]
		_slot_layer.set_cell(cell, 1, Vector2i.ZERO, 1)
		_cell_to_slot[cell] = i
		_slot_to_cell[i]    = cell

	var locked_cells: Array[Vector2i] = _get_locked_ring_cells(hs)
	for cell: Vector2i in locked_cells:
		if not _cell_to_slot.has(cell):
			_slot_layer.set_cell(cell, 1, Vector2i.ZERO, 1)
			_cell_to_slot[cell] = -1

	_camera.position = _slot_layer.map_to_local(Vector2i.ZERO)
	call_deferred("_deferred_configure_all", hs)

func _get_locked_ring_cells(hs: HiveState) -> Array[Vector2i]:
	var next_tier_count: int = hs.slot_count + 18
	var all_next: Array[Vector2i] = _hex_spiral_cells(next_tier_count)
	var active_set: Dictionary = {}
	for cell: Vector2i in _cell_to_slot:
		active_set[cell] = true
	var locked: Array[Vector2i] = []
	for cell: Vector2i in all_next:
		if not active_set.has(cell):
			locked.append(cell)
	return locked

func _deferred_configure_all(hs: HiveState) -> void:
	_index_tile_instances()
	for cell: Vector2i in _cell_to_slot:
		var idx: int       = _cell_to_slot[cell]
		var tile: SlotTile = _get_slot_tile(cell)
		if tile == null:
			continue
		if idx < 0:
			tile.set_designation(HiveSlot.SlotDesignation.LOCKED)
			continue
		var slot: HiveSlot = hs.slots[idx] if idx < hs.slots.size() else null
		tile.set_designation(
			slot.designation if slot else HiveSlot.SlotDesignation.GENERAL,
			slot.subtype     if slot else HiveSlot.SlotSubtype.DEFAULT
		)
		tile.set_contents(
			slot.stored_items if slot else {},
			slot.sleeper_id   if slot else -1
		)
	_select_tilemap_cell(Vector2i.ZERO, false)

func _index_tile_instances() -> void:
	_tile_instances.clear()
	for child in _slot_layer.get_children(true):
		var tile := child as SlotTile
		if tile == null:
			continue
		var cell: Vector2i = _slot_layer.local_to_map(child.position)
		_tile_instances[cell] = tile

# ── Hex math ──────────────────────────────────────────────────────────────────

func _hex_spiral_cells(count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ring: int = 0
	while out.size() < count:
		for q: int in range(-ring, ring + 1):
			for r: int in range(-ring, ring + 1):
				var s: int = -q - r
				if maxi(absi(q), maxi(absi(r), absi(s))) == ring:
					out.append(Vector2i(q, r))
					if out.size() >= count:
						return out
		ring += 1
	return out

func _get_max_ring(cells: Array[Vector2i]) -> int:
	var max_r: int = 0
	for cell: Vector2i in cells:
		var r: int = (absi(cell.x) + absi(cell.y) + absi(cell.x + cell.y)) / 2
		max_r = maxi(max_r, r)
	return max_r

# ════════════════════════════════════════════════════════════════════════════ #
#  Selection and navigation
# ════════════════════════════════════════════════════════════════════════════ #

func _select_tilemap_cell(cell: Vector2i, tween_cam: bool) -> void:
	if _cell_to_slot.has(_selected_cell):
		var prev: SlotTile = _get_slot_tile(_selected_cell)
		if prev:
			prev.set_selected(false)
	_select_layer.clear()

	if not _cell_to_slot.has(cell):
		return

	_selected_cell = cell

	var tile: SlotTile = _get_slot_tile(cell)
	if tile:
		tile.set_selected(true)

	var target_pos: Vector2 = _slot_layer.map_to_local(cell)
	if tween_cam:
		if _cam_tween:
			_cam_tween.kill()
		_cam_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_cam_tween.tween_property(_camera, "position", target_pos, CAM_TWEEN_DURATION)
	else:
		_camera.position = target_pos

	_rebuild_slot_panel()

func _navigate_to_neighbor(direction: Vector2) -> bool:
	var neighbors: Array[Vector2i] = _slot_layer.get_surrounding_cells(_selected_cell)
	var best_cell: Vector2i        = _selected_cell
	var best_dot:  float           = 0.3
	var cur_local: Vector2         = _slot_layer.map_to_local(_selected_cell)

	for n: Vector2i in neighbors:
		if not _cell_to_slot.has(n):
			continue
		var offset: Vector2 = (_slot_layer.map_to_local(n) - cur_local).normalized()
		var dot: float      = direction.dot(offset)
		if dot > best_dot:
			best_dot  = dot
			best_cell = n

	if best_cell == _selected_cell:
		return false
	_select_tilemap_cell(best_cell, true)
	return true

func _handle_viewport_click(screen_pos: Vector2) -> void:
	var vpc: SubViewportContainer = _viewport.get_parent() as SubViewportContainer
	if vpc == null:
		return
	var vpc_rect: Rect2 = vpc.get_global_rect()
	if not vpc_rect.has_point(screen_pos):
		return
	var local: Vector2    = screen_pos - vpc_rect.position
	var scale: Vector2    = Vector2(_viewport.size) / vpc_rect.size
	var vp_local: Vector2 = local * scale
	var map_local: Vector2 = vp_local - Vector2(_viewport.size) * 0.5 + _camera.position
	var cell: Vector2i = _slot_layer.local_to_map(map_local)
	if _cell_to_slot.has(cell):
		_select_tilemap_cell(cell, true)
		if _cell_to_slot[cell] >= 0:   # real slot only
			_focus_panel()

# ════════════════════════════════════════════════════════════════════════════ #
#  Slot panel
# ════════════════════════════════════════════════════════════════════════════ #

func _rebuild_slot_panel() -> void:
	var hs: HiveState = HiveSystem.get_hive(_hive_id)
	if hs == null:
		_hide_panel()
		return

	var slot_index: int = _cell_to_slot.get(_selected_cell, -2)
	if slot_index == -2:
		_hide_panel()
		return



	_show_panel()

	# Locked slot
	if slot_index < 0:
		_slot_title.text          = "Locked"
		_contents_label.text      = "Upgrade hive to unlock"
		_designation_box.visible  = false
		_deposit_section.visible  = false
		_withdraw_section.visible = false
		for child in _contents_grid.get_children():
			child.queue_free()
		return

	var slot: HiveSlot = hs.slots[slot_index] if slot_index < hs.slots.size() else null
	if slot == null:
		return

	var def: SlotDesignationDef = SlotDesignationRegistry.get_def(slot.designation)
	_slot_title.text = "Slot %d — %s" % [slot_index, def.display_name]

	_rebuild_designation_section(slot)
	_rebuild_contents_section(slot)
	_rebuild_deposit_section(slot)
	_rebuild_withdraw_section(slot)

# ── Designation section ───────────────────────────────────────────────────────

func _rebuild_designation_section(slot: HiveSlot) -> void:
	for child in _designation_box.get_children():
		child.queue_free()

	if not _inside_pawn_is_queen():
		_designation_box.visible = false
		return

	_designation_box.visible = true
	for def: SlotDesignationDef in SlotDesignationRegistry.get_all():
		if def.is_locked:
			continue
		var btn := Button.new()
		btn.text           = def.display_name
		btn.toggle_mode    = true
		btn.focus_mode     = Control.FOCUS_ALL
		btn.button_pressed = (slot.designation == def.designation_id)
		btn.add_theme_color_override("font_color", def.color)
		btn.pressed.connect(_on_designation_pressed.bind(def.designation_id))
		_designation_box.add_child(btn)

# ── Contents section ──────────────────────────────────────────────────────────

func _rebuild_contents_section(slot: HiveSlot) -> void:
	for child in _contents_grid.get_children():
		child.queue_free()

	if slot.stored_items.is_empty() and slot.sleeper_id < 0:
		_contents_label.text = "Contents: Empty"
		return

	_contents_label.text = "Contents:"
	for item_id: StringName in slot.stored_items:
		var lbl  := Label.new()
		lbl.text  = "%s × %d" % [item_id, slot.stored_items[item_id]]
		_contents_grid.add_child(lbl)
	if slot.sleeper_id >= 0:
		var ps: PawnState = PawnRegistry.get_state(slot.sleeper_id)
		var lbl           := Label.new()
		lbl.text           = "💤 %s" % (ps.pawn_name if ps else "?")
		_contents_grid.add_child(lbl)

# ── Deposit section ───────────────────────────────────────────────────────────

func _rebuild_deposit_section(slot: HiveSlot) -> void:
	_deposit_section.visible          = false
	_storage_lock_section.visible     = false
	_crafting_recipe_section.visible  = false

	if not SlotDepositRules.deposit_enabled(slot):
		return

	var bee_state: PawnState = _get_inside_pawn_state()
	if bee_state == null or bee_state.inventory == null:
		return

	var valid_items: Array[StringName] = SlotDepositRules.filter_depositable(bee_state.inventory, slot)
	if not valid_items.is_empty():
		_deposit_section.visible = true
		_item_selector.clear()
		for item_id: StringName in valid_items:
			var count: int = bee_state.inventory.get_count(item_id)
			_item_selector.add_item("%s (%d)" % [item_id, count])
			_item_selector.set_item_metadata(_item_selector.item_count - 1, item_id)
		_quantity_input.min_value = 1
		_quantity_input.max_value = _get_deposit_max()
		_quantity_input.value     = 1

	if _inside_pawn_is_queen():
		if slot.designation == HiveSlot.SlotDesignation.STORAGE:
			_rebuild_storage_lock_section(slot)
		elif slot.designation == HiveSlot.SlotDesignation.CRAFTING:
			_rebuild_crafting_recipe_section(slot)

# ── Withdraw section ──────────────────────────────────────────────────────────

func _rebuild_withdraw_section(slot: HiveSlot) -> void:
	if slot.stored_items.is_empty():
		_withdraw_section.visible = false
		return
	_withdraw_section.visible = true
	_withdraw_item.clear()
	for item_id: StringName in slot.stored_items:
		var count: int = slot.stored_items[item_id]
		_withdraw_item.add_item("%s (%d)" % [item_id, count])
		_withdraw_item.set_item_metadata(_withdraw_item.item_count - 1, item_id)
	_withdraw_qty.min_value = 1
	_withdraw_qty.max_value = _get_withdraw_max(slot)
	_withdraw_qty.value     = 1

# ── Stub sections (Phase 5+) ──────────────────────────────────────────────────
func _rebuild_sleep_section(_slot: HiveSlot) -> void: pass
func _rebuild_craft_section(_slot: HiveSlot) -> void: pass
func _rebuild_feed_section(_slot: HiveSlot) -> void:  pass

func _rebuild_storage_lock_section(slot: HiveSlot) -> void:
	_storage_lock_section.visible = true
	_storage_lock_selector.clear()
	var known_items: Array[StringName] = [
		&"nectar", &"pollen", &"honey", &"beeswax", &"royal_wax",
		&"bee_jelly", &"bee_bread", &"water", &"plant_fiber", &"tree_resin",
	]
	for item_id: StringName in known_items:
		_storage_lock_selector.add_item(str(item_id))
		_storage_lock_selector.set_item_metadata(_storage_lock_selector.item_count - 1, item_id)
		if item_id == slot.locked_item_id:
			_storage_lock_selector.selected = _storage_lock_selector.item_count - 1
	var lock_label: Label = _storage_lock_section.get_node_or_null("StorageLockLabel")
	if lock_label:
		lock_label.text = "Lock to item: %s" % \
			(str(slot.locked_item_id) if slot.locked_item_id != &"" else "Any")

func _rebuild_crafting_recipe_section(slot: HiveSlot) -> void:
	_crafting_recipe_section.visible = true
	_recipe_selector.clear()
	var stub_recipes: Array[StringName] = [
		&"honey_basic", &"beeswax", &"royal_wax",
		&"bee_jelly", &"bee_bread", &"marker_base",
	]
	for recipe_id: StringName in stub_recipes:
		_recipe_selector.add_item(str(recipe_id))
		_recipe_selector.set_item_metadata(_recipe_selector.item_count - 1, recipe_id)
		if recipe_id == slot.locked_item_id:
			_recipe_selector.selected = _recipe_selector.item_count - 1
	var recipe_label: Label = _crafting_recipe_section.get_node_or_null("RecipeLabel")
	if recipe_label:
		recipe_label.text = "Recipe: %s" % \
			(str(slot.locked_item_id) if slot.locked_item_id != &"" else "None set")

# ════════════════════════════════════════════════════════════════════════════ #
#  Actions
# ════════════════════════════════════════════════════════════════════════════ #

func _on_designation_pressed(desig_id: int) -> void:
	var hs: HiveState   = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	var slot_index: int = _cell_to_slot.get(_selected_cell, -1)
	if slot_index < 0 or slot_index >= hs.slots.size():
		return
	hs.slots[slot_index].designation = desig_id
	var tile: SlotTile = _get_slot_tile(_selected_cell)
	if tile:
		tile.set_designation(desig_id, hs.slots[slot_index].subtype)
	_rebuild_slot_panel()
	_return_to_grid()


func _on_deposit_pressed() -> void:
	var hs: HiveState   = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	var slot_index: int = _cell_to_slot.get(_selected_cell, -1)
	if slot_index < 0 or slot_index >= hs.slots.size():
		return
	var bee_state: PawnState = _get_inside_pawn_state()
	if bee_state == null or bee_state.inventory == null:
		return
	if _item_selector.item_count == 0 or _item_selector.selected < 0:
		return

	var meta: Variant = _item_selector.get_item_metadata(_item_selector.selected)
	if meta == null:
		return
	var item_id: StringName = StringName(str(meta))
	var qty: int            = int(_quantity_input.value)
	if bee_state.inventory.get_count(item_id) < qty:
		return

	var slot: HiveSlot = hs.slots[slot_index]
	if not SlotDepositRules.can_deposit(item_id, slot):
		return

	if SlotDepositRules.should_auto_nursery(item_id, slot):
		slot.designation = HiveSlot.SlotDesignation.NURSERY
		var tile: SlotTile = _get_slot_tile(_selected_cell)
		if tile:
			tile.set_designation(slot.designation)

	if SlotDepositRules.should_lock_storage(item_id, slot):
		slot.locked_item_id = item_id

	slot.stored_items[item_id] = slot.stored_items.get(item_id, 0) + qty
	bee_state.inventory.remove_item(item_id, qty)
	EventBus.item_deposited.emit(_get_inside_pawn_id(), _hive_id, item_id, qty)

	var t: SlotTile = _get_slot_tile(_selected_cell)
	if t:
		t.set_contents(slot.stored_items, slot.sleeper_id)
	_rebuild_slot_panel()
	_refocus_panel()


func _on_withdraw_pressed() -> void:
	var hs: HiveState   = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	var slot_index: int = _cell_to_slot.get(_selected_cell, -1)
	if slot_index < 0 or slot_index >= hs.slots.size():
		return
	var bee_state: PawnState = _get_inside_pawn_state()
	if bee_state == null or bee_state.inventory == null:
		return
	if _withdraw_item.item_count == 0 or _withdraw_item.selected < 0:
		return

	var meta: Variant = _withdraw_item.get_item_metadata(_withdraw_item.selected)
	if meta == null:
		return
	var item_id: StringName = StringName(str(meta))
	var qty: int            = int(_withdraw_qty.value)

	var slot: HiveSlot = hs.slots[slot_index]
	var available: int = slot.stored_items.get(item_id, 0)
	if available < qty:
		return

	slot.stored_items[item_id] = available - qty
	if slot.stored_items[item_id] <= 0:
		slot.stored_items.erase(item_id)
	bee_state.inventory.add_item(item_id, qty)

	var t: SlotTile = _get_slot_tile(_selected_cell)
	if t:
		t.set_contents(slot.stored_items, slot.sleeper_id)
	_rebuild_slot_panel()
	_refocus_panel()

# ════════════════════════════════════════════════════════════════════════════ #
#  Storage lock / Recipe
# ════════════════════════════════════════════════════════════════════════════ #

func _on_storage_lock_pressed() -> void:
	var hs: HiveState   = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	var slot_index: int = _cell_to_slot.get(_selected_cell, -1)
	if slot_index < 0 or slot_index >= hs.slots.size():
		return
	if _storage_lock_selector.selected < 0:
		return
	var meta: Variant = _storage_lock_selector.get_item_metadata(_storage_lock_selector.selected)
	if meta == null:
		return
	hs.slots[slot_index].locked_item_id = StringName(str(meta))
	_rebuild_slot_panel()
	_refocus_panel()


func _on_storage_clear_pressed() -> void:
	var hs: HiveState   = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	var slot_index: int = _cell_to_slot.get(_selected_cell, -1)
	if slot_index < 0 or slot_index >= hs.slots.size():
		return
	hs.slots[slot_index].locked_item_id = &""
	_rebuild_slot_panel()
	_refocus_panel()

func _on_recipe_set_pressed() -> void:
	var hs: HiveState   = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	var slot_index: int = _cell_to_slot.get(_selected_cell, -1)
	if slot_index < 0 or slot_index >= hs.slots.size():
		return
	if _recipe_selector.selected < 0:
		return
	var meta: Variant = _recipe_selector.get_item_metadata(_recipe_selector.selected)
	if meta == null:
		return
	hs.slots[slot_index].locked_item_id = StringName(str(meta))
	_rebuild_slot_panel()
	_return_to_grid()


# ════════════════════════════════════════════════════════════════════════════ #
#  Hive name
# ════════════════════════════════════════════════════════════════════════════ #

func _on_name_submitted(new_name: String) -> void:
	var hs: HiveState = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	hs.hive_name = new_name
	var ctrl: HiveController = HiveSystem.get_controller(_hive_id)
	if ctrl:
		ctrl._refresh_name_label()

# ════════════════════════════════════════════════════════════════════════════ #
#  Helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _refresh_slot_tint(cell: Vector2i) -> void:
	var hs: HiveState = HiveSystem.get_hive(_hive_id)
	if hs == null:
		return
	var idx: int = _cell_to_slot.get(cell, -1)
	if idx < 0 or idx >= hs.slots.size():
		return
	var slot: HiveSlot = hs.slots[idx]
	var tile: SlotTile = _get_slot_tile(cell)
	if tile == null:
		return
	tile.set_designation(slot.designation, slot.subtype)
	tile.set_contents(slot.stored_items, slot.sleeper_id)

func _get_deposit_max() -> int:
	var bee_state: PawnState = _get_inside_pawn_state()
	if bee_state == null or bee_state.inventory == null:
		return 1
	if _item_selector.item_count == 0:
		return 1
	var meta: Variant = _item_selector.get_item_metadata(_item_selector.selected)
	if meta == null:
		return 1
	return bee_state.inventory.get_count(StringName(str(meta)))

func _get_withdraw_max(slot: HiveSlot) -> int:
	if _withdraw_item.item_count == 0:
		return 1
	var meta: Variant = _withdraw_item.get_item_metadata(_withdraw_item.selected)
	if meta == null:
		return 1
	return slot.stored_items.get(StringName(str(meta)), 1)

func get_inside_pawn() -> PawnBase:
	if _controller == null:
		return null
	return _controller.get_inside_pawn()

func _get_inside_pawn_state() -> PawnState:
	var pawn: PawnBase = get_inside_pawn()
	return pawn.state if pawn else null

func _get_inside_pawn_id() -> int:
	var state: PawnState = _get_inside_pawn_state()
	return state.pawn_id if state else -1

func _get_slot_tile(cell: Vector2i) -> SlotTile:
	return _tile_instances.get(cell, null)

func _inside_pawn_is_queen() -> bool:
	var state: PawnState = _get_inside_pawn_state()
	if state == null:
		return false
	return PawnRegistry.is_queen(state.pawn_id, state.colony_id)

func fill_centered_area(layer: TileMapLayer, center: Vector2i, radius: int, source_id: int, atlas_coords: Vector2i) -> void:
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			layer.set_cell(Vector2i(x, y), source_id, atlas_coords)

func _return_to_grid() -> void:
	_focus_area = FocusArea.GRID
	_hide_panel()
