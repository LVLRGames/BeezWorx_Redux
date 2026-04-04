# item_registry.gd
# res://autoloads/item_registry.gd
# Autoload. Loads all ItemDef resources and indexes them by item_id.

extends Node

var _defs: Dictionary[StringName, ItemDef] = {}

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	var dir := DirAccess.open("res://defs/items/")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") or fname.ends_with(".res"):
			var def: ItemDef = load("res://defs/items/" + fname) as ItemDef
			if def and def.item_id != &"":
				_defs[def.item_id] = def
		fname = dir.get_next()
	dir.list_dir_end()

func get_def(item_id: StringName) -> ItemDef:
	return _defs.get(item_id, null)

func get_icon(item_id: StringName) -> Texture2D:
	var def: ItemDef = get_def(item_id)
	return def.icon if def else null

func get_display_name(item_id: StringName) -> String:
	var def: ItemDef = get_def(item_id)
	return def.display_name if def else str(item_id)
