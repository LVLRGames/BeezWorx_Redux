# ability_context.gd
# res://abilities/ability_context.gd
#
# Pre-computed per-execution data passed to every ability.
# Defs call autoloads directly for system access — context only holds
# values that require computation at call time.

class_name AbilityContext
extends RefCounted

## The pawn executing the ability
var pawn: PawnBase

## Hex cell the pawn currently occupies — computed once per execute call
var pawn_cell: Vector2i

## Snapshot of TimeService.world_time at execution start
## Use this instead of calling TimeService.world_time directly so all
## ability logic in one execution sees a consistent time value.
var world_time: float
