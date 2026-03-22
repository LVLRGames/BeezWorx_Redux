# hex_cell_state.gd
class_name HexCellState
extends RefCounted

var occupied: bool = false
var origin: Vector2i = Vector2i.ZERO
var object_id: String = ""
var definition: HexGridObjectDef = null
var category: int = -1
var source: StringName = &"baseline" # baseline | delta
var occupant_data: CellOccupantData = null

# Plant-specific
var stage: int = -1
var genes: HexPlantGenes = null
var thirst: float = 0.0
var has_pollen: bool = false
var pollen_amount: float = 0.0
var nectar_amount: float = 0.0
var fruit_cycles_done: int = 0
var plant_variant: int = -1
var birth_time: float = 0.0

func duplicate_state() -> HexCellState:
	var s := HexCellState.new()
	s.occupied = occupied
	s.origin = origin
	s.object_id = object_id
	s.definition = definition
	s.category = category
	s.source = source
	s.occupant_data = occupant_data
	s.stage = stage
	s.genes = genes
	s.thirst = thirst
	s.has_pollen = has_pollen
	s.pollen_amount = pollen_amount
	s.nectar_amount = nectar_amount
	s.fruit_cycles_done = fruit_cycles_done
	s.plant_variant = plant_variant
	s.birth_time = birth_time
	return s

func to_dict() -> Dictionary:
	return {
		"occupied": occupied,
		"origin": origin,
		"object_id": object_id,
		"definition": definition,
		"category": category,
		"source": source,
		"occupant_data": occupant_data,
		"stage": stage,
		"genes": genes,
		"thirst": thirst,
		"has_pollen": has_pollen,
		"pollen_amount": pollen_amount,
		"nectar_amount": nectar_amount,
		"fruit_cycles_done": fruit_cycles_done,
		"plant_variant": plant_variant,
		"_birth": birth_time,
	}
