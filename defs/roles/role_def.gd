# role_def.gd
# res://defs/roles/role_def.gd
# Functional specialisation for a pawn (e.g. Nurse, Soldier, Landscaper).
#
# ABILITY ASSIGNMENT:
#   action_ability and alt_ability are the primary abilities for this role.
#   PawnAbilityExecutor resolves these first; falls back to PawnBase defaults
#   only when both are null (e.g. an unspecialised pawn with no role).
#
# AUTHORING:
#   Create a .tres per role. Assign to PawnBase.role_def in the scene,
#   or swap at runtime on PawnState role change (maturation, promotion).

class_name RoleDef
extends Resource

@export var role_id:      StringName = &""
@export var display_name: String     = ""

# ── Abilities ──────────────────────────────────────────────────────────────
## Prioritised action abilities for this role. First can_use() winner fires.
@export var action_abilities: Array[AbilityDef] = []
## Prioritised alt-action abilities for this role.
@export var alt_abilities:    Array[AbilityDef] = []

# ── AI ─────────────────────────────────────────────────────────────────────
@export var utility_behaviors:    Array[Resource]   = []
@export var harvest_restrictions: Array[StringName] = []
@export var craft_wait_interval:  float             = 0.5
@export var fallback_behavior_id: StringName        = &"idle"
