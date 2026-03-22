# hex_chunk.gd
# Generates one CHUNK_SIZE × CHUNK_SIZE terrain patch.

#@tool
class_name HexChunk
extends Node3D

const CHUNK_SIZE: int = HexConsts.CHUNK_SIZE
const RAMP_NOISE_THRESHOLD: float = 0.15
const _HC_STRIDE: int = CHUNK_SIZE + 2
const CHECK_INTERVAL: float = 1.0
const CHECK_RADIUS: int = 6
const COLLISION_RADIUS: int = 5

const TERRAIN_MATERIAL := preload("uid://d2fo1pqgsc4on")

const NDIRS: Array[Vector2i] = [
	Vector2i( 1, 0), Vector2i( 0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i( 0,-1), Vector2i( 1,-1),
]

static var plant_mesh: Mesh = null
static var plant_material: Material = null
static var _lut: HexMeshLUT = null

var chunk_coord: Vector2i
var use_puffy: bool = true
var generating: bool = false

var terrain_mesh: Mesh = null
var grass_mm: MultiMesh = null

var object_mms: Dictionary[String, MultiMesh] = {}
var _object_batch_meta: Dictionary[String, HexStaticBatch] = {}
var _active_scenes: Dictionary[Vector2i, PackedScene] = {}

var _plant_mm: MultiMesh = null

var _terrain_material: Material = null
var _height_cache: PackedFloat32Array
var _skirt_masks: PackedByteArray
var _ramp_edges: PackedByteArray
var _grass_node: MultiMeshInstance3D = null

var _cell_states: Dictionary[Vector2i, HexCellState] = {}
var _plant_instance_map: Dictionary[Vector2i, HexPlantInstanceRef] = {}
var _pending_bounces: Dictionary[Vector2i, bool] = {}
var _next_check_time: float = 0.0
var _next_transition: Dictionary[Vector2i, float] = {}
var _has_tree_collision: bool = false
var terrain_manager: HexTerrainManager
var _first_check_done: bool = false

var _gen_cache: HexChunkGenCache = null
var _generation_world_time: float = 0.0

func _init(coord: Vector2i, puffy: bool) -> void:
	chunk_coord = coord
	use_puffy = puffy

func _ready() -> void:
	if Engine.is_editor_hint():
		if not HexWorldState.cell_changed.is_connected(_on_cell_changed):
			HexWorldState.cell_changed.connect(_on_cell_changed)
		return

	_next_check_time = TimeService.world_time + randf() * CHECK_INTERVAL

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var now: float = TimeService.world_time
	if now < _next_check_time:
		return
	_next_check_time = now + CHECK_INTERVAL

	if not _is_near_player():
		return

	#var t0 := Time.get_ticks_usec()
	_check_stale_plants()
	#var elapsed := Time.get_ticks_usec() - t0
	#if elapsed > 500:
		#print("stale check: %d us, chunk: %s" % [elapsed, chunk_coord])

	var should_have: bool = _should_have_tree_collision()
	if should_have and not _has_tree_collision:
		_add_tree_collision()
	elif not should_have and _has_tree_collision:
		_remove_tree_collision()

func _is_near_player() -> bool:
	if not terrain_manager or not terrain_manager.player:
		return false
	var player_chunk := terrain_manager._world_to_chunk(terrain_manager.player.global_position)
	var dx: int = absi(chunk_coord.x - player_chunk.x)
	var dy: int = absi(chunk_coord.y - player_chunk.y)
	return dx <= CHECK_RADIUS and dy <= CHECK_RADIUS

func _should_have_tree_collision() -> bool:
	var manager: HexTerrainManager = get_parent()
	if not manager or not manager.player:
		return false
	var player_chunk := manager._world_to_chunk(manager.player.global_position)
	var dx: int = absi(chunk_coord.x - player_chunk.x)
	var dy: int = absi(chunk_coord.y - player_chunk.y)
	return dx <= COLLISION_RADIUS and dy <= COLLISION_RADIUS

func _add_tree_collision() -> void:
	_remove_tree_collision()

	for batch_key: String in object_mms:
		if not _object_batch_meta.has(batch_key):
			continue

		var batch: HexStaticBatch = _object_batch_meta[batch_key]
		var def: HexGridObjectDef = batch.def
		if not (def is HexTreeDef):
			continue

		var shape: Shape3D = null
		if batch.tree_variant != null:
			shape = batch.tree_variant.get_collision_shape()
		if shape == null:
			shape = (def as HexTreeDef).get_collision_shape()
		if shape == null:
			continue

		var mm: MultiMesh = object_mms[batch_key]
		for i: int in mm.instance_count:
			var xform: Transform3D = mm.get_instance_transform(i)
			var sb := StaticBody3D.new()
			sb.set_meta("tree_collision", true)

			var cs := CollisionShape3D.new()
			cs.shape = shape
			sb.transform = xform
			sb.add_child(cs)
			add_child(sb)

	_has_tree_collision = true

func _remove_tree_collision() -> void:
	for child: Node in get_children():
		if child is StaticBody3D and child.has_meta("tree_collision"):
			child.queue_free()
	_has_tree_collision = false

func generate_all_data() -> void:
	_generation_world_time = TimeService.world_time

	_gen_cache = HexChunkGenCache.new()
	_gen_cache.build(HexWorldState.cfg, HexWorldState.registry, chunk_coord, CHUNK_SIZE)

	_precompute_heights()
	_precompute_ramps()
	_generate_terrain_mesh()
	_generate_grass()
	_generate_objects()

func _precompute_heights() -> void:
	var cfg: HexTerrainConfig = HexWorldState.cfg
	_height_cache.resize(_HC_STRIDE * _HC_STRIDE)

	for dq: int in range(-1, CHUNK_SIZE + 1):
		for dr: int in range(-1, CHUNK_SIZE + 1):
			var q: int = chunk_coord.x * CHUNK_SIZE + dq
			var r: int = chunk_coord.y * CHUNK_SIZE + dr
			var w := HexConsts.AXIAL_TO_WORLD(q, r)
			_height_cache[(dq + 1) * _HC_STRIDE + (dr + 1)] = snappedf(
				cfg.get_height(w.x, w.y),
				HexConsts.HEIGHT_STEP
			)

func _precompute_ramps() -> void:
	var total: int = CHUNK_SIZE * CHUNK_SIZE
	_skirt_masks = PackedByteArray()
	_skirt_masks.resize(total)

	_ramp_edges = PackedByteArray()
	_ramp_edges.resize(total)
	_ramp_edges.fill(255)

	for dq: int in CHUNK_SIZE:
		for dr: int in CHUNK_SIZE:
			var idx: int = dq * CHUNK_SIZE + dr
			var h: float = _hc(dq, dr)
			var mask: int = 0
			var lower_count: int = 0
			var lower_edge: int = -1
			var lower_diff: float = 0.0

			for e: int in 6:
				var ndq: int = dq + NDIRS[e].x
				var ndr: int = dr + NDIRS[e].y
				if ndq < -1 or ndq > CHUNK_SIZE or ndr < -1 or ndr > CHUNK_SIZE:
					continue

				var diff: float = h - _hc(ndq, ndr)
				if diff > HexConsts.HEIGHT_STEP * 0.1:
					mask |= (1 << e)
					lower_count += 1
					lower_edge = e
					lower_diff = diff

			_skirt_masks[idx] = mask

			if lower_count == 1 \
					and lower_edge >= 0 \
					and lower_diff >= HexConsts.HEIGHT_STEP * 0.9 \
					and lower_diff <= HexConsts.HEIGHT_STEP * 1.1:
				var q: int = chunk_coord.x * CHUNK_SIZE + dq
				var r: int = chunk_coord.y * CHUNK_SIZE + dr
				var nv: float = _gen_cache.get_placement(Vector2i(q, r))
				if nv > RAMP_NOISE_THRESHOLD:
					_ramp_edges[idx] = lower_edge

func _generate_terrain_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for dq: int in CHUNK_SIZE:
		for dr: int in CHUNK_SIZE:
			_emit_hex(st, dq, dr)

	st.generate_normals()
	if use_puffy:
		st.index()
	terrain_mesh = st.commit()

func _emit_hex(st: SurfaceTool, dq: int, dr: int) -> void:
	var q: int = chunk_coord.x * CHUNK_SIZE + dq
	var r: int = chunk_coord.y * CHUNK_SIZE + dr
	var cell := Vector2i(q, r)

	var w: Vector2 = HexConsts.AXIAL_TO_WORLD(q, r)
	var center: Vector3 = Vector3(w.x, 0.0, w.y)
	var h: float = _hc(dq, dr)
	center.y = h

	var biome_id: StringName = _gen_cache.get_biome(cell)
	var biome: HexBiome = HexWorldState.cfg.get_biome_definition(biome_id)
	var biome_u: float = biome.terrain_atlas_col * HexConsts.TERRAIN_TILE_U if biome else 0.0

	var corners: Array[Vector3] = []
	for i: int in 6:
		var angle: float = deg_to_rad(60.0 * i - 30.0)
		corners.append(center + Vector3(
			HexConsts.HEX_SIZE * cos(angle),
			0.0,
			HexConsts.HEX_SIZE * sin(angle)
		))

	var idx: int = dq * CHUNK_SIZE + dr
	var mask: int = _skirt_masks[idx]
	var ramp_e: int = _ramp_edges[idx]
	var true_re: int = ramp_e if ramp_e != 255 else -1
	var indices = _lut.get_indices(mask, true_re)

	var n_heights: PackedFloat32Array
	n_heights.resize(6)
	for e: int in 6:
		var ndq: int = dq + NDIRS[e].x
		var ndr: int = dr + NDIRS[e].y
		if ndq >= -1 and ndq <= CHUNK_SIZE and ndr >= -1 and ndr <= CHUNK_SIZE:
			n_heights[e] = _hc(ndq, ndr)
		else:
			n_heights[e] = h

	var slots: Array[Vector3] = []
	slots.resize(31)
	slots[0] = center
	for i: int in 6:
		slots[1 + i] = corners[i]
	for i: int in 6:
		slots[7 + i] = Vector3(corners[i].x, h - HexConsts.HEIGHT_STEP, corners[i].z)

	var ramp_neighbor_center: Vector3 = Vector3.ZERO
	var ramp_biome_u: float = biome_u

	for e: int in 6:
		if not (mask & (1 << e)) or ramp_e != e:
			continue

		var low_y: float = n_heights[e]
		var out_d: Vector3 = (corners[e] + corners[(e + 1) % 6]) * 0.5 - Vector3(center.x, 0.0, center.z)
		out_d.y = 0.0
		out_d = out_d.normalized()

		var nx: float = center.x + out_d.x * HexConsts.SQRT3 * HexConsts.HEX_SIZE
		var nz: float = center.z + out_d.z * HexConsts.SQRT3 * HexConsts.HEX_SIZE
		ramp_neighbor_center = Vector3(nx, low_y, nz)

		var n_cell: Vector2i = cell + NDIRS[e]
		var n_bid: StringName = _gen_cache.get_biome(n_cell)
		var n_biome: HexBiome = HexWorldState.cfg.get_biome_definition(n_bid)
		ramp_biome_u = n_biome.terrain_atlas_col * HexConsts.TERRAIN_TILE_U if n_biome else biome_u

		var ra: float = deg_to_rad(60.0 * ((e + 2) % 6) - 30.0)
		var rb: float = deg_to_rad(60.0 * ((e + 5) % 6) - 30.0)
		slots[HexMeshLUT.SLOT_R_BASE + e * 3 + 0] = ramp_neighbor_center
		slots[HexMeshLUT.SLOT_R_BASE + e * 3 + 1] = Vector3(
			nx + HexConsts.HEX_SIZE * cos(ra),
			low_y,
			nz + HexConsts.HEX_SIZE * sin(ra)
		)
		slots[HexMeshLUT.SLOT_R_BASE + e * 3 + 2] = Vector3(
			nx + HexConsts.HEX_SIZE * cos(rb),
			low_y,
			nz + HexConsts.HEX_SIZE * sin(rb)
		)

	const TOP_FACE_VERTS: int = 18
	var uv_o: Vector2 = Vector2(biome_u, 0.0)
	var ramp_uv_o: Vector2 = Vector2(ramp_biome_u, 0.0)

	for i: int in indices.size():
		var s: int = indices[i]
		if i < TOP_FACE_VERTS:
			_emit_vert(st, slots[s], uv_o, center)
		else:
			_emit_vert(st, slots[s], ramp_uv_o, ramp_neighbor_center)

	for e: int in 6:
		if not (mask & (1 << e)):
			continue
		if ramp_e == e:
			continue
		_emit_skirt(st, corners[e], corners[(e + 1) % 6], h, n_heights[e], biome_u)

func _emit_vert(st: SurfaceTool, v: Vector3, uv_o: Vector2, center: Vector3) -> void:
	var local: Vector3 = v - center
	local.y = 0.0
	var u: float = (local.x / (HexConsts.HEX_SIZE * HexConsts.SQRT3)) + 0.5
	var vv: float = (local.z / (HexConsts.HEX_SIZE * 2.0)) + 0.5
	st.set_uv(uv_o + Vector2(u * HexConsts.TERRAIN_TILE_U, vv * HexConsts.TERRAIN_TILE_V * 2.0))
	st.add_vertex(v)

func _emit_skirt(st: SurfaceTool, ca: Vector3, cb: Vector3, h: float, nh: float, biome_u: float) -> void:
	var cur: float = h
	var first: bool = true

	while cur > nh:
		var nxt: float = maxf(cur - HexConsts.HEIGHT_STEP, nh)
		var uv_y: float = HexConsts.TERRAIN_TILE_V * (2.0 if first else 3.0)
		var uvo: Vector2 = Vector2(biome_u, uv_y)
		var tu: float = HexConsts.TERRAIN_TILE_U * 0.5
		var tv: float = HexConsts.TERRAIN_TILE_V * 0.5

		st.set_uv(uvo)
		st.add_vertex(Vector3(ca.x, cur, ca.z))
		st.set_uv(uvo + Vector2(0.0, tv))
		st.add_vertex(Vector3(ca.x, nxt, ca.z))
		st.set_uv(uvo + Vector2(tu, tv))
		st.add_vertex(Vector3(cb.x, nxt, cb.z))

		st.set_uv(uvo)
		st.add_vertex(Vector3(ca.x, cur, ca.z))
		st.set_uv(uvo + Vector2(tu, tv))
		st.add_vertex(Vector3(cb.x, nxt, cb.z))
		st.set_uv(uvo + Vector2(tu, 0.0))
		st.add_vertex(Vector3(cb.x, cur, cb.z))

		cur = nxt
		first = false

func _generate_grass() -> void:
	var cfg: HexTerrainConfig = HexWorldState.cfg
	if not cfg.grass_mesh:
		return

	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []

	for dq: int in CHUNK_SIZE:
		for dr: int in CHUNK_SIZE:
			var q: int = chunk_coord.x * CHUNK_SIZE + dq
			var r: int = chunk_coord.y * CHUNK_SIZE + dr
			var cell := Vector2i(q, r)

			var bid: StringName = _gen_cache.get_biome(cell)
			var biome: HexBiome = HexWorldState.cfg.get_biome_definition(bid)
			if not biome or not biome.has_grass:
				continue

			var tint: Color = biome.grass_tint
			var w: Vector2 = HexConsts.AXIAL_TO_WORLD(q, r)
			var wp: Vector3 = Vector3(w.x, 0.0, w.y)
			wp.y = _hc(dq, dr)

			var d_n: float = cfg.grass_density_noise.get_noise_2dv(Vector2(q, r) * 10.1)
			if d_n < biome.grass_density_threshold:
				continue

			var count: int = int(round(remap(d_n, -1.0, 1.0, 0.0, cfg.max_grass_per_hex)))
			for i: int in count:
				var angle: float = randf() * TAU
				var dist: float = randf_range(0.15, 0.7) * HexConsts.HEX_SIZE
				var offset: Vector3 = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
				var s_n: float = cfg.grass_stage_noise.get_noise_2d(wp.x + offset.x, wp.z + offset.z)

				xforms.append(Transform3D(
					Basis.from_euler(Vector3(0.0, randf() * TAU, 0.0)),
					wp + offset
				))
				colors.append(tint)

				var rows: Array[int] = biome.grass_atlas_rows
				if rows.is_empty():
					rows = [0]

				var base_row_idx: int = int(remap(s_n, -1.0, 1.0, 0.0, float(rows.size()))) % rows.size()
				var hash_val: int = (q * 1619 + r * 31337 + i * 6971) ^ (q * 7)
				var deviation: float = float(hash_val & 0xFF) / 255.0

				var row_idx: int = base_row_idx
				if deviation > 0.85:
					row_idx = (hash_val >> 8) % rows.size()

				var col: int = hash_val & 3
				customs.append(Color(float(col), float(rows[row_idx]), 0.0, 0.0))

	if xforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = cfg.grass_mesh
	mm.instance_count = xforms.size()

	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])

	grass_mm = mm

