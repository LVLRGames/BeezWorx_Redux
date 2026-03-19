# FILE: res://colony/hive/feed_entry.gd
# Data structure for tracking nutrition provided to a maturing egg.
class_name FeedEntry
extends RefCounted

var item_id: StringName = &""
var fed_at: float = 0.0
var fed_by: int = 0
