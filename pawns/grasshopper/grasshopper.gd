# grasshopper.gd
# Grasshopper species — extends PawnHopper.
# Role: Landscaper. Damage handled via action_abilities = [eat_grass.tres].

class_name Grasshopper
extends PawnHopper

func _ready() -> void:
	super()

func get_pawn_info() -> String:
	return "--- Grasshopper ---\nRole: Landscaper"
