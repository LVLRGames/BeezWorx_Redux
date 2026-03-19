# FILE: res://colony/queen_record.gd
# Historical record of a colony's queen and her reign.
class_name QueenRecord
extends RefCounted

var pawn_name: String = ""
var pawn_id: int = 0
var reign_start: int = 0
var reign_end: int = 0
var cause: StringName = &""