func _generate_objects() -> void:
	object_mms.clear()
	_object_batch_meta.clear()
	_active_scenes.clear()
	_cell_states.clear()
 
	var plant_xforms: Array[Transform3D] = []
	var plant_colors: Array[Color] = []
	var plant_custom: Array[Color] = []

	var static_batches: Dictionary[String, HexStaticBatch] = {}

	for dq: int in CHUNK_SIZE:
		for dr: int in CHUNK_SIZE:
			var q: int = chunk_coord.x * CHUNK_SIZE + dq
			var r: int = chunk_coord.y * CHUNK_SIZE + dr
			var cell: Vector2i = Vector2i(q, r)

			var state: HexCellState = HexWorldState.get_cell_ref(cell, _generation_world_time, _gen_cache)
			_cell_states[cell] = state

			if not state.occupied:
				continue
			if state.origin != cell:
				continue

			var def: HexGridObjectDef = state.definition
			if not def:
				continue

			var w: Vector2 = HexConsts.AXIAL_TO_WORLD(q, r)
			var wp: Vector3 = Vector3(w.x, 0.0, w.y)
			wp.y = _hc(dq, dr)

			match def.category:
				HexGridObjectDef.Category.RESOURCE_PLANT:
					_batch_plant(state, wp, plant_xforms, plant_colors, plant_custom)

				HexGridObjectDef.Category.DEFENSIVE_ACTIVE:
					_active_scenes[cell] = def.scene

				_:
					var batch_key: String = def.id
					var batch_mesh: Mesh = def.mesh
					var batch_material: Material = def.material
					var variant_scale_range: Vector2 = def.random_scale_range
					var rot_offset_radians: float = 0.0
					var tree_variant: HexTreeVariant = null

					if def is HexTreeDef:
						var tree_def: HexTreeDef = def as HexTreeDef
						var variant_index: int = _pick_tree_variant_index(cell, tree_def)
						if variant_index >= 0:
							tree_variant = tree_def.get_variant(variant_index)
							if tree_variant != null:
								batch_key = "%s::v%d" % [def.id, variant_index]
								batch_mesh = tree_variant.mesh if tree_variant.mesh != null else def.mesh
								batch_material = tree_variant.material if tree_variant.material != null else def.material
								variant_scale_range = tree_variant.scale_range
								rot_offset_radians = deg_to_rad(tree_variant.y_rotation_offset_degrees)

					if batch_mesh == null:
						continue

					if not static_batches.has(batch_key):
						static_batches[batch_key] = HexStaticBatch.new(
							def,
							batch_mesh,
							batch_material,
							tree_variant
						)

					var basis: Basis = Basis(Vector3.UP, _det_angle(cell) + rot_offset_radians) if def.random_rotation else Basis()
					var hash_val: int = (cell.x * 1619 + cell.y * 31337) ^ (cell.x * 6971)
					var scale_t: float = float(hash_val & 0xFFFF) / float(0xFFFF)
					var scale: float = lerpf(variant_scale_range.x, variant_scale_range.y, scale_t)

					var batch: HexStaticBatch = static_batches[batch_key]
					batch.xforms.append(Transform3D(basis.scaled(Vector3.ONE * scale), wp))
					batch.customs.append(Color.WHITE)

	_plant_mm = _build_plant_mm(plant_mesh, plant_xforms, plant_colors, plant_custom)

	_rebuild_plant_instance_map()

	_next_transition.clear()
	for c: Vector2i in _cell_states:
		var st: HexCellState = _cell_states[c]
		if st.category != HexGridObjectDef.Category.RESOURCE_PLANT:
			continue
		if st.origin != c:
			continue
		_next_transition[c] = _compute_next_transition(c, st)

	for batch_key: String in static_batches:
		var batch: HexStaticBatch = static_batches[batch_key]
		if batch.xforms.is_empty():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = batch.mesh
		mm.instance_count = batch.xforms.size()

		for i: int in batch.xforms.size():
			mm.set_instance_transform(i, batch.xforms[i])
			mm.set_instance_custom_data(i, batch.customs[i])

		object_mms[batch_key] = mm
		_object_batch_meta[batch_key] = batch

