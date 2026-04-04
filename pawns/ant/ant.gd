# ant.gd
# res://pawns/ant/ant.gd
#
# Ant pawn — ground walker, surface-aligned movement.
# Attach to root of ant.tscn.
#
# SCENE REQUIREMENTS (ant.tscn):
#   Ant (this script, CharacterBody3D via GroundPawn)
#   ├── CollisionShape3D
#   ├── [Mesh or GFX node]
#   ├── GroundRay    (RayCast3D, down 20 units)
#   ├── ClimbRay     (RayCast3D, forward 1 unit)
#   ├── FloorRay     (RayCast3D, down 1 unit)
#   ├── AngleRay     (RayCast3D, forward-down 45°, 1.5 units)
#   ├── PawnAbilityExecutor (Node)
#   └── NameTag

class_name Ant
extends PawnWalker

# ── Tuning overrides ──────────────────────────────────────────────────────────
@export var sprint_multiplier: float = 1.8
@onready var gfx: GFXAnt = $GFX

func _ready() -> void:
	super()

func get_pawn_info() -> String:
	var text := "--- Ant ---"
	if state and state.inventory:
		for id in state.inventory.get_item_ids():
			text += "\n%s: %d" % [id, state.inventory.get_count(id)]
	return text
