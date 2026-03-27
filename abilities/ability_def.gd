# ability_def.gd
# res://abilities/ability_def.gd
#
# Abstract base for all ability definitions.
# Subclass this for each ability type — do not instantiate directly.
#
# EXECUTION FLOW:
#   PawnAbilityExecutor calls:
#     1. can_use(ctx)        — gate check (cooldown, inventory, stage, etc.)
#     2. resolve_target(ctx) — find best valid target, return null if none
#     3. execute(ctx, target) — perform the effect
#
# AUTOLOAD ACCESS:
#   Defs call autoloads directly (HexWorldState, HiveSystem, etc.)
#   Context provides only pre-computed per-call data.

@abstract
class_name AbilityDef
extends Resource

@export var ability_id:    StringName = &""
@export var display_name:  String     = ""
@export var description:   String     = ""
@export var icon:          Texture2D  = null

# ── Timing ────────────────────────────────────────────────────────────────────
@export var cooldown:         float = 0.5    # seconds between uses
@export var channel_duration: float = 0.0   # 0 = instant

# ── Targeting ─────────────────────────────────────────────────────────────────
@export var range: float = 2.0   # max distance from pawn to valid target

# ── AI hints ──────────────────────────────────────────────────────────────────
@export var ai_priority: float = 1.0

# ════════════════════════════════════════════════════════════════════════════ #
#  Virtual interface — override in subclasses
# ════════════════════════════════════════════════════════════════════════════ #

## Return false to block use (inventory full, wrong stage, on cooldown etc.)
## Cooldown is checked by the executor before calling this — no need to recheck.
func can_use(ctx: AbilityContext) -> bool:
	return true

## Return the best valid target for this ability, or null if none in range.
## Target type varies by ability: Vector2i for world cells, PawnBase for pawns.
func resolve_target(ctx: AbilityContext) -> Variant:
	return null

## Perform the ability effect. Target is the value returned by resolve_target().
func execute(ctx: AbilityContext, target: Variant) -> void:
	pass

## Human-readable description of what this ability does right now.
## Used by HUD to show context-sensitive button labels.
func get_prompt(ctx: AbilityContext) -> String:
	return display_name
