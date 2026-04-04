# compass_panel.gd
# res://ui/hud/compass_panel.gd
#
# Skyrim-style horizontal compass strip.
# Strip scrolls based on camera yaw. Markers (hives, queen, etc.)
# are positioned along the strip based on their world-space angle from the pawn.
#
# SCENE STRUCTURE:
#   CompassPanel (Control, this script)
#   ├── Strip (Control)          — clipped, contains scrolling content
#   │   ├── CardinalLabels       — N/S/E/W labels, repositioned each frame
#   │   └── MarkerContainer      — compass marker icons, repositioned each frame
#   └── CenterLine (Control)     — static center indicator

class_name CompassPanel
extends Control

const STRIP_WIDTH:   float = 600.0   # pixels visible
const DEGREES_SHOWN: float = 180.0   # how many degrees the strip covers
const PX_PER_DEGREE: float = STRIP_WIDTH / DEGREES_SHOWN
const MARKER_ICON_SIZE: Vector2 = Vector2(16.0, 16.0)

@onready var center_line:   TextureRect = $VBoxContainer/Strip/CenterLine
@onready var _strip:            Control = $VBoxContainer/Strip
@onready var _marker_container: Control = $VBoxContainer/Strip/MarkerContainer
@onready var _cardinal_labels:  Control = $VBoxContainer/Strip/CardinalLabels
@onready var _cell_coords: 		Label   = $VBoxContainer/CellCoordsLabel

var _colony_id: int   = 0
var _pawn_id:   int   = -1
var _markers:   Array[Dictionary] = []   # {angle_deg, label, color, priority}

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	_build_cardinal_labels()
	clip_contents = true

func _process(_delta: float) -> void:
	var rig: CameraRig = CameraRig.for_player(1)
	if rig == null:
		return
	var raw_yaw: float = rad_to_deg(rig.rotation.y)
	var yaw_deg: float = -raw_yaw
	_update_strip(yaw_deg)
	_update_cell_coords()

# ════════════════════════════════════════════════════════════════════════════ #
#  Public
# ════════════════════════════════════════════════════════════════════════════ #

func set_colony(colony_id: int) -> void:
	_colony_id = colony_id
	refresh_markers()

func set_pawn_id(pawn_id: int) -> void:
	_pawn_id = pawn_id
	refresh_markers()

func refresh_markers() -> void:
	_markers.clear()
	if _pawn_id < 0:
		return

	var state: PawnState = PawnRegistry.get_state(_pawn_id)
	if state == null:
		return

	var pawn_pos: Vector3 = _get_pawn_world_pos(state)

	# Colony hives
	for hs: HiveState in HiveSystem.get_hives_for_colony(_colony_id):
		if hs.is_destroyed:
			continue
		var w: Vector2   = HexConsts.AXIAL_TO_WORLD(hs.anchor_cell.x, hs.anchor_cell.y)
		var hive_pos     := Vector3(w.x, 0.0, w.y)
		var angle: float = _world_angle(pawn_pos, hive_pos)
		_markers.append({
			"angle":    angle,
			"label":    "🏠",
			"color":    Color(0.9, 0.75, 0.3),
			"priority": 1,
		})

	# Queen position (if not possessing queen)
	var queen_id: int = ColonyState.get_queen_id(_colony_id)
	if queen_id >= 0 and queen_id != _pawn_id:
		var queen_state: PawnState = PawnRegistry.get_state(queen_id)
		if queen_state:
			var qw: Vector2 = HexConsts.AXIAL_TO_WORLD(
				queen_state.last_known_cell.x,
				queen_state.last_known_cell.y
			)
			var angle: float = _world_angle(pawn_pos, Vector3(qw.x, 0.0, qw.y))
			_markers.append({
				"angle":    angle,
				"label":    "👑",
				"color":    Color(1.0, 0.9, 0.2),
				"priority": 0,
			})

	# TODO Phase 7: add job markers from JobSystem

# ════════════════════════════════════════════════════════════════════════════ #
#  Strip rendering
# ════════════════════════════════════════════════════════════════════════════ #

