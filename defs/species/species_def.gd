# species_def.gd
# res://defs/species/species_def.gd
# Defines baseline stats for a creature species.

class_name SpeciesDef
extends Resource

@export var species_id:   StringName = &""
@export var display_name: String     = ""

# ── Roles ──────────────────────────────────────────────────────────────────
## RoleDef ids this species can be assigned. Empty = any role is valid.
## Enforced by PawnRegistry on role assignment to prevent e.g. a bee
## being assigned a landscaper role intended for grasshoppers.
@export var valid_role_ids: Array[StringName] = []

# ── Movement ───────────────────────────────────────────────────────────────
@export_group("Movement")
@export var movement_type: int   = 1      # 0=GROUND 1=FLYING
@export var base_speed:    float = 16.0
@export var base_accel:    float = 60.0

# ── Vitals ─────────────────────────────────────────────────────────────────
@export_group("Vitals")
@export var base_health:                 float = 100.0
@export var base_lifespan_days:          int   = 35
@export var lifespan_variance_days:      int   = 5
@export var min_lifespan_days:           int   = 25
@export var stubbornness_lifespan_bonus: int   = 5
@export var fatigue_rate:                float = 0.004
@export var rest_rate:                   float = 0.012

# ── Inventory ──────────────────────────────────────────────────────────────
@export_group("Inventory")
@export var inventory_capacity: int   = 5
@export var carry_weight_limit: float = 10.0

# ── Possession boost ───────────────────────────────────────────────────────
@export_group("Possession")
@export var possession_speed_boost:  float = 1.08
@export var possession_action_boost: float = 1.05
