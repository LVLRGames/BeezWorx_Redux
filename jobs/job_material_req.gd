# FILE: res://jobs/job_material_req.gd
# Specification for a material item required for a job.
class_name JobMaterialReq
extends RefCounted

var item_id: StringName = &""
var count: int = 0
var per_colony: bool = false
