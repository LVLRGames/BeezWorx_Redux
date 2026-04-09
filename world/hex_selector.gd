class_name HexSelector
extends Node3D

const SELECTOR_MATERIAL = preload("uid://b7oklnoslky06")

@onready var label_3d: Label3D = $Label3D
@onready var mesh_inst: MeshInstance3D = $MeshInstance3D

@export var terrain: HexTerrainManager
@export var ray_origin: Node3D
@export_flags_3d_physics var ray_mask: int = 1

@export var ui_debug: HexCellDebug

func _ready() -> void:
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 6
	cyl.top_radius = HexConsts.HEX_SIZE
	cyl.bottom_radius = HexConsts.HEX_SIZE
	cyl.height = HexConsts.HEX_SIZE
	cyl.material = SELECTOR_MATERIAL

	mesh_inst.position.y = HexConsts.HEX_SIZE / 2.0 * -1.0
	mesh_inst.mesh = cyl

	if ui_debug:
		label_3d.hide()

func get_look_at_point() -> Vector3:
	if not ray_origin:
		return Vector3.ZERO

	var space_state := get_world_3d().direct_space_state
	var origin: Vector3 = ray_origin.global_position
	var end: Vector3 = origin + (-ray_origin.global_transform.basis.y * 1000.0)

	var query := PhysicsRayQueryParameters3D.create(origin, end, ray_mask)
	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		var raw_pos: Vector3 = result.position

		var axial: Vector2i = HexConsts.WORLD_TO_AXIAL(raw_pos.x, raw_pos.z)

		if ui_debug:
			label_3d.hide()
			ui_debug.text = _get_cell_info(axial.x, axial.y)
		elif label_3d:
			label_3d.text = _get_cell_info(axial.x, axial.y)

		var w: Vector2 = HexConsts.AXIAL_TO_WORLD(axial.x, axial.y)
		var snapped_pos := Vector3(w.x, 0.0, w.y)
		snapped_pos.y = snappedf(raw_pos.y, HexConsts.HEIGHT_STEP)

		return snapped_pos

	return Vector3.ZERO

func _process(_delta: float) -> void:
	global_position = get_look_at_point()

func _get_cell_info(q: int, r: int) -> String:
	var w: Vector2 = HexConsts.AXIAL_TO_WORLD(q, r)
	var ctx: Dictionary = terrain.config.get_terrain_context(w.x, w.y)
	var region: ContinentalRegion = ctx["region"] as ContinentalRegion

	var text := "Q: %d, R: %d\nY: %.2f\nH: %.2f\nH_Norm: %.2f\nMtn: %.2f\nB: %s\nCR: %s\nCNTL: %.2f" % [
		q,
		r,
		global_position.y,
		ctx["height"],
		ctx["height"] / (HexConsts.MAX_HEIGHT + terrain.config.mountain_max_height),
		ctx["mountain"],
		ctx["biome"],
		region.display_name,
		ctx["cntl"],
	]

	var cell := Vector2i(q, r)
	var state: HexCellState = HexWorldState.get_cell(cell)

	if state.occupied and state.category == HexGridObjectDef.Category.PLANT:
		var stage_names: PackedStringArray = [
			"SEED", "SPROUT", "GROWTH", "FLOWERING",
			"FRUITING", "IDLE", "WILT", "DEAD"
		]

		text += "\n--- Plant ---"
		text += "\nID: %s" % state.object_id
		text += "\nStage: %s" % stage_names[state.stage]
		text += "\nThirst: %.0f%%" % (state.thirst * 100.0)
		text += "\nPollen: %.1f" % state.pollen_amount
		text += "\nNectar: %.1f" % state.nectar_amount
		text += "\nCycles: %d" % state.fruit_cycles_done

		if state.genes:
			text += "\nSpeed: %.2f" % state.genes.cycle_speed
			text += "\nDrought: %.2f" % state.genes.drought_resist

	elif state.occupied:
		text += "\n--- Object ---"
		text += "\nID: %s" % state.object_id

	var bee: Node = get_tree().get_first_node_in_group("bees")
	if bee and bee.has_method("get_bee_info"):
		text += "\n" + bee.get_bee_info()

	return text

func bounce_cell() -> void:
	var cell: Vector2i = HexConsts.WORLD_TO_AXIAL(global_position.x, global_position.z)
	var chunk_coord := Vector2i(
		floori(float(cell.x) / HexConsts.CHUNK_SIZE),
		floori(float(cell.y) / HexConsts.CHUNK_SIZE)
	)

	var chunk: HexChunk = terrain.get_loaded_chunk(chunk_coord)
	if chunk:
		chunk.trigger_plant_bounce(cell)
