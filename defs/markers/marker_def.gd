# FILE: res://defs/markers/marker_def.gd
# Definition for pheromone markers and the jobs they generate.
class_name MarkerDef
extends Resource

class JobTemplateDef:
	@export var job_type_id: StringName = &""
	@export var required_role_tags: Array[StringName] = []
	@export var required_items: Array = []
	@export var priority: int = 0
	@export var max_claimants: int = 1
	@export var expires_after: float = 0.0
	@export var consumption_rate: float = 0.0
	@export var progress_on_completion: float = 100.0

@export var marker_type_id: StringName = &""
@export_enum("Job:0", "Nav:1", "Info:2") var marker_category: int = 0
@export var display_name: String = ""
@export var icon: Texture2D = null
@export var color: Color = Color.WHITE
@export var crafted_from_item_id: StringName = &""
@export var requires_xz_alignment: bool = false
@export var valid_cell_categories: Array[int] = []
@export var max_per_cell: int = 1
@export var can_place_outside_territory: bool = false
@export var is_trail_node: bool = false
@export var trail_species_tags: Array[StringName] = []
@export var trail_item_filter: Array[StringName] = []
@export var generates_jobs: Array[JobTemplateDef] = []
@export var repost_on_complete: bool = false
@export var repost_condition: StringName = &""
@export var is_persistent: bool = false
@export var decay_outside_territory: float = 1.0
@export var manual_remove_only: bool = false
@export var return_item_on_remove: bool = false
@export var return_item_cost: int = 1
