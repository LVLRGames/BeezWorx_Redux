# FILE: res://defs/threats/threat_def.gd
# Configuration for raids and ambient environmental hazards.
class_name ThreatDef
extends Resource

@export var threat_id: StringName = &""
@export_enum("Predator:0", "Swarm:1", "Environmental:2") var threat_category: int = 0
@export var species_id: StringName = &""
@export var spawn_count_range: Vector2i = Vector2i(1, 3)
@export var spawn_distance_range: Vector2 = Vector2(10, 20)
@export var base_spawn_chance: float = 0.05
@export var influence_scale: float = 1.0
@export var honey_scale: float = 1.0
@export var seasonal_multipliers: Array[float] = [1.0, 1.0, 1.0, 1.0]
@export var raid_cooldown_days: int = 3
@export var can_be_appeased: bool = false
@export var appeasement_faction: StringName = &""
