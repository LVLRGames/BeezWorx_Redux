# pawn_registry.gd
# res://autoloads/pawn_registry.gd
#
# Autoload. Lightweight index of all pawns in the simulation.
# Does NOT store pawn nodes directly — uses WeakRef so GC can free nodes.
# Does store PawnState directly — second reference keeps state alive across
# chunk unloads even when the node is freed.
#
# REGISTRATION FLOW:
#   1. PawnBase._ready() calls PawnRegistry.register(self)
#   2. PawnRegistry assigns pawn_id, creates PawnState, stores both
#   3. PawnBase stores the returned pawn_id and PawnState ref
#   4. On death: PawnBase calls PawnRegistry.deregister(pawn_id)
#   5. On chunk unload: node is freed but PawnState stays in registry
#
# POSSESSION:
#   PossessionManager reads PawnRegistry to find eligible pawns.
#   _by_colony index makes get_pawns_for_colony() O(1).
#
# NOTE: class_name intentionally omitted — accessed via autoload name PawnRegistry.

extends Node

# ── State ─────────────────────────────────────────────────────────────────────
var _states:    Dictionary[int, PawnState]       = {}   # pawn_id → PawnState
var _nodes:     Dictionary[int, WeakRef]         = {}   # pawn_id → WeakRef<PawnBase>
var _by_colony: Dictionary[int, Array]           = {}   # colony_id → [pawn_ids]
var _by_cell:   Dictionary[Vector2i, Array]      = {}   # cell → [pawn_ids]
var _next_id:   int = 0

# ════════════════════════════════════════════════════════════════════════════ #
#  Registration
# ════════════════════════════════════════════════════════════════════════════ #
func _ready() -> void:
	_states.clear()


## Register a pawn node. Returns the assigned pawn_id.
## Creates a PawnState populated from the pawn's exports.
## Call from PawnBase._ready().
func register(pawn: PawnBase) -> int:
	var id: int = _next_id
	_next_id += 1

	# Build PawnState from pawn's current data
	var state := PawnState.new()
	state.pawn_id   = id
	state.colony_id = 0   # default to player colony; caller can override
	state.scene_path = pawn.scene_file_path
	
	# Read species/role from exports if available
	if pawn.species_def and pawn.species_def.get("species_id"):
		state.species_id = pawn.species_def.get("species_id")
	if pawn.role_def and pawn.role_def.get("role_id"):
		state.role_id = pawn.role_def.get("role_id")

	# Movement type from class
	state.movement_type = 1 if pawn is PawnFlyer else 0

	# Create inventory from SpeciesDef capacity
	var inv_capacity: int = 1   # default
	if pawn.species_def != null:
		var cap = pawn.species_def.get("inventory_capacity")
		if cap != null:
			inv_capacity = cap
	state.inventory = PawnInventory.new()
	state.inventory.setup(id, inv_capacity)
	
	# Generate a name if none set
	if state.pawn_name.is_empty():
		state.pawn_name = _generate_name(id)

	# Store
	_states[id] = state
	_nodes[id]  = weakref(pawn)
	_add_to_colony(id, state.colony_id)

	# Update cell index
	var cell: Vector2i = HexConsts.WORLD_TO_AXIAL(
		pawn.global_position.x,
		pawn.global_position.z
	)
	state.last_known_cell = cell
	_add_to_cell(id, cell)

	# Wire pawn back
	pawn.pawn_id = id
	pawn.state   = state

	# Add to "pawns" group for possession system
	if not pawn.is_in_group("pawns"):
		pawn.add_to_group("pawns")

	EventBus.pawn_spawned.emit(id, state.colony_id, cell)
	print("PawnRegistry.register: id=", id, " pawn=", pawn.name)
	EventBus.pawn_registered.emit(id, state.colony_id)
	return id


## Deregister a pawn. Call from PawnBase when pawn dies or is permanently removed.
## State is erased — use unload_node() instead for temporary chunk unloads.
func deregister(pawn_id: int) -> void:
	var state: PawnState = _states.get(pawn_id)
	if state == null:
		return

	_remove_from_colony(pawn_id, state.colony_id)
	_remove_from_cell(pawn_id, state.last_known_cell)
	_states.erase(pawn_id)
	_nodes.erase(pawn_id)

## Called when a chunk unloads under a pawn — node freed but state preserved.
func unload_pawn(pawn_id: int) -> void:
	_nodes.erase(pawn_id)

## Called when a chunk reloads and a pawn node is respawned for an existing state.
func reload_pawn(pawn_id: int, pawn: PawnBase) -> void:
	if not _states.has(pawn_id):
		push_error("PawnRegistry.reload_node: unknown pawn_id %d" % pawn_id)
		return
	_nodes[pawn_id] = weakref(pawn)
	pawn.pawn_id    = pawn_id
	pawn.state      = _states[pawn_id]
	if not pawn.is_in_group("pawns"):
		pawn.add_to_group("pawns")

