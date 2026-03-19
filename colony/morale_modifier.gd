# FILE: res://colony/morale_modifier.gd
# Tracks a single factor influencing collective colony morale.
class_name MoraleModifier
extends RefCounted

var source_id: StringName = &""
var value: float = 0.0
var expires_day: int = -1
var description: String = ""
