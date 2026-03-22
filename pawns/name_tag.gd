class_name NameTag
extends Label3D


@export var info:String = "Name":
	get: return _info
	set(v): set_info(v)

var _info:String = name


func set_info(new_info:String):
	_info = new_info
	text = "%s" % [_info]
