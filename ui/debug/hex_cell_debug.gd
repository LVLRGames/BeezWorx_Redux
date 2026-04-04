class_name HexCellDebug
extends RichTextLabel

var _pawn


func _ready() -> void:
	EventBus.player_pawn_ready.connect( _on_player_pawn_ready, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if not _pawn:
		return
	var cell := HexConsts.WORLD_TO_AXIAL(_pawn.global_position.x, _pawn.global_position.z)
	var biome := HexWorldState.cfg.get_cell_biome(cell.x, cell.y) if HexWorldState.cfg else &""
	var state := HexWorldState.get_cell(cell)

	var time_of_day: String
	var phase: float = TimeService.day_phase
	var split: float = TimeService.config.get("day_night_split") if TimeService.config else 0.6
	if TimeService.is_daytime:
		var day_t: float = phase / split
		if day_t < 0.15:
			time_of_day = "Dawn"
		elif day_t > 0.85:
			time_of_day = "Dusk"
		else:
			time_of_day = "Day"
	else:
		time_of_day = "Night"

	# Territory info
	var controlling := TerritorySystem.get_controlling_colony(cell)
	var my_influence := TerritorySystem.get_influence(cell, 0)
	var territory_str := "None"
	if controlling == 0:
		territory_str = "Player (%.0f%%)" % (my_influence * 100.0)
	elif controlling > 0:
		territory_str = "Colony %d" % controlling
	var inv_str: String = ""
	if _pawn is PawnBase and (_pawn as PawnBase).state and (_pawn as PawnBase).state.inventory:
		var inv: PawnInventory = (_pawn as PawnBase).state.inventory
		for item_id in inv.get_item_ids():
			inv_str += "\n~%s: %d" % [item_id, inv.get_count(item_id)]
		if inv_str.is_empty():
			inv_str = "\n~[empty]"

	text = "Cell: %s\nBiome: %s\nOccupied: %s\nCategory: %d\nTerritory: %s\nDay: %d  %s  %s  %s\n%s\nPos: %.1f, %.1f, %.1f\nInv:%s" % [
		cell,
		biome,
		state.occupied,
		state.category,
		territory_str,
		TimeService.current_day,
		TimeService.get_current_season_name(),
		TimeService.get_time_of_day_name(),
		TimeService.get_time_string(),
		"Day" if TimeService.is_daytime else "Night",
		_pawn.global_position.x,
		_pawn.global_position.y,
		_pawn.global_position.z,
		inv_str
	]


func _on_player_pawn_ready(pawn: Node3D, player_slot: int):
	if pawn and player_slot == 1:
		_pawn = pawn
