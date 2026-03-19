# FILE: res://defs/items/item_def.gd
# Resource definition for all items, materials, and biological resources.
class_name ItemDef
extends Resource

@export var item_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var mesh: Mesh = null
@export var stack_size: int = 20
@export var carry_weight: float = 1.0
@export var is_liquid: bool = false
@export var tags: Array[StringName] = []

@export_group("Biological")
@export var nutrition_value: float = 0.0
@export var nursing_role_tag: StringName = &""
@export var perishable: bool = false
@export var spoil_time: float = 3600.0

@export_group("Chemistry")
@export var chem_sweetness: float = 0.0
@export var chem_heat: float = 0.0
@export var chem_cool: float = 0.0
@export var chem_vigor: float = 0.0
@export var chem_calm: float = 0.0
@export var chem_restore: float = 0.0
@export var chem_fortify: float = 0.0
@export var chem_toxicity: float = 0.0
@export var chem_aroma: float = 0.0
@export var chem_purity: float = 1.0

@export_group("Pollen")
@export var pollen_protein: float = 0.0
@export var pollen_lipid: float = 0.0
@export var pollen_mineral: float = 0.0
@export var pollen_medicine: float = 0.0
@export var pollen_irritant: float = 0.0
@export var pollen_fertility: float = 0.0

@export_group("Meta")
@export var quality_grade: int = 1
@export var diplomacy_value: float = 0.0
@export var preferred_by_factions: Array[StringName] = []
