# pawn_state.gd
# res://pawns/pawn_state.gd
#
# Canonical runtime data for one pawn. RefCounted — owned by the pawn node,
# second reference held by PawnRegistry so state survives chunk unload.
#
# This is NOT a Node. It is safe to read from any autoload.
# No node references stored here — use PawnRegistry.get_node(pawn_id) for that.

class_name PawnState
extends RefCounted

# ── Identity ──────────────────────────────────────────────────────────────────
var pawn_id:       int         = -1
var pawn_name:     String      = ""
var species_id:    StringName  = &""    # references SpeciesDef
var role_id:       StringName  = &""    # references RoleDef
var colony_id:     int         = -1     # -1 = wild/neutral
var movement_type: int         = 0      # MovementType enum (0=GROUND, 1=FLYING)

# ── Vitals ────────────────────────────────────────────────────────────────────
var health:       float = 100.0
var max_health:   float = 100.0
var fatigue:      float = 0.0       # 0=rested, 1=must sleep
var age_days:     int   = 0
var max_age_days: int   = 35
var is_alive:     bool  = true
var is_awake:     bool  = true

# ── Loyalty ───────────────────────────────────────────────────────────────────
var loyalty: float = 1.0   # 0..1; < threshold → abandons colony

# ── Possession ────────────────────────────────────────────────────────────────
var possessor_id:         int  = -1     # -1 = no possessor; ≥ 0 = player slot
var player_boost_active:  bool = false

# ── AI resume state ───────────────────────────────────────────────────────────
var ai_resume_state: Dictionary = {}

# ── World position ────────────────────────────────────────────────────────────
var last_known_cell: Vector2i = Vector2i.ZERO

# ── Inventory ─────────────────────────────────────────────────────────────────
var inventory: PawnInventory = null


# ════════════════════════════════════════════════════════════════════════════ #
#  Serialisation
# ════════════════════════════════════════════════════════════════════════════ #

func to_dict() -> Dictionary:
	return {
		"pawn_id":           pawn_id,
		"pawn_name":         pawn_name,
		"species_id":        str(species_id),
		"role_id":           str(role_id),
		"colony_id":         colony_id,
		"movement_type":     movement_type,
		"health":            health,
		"max_health":        max_health,
		"fatigue":           fatigue,
		"age_days":          age_days,
		"max_age_days":      max_age_days,
		"is_alive":          is_alive,
		"is_awake":          is_awake,
		"loyalty":           loyalty,
		"possessor_id":      possessor_id,
		"last_known_cell_x": last_known_cell.x,
		"last_known_cell_y": last_known_cell.y,
		"ai_resume_state":   ai_resume_state,
		"schema_version":    1,
		"inventory":         inventory.to_dict() if inventory else {},
	}

static func from_dict(d: Dictionary) -> PawnState:
	var s := PawnState.new()
	s.pawn_id       = d.get("pawn_id",       -1)
	s.pawn_name     = d.get("pawn_name",      "")
	s.species_id    = StringName(d.get("species_id",  ""))
	s.role_id       = StringName(d.get("role_id",     ""))
	s.colony_id     = d.get("colony_id",      -1)
	s.movement_type = d.get("movement_type",  0)
	s.health        = d.get("health",         100.0)
	s.max_health    = d.get("max_health",     100.0)
	s.fatigue       = d.get("fatigue",        0.0)
	s.age_days      = d.get("age_days",       0)
	s.max_age_days  = d.get("max_age_days",   35)
	s.is_alive      = d.get("is_alive",       true)
	s.is_awake      = d.get("is_awake",       true)
	s.loyalty       = d.get("loyalty",        1.0)
	if d.has("inventory") and not d["inventory"].is_empty():
		s.inventory = PawnInventory.from_dict(d["inventory"])
	else:
		# Create default inventory — capacity set later when species_def is read
		s.inventory = PawnInventory.new()
		var spec: SpeciesDef = load("res://defs/species/%s.tres" % str(s.species_id))
		s.inventory.setup(spec.inventory_capacity if spec else 10)


	s.possessor_id  = d.get("possessor_id",  -1)
	s.last_known_cell = Vector2i(
		d.get("last_known_cell_x", 0),
		d.get("last_known_cell_y", 0)
	)
	s.ai_resume_state = d.get("ai_resume_state", {})
	return s