# ════════════════════════════════════════════════════════════════════════════ #
#  Queries
# ════════════════════════════════════════════════════════════════════════════ #

func set_pawn(pawn_id: int, node: PawnBase) -> void:
	if not _states.has(pawn_id):
		push_error("PawnRegistry.set_node: pawn_id %d not in registry" % pawn_id)
		return
	_nodes[pawn_id] = weakref(node)
	# Update cell index
	var state: PawnState = _states[pawn_id]
	_add_to_cell(pawn_id, state.last_known_cell)

func get_state(pawn_id: int) -> PawnState:
	return _states.get(pawn_id, null)

func get_pawn(pawn_id: int) -> PawnBase:
	var wr: WeakRef = _nodes.get(pawn_id)
	if wr == null:
		return null
	return wr.get_ref() as PawnBase

func get_all_pawn_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _states:
		out.append(id)
	return out

func get_pawns_for_colony(colony_id: int) -> Array[int]:
	var ids: Array = _by_colony.get(colony_id, [])
	var out: Array[int] = []
	for id in ids:
		out.append(id)
	return out

func get_pawns_near_cell(cell: Vector2i) -> Array[int]:
	var ids: Array = _by_cell.get(cell, [])
	var out: Array[int] = []
	for id in ids:
		out.append(id)
	return out

func get_living_pawns_for_colony(colony_id: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in get_pawns_for_colony(colony_id):
		var state: PawnState = _states.get(id)
		if state and state.is_alive:
			out.append(id)
	return out

func get_player_colony_pawns() -> Array[int]:
	return get_pawns_for_colony(0)

## Update a pawn's cell position in the spatial index.
## Call from PawnBase._physics_process when the pawn moves to a new cell.
func update_cell(pawn_id: int, new_cell: Vector2i) -> void:
	var state: PawnState = _states.get(pawn_id)
	if state == null:
		return
	if state.last_known_cell == new_cell:
		return
	_remove_from_cell(pawn_id, state.last_known_cell)
	_add_to_cell(pawn_id, new_cell)
	state.last_known_cell = new_cell

## Returns true if the pawn_id is the queen of the given colony.
func is_queen(pawn_id: int, colony_id: int) -> bool:
	var col := ColonyState.get_colony(colony_id)
	if col == null:
		return false
	return col.get("queen_pawn_id") == pawn_id

# ════════════════════════════════════════════════════════════════════════════ #
#  Save / Load
# ════════════════════════════════════════════════════════════════════════════ #

func save_state() -> Dictionary:
	var pawns: Array = []
	for pawn_id: int in _states:
		pawns.append(_states[pawn_id].to_dict())
	return {
		"pawns":          pawns,
		"next_id":        _next_id,
		"schema_version": 1,
	}

func load_state(data: Dictionary) -> void:
	_states.clear()
	_nodes.clear()
	_by_colony.clear()
	_by_cell.clear()
	_next_id = data.get("next_id", 0)

	for d: Dictionary in data.get("pawns", []):
		var state: PawnState = PawnState.from_dict(d)
		_states[state.pawn_id] = state
		_add_to_colony(state.pawn_id, state.colony_id)
		_add_to_cell(state.pawn_id, state.last_known_cell)

# ════════════════════════════════════════════════════════════════════════════ #
#  Private helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _add_to_colony(pawn_id: int, colony_id: int) -> void:
	if not _by_colony.has(colony_id):
		_by_colony[colony_id] = []
	if not _by_colony[colony_id].has(pawn_id):
		_by_colony[colony_id].append(pawn_id)

func _remove_from_colony(pawn_id: int, colony_id: int) -> void:
	var arr: Array = _by_colony.get(colony_id, [])
	arr.erase(pawn_id)

func _add_to_cell(pawn_id: int, cell: Vector2i) -> void:
	if not _by_cell.has(cell):
		_by_cell[cell] = []
	if not _by_cell[cell].has(pawn_id):
		_by_cell[cell].append(pawn_id)

func _remove_from_cell(pawn_id: int, cell: Vector2i) -> void:
	var arr: Array = _by_cell.get(cell, [])
	arr.erase(pawn_id)

func _generate_name(id: int) -> String:
	# Simple deterministic name from pawn_id
	# TODO Phase 3: use NamePoolDef resource per species
	var syllables: Array[String] = [
		"Bri", "Zae", "Vel", "Kor", "Wyn", "Tae", "Ren", "Sol",
		"Mir", "Cal", "Dex", "Fae", "Gal", "Hex", "Ira", "Jun"
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 6271 + 1337
	var a: String = syllables[rng.randi() % syllables.size()]
	var b: String = syllables[rng.randi() % syllables.size()].to_lower()
	return a + b
