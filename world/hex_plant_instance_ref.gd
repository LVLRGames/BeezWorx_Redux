class_name HexPlantInstanceRef
extends RefCounted

var multimesh: MultiMesh
var index: int

func _init(p_multimesh: MultiMesh = null, p_index: int = -1) -> void:
	multimesh = p_multimesh
	index = p_index
