# FILE: res://pawns/effect_instance.gd
# Runtime tracking for an active status effect or buff on a pawn.
class_name EffectInstance
extends RefCounted

var effect_id: StringName = &""
var duration: float = 0.0
var magnitude: float = 0.0
var source_id: int = 0