func _batch_plant(
	state: HexCellState,
	wp: Vector3,
	xf: Array[Transform3D],
	col: Array[Color],
	cus: Array[Color]
) -> void:
	var genes: HexPlantGenes = state.genes
	if genes == null:
		return
 
	var variant: int = state.plant_variant \
		if state.plant_variant >= 0 \
		else HexConsts.PlantVariant.NORMAL
 
	var custom_data := Color(
		genes.pack_variants(state.stage, variant),
		genes.pack_flower_colors(),
		genes.pack_foliage_colors(),
		0.0   # .a reserved for bounce start time — written by trigger_plant_bounce()
	)
 
	var inst_color := Color(state.thirst, 1.0, 1.0, 1.0)
 
	var origin: Vector2i = state.origin
	if _pending_bounces.has(origin):
		custom_data.a = float(Time.get_ticks_usec()) / 1000000.0
 
	var hash_val: int = (origin.x * 1619 + origin.y * 31337) ^ (origin.x * 6971)
	var angle: float  = ((hash_val & 0xFFFF) / float(0xFFFF)) * TAU
	var dist: float   = (((hash_val >> 16) & 0xFFFF) / float(0xFFFF)) * 0.5 * HexConsts.HEX_SIZE
	var offset: Vector3 = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
 
	var basis: Basis = Basis.from_euler(Vector3(0.0, _det_angle(origin), 0.0))
	xf.append(Transform3D(basis, wp + offset))
	col.append(inst_color)
	cus.append(custom_data)



