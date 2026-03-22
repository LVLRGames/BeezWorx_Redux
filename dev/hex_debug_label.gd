extends Label

var _pawn


func _ready() -> void:
	EventBus.player_pawn_ready.connect( _on_player_pawn_ready, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if not _pawn:
		return
	var cell := HexConsts.WORLD_TO_AXIAL(_pawn.global_position.x, _pawn.global_position.z)
	var biome := HexWorldState.cfg.get_cell_biome(cell.x, cell.y) if HexWorldState.cfg else &""
	var state := HexWorldState.get_cell(cell)

	# Territory info
	var controlling := TerritorySystem.get_controlling_colony(cell)
	var my_influence := TerritorySystem.get_influence(cell, 0)
	var territory_str := "None"
	if controlling == 0:
		territory_str = "Player (%.0f%%)" % (my_influence * 100.0)
	elif controlling > 0:
		territory_str = "Colony %d" % controlling
	
	text = "Cell: %s\nBiome: %s\nOccupied: %s\nCategory: %d\nTerritory: %s\nPos: %.1f, %.1f, %.1f\nDay: %d  %s  %s" % [
		cell, biome,
		state.occupied,
		state.category,
		territory_str,
		_pawn.global_position.x,
		_pawn.global_position.y,
		_pawn.global_position.z
	]


func _on_player_pawn_ready(pawn: Node3D, player_slot: int):
	if pawn and player_slot == 1:
		_pawn = pawn
