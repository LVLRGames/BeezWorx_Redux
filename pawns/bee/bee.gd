# bee.gd
# res://pawns/bee/bee.gd
#
# Generic bee pawn. Inherits PawnFlyer. Role is entirely data-driven via
# RoleDef and AbilityDef resources — no subclasses per role.
#
# VISUAL DIFFERENTIATION (per spec):
#   Scale, color variation, and equipment accessory slots are configured
#   in the scene and/or driven by PawnState/SpeciesDef at spawn time.
#   The queen is this same scene with a larger scale, queen ability defs,
#   and a crown in the crown equipment slot.
#


class_name Bee
extends PawnFlyer

# ── Flight tuning overrides ───────────────────────────────────────────────────
@export var vertical_speed: float = 14.0
@export var max_roll:       float = 45.0

var linear_velocity:float = 0.0

# ════════════════════════════════════════════════════════════════════════════ #
#  Lifecycle
# ════════════════════════════════════════════════════════════════════════════ #

func _ready() -> void:
	# Map bee-specific tuning onto PawnFlyer knobs
	vertical_accel_scale = vertical_speed
	max_roll_deg         = max_roll
	super()



# ════════════════════════════════════════════════════════════════════════════ #
#  PawnBase required override
# ════════════════════════════════════════════════════════════════════════════ #

func get_pawn_info() -> String:
	var role_name: String = "Bee"
	if role_def and role_def.get("display_name"):
		role_name = role_def.display_name
 
	var text := "--- %s ---" % role_name
	if state and state.inventory:
		var pollen_count: int = state.inventory.get_count(&"pollen")
		var nectar_count: int = state.inventory.get_count(&"nectar")
		text += "\nPollen: %d" % pollen_count
		text += "\nNectar: %d" % nectar_count
	else:
		text += "\nNo inventory"
	return text