func _pick_tree_variant_index(cell: Vector2i, def: HexTreeDef) -> int:
	if def == null or def.variants.is_empty():
		return -1
	if def.variants.size() == 1:
		return 0

	var total_weight: float = 0.0
	for variant: HexTreeVariant in def.variants:
		total_weight += maxf(variant.weight, 0.0)

	if total_weight <= 0.0:
		return 0

	var h: int = (cell.x * 92821 + cell.y * 68917) ^ (cell.x * 1237)
	var t: float = float(h & 0xFFFF) / 65535.0
	var roll: float = t * total_weight

	var accum: float = 0.0
	for i: int in def.variants.size():
		var variant: HexTreeVariant = def.variants[i]
		accum += maxf(variant.weight, 0.0)
		if roll <= accum:
			return i

	return def.variants.size() - 1

static func _build_plant_mm(
	mesh: Mesh,
	xforms: Array[Transform3D],
	colors: Array[Color],
	customs: Array[Color]
) -> MultiMesh:
	if xforms.is_empty() or not mesh:
		return null

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()

	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])

	return mm

func _rebuild_plant_instance_map() -> void:
	_plant_instance_map.clear()
	if _plant_mm == null:
		return
	for i: int in _plant_mm.instance_count:
		var xform: Transform3D = _plant_mm.get_instance_transform(i)
		var c: Vector2i = HexConsts.WORLD_TO_AXIAL(xform.origin.x, xform.origin.z)
		_plant_instance_map[c] = HexPlantInstanceRef.new(_plant_mm, i)


