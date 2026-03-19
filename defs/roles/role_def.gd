# FILE: res://defs/roles/role_def.gd
# Functional specialization for a pawn (eg. Nurse, Soldier, Carpenter).
class_name RoleDef
extends Resource

@export var role_id: StringName = &""
@export var display_name: String = ""
@export var utility_behaviors: Array[Resource] = []
@export var harvest_restrictions: Array[StringName] = []
@export var craft_wait_interval: float = 0.5
@export var fallback_behavior_id: StringName = &"idle"
