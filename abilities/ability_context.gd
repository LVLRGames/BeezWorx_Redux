# ability_context.gd
# res://abilities/ability_context.gd

class_name AbilityContext
extends RefCounted

## The pawn executing the ability
var pawn: PawnBase

## Hex cell the pawn currently occupies
var pawn_cell: Vector2i

## Resolved interaction target cell (plant, marker, etc.)
var target_cell: Vector2i = Vector2i(-9999, -9999)

## Nearest pawn in interaction range (for give/trade abilities)
var target_pawn: PawnBase = null

## Nearest hive id in range (-1 = none)
var target_hive_id: int = -1

## Snapshot of TimeService.world_time at execution start
var world_time: float

## True if target_cell is a valid world cell
func has_target_cell() -> bool:
	return target_cell != Vector2i(-9999, -9999)

## Cell state at target_cell, or null
func get_target_cell_state() -> HexCellState:
	if not has_target_cell():
		return null
	return HexWorldState.get_cell(target_cell)

## Cell state at pawn_cell
func get_pawn_cell_state() -> HexCellState:
	return HexWorldState.get_cell(pawn_cell)
