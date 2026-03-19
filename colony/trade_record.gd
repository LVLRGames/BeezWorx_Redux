# FILE: res://colony/trade_record.gd
# Persistent record of a commercial transaction with another faction.
class_name TradeRecord
extends RefCounted

var day: int = 0
var item_id: StringName = &""
var item_count: int = 0
var match_score: float = 0.0
var relation_delta: float = 0.0
