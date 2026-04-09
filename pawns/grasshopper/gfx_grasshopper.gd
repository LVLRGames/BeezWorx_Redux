class_name GFXGrasshopper
extends Node3D

@export var anim: AnimationPlayer
@export var anim_tree: AnimationTree
@export var pivot: Node3D
# Add a reference to your TimeScale node in the inspector
@export var time_scale_path: String = "parameters/motion/TimeScale/scale"
# Maximum expected velocity for normalization
@export var max_speed: float = 5.0 

var grasshopper:Grasshopper
var is_grounded:bool = false
var is_hovering:bool = false
var velocity_y:float = 0.0
var near_ground:bool = false

var prep:float = 0.0
var hovering:float = 0.0
var grounded:float = 0.0


func _ready() -> void:
	anim.play("idle")
	grasshopper = owner



func _process(delta: float) -> void:
	if not anim:
		return 
	
	is_hovering = grasshopper.get_hop_state() == PawnHopper.HopState.HOVERING
	is_grounded = grasshopper.is_on_floor()
	near_ground = grasshopper.near_ground()
	var short_hop := grasshopper.wants_short_hop
	
	# Get raw velocity length
	var velocity_y = grasshopper.velocity.y
	var linear_velocity = grasshopper.velocity.length()
	
	var fatigue:float = 1.0
	#prep += 0.1 if short_hop else -0.1
	#prep = clampf(prep,0,1)
	hovering = lerpf(hovering,1 if is_hovering else 0, delta * 30)
	grounded = lerpf(grounded,1 if is_grounded else 0, delta * 30)
	prep = lerpf(prep,1 if short_hop else 0, delta * 30)
	var vel_y:float = remap(clampf(-velocity_y/1.0, -1, 1), -1, 1, 0, 1) * 0.25 if short_hop else 1.0
	
	
	anim_tree.set("parameters/BlendTree/fatigue/add_amount", fatigue)
	anim_tree.set("parameters/BlendTree/velocity_y/blend_amount", vel_y)
	anim_tree.set("parameters/BlendTree/prep/blend_amount", prep)
	anim_tree.set("parameters/BlendTree/is_hovering/blend_amount", hovering)
	anim_tree.set("parameters/BlendTree/is_grounded/blend_amount", grounded)
	
	#prints(hovering)
	
	grasshopper.name_tag.text = anim_tree.get("parameters/playback").get_current_node()
	
	# Update animation speed based on velocity
	# Map speed to a reasonable range (e.g., 0.5x to 1.5x)
	#var time_scale = clamp(linear_velocity / 2.0, 0.5, 5)
	#anim_tree.set(time_scale_path, time_scale)
