class_name GFXAnt
extends Node3D

@export var anim: AnimationPlayer
@export var anim_tree: AnimationTree
@export var pivot: Node3D
# Add a reference to your TimeScale node in the inspector
@export var time_scale_path: String = "parameters/motion/TimeScale/scale"
# Maximum expected velocity for normalization
@export var max_speed: float = 5.0 

func _process(delta: float) -> void:
	if not anim_tree:
		return 
	
	# Get raw velocity length
	var linear_velocity = owner.velocity.length()
	
	# Update blend amount for animation mixing (0.0 to 1.0)
	var blend_amount = clamp(linear_velocity / max_speed, 0.0, 1.0)
	anim_tree.set("parameters/motion/idle_v_walk/blend_amount", blend_amount)
	#print(blend_amount, linear_velocity, owner.velocity)
	# Update animation speed based on velocity
	# Map speed to a reasonable range (e.g., 0.5x to 1.5x)
	var time_scale = clamp(linear_velocity / 2.0, 0.5, 5)
	anim_tree.set(time_scale_path, time_scale)
