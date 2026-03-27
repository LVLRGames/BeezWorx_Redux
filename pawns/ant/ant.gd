class_name Ant
extends PawnWalker

enum AntRole{ QUEEN, SOLDIER, SCOUT, CARRIER, WORKER }


@export var vertical_speed := 14.0
@export var max_roll: float = 45.0
@export var is_player_1: bool = false
@export var role:AntRole = AntRole.SCOUT

var linear_velocity:float = 0.0
var carried_item:Dictionary = {
	"display_name":"NONE"
}

func _ready() -> void:
	# Map your existing Bee knobs onto the generic flight pawn knobs.
	#vertical_accel_scale = vertical_speed
	#max_roll_deg = max_roll

	if is_player_1:
		controller = preload("res://pawns/player_controller.gd").new()
		controller.attach(self)
		controller.player_index = 1
		name_tag.info = "%s" % [name]
	else:
		super()


func _process(_delta: float) -> void:
	linear_velocity = velocity.length()
	

func interact() -> void:
	if not selector: return
	var cell := HexConsts.WORLD_TO_AXIAL(selector.global_position.x, selector.global_position.z)
	var state: HexCellState = HexWorldState.get_cell(cell)
	if not state.occupied: return
	if state.category != HexGridObjectDef.Category.RESOURCE_PLANT: return

	var stage: int = state.stage
	#match stage:
		#HexWorldState.Stage.FLOWERING:
			#if carried_pollen.is_empty():
				#_collect_pollen(cell, state)
			#else:
				#_pollinate(cell, state)
		#HexWorldState.Stage.FRUITING:
			#_collect_nectar(cell, state)


func alt_interact() -> void:
	print("alt_interact")
	if not selector: return
	var cell := HexConsts.WORLD_TO_AXIAL(selector.global_position.x, selector.global_position.z)
	var state: HexCellState = HexWorldState.get_cell(cell)
	if not state.occupied: return
	if state.category != HexGridObjectDef.Category.RESOURCE_PLANT: return

	if state.stage == HexWorldState.Stage.WILT:
		HexWorldState.water_plant(cell)
		print("Watered plant at %s" % cell)


func get_pawn_info() -> String:
	var text := "--- Ant ---"
	if carried_item.is_empty():
		text += "\nItem: None"
	else:
		text += "\nItem: %s" % carried_item.get("display_name", "???")
	text += "\nJob:" % [AntRole.find_key(role)]
	return text
