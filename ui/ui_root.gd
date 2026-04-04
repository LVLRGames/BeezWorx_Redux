class_name UIRoot
extends CanvasLayer

@onready var _pawn_card:   PawnCardPanel = $PawnCard
@onready var _compass:     CompassPanel  = $CompassPanel
@onready var _time_panel:  TimePanel     = $TimePanel
@onready var _context_hud: ContextHUD    = $ContextHUD

var _possessed_pawn_id: int = -1

func _ready() -> void:
	EventBus.pawn_possessed.connect(_on_pawn_possessed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.season_changed.connect(_on_season_changed)
	EventBus.day_started.connect(_on_day_started)
	EventBus.night_started.connect(_on_night_started)
	EventBus.hive_built.connect(_on_hive_built)
	EventBus.hive_destroyed.connect(_on_hive_destroyed)
	EventBus.marker_placed.connect(_on_marker_placed)
	EventBus.marker_removed.connect(_on_marker_removed)
	# pawn_inventory_changed and interaction_target_changed
	# are now handled internally by ContextHUD — no longer needed here

func _on_pawn_possessed(player_slot: int, pawn_id: int) -> void:
	if player_slot != 1:
		return
	_possessed_pawn_id = pawn_id
	var state: PawnState = PawnRegistry.get_state(pawn_id)
	_pawn_card.set_pawn(pawn_id, state)
	_compass.set_pawn_id(pawn_id)
	_compass.set_colony(state.colony_id if state else 0)
	# ContextHUD handles its own pawn_possessed listener internally

func _on_day_changed(_new_day: int) -> void:
	_time_panel.refresh()
	_compass.refresh_markers()

func _on_season_changed(_new_season: int) -> void:
	_time_panel.refresh()

func _on_day_started() -> void:
	_time_panel.refresh()

func _on_night_started() -> void:
	_time_panel.refresh()

func _on_hive_built(_hive_id: int, _anchor_cell: Vector2i, _colony_id: int) -> void:
	_compass.refresh_markers()

func _on_hive_destroyed(_hive_id: int, _anchor_cell: Vector2i, _colony_id: int) -> void:
	_compass.refresh_markers()

func _on_marker_placed(_marker_id: int, _type: StringName, _cell: Vector2i, _colony_id: int) -> void:
	_compass.refresh_markers()

func _on_marker_removed(_marker_id: int, _cell: Vector2i, _reason: StringName) -> void:
	_compass.refresh_markers()

func is_hive_overlay_open() -> bool:
	var overlay: Node = get_tree().get_first_node_in_group("hive_overlay")
	return overlay != null and overlay.visible
