# FILE: res://colony/faction_relation.gd
# Tracks diplomatic standing and trade history with a specific faction.
class_name FactionRelation
extends RefCounted

class TradeRecord:
	var day: int = 0
	var item_id: StringName = &""
	var item_count: int = 0
	var match_score: float = 0.0
	var relation_delta: float = 0.0

var faction_id: StringName = &""
var relation_score: float = 0.0
var is_allied: bool = false
var is_hostile: bool = false
var trade_history: Array[TradeRecord] = []
var first_contact_day: int = 0
var last_gift_day: int = 0
var preference_revealed: bool = false

func to_dict() -> Dictionary:
	return {}

static func from_dict(data: Dictionary) -> FactionRelation:
	return null
