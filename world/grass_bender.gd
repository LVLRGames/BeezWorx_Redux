class_name GrassBender
extends Node

@export var max_benders: int = 64

var _bender_texture: ImageTexture
var _bender_image: Image

func _ready() -> void:
	_bender_image = Image.create(max_benders, 1, false, Image.FORMAT_RGBF)
	_bender_texture = ImageTexture.create_from_image(_bender_image)
	RenderingServer.global_shader_parameter_set("bender_texture", _bender_texture)
	RenderingServer.global_shader_parameter_set("bender_count", 0)

func _process(_delta: float) -> void:
	var benders := get_tree().get_nodes_in_group("grass_benders")
	var count := mini(benders.size(), max_benders)
	
	for i in count:
		var pos: Vector3 = benders[i].global_position
		_bender_image.set_pixel(i, 0, Color(pos.x, pos.y, pos.z))
	
	# Clear unused slots
	for i in range(count, max_benders):
		_bender_image.set_pixel(i, 0, Color(0.0, -9999.0, 0.0))
	
	_bender_texture.update(_bender_image)
	RenderingServer.global_shader_parameter_set("bender_count", count)
