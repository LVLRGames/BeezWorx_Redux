class_name Grasshopper
extends PawnHopper


@export var sprint_multiplier: float = 1.8
@onready var gfx: GFXGrasshopper = $GFX

func _ready() -> void:
	super()

func get_pawn_info() -> String:
	var text := "--- Grasshopper ---"
	if state and state.inventory:
		for id in state.inventory.get_item_ids():
			text += "\n%s: %d" % [id, state.inventory.get_count(id)]
	return text