func _update_strip(yaw_deg: float) -> void:
	var center_x: float = STRIP_WIDTH * 0.5

	# Update cardinal labels
	for child in _cardinal_labels.get_children():
		var lbl: Label = child as Label
		if lbl == null:
			continue
		var world_angle: float = lbl.get_meta("world_angle", 0.0)
		var offset: float      = _angle_offset(world_angle, yaw_deg)
		lbl.position = Vector2(
			center_x + offset - lbl.size.x * 0.5,
			_cardinal_labels.size.y * 0.5 - lbl.size.y * 0.5
		)
		lbl.visible = abs(offset) < STRIP_WIDTH * 0.5 + 32.0


	# Update marker icons
	for child in _marker_container.get_children():
		child.queue_free()

	for marker: Dictionary in _markers:
		var offset: float = _angle_offset(marker["angle"], yaw_deg)
		if abs(offset) > STRIP_WIDTH * 0.5:
			continue
		var lbl := Label.new()
		lbl.text                  = marker["label"]
		lbl.add_theme_color_override("font_color", marker["color"])
		lbl.position = Vector2(
			center_x + offset - lbl.size.x * 0.5,
			_marker_container.size.y * 0.5 - lbl.size.y * 0.5
		)
		_marker_container.add_child(lbl)

func _angle_offset(world_angle_deg: float, camera_yaw_deg: float) -> float:
	var diff: float = fposmod(world_angle_deg - camera_yaw_deg + 180.0, 360.0) - 180.0
	return diff * PX_PER_DEGREE

func _build_cardinal_labels() -> void:
	var cardinals: Array[Dictionary] = [
		{"text": "N",  "angle": 0.0},
		{"text": "NE", "angle": 45.0},
		{"text": "E",  "angle": 90.0},
		{"text": "SE", "angle": 135.0},
		{"text": "S",  "angle": 180.0},
		{"text": "SW", "angle": 225.0},
		{"text": "W",  "angle": 270.0},
		{"text": "NW", "angle": 315.0},
		{"text": "N",  "angle": 360.0},
		{"text": "NW", "angle": -45.0},
		{"text": "W",  "angle": -90.0},
	]
	for c: Dictionary in cardinals:
		var lbl := Label.new()
		lbl.text = c["text"]
		var is_major: bool = c["text"].length() == 1
		lbl.add_theme_font_size_override("font_size", 14 if is_major else 10)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.set_meta("world_angle", c["angle"])
		_cardinal_labels.add_child(lbl)

	# Tick marks every 22.5° between cardinals
	for i: int in 16:
		var angle: float = i * 22.5
		if fmod(angle, 45.0) == 0.0:
			continue
		for offset: float in [0.0, -360.0]:
			var tick := Label.new()
			tick.text = "·"
			tick.add_theme_font_size_override("font_size", 10)
			tick.add_theme_color_override("font_color", Color.WHITE)
			tick.modulate.a              = 1.0
			tick.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
			tick.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
			tick.set_meta("world_angle", angle + offset)
			_cardinal_labels.add_child(tick)
# ════════════════════════════════════════════════════════════════════════════ #
#  Helpers
# ════════════════════════════════════════════════════════════════════════════ #

func _update_cell_coords() -> void:
	if _pawn_id < 0:
		return
	var pawn: PawnBase = PawnRegistry.get_pawn(_pawn_id)
	if pawn == null or not is_instance_valid(pawn):
		return
	var pos: Vector3   = pawn.global_position
	var cell: Vector2i = HexConsts.WORLD_TO_AXIAL(pos.x, pos.z)
	_cell_coords.text  = "<%d, %d, %d>" % [cell.x, int(round(pos.y)), cell.y]
	_cell_coords.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _get_pawn_world_pos(state: PawnState) -> Vector3:
	var pawn: PawnBase = PawnRegistry.get_pawn(_pawn_id)
	if pawn and is_instance_valid(pawn):
		return pawn.global_position
	var w: Vector2 = HexConsts.AXIAL_TO_WORLD(
		state.last_known_cell.x,
		state.last_known_cell.y
	)
	return Vector3(w.x, 0.0, w.y)

static func _world_angle(from: Vector3, to: Vector3) -> float:
	var diff: Vector3 = to - from
	return rad_to_deg(atan2(diff.x, -diff.z))
