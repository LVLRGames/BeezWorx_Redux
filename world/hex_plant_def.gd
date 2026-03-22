#@tool

# ──────────────────────────────────────────────────────────────────── #
#  HexPlantDef
#  Category: RESOURCE_PLANT
#  Rendering is fully shader-driven from genes — no mesh/material needed
#  on the def itself.  A special "wild_plant" def (id = "wild_plant") is
#  registered at runtime to represent procedural hybrid offspring; it has
#  no fixed genes — the delta's hybrid_genes field drives everything.
# ──────────────────────────────────────────────────────────────────── #
class_name HexPlantDef
extends HexGridObjectDef

func _init() -> void:
	category = Category.RESOURCE_PLANT

@export var genes: HexPlantGenes = null
@export var plant_data: HexPlantData = null

# ════════════════════════════════════════════════════════════════════ #