func _compute_next_transition(cell: Vector2i, state: HexCellState) -> float:
	var def: HexGridObjectDef = state.definition
	if not (def is HexPlantDef):
		return INF

	var pd: HexPlantData = (def as HexPlantDef).plant_data
	var genes: HexPlantGenes = state.genes
	if not pd or not genes:
		return INF

	var stage: int = state.stage
	if stage >= HexWorldState.Stage.DEAD:
		return INF

	var speed: float = maxf(genes.cycle_speed, 0.01)
	var duration: float = pd.stage_durations[stage] / speed
	return TimeService.world_time + duration

func finalize_chunk(prebuilt_shape: Shape3D = null) -> void:
	if not terrain_mesh:
		return

	var mi := MeshInstance3D.new()
	mi.mesh = terrain_mesh
	if TERRAIN_MATERIAL:
		mi.mesh.surface_set_material(0, TERRAIN_MATERIAL)
	add_child(mi)

	if grass_mm:
		var gmi := MultiMeshInstance3D.new()
		gmi.multimesh = grass_mm
		gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_grass_node = gmi
		add_child(gmi)

	if _plant_mm:
		var plant_mi := MultiMeshInstance3D.new()
		plant_mi.multimesh = _plant_mm
		if plant_material:
			plant_mi.material_override = plant_material
		add_child(plant_mi)

	for batch_key: String in object_mms:
		if not _object_batch_meta.has(batch_key):
			continue

		var batch: HexStaticBatch = _object_batch_meta[batch_key]
		var gmi := MultiMeshInstance3D.new()
		gmi.multimesh = object_mms[batch_key]
		if batch.material:
			gmi.material_override = batch.material
		add_child(gmi)

	for cell: Vector2i in _active_scenes:
		var scene: PackedScene = _active_scenes[cell]
		if not scene:
			continue
		var instance: Node = scene.instantiate()
		if instance.has_method("set_grid_cell"):
			instance.set_grid_cell(cell)
		add_child(instance)

	if _should_have_tree_collision():
		_add_tree_collision()

	if not Engine.is_editor_hint():
		var shape: Shape3D = prebuilt_shape if prebuilt_shape else terrain_mesh.create_trimesh_shape()
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = shape
		sb.add_child(cs)
		add_child(sb)

