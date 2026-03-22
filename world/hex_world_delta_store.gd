# hex_world_delta_store.gd
class_name HexWorldDeltaStore
extends RefCounted

var deltas: Dictionary = {}    # Vector2i -> HexCellDelta
var occupancy: Dictionary = {} # occupied_cell -> origin_cell

func clear() -> void:
	deltas.clear()
	occupancy.clear()

func get_delta(cell: Vector2i) -> HexCellDelta:
	return deltas.get(cell, null)

func set_delta(cell: Vector2i, delta: HexCellDelta) -> void:
	deltas[cell] = delta

func erase_delta(cell: Vector2i) -> void:
	deltas.erase(cell)

func has_delta(cell: Vector2i) -> bool:
	return deltas.has(cell)

func get_origin_for_cell(cell: Vector2i) -> Vector2i:
	return occupancy.get(cell, cell)

func set_occupancy(origin: Vector2i, footprint: Array[Vector2i]) -> void:
	for offset: Vector2i in footprint:
		occupancy[origin + offset] = origin

func clear_occupancy_in_chunk(chunk_coord: Vector2i, chunk_size: int) -> void:
	for dq in chunk_size:
		for dr in chunk_size:
			var cell := Vector2i(
				chunk_coord.x * chunk_size + dq,
				chunk_coord.y * chunk_size + dr
			)
			occupancy.erase(cell)

func save(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false

	var data: Dictionary = {}
	for cell: Vector2i in deltas:
		data["%d,%d" % [cell.x, cell.y]] = (deltas[cell] as HexCellDelta).to_dict()

	file.store_var(data)
	return true

func load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false

	var data: Variant = file.get_var()
	if typeof(data) != TYPE_DICTIONARY:
		return false

	var loaded: Dictionary = {}
	for k: String in data:
		var p: PackedStringArray = k.split(",")
		loaded[Vector2i(int(p[0]), int(p[1]))] = HexCellDelta.from_dict(data[k])

	deltas = loaded
	return true
