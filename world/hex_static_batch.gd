class_name HexStaticBatch
extends RefCounted

var def: HexGridObjectDef
var mesh: Mesh
var material: Material
var tree_variant: HexTreeVariant = null
var xforms: Array[Transform3D] = []
var customs: Array[Color] = []

func _init(
	p_def: HexGridObjectDef = null,
	p_mesh: Mesh = null,
	p_material: Material = null,
	p_tree_variant: HexTreeVariant = null
) -> void:
	def = p_def
	mesh = p_mesh
	material = p_material
	tree_variant = p_tree_variant