func refresh_plants() -> void:
	# Remove existing plant MMI
	for child: Node in get_children():
		if child is MultiMeshInstance3D and child != _grass_node:
			if child.multimesh == _plant_mm:
				child.queue_free()
 
	var plant_xforms: Array[Transform3D] = []
	var plant_colors: Array[Color] = []
	var plant_custom: Array[Color] = []
 
	for cell: Vector2i in _cell_states:
		var state: HexCellState = HexWorldState.get_cell_ref(cell)
		_cell_states[cell] = state
 
		if not state.occupied:
			continue
		if state.origin != cell:
			continue
 
		var def: HexGridObjectDef = state.definition
		if not def:
			continue
		if def.category != HexGridObjectDef.Category.RESOURCE_PLANT:
			continue
 
		var w: Vector2 = HexConsts.AXIAL_TO_WORLD(cell.x, cell.y)
		var local: Vector2i = cell - chunk_coord * CHUNK_SIZE
		var wp := Vector3(w.x, 0.0, w.y)
		wp.y = _hc(local.x, local.y)
 
		_batch_plant(state, wp, plant_xforms, plant_colors, plant_custom)
 
	_plant_mm = _build_plant_mm(plant_mesh, plant_xforms, plant_colors, plant_custom)
	_rebuild_plant_instance_map()
 
	if _plant_mm:
		var plant_mi := MultiMeshInstance3D.new()
		plant_mi.multimesh = _plant_mm
		if plant_material:
			plant_mi.material_override = plant_material
		add_child(plant_mi)


