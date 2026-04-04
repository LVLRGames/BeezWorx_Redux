# interaction_detector.gd
# res://pawns/interaction_detector.gd
#
# Attach as a child of PawnBase.
# Sphere Area3D detects nearby interactables for context panel.
# Raycast finds the most relevant target directly ahead for action labels.
# Emits EventBus.interaction_target_changed when the primary target changes.
#
# SCENE STRUCTURE (build in editor or add via code in PawnBase._ready()):
#   InteractionDetector (Node, this script)
#   ├── SphereArea (Area3D)
#   │   └── CollisionShape3D (SphereShape3D, radius = SPHERE_RADIUS)
#   └── (RayCast3D added in code)

class_name InteractionDetector
extends Node3D

const SPHERE_RADIUS:   float = 4.0   # world units — ~2 hex cells
const RAYCAST_LENGTH:  float = 3.0
const UPDATE_INTERVAL: float = 0.1   # 10Hz position-based update

@export var sphere_area_path: NodePath = ^"SphereArea"
@onready var _sphere: Area3D = get_node_or_null(sphere_area_path)

var _pawn: PawnBase = null
var _raycast: RayCast3D = null
var _current_target: Dictionary = {}
var _nearby_bodies: Array[Node3D] = []
var _update_timer: float = 0.0

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	_pawn = get_parent() as PawnBase
	if _pawn == null:
		push_error("InteractionDetector: parent is not PawnBase")
		return

	# Build raycast in code
	_raycast = RayCast3D.new()
	_raycast.target_position = Vector3(0.0, 0.0, -RAYCAST_LENGTH)
	_raycast.collision_mask  = 0b11   # adjust to match your physics layers
	_raycast.enabled         = true
	add_child(_raycast)

	if _sphere:
		_sphere.body_entered.connect(_on_body_entered)
		_sphere.body_exited.connect(_on_body_exited)
		_sphere.area_entered.connect(_on_area_entered)
		_sphere.area_exited.connect(_on_area_exited)

func _process(delta: float) -> void:
	if _pawn == null:
		return
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = UPDATE_INTERVAL
	_evaluate_target()

# ════════════════════════════════════════════════════════════════════════════ #
#  Target evaluation
# ════════════════════════════════════════════════════════════════════════════ #

func _evaluate_target() -> void:
	var best: Dictionary = _raycast_target()
	if best.is_empty():
		best = _nearest_sphere_target()
	if best.is_empty():
		best = _current_cell_target()   # check plant at pawn's own cell

	if _targets_equal(best, _current_target):
		return
	_current_target = best
	EventBus.interaction_target_changed.emit(_pawn.pawn_id, _current_target)


func _current_cell_target() -> Dictionary:
	var cell: Vector2i = HexConsts.WORLD_TO_AXIAL(
		_pawn.global_position.x,
		_pawn.global_position.z
	)
	var cell_state: HexCellState = HexWorldState.get_cell(cell)
	if cell_state == null or not cell_state.occupied:
		return {}
	if cell_state.category != HexGridObjectDef.Category.RESOURCE_PLANT:
		return {}
	return {
		"type":         &"plant",
		"cell":         cell,
		"display_name": cell_state.object_id,
		"stage":        cell_state.stage,
		"nectar":       cell_state.nectar_amount,
		"pollen":       cell_state.pollen_amount,
	}


func _raycast_target() -> Dictionary:
	if _raycast == null or not _raycast.is_colliding():
		return {}
	var collider: Object = _raycast.get_collider()
	return _classify_node(collider as Node3D)

func _nearest_sphere_target() -> Dictionary:
	if _nearby_bodies.is_empty():
		return {}
	var pawn_pos: Vector3 = _pawn.global_position
	var best_node: Node3D = null
	var best_dist: float  = INF

	for body: Node3D in _nearby_bodies:
		if not is_instance_valid(body):
			continue
		var d: float = pawn_pos.distance_squared_to(body.global_position)
		if d < best_dist:
			best_dist = d
			best_node = body

	if best_node == null:
		return {}
	return _classify_node(best_node)

func _classify_node(node: Node3D) -> Dictionary:
	if node == null:
		return {}

	# Hive controller
	var hc: HiveController = node as HiveController
	if hc == null:
		hc = node.get_parent() as HiveController
	if hc != null:
		var hs: HiveState = HiveSystem.get_hive(hc.hive_id)
		return {
			"type":         &"hive",
			"hive_id":      hc.hive_id,
			"cell":         hs.anchor_cell if hs else Vector2i.ZERO,
			"display_name": hs.hive_name if hs and not hs.hive_name.is_empty() \
				else "Hive %d" % hc.hive_id,
		}

	# Pawn
	var pb: PawnBase = node as PawnBase
	if pb != null and pb != _pawn:
		var state: PawnState = pb.state
		return {
			"type":         &"pawn",
			"pawn_id":      pb.pawn_id,
			"species":      pb.species_def.display_name,
			"cell":         state.last_known_cell if state else Vector2i.ZERO,
			"display_name": state.pawn_name if state else "?",
		}

	# Plant cell — check hex world at node position
	var cell: Vector2i = HexConsts.WORLD_TO_AXIAL(
		node.global_position.x,
		node.global_position.z
	)
	var cell_state: HexCellState = HexWorldState.get_cell(cell)
	if cell_state != null and cell_state.occupied:
		return {
			"type":         &"plant",
			"cell":         cell,
			"display_name": cell_state.object_id,
			"stage":        cell_state.stage,
			"nectar":       cell_state.nectar_amount,
			"pollen":       cell_state.pollen_amount,
		}

	return {}

func _targets_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.get("type") != b.get("type"):
		return false
	match a.get("type"):
		&"hive":  return a.get("hive_id") == b.get("hive_id")
		&"pawn":  return a.get("pawn_id") == b.get("pawn_id")
		&"plant": return a.get("cell")    == b.get("cell")
	return true

# ── Public ────────────────────────────────────────────────────────────────────

func get_current_target() -> Dictionary:
	return _current_target

func has_target() -> bool:
	return not _current_target.is_empty()

# ════════════════════════════════════════════════════════════════════════════ #
#  Sphere callbacks
# ════════════════════════════════════════════════════════════════════════════ #

func _on_body_entered(body: Node3D) -> void:
	if body != _pawn and not _nearby_bodies.has(body):
		_nearby_bodies.append(body)
		_update_timer = 0.0   # evaluate immediately

func _on_body_exited(body: Node3D) -> void:
	_nearby_bodies.erase(body)
	print("body_exited: ", body.name, " current_target=", _current_target.get("type"))
	var exited_info: Dictionary = _classify_node(body)
	print("exited_info=", exited_info)
	if not exited_info.is_empty() and _targets_equal(exited_info, _current_target):
		_current_target = {}
		EventBus.interaction_target_changed.emit(_pawn.pawn_id, {})
	_update_timer = 0.0

func _on_area_entered(area: Area3D) -> void:
	var parent: Node3D = area.get_parent() as Node3D
	if parent and not _nearby_bodies.has(parent):
		_nearby_bodies.append(parent)
		_update_timer = 0.0

func _on_area_exited(area: Area3D) -> void:
	var parent: Node3D = area.get_parent() as Node3D
	if parent:
		_nearby_bodies.erase(parent)
		var exited_info: Dictionary = _classify_node(parent)
		if not exited_info.is_empty() and _targets_equal(exited_info, _current_target):
			_current_target = {}
			EventBus.interaction_target_changed.emit(_pawn.pawn_id, {})
	_update_timer = 0.00
