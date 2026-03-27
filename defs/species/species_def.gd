# species_def.gd
# res://defs/species/species_def.gd
#
# Defines baseline stats for a creature species.
# Author .tres files in res://defs/species/.
# Phase 1: bee_queen.tres (used for all bee roles until RoleDef is implemented)

class_name SpeciesDef
extends Resource

@export var species_id:    StringName = &""
@export var display_name:  String     = ""

# ── Movement ──────────────────────────────────────────────────────────────────
@export_group("Movement")
@export var movement_type: int   = 1      # 0=GROUND 1=FLYING
@export var base_speed:    float = 16.0
@export var base_accel:    float = 60.0

# ── Vitals ────────────────────────────────────────────────────────────────────
@export_group("Vitals")
@export var base_health:          float = 100.0
@export var base_lifespan_days:   int   = 35
@export var lifespan_variance_days: int = 5
@export var min_lifespan_days:    int   = 25
@export var stubbornness_lifespan_bonus: int = 5
@export var fatigue_rate:         float = 0.004   # per in-game second
@export var rest_rate:            float = 0.012   # per in-game second while sleeping

# ── Inventory ─────────────────────────────────────────────────────────────────
@export_group("Inventory")
@export var inventory_capacity: int   = 5     # max item slots
@export var carry_weight_limit: float = 10.0  # total weight before speed penalty

# ── Possession boost (subtle — never shown to player) ─────────────────────────
@export_group("Possession")
@export var possession_speed_boost:  float = 1.08
@export var possession_action_boost: float = 1.05