func refresh_objects() -> void:
	for child: Node in get_children():
		if child is MultiMeshInstance3D and child != _grass_node:
			child.queue_free()
		elif child is Node3D \
				and not (child is MeshInstance3D) \
				and not (child is StaticBody3D) \
				and child != _grass_node:
			child.queue_free()

	_remove_tree_collision()

	object_mms.clear()
	_object_batch_meta.clear()
	_active_scenes.clear()
	_generate_objects()

	if _plant_mm:
		var plant_mi := MultiMeshInstance3D.new()
		plant_mi.multimesh = _plant_mm
		if plant_material:
			plant_mi.material_override = plant_material
		add_child(plant_mi)

	for batch_key: String in object_mms:
		if not _object_batch_meta.has(batch_key):
			continue

		var batch: HexStaticBatch = _object_batch_meta[batch_key]
		var gmi := MultiMeshInstance3D.new()
		gmi.multimesh = object_mms[batch_key]
		if batch.material:
			gmi.material_override = batch.material
		add_child(gmi)

	for cell: Vector2i in _active_scenes:
		var scene: PackedScene = _active_scenes[cell]
		if not scene:
			continue
		var instance: Node = scene.instantiate()
		if instance.has_method("set_grid_cell"):
			instance.set_grid_cell(cell)
		add_child(instance)

	if _should_have_tree_collision():
		_add_tree_collision()

