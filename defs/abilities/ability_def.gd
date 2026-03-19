# FILE: res://defs/abilities/ability_def.gd
# Definition of an active capability (attack, gather, build, etc.) usable by pawns.
class_name AbilityDef
extends Resource

enum TargetingMode {
	SELF,
	WORLD_CELL,
	NEARBY_ITEM,
	NEARBY_PAWN,
	INVENTORY_ITEM,
	CONTEXTUAL,
	HIVE_SLOT
}

enum ExecutionMode {
	INSTANT,
	CHANNEL,
	TOGGLE
}

enum AbilityEffectType {
	GATHER_RESOURCE,
	DROP_ITEM,
	PLACE_MARKER,
	REMOVE_MARKER,
	ATTACK,
	CRAFT,
	POLLINATE,
	WATER_PLANT,
	BUILD_STRUCTURE,
	ENTER_HIVE,
	OFFER_TRADE,
	LAY_EGG,
	POSSESS_PAWN,
	INTERACT_GENERIC
}

@export var ability_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null

@export_group("Targeting")
@export var targeting_mode: int = TargetingMode.SELF
@export var range: float = 2.0
@export var requires_xz_alignment: bool = false
@export var valid_categories: Array[int] = []
@export var valid_item_tags: Array[StringName] = []
@export var valid_pawn_tags: Array[StringName] = []

@export_group("Execution")
@export var execution_mode: int = ExecutionMode.INSTANT
@export var channel_duration: float = 0.0
@export var cooldown: float = 1.0
@export var stamina_cost: float = 0.0

@export_group("Effects")
@export var effect_type: int = AbilityEffectType.INTERACT_GENERIC
@export var item_id: StringName = &""
@export var item_count: int = 1
@export var job_marker_type: StringName = &""
@export var damage: float = 0.0
@export var diplomacy_item_id: StringName = &""

@export_group("Presentation")
@export var animation_hint: StringName = &""
@export var vfx_id: StringName = &""
@export var sfx_id: StringName = &""

@export_group("AI")
@export var ai_use_conditions: Array[StringName] = []
@export var ai_priority: int = 0
