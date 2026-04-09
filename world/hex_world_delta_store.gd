# hex_world_delta_store.gd
# Stores player-driven cell overrides as HexCellDelta records.
#
# KEY CHANGE (plant system overhaul):
#   All keys are now Vector3i(q, r, slot) where slot = 0-5.
#   Single-slot plants  → stored at their specific slot.
#   Multi-slot objects  → stored at slot 0; slots 1..N-1 registered in occupancy.
#   Multi-cell objects  → all slots of satellite cells registered in occupancy.
#
# OCCUPANCY dict maps satellite Vector3i → anchor Vector3i.
# If a key is absent, the slot is its own anchor (no redirect needed).

class_name HexWorldDeltaStore
extends RefCounted

var deltas:    Dictionary = {}   # Vector3i → HexCellDelta
var occupancy: Dictionary = {}   # Vector3i → Vector3i  (satellite → anchor)

func clear() -> void:
	deltas.clear()
	occupancy.clear()

# ── Delta access ──────────────────────────────────────────────────────

func get_delta(slot_key: Vector3i) -> HexCellDelta:
	return deltas.get(slot_key, null)

func set_delta(slot_key: Vector3i, delta: HexCellDelta) -> void:
	deltas[slot_key] = delta

func erase_delta(slot_key: Vector3i) -> void:
	deltas.erase(slot_key)

func has_delta(slot_key: Vector3i) -> bool:
	return deltas.has(slot_key)

# ── Anchor resolution ─────────────────────────────────────────────────

## Returns the anchor slot key for the given slot.
## If the slot is not registered in occupancy, it IS its own anchor.
func get_anchor_for_slot(slot_key: Vector3i) -> Vector3i:
	return occupancy.get(slot_key, slot_key)

# ── Occupancy registration ─────────────────────────────────────────────
## Call after placing any object with slots_occupied > 1 or footprint.size() > 1.
##
## anchor_slot  : the Vector3i key where the delta is stored (always slot 0)
## footprint    : Array[Vector2i] of axial offsets from origin cell (includes (0,0))
## slots_occupied : how many contiguous slots (0..N-1) the object occupies in each cell

func set_occupancy(
	anchor_slot: Vector3i,
	footprint: Array[Vector2i],
	slots_occupied: int
) -> void:
	var origin_cell := Vector2i(anchor_slot.x, anchor_slot.y)

	# Same-cell satellite slots (multi-slot objects like trees).
	for s: int in range(1, slots_occupied):
		occupancy[Vector3i(origin_cell.x, origin_cell.y, s)] = anchor_slot

	# Multi-cell footprint satellite cells — all 6 slots of each satellite cell.
	for offset: Vector2i in footprint:
		if offset == Vector2i.ZERO:
			continue
		var sat_cell: Vector2i = origin_cell + offset
		for s: int in range(6):
			occupancy[Vector3i(sat_cell.x, sat_cell.y, s)] = anchor_slot


func clear_occupancy_in_chunk(chunk_coord: Vector2i, chunk_size: int) -> void:
	var to_erase: Array[Vector3i] = []
	for slot_key: Vector3i in occupancy:
		var cell := Vector2i(slot_key.x, slot_key.y)
		var local: Vector2i = cell - chunk_coord * chunk_size
		if local.x >= 0 and local.x < chunk_size \
				and local.y >= 0 and local.y < chunk_size:
			to_erase.append(slot_key)
	for key: Vector3i in to_erase:
		occupancy.erase(key)

# ── Serialization ─────────────────────────────────────────────────────

func save(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false

	var data: Dictionary = {}
	for slot_key: Vector3i in deltas:
		var k: String = "%d,%d,%d" % [slot_key.x, slot_key.y, slot_key.z]
		data[k] = (deltas[slot_key] as HexCellDelta).to_dict()

	file.store_var(data)
	return true


func load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false

	var raw: Variant = file.get_var()
	if typeof(raw) != TYPE_DICTIONARY:
		return false

	var loaded: Dictionary = {}
	for k: String in raw:
		var p: PackedStringArray = k.split(",")
		if p.size() == 3:
			# New Vector3i format.
			loaded[Vector3i(int(p[0]), int(p[1]), int(p[2]))] = HexCellDelta.from_dict(raw[k])
		elif p.size() == 2:
			# Legacy Vector2i save — migrate to slot 0.
			loaded[Vector3i(int(p[0]), int(p[1]), 0)] = HexCellDelta.from_dict(raw[k])

	deltas = loaded
	return true