func refresh_objects_with_bounce(cells: Array[Vector2i] = []) -> void:
	refresh_objects()
	for cell: Vector2i in cells:
		trigger_plant_bounce(cell)

func _check_stale_plants() -> void:
	if _next_transition.is_empty():
		return

	if not _first_check_done:
		_first_check_done = true
		for c: Vector2i in _cell_states:
			if _next_transition.has(c):
				_next_transition[c] = _compute_next_transition(c, _cell_states[c])
		return

	var now: float = TimeService.world_time
	var changed_cells: Array[Vector2i] = []

	for cell: Vector2i in _next_transition:
		if _next_transition[cell] > now:
			continue
		_pending_bounces[cell] = true
		changed_cells.append(cell)

	if changed_cells.is_empty():
		return

	HexWorldState.invalidate_cells(changed_cells)
	refresh_plants()
	_pending_bounces.clear()

	for cell: Vector2i in changed_cells:
		if _cell_states.has(cell):
			_next_transition[cell] = _compute_next_transition(cell, _cell_states[cell])

func _on_cell_changed(cell: Vector2i) -> void:
	var local: Vector2i = cell - chunk_coord * CHUNK_SIZE
	if local.x < 0 or local.x >= CHUNK_SIZE or local.y < 0 or local.y >= CHUNK_SIZE:
		return

	queue_bounce(cell)
	refresh_objects()
	_pending_bounces.clear()

func trigger_plant_bounce(cell: Vector2i) -> void:
	if not _plant_instance_map.has(cell):
		return

	var entry: HexPlantInstanceRef = _plant_instance_map[cell]
	if entry.multimesh == null or entry.index < 0:
		return

	var custom: Color = entry.multimesh.get_instance_custom_data(entry.index)
	custom.a = float(Time.get_ticks_msec()) / 1000.0
	entry.multimesh.set_instance_custom_data(entry.index, custom)

func _on_cell_bounced(cell: Vector2i) -> void:
	print("chunk received bounce at: ", Time.get_ticks_msec())
	var local: Vector2i = cell - chunk_coord * CHUNK_SIZE
	if local.x < 0 or local.x >= CHUNK_SIZE or local.y < 0 or local.y >= CHUNK_SIZE:
		return
	trigger_plant_bounce(cell)
	print("custom data set at: ", Time.get_ticks_msec())

func queue_bounce(cell: Vector2i) -> void:
	_pending_bounces[cell] = true

func _hc(dq: int, dr: int) -> float:
	return _height_cache[(dq + 1) * _HC_STRIDE + (dr + 1)]

static func _det_angle(cell: Vector2i) -> float:
	var h: int = (cell.x * 1619 + cell.y * 31337) ^ (cell.x * 1619)
	return (h & 0xFFFF) / float(0xFFFF) * TAU
