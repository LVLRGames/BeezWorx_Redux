# FILE: res://defs/markers/JobTemplateDef.gd
class_name JobTemplateDef
extends Resource

@export var job_type_id: StringName = &""
@export var required_role_tags: Array[StringName] = []
@export var required_items: Array = []
@export var priority: int = 0
@export var max_claimants: int = 1
@export var expires_after: float = 0.0
@export var consumption_rate: float = 0.0
@export var progress_on_completion: float = 100.0
