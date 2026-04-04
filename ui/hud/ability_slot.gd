# ability_slot.gd
# res://ui/hud/ability_slot.gd
#
# HexPickerSlot subclass for ability selection.
# Shows available abilities as hex cells — icon + name.
# Used by ActionPanel for action and alt-action slots.

class_name AbilitySlot
extends HexPickerSlot

signal ability_selected(ability: AbilityDef)

const ABILITY_CELL_SCENE := preload("res://ui/hud/ability_cell.tscn")

var _pawn_id:    int               = -1
var _abilities:  Array[AbilityDef] = []   # the ability pool for this slot

# ════════════════════════════════════════════════════════════════════════════ #
#  Public
# ════════════════════════════════════════════════════════════════════════════ #

# In ability_slot.gd
func setup_for_pawn(pawn_id: int, abilities: Array[AbilityDef]) -> void:
	_pawn_id   = pawn_id
	_abilities = abilities
	_last_usable_ids.clear()
	
	# Build all cells once
	for child in _grid.get_children():
		child.queue_free()
	_entries.clear()
	
	for ability: AbilityDef in abilities:
		if ability == null:
			continue
		_entries.append(ability)
		var cell: Control = _make_ability_cell(ability)
		cell.modulate.a   = 0.0
		cell.visible      = false   # start hidden
		_grid.add_child(cell)
	
	# Pad to min slots
	for i in range(_entries.size(), min_visible_slots):
		_entries.append(null)
		var cell: Control = _make_preview_cell(i)
		if cell:
			cell.modulate.a = 0.0
			cell.visible    = false
			_grid.add_child(cell)

## Called every context update — just show/hide, no rebuild
func update_usable(usable_abilities: Array[AbilityDef]) -> void:
	var usable_ids: Array[StringName] = []
	for a: AbilityDef in usable_abilities:
		if a:
			usable_ids.append(a.ability_id)
	
	# Skip if nothing changed
	if usable_ids == _last_usable_ids:
		return
	_last_usable_ids = usable_ids
	
	var children = _grid.get_children()
	var first_visible_idx: int = -1
	
	for i: int in children.size():
		var cell: Control = children[i] as Control
		if cell == null:
			continue
		var ability: AbilityDef = _entries[i] as AbilityDef
		var is_usable: bool = ability != null and usable_ids.has(ability.ability_id)
		cell.visible = is_usable or ability == null  # keep empty padding visible
		if is_usable and first_visible_idx < 0:
			first_visible_idx = i
	
	# Select first usable
	if first_visible_idx >= 0:
		var cr: Vector2i = _grid.index_to_col_row(first_visible_idx)
		_sel_col = cr.x
		_sel_row = cr.y
		_update_selection_visuals()
		_scroll_to_selected(false)
		_fade_cells(false)
		_refresh_info_label()
		_fade_info_label(true)
	else:
		_fade_info_label(false)

## Set the pool of abilities this slot can show, filtered to usable ones.
# In ability_slot.gd
# In ability_slot.gd — compare by ability_id strings
var _last_usable_ids: Array[StringName] = []

func set_abilities(abilities: Array[AbilityDef], pawn_id: int) -> void:
	_pawn_id   = pawn_id
	_abilities = abilities

	# Build id list from incoming usable abilities
	var new_ids: Array[StringName] = []
	for a: AbilityDef in abilities:
		if a != null:
			new_ids.append(a.ability_id)

	# Only rebuild if the set actually changed
	if new_ids == _last_usable_ids:
		return
	_last_usable_ids = new_ids

	refresh()
	# If we have abilities, show selected cell
	if not _entries.filter(func(e): return e != null).is_empty():
		_fade_cells(false)
		_refresh_info_label()
		_fade_info_label(true)
	else:
		# No usable abilities — fade everything
		_fade_cells(false)
		_fade_info_label(false)

## Returns the currently selected ability, or null.
func get_selected_ability() -> AbilityDef:
	var idx: int = get_selected_index()
	if idx < 0 or idx >= _entries.size():
		return null
	return _entries[idx] as AbilityDef

# ════════════════════════════════════════════════════════════════════════════ #
#  HexPickerSlot overrides
# ════════════════════════════════════════════════════════════════════════════ #

func _build_cells() -> void:
	super()

	var pawn: PawnBase = PawnRegistry.get_pawn(_pawn_id)
	var executor: PawnAbilityExecutor = pawn.get_node_or_null("PawnAbilityExecutor") \
		as PawnAbilityExecutor if pawn else null

	for ability: AbilityDef in _abilities:
		if ability == null:
			continue
		# Only show usable abilities
		var ctx: AbilityContext = AbilityContext.new()
		ctx.pawn      = pawn
		ctx.pawn_cell = pawn.state.last_known_cell if pawn.state else Vector2i.ZERO
		# then:
		if not ability.can_use(ctx):
			continue
		_entries.append(ability)
		var cell: Control = _make_ability_cell(ability)
		cell.modulate.a = 0.0
		_grid.add_child(cell)
		if cell.has_method("set_ability"):
			cell.set_ability(ability)

	# Pad to min slots
	var current: int = _entries.size()
	for i in range(current, min_visible_slots):
		_entries.append(null)
		var cell: Control = _make_preview_cell(i)
		if cell:
			_grid.add_child(cell)
			cell.modulate.a = 0.0
		if cell.has_method("set_empty"):
			cell.set_empty()
	
	if not Engine.is_editor_hint():
		_refresh_info_label()
		var has_ability: bool = not _entries.filter(
			func(e): return e != null
		).is_empty()
		_fade_info_label(has_ability)


func _get_entry_display_name(idx: int) -> String:
	if idx < 0 or idx >= _entries.size():
		return ""
	var ability: AbilityDef = _entries[idx] as AbilityDef
	if ability == null:
		return ""
	return ability.display_name

func _on_confirmed(idx: int) -> void:
	var ability: AbilityDef = _entries[idx] as AbilityDef
	if ability:
		emit_signal("ability_selected", ability)

func _make_preview_cell(_index: int) -> Control:
	# Fallback: use InventoryCell as placeholder until AbilityCell scene exists
	if ResourceLoader.exists("res://ui/hud/ability_cell.tscn"):
		var cell: Control = load("res://ui/hud/ability_cell.tscn").instantiate()
		return cell
	# Graceful fallback
	var lbl := Label.new()
	lbl.text = ""
	lbl.custom_minimum_size = Vector2(64, 64)
	return lbl

func _make_ability_cell(ability: AbilityDef) -> Control:
	if ResourceLoader.exists("res://ui/hud/ability_cell.tscn"):
		var cell: Control = load("res://ui/hud/ability_cell.tscn").instantiate()
		return cell
	# Graceful fallback label
	var lbl := Label.new()
	lbl.text = ability.display_name
	lbl.custom_minimum_size = Vector2(64, 64)
	return lbl
