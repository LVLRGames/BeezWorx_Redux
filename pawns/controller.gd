extends Resource
class_name Controller

var pawn: PawnBase

func attach(p: PawnBase) -> void:
	pawn = p

func detach() -> void:
	pawn = null

func physics_tick(_delta: float) -> void:
	# override
	pass
