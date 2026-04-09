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

var _plant_mm:       MultiMesh = null
var _grass_plant_mm: MultiMesh = null

var _terrain_material: Material = null
var _height_cache: PackedFloat32Array
var _skirt_masks: PackedByteArray
var _ramp_edges: PackedByteArray
var _grass_node: MultiMeshInstance3D = null

# ── Instance tracking (slot-keyed) ───────────────────────────────────────
var _cell_states: Dictionary[Vector3i, HexCellState] = {}
var _plant_instance_map: Dictionary[Vector3i, HexPlantInstanceRef] = {}
var _pending_bounces:       Dictionary[Vector3i, bool] = {}
var _pending_grass_slot_keys: Array[Vector3i] = []
## Ordered slot keys matching _plant_mm instance indices.
var _pending_plant_slot_keys: Array[Vector3i] = []
## Cells dirtied by cell_changed signal; flushed once per frame.
var _dirty_cells: Dictionary[Vector2i, bool] = {}
var _next_check_time: float = 0.0
var _next_transition: Dictionary[Vector3i, float] = {}
var _has_tree_collision: bool = false
var terrain_manager: HexTerrainManager
var _first_check_done: bool = false

var _gen_cache: HexChunkGenCache = null
var _generation_world_time: float = 0.0

func _init(coord: Vector2i, puffy: bool) -> void:
	chunk_coord = coord
	use_puffy = puffy

func _ready() -> void:
	add_to_group("hex_chunks")
	if Engine.is_editor_hint():
		if not HexWorldState.cell_changed.is_connected(_on_cell_changed):
			HexWorldState.cell_changed.connect(_on_cell_changed)
		return

	_next_check_time = TimeService.world_time + randf() * CHECK_INTERVAL

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Flush batched dirty cells every frame.
	if not _dirty_cells.is_empty():
		_flush_dirty_cells()

	var now: float = TimeService.world_time
	if now < _next_check_time:
		return
	_next_check_time = now + CHECK_INTERVAL

	if not _is_near_player():
		return

	_check_stale_plants()

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
	# _generate_grass() retired — grass is now a logical plant in baseline slots.
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
	var grass_xforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var grass_custom: Array[Color] = []
	_pending_grass_slot_keys.clear()
	_pending_plant_slot_keys.clear()

	var static_batches: Dictionary[String, HexStaticBatch] = {}

	for dq: int in CHUNK_SIZE:
		for dr: int in CHUNK_SIZE:
			var q: int = chunk_coord.x * CHUNK_SIZE + dq
			var r: int = chunk_coord.y * CHUNK_SIZE + dr
			var cell := Vector2i(q, r)

			var w: Vector2 = HexConsts.AXIAL_TO_WORLD(q, r)
			var wp: Vector3 = Vector3(w.x, 0.0, w.y)
			wp.y = _hc(dq, dr)

			# Query all 6 slots per cell.
			for slot: int in 6:
				var sk := Vector3i(q, r, slot)
				var state: HexCellState = HexWorldState.get_slot_ref(
					cell, slot, _generation_world_time, _gen_cache
				)
				_cell_states[sk] = state

				if not state.occupied:
					continue
				if state.origin != cell:
					continue   # satellite of a multi-cell object; origin renders it

				var def: HexGridObjectDef = state.definition
				if not def:
					continue

				# Multi-slot objects (trees, big rocks): only render from slot 0.
				if def.slots_occupied > 1 and slot > 0:
					continue

				match def.category:
					HexGridObjectDef.Category.PLANT:
						var plant_def: HexPlantDef = def as HexPlantDef
						match plant_def.plant_subcategory:
							HexPlantDef.PlantSubcategory.RESOURCE, \
							HexPlantDef.PlantSubcategory.PASSIVE_DEFENSE:
								_batch_plant(state, wp, plant_xforms, plant_colors, plant_custom)

							HexPlantDef.PlantSubcategory.GRASS:
								var biome_id2: StringName = _gen_cache.get_biome(cell) if _gen_cache else &""
								var biome2: HexBiome = HexWorldState.cfg.get_biome_definition(biome_id2)
								_batch_grass_plant(state, wp, biome2, grass_xforms, grass_colors, grass_custom)

							HexPlantDef.PlantSubcategory.ACTIVE_DEFENSE:
								_active_scenes[cell] = def.scene

							HexPlantDef.PlantSubcategory.TREE:
								var tree_def: HexTreeDef = def as HexTreeDef
								var batch_key: String         = def.id
								var batch_mesh: Mesh           = def.mesh
								var batch_material: Material   = def.material
								var variant_scale_range: Vector2 = def.random_scale_range
								var rot_offset_radians: float  = 0.0
								var tree_variant: HexTreeVariant = null

								var variant_index: int = _pick_tree_variant_index(cell, tree_def)
								if variant_index >= 0:
									tree_variant = tree_def.get_variant(variant_index)
									if tree_variant != null:
										batch_key          = "%s::v%d" % [def.id, variant_index]
										batch_mesh         = tree_variant.mesh if tree_variant.mesh != null else def.mesh
										batch_material     = tree_variant.material if tree_variant.material != null else def.material
										variant_scale_range = tree_variant.scale_range
										rot_offset_radians = deg_to_rad(tree_variant.y_rotation_offset_degrees)

								if batch_mesh == null:
									continue

								if not static_batches.has(batch_key):
									static_batches[batch_key] = HexStaticBatch.new(
										def, batch_mesh, batch_material, tree_variant
									)

								var basis: Basis = Basis(Vector3.UP, _det_angle(cell) + rot_offset_radians) \
									if def.random_rotation else Basis()
								var hash_val: int = (cell.x * 1619 + cell.y * 31337) ^ (cell.x * 6971)
								var scale_t: float = float(hash_val & 0xFFFF) / float(0xFFFF)
								var scale: float   = lerpf(variant_scale_range.x, variant_scale_range.y, scale_t)

								static_batches[batch_key].xforms.append(
									Transform3D(basis.scaled(Vector3.ONE * scale), wp)
								)
								static_batches[batch_key].customs.append(Color.WHITE)

					_:   # ROCK, PORTAL — non-plant static objects
						var batch_key: String       = def.id
						var batch_mesh: Mesh         = def.mesh
						var batch_mat: Material      = def.material
						var scale_range: Vector2     = def.random_scale_range

						if batch_mesh == null:
							continue

						if not static_batches.has(batch_key):
							static_batches[batch_key] = HexStaticBatch.new(
								def, batch_mesh, batch_mat, null
							)

						var basis2: Basis = Basis(Vector3.UP, _det_angle(cell)) \
							if def.random_rotation else Basis()
						var hv: int = (cell.x * 1619 + cell.y * 31337) ^ (cell.x * 6971)
						var st2: float = float(hv & 0xFFFF) / float(0xFFFF)
						var sc: float  = lerpf(scale_range.x, scale_range.y, st2)

						static_batches[batch_key].xforms.append(
							Transform3D(basis2.scaled(Vector3.ONE * sc), wp)
						)
						static_batches[batch_key].customs.append(Color.WHITE)

	_plant_mm       = _build_plant_mm(plant_mesh, plant_xforms, plant_colors, plant_custom)
	var grass_mesh_res: Mesh = HexWorldState.cfg.grass_mesh if HexWorldState.cfg else null
	_grass_plant_mm = _build_plant_mm(grass_mesh_res, grass_xforms, grass_colors, grass_custom)
	_rebuild_plant_instance_map()

	# Build next-transition table for all plant slots.
	_next_transition.clear()
	for sk: Vector3i in _cell_states:
		var st: HexCellState = _cell_states[sk]
		if st.category != HexGridObjectDef.Category.PLANT:
			continue
		var cell2 := Vector2i(sk.x, sk.y)
		if st.origin != cell2:
			continue
		if st.definition and (st.definition as HexGridObjectDef).slots_occupied > 1 and sk.z > 0:
			continue
		_next_transition[sk] = _compute_next_transition(Vector2i(sk.x, sk.y), st)

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


# Slot centroid offsets (normalized XZ directions × 0.35 × HEX_SIZE).
# Slot K = triangle toward NDIRS[K]. Jitter is added inside the triangle.
static func _slot_centroid_offset(slot: int, hex_size: float) -> Vector3:
	const DIRS: Array[Vector2] = [
		Vector2( 1.0,    0.0  ),   # slot 0
		Vector2( 0.5,    0.866),   # slot 1
		Vector2(-0.5,    0.866),   # slot 2
		Vector2(-1.0,    0.0  ),   # slot 3
		Vector2(-0.5,   -0.866),   # slot 4
		Vector2( 0.5,   -0.866),   # slot 5
	]
	var d: Vector2 = DIRS[clampi(slot, 0, 5)]
	return Vector3(d.x, 0.0, d.y) * hex_size * 0.35

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
		0.0   # .a = bounce start time; written by trigger_plant_bounce
	)

	var inst_color := Color(state.thirst, state.get_health_fraction(), 1.0, 1.0)
	# COLOR.r = thirst (desaturation shader)
	# COLOR.g = health_fraction (browning on damage — shader reads this next session)

	var origin: Vector2i = state.origin
	var slot: int = state.slot_index if state.slot_index >= 0 else 0
	var sk := Vector3i(origin.x, origin.y, slot)

	if _pending_bounces.has(sk):
		custom_data.a = float(Time.get_ticks_usec()) / 1000000.0

	# Position: slot centroid + small jitter within triangle.
	var centroid_offset: Vector3 = _slot_centroid_offset(slot, HexConsts.HEX_SIZE)
	var hash_val: int = (origin.x * 1619 + origin.y * 31337 + slot * 6971) ^ (origin.x * 7)
	var jitter_angle: float = ((hash_val & 0xFFFF) / float(0xFFFF)) * TAU
	var jitter_dist: float  = (((hash_val >> 16) & 0xFFFF) / float(0xFFFF)) * 0.18 * HexConsts.HEX_SIZE
	var jitter := Vector3(cos(jitter_angle) * jitter_dist, 0.0, sin(jitter_angle) * jitter_dist)

	var basis: Basis = Basis.from_euler(Vector3(0.0, _det_angle(origin) + slot * (TAU / 6.0), 0.0))
	xf.append(Transform3D(basis, wp + centroid_offset + jitter))
	_pending_plant_slot_keys.append(sk)
	col.append(inst_color)
	cus.append(custom_data)

func _batch_grass_plant(
	state: HexCellState,
	wp: Vector3,
	biome: HexBiome,
	xf: Array[Transform3D],
	col: Array[Color],
	cus: Array[Color]
) -> void:
	var origin: Vector2i = state.origin
	var slot: int = state.slot_index if state.slot_index >= 0 else 0
	var sk := Vector3i(origin.x, origin.y, slot)

	var tint: Color = biome.grass_tint if biome else Color.WHITE
	var rows: Array[int] = biome.grass_atlas_rows if biome else [0]
	if rows.is_empty():
		rows = [0]

	var hash_val: int = (origin.x * 1619 + origin.y * 31337 + slot * 6971) ^ (origin.x * 7)

	var s_n: float = 0.0
	if HexWorldState.cfg and HexWorldState.cfg.grass_stage_noise:
		s_n = HexWorldState.cfg.grass_stage_noise.get_noise_2d(wp.x, wp.z)
	var base_row_idx: int = int(remap(s_n, -1.0, 1.0, 0.0, float(rows.size()))) % rows.size()
	var deviation: float  = float(hash_val & 0xFF) / 255.0
	var row_idx: int      = base_row_idx
	if deviation > 0.85:
		row_idx = (hash_val >> 8) % rows.size()
	var atlas_col: int = hash_val & 3

	var bounce_t: float = float(Time.get_ticks_usec()) / 1000000.0 		if _pending_bounces.has(sk) else 0.0

	var centroid: Vector3 = _slot_centroid_offset(slot, HexConsts.HEX_SIZE)
	var jitter_angle: float = ((hash_val & 0xFFFF) / float(0xFFFF)) * TAU
	var jitter_dist: float  = (((hash_val >> 16) & 0xFFFF) / float(0xFFFF)) * 0.18 * HexConsts.HEX_SIZE
	var jitter := Vector3(cos(jitter_angle) * jitter_dist, 0.0, sin(jitter_angle) * jitter_dist)

	# Track slot key in order — used by _rebuild_plant_instance_map to
	# map instance index → slot without relying on jittered world position.
	_pending_grass_slot_keys.append(sk)
	xf.append(Transform3D(
		Basis.from_euler(Vector3(0.0, _det_angle(origin) + slot * (TAU / 6.0), 0.0)),
		wp + centroid + jitter
	))
	col.append(tint)
	cus.append(Color(float(atlas_col), float(rows[row_idx]), 0.0, bounce_t))


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
	# Direct slot→index mapping using keys tracked during batching.
	if _plant_mm != null:
		for i: int in _pending_plant_slot_keys.size():
			var sk: Vector3i = _pending_plant_slot_keys[i]
			if not _plant_instance_map.has(sk):
				_plant_instance_map[sk] = HexPlantInstanceRef.new(_plant_mm, i)
	if _grass_plant_mm != null:
		for i: int in _pending_grass_slot_keys.size():
			var sk: Vector3i = _pending_grass_slot_keys[i]
			if not _plant_instance_map.has(sk):
				_plant_instance_map[sk] = HexPlantInstanceRef.new(_grass_plant_mm, i)

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
	if _grass_plant_mm:
		var grass_mi := MultiMeshInstance3D.new()
		grass_mi.multimesh = _grass_plant_mm
		# No material_override — grass mesh carries its own shader material.
		grass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(grass_mi)

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
	# Remove existing plant and grass plant MMIs.
	for child: Node in get_children():
		if child is MultiMeshInstance3D and child != _grass_node:
			if child.multimesh == _plant_mm or child.multimesh == _grass_plant_mm:
				child.queue_free()

	var plant_xforms: Array[Transform3D] = []
	var plant_colors: Array[Color] = []
	var plant_custom: Array[Color] = []
	var grass_xforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var grass_custom: Array[Color] = []
	_pending_plant_slot_keys.clear()
	_pending_grass_slot_keys.clear()

	for sk: Vector3i in _cell_states:
		var cell := Vector2i(sk.x, sk.y)
		var slot: int = sk.z
		var state: HexCellState = HexWorldState.get_slot_ref(cell, slot)
		_cell_states[sk] = state

		if not state.occupied:
			continue
		if state.origin != cell:
			continue
		var def: HexGridObjectDef = state.definition
		if not def or def.category != HexGridObjectDef.Category.PLANT:
			continue
		var plant_def: HexPlantDef = def as HexPlantDef
		if def.slots_occupied > 1 and slot > 0:
			continue
		var w: Vector2 = HexConsts.AXIAL_TO_WORLD(cell.x, cell.y)
		var local: Vector2i = cell - chunk_coord * CHUNK_SIZE
		var wp := Vector3(w.x, 0.0, w.y)
		wp.y = _hc(local.x, local.y)
		match plant_def.plant_subcategory:
			HexPlantDef.PlantSubcategory.RESOURCE, \
			HexPlantDef.PlantSubcategory.PASSIVE_DEFENSE:
				_batch_plant(state, wp, plant_xforms, plant_colors, plant_custom)
			HexPlantDef.PlantSubcategory.GRASS:
				var bid: StringName = HexWorldState.cfg.get_cell_biome(cell.x, cell.y)
				var bm: HexBiome = HexWorldState.cfg.get_biome_definition(bid)
				_batch_grass_plant(state, wp, bm, grass_xforms, grass_colors, grass_custom)

	_plant_mm = _build_plant_mm(plant_mesh, plant_xforms, plant_colors, plant_custom)
	var gmesh: Mesh = HexWorldState.cfg.grass_mesh if HexWorldState.cfg else null
	_grass_plant_mm = _build_plant_mm(gmesh, grass_xforms, grass_colors, grass_custom)
	_rebuild_plant_instance_map()

	if _plant_mm:
		var plant_mi := MultiMeshInstance3D.new()
		plant_mi.multimesh = _plant_mm
		if plant_material:
			plant_mi.material_override = plant_material
		add_child(plant_mi)

	if _grass_plant_mm:
		var gmi2 := MultiMeshInstance3D.new()
		gmi2.multimesh = _grass_plant_mm
		gmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(gmi2)

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

	if _grass_plant_mm:
		var grass_mi := MultiMeshInstance3D.new()
		grass_mi.multimesh = _grass_plant_mm
		grass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(grass_mi)

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


func _check_stale_plants() -> void:
	if _next_transition.is_empty():
		return

	if not _first_check_done:
		_first_check_done = true
		for sk: Vector3i in _cell_states:
			if _next_transition.has(sk):
				_next_transition[sk] = _compute_next_transition(
					Vector2i(sk.x, sk.y), _cell_states[sk]
				)
		return

	var now: float = TimeService.world_time
	var changed_slots: Array[Vector3i] = []

	for sk: Vector3i in _next_transition:
		if _next_transition[sk] > now:
			continue
		changed_slots.append(sk)

	if changed_slots.is_empty():
		return

	# Invalidate cache for changed cells only.
	var changed_cells: Array[Vector2i] = []
	for sk: Vector3i in changed_slots:
		var cell := Vector2i(sk.x, sk.y)
		if not changed_cells.has(cell):
			changed_cells.append(cell)
	HexWorldState.invalidate_cells(changed_cells)

	# Re-query changed slots and try in-place update.
	var needs_rebuild: bool = false
	for sk: Vector3i in changed_slots:
		var cell := Vector2i(sk.x, sk.y)
		var slot: int = sk.z
		var old_state: HexCellState = _cell_states.get(sk)
		var new_state: HexCellState = HexWorldState.get_slot_ref(cell, slot)
		_cell_states[sk] = new_state

		var old_occ: bool = old_state != null and old_state.occupied
		var new_occ: bool = new_state.occupied

		if old_occ != new_occ or (old_occ and new_occ and old_state.object_id != new_state.object_id):
			needs_rebuild = true
			break

	if needs_rebuild:
		# Fall back to full rebuild when plants appear/disappear.
		for sk: Vector3i in changed_slots:
			_pending_bounces[sk] = true
		refresh_plants()
		_pending_bounces.clear()
	else:
		# In-place update — just write new color + custom_data per instance.
		for sk: Vector3i in changed_slots:
			var state: HexCellState = _cell_states.get(sk)
			if state != null and state.occupied:
				_update_plant_instance_data(sk, state)
				trigger_plant_bounce_slot(sk)

	# Refresh transition timers for all tracked plants.
	for sk: Vector3i in _next_transition:
		if _cell_states.has(sk):
			_next_transition[sk] = _compute_next_transition(
				Vector2i(sk.x, sk.y), _cell_states[sk]
			)


func _on_cell_changed(cell: Vector2i) -> void:
	var local: Vector2i = cell - chunk_coord * CHUNK_SIZE
	if local.x < 0 or local.x >= CHUNK_SIZE or local.y < 0 or local.y >= CHUNK_SIZE:
		return
	# Debounce: accumulate and process once per frame in _process.
	_dirty_cells[cell] = true


## Process batched dirty cells. Compares old vs new state to determine
## whether a full plant MM rebuild is needed or an in-place update suffices.
func _flush_dirty_cells() -> void:
	var needs_rebuild: bool = false
	var update_slots: Array[Vector3i] = []

	for cell: Vector2i in _dirty_cells:
		if needs_rebuild:
			break
		for slot: int in 6:
			var sk := Vector3i(cell.x, cell.y, slot)
			if not _cell_states.has(sk):
				continue
			var old_state: HexCellState = _cell_states[sk]
			var new_state: HexCellState = HexWorldState.get_slot_ref(cell, slot)

			var old_occ: bool = old_state.occupied
			var new_occ: bool = new_state.occupied

			if old_occ != new_occ or (old_occ and new_occ and old_state.object_id != new_state.object_id):
				needs_rebuild = true
				break
			elif old_occ and new_occ:
				update_slots.append(sk)

			_cell_states[sk] = new_state

	_dirty_cells.clear()

	if needs_rebuild:
		refresh_plants()
		_rebuild_next_transitions()
	else:
		for sk: Vector3i in update_slots:
			var state: HexCellState = _cell_states.get(sk)
			if state != null:
				_update_plant_instance_data(sk, state)
			if _next_transition.has(sk):
				_next_transition[sk] = _compute_next_transition(
					Vector2i(sk.x, sk.y), state
				)


## Update a single plant's MultiMesh instance color + custom data in-place.
func _update_plant_instance_data(sk: Vector3i, state: HexCellState) -> void:
	if not _plant_instance_map.has(sk):
		return
	var entry: HexPlantInstanceRef = _plant_instance_map[sk]
	if entry.multimesh == null or entry.index < 0 or entry.index >= entry.multimesh.instance_count:
		return

	var def: HexGridObjectDef = state.definition
	if not (def is HexPlantDef):
		return
	var plant_def: HexPlantDef = def as HexPlantDef

	match plant_def.plant_subcategory:
		HexPlantDef.PlantSubcategory.RESOURCE, \
		HexPlantDef.PlantSubcategory.PASSIVE_DEFENSE:
			var genes: HexPlantGenes = state.genes
			if genes == null:
				return
			var variant: int = state.plant_variant \
				if state.plant_variant >= 0 \
				else HexConsts.PlantVariant.NORMAL
			var old_custom: Color = entry.multimesh.get_instance_custom_data(entry.index)
			var custom := Color(
				genes.pack_variants(state.stage, variant),
				genes.pack_flower_colors(),
				genes.pack_foliage_colors(),
				old_custom.a   # preserve bounce time
			)
			entry.multimesh.set_instance_custom_data(entry.index, custom)
			var new_color := Color(state.thirst, state.get_health_fraction(), 1.0, 1.0)
			entry.multimesh.set_instance_color(entry.index, new_color)
		HexPlantDef.PlantSubcategory.GRASS:
			# Grass has no per-stage visual change in current implementation.
			pass


## Rebuild _next_transition for all tracked plant slots from current _cell_states.
func _rebuild_next_transitions() -> void:
	_next_transition.clear()
	for sk: Vector3i in _cell_states:
		var st: HexCellState = _cell_states[sk]
		if st.category != HexGridObjectDef.Category.PLANT:
			continue
		var cell2 := Vector2i(sk.x, sk.y)
		if st.origin != cell2:
			continue
		if st.definition and (st.definition as HexGridObjectDef).slots_occupied > 1 and sk.z > 0:
			continue
		_next_transition[sk] = _compute_next_transition(cell2, st)


## Trigger the bounce animation on a specific plant slot.
func trigger_plant_bounce_slot(slot_key: Vector3i) -> void:
	if not _plant_instance_map.has(slot_key):
		return
	var entry: HexPlantInstanceRef = _plant_instance_map[slot_key]
	if entry.multimesh == null or entry.index < 0:
		return
	var custom: Color = entry.multimesh.get_instance_custom_data(entry.index)
	custom.a = float(Time.get_ticks_usec()) / 1000000.0
	entry.multimesh.set_instance_custom_data(entry.index, custom)


## Legacy compat: bounces slot 0 of the cell.
func trigger_plant_bounce(cell: Vector2i) -> void:
	trigger_plant_bounce_slot(Vector3i(cell.x, cell.y, 0))


func queue_bounce(cell: Vector2i) -> void:
	for s: int in 6:
		_pending_bounces[Vector3i(cell.x, cell.y, s)] = true

func queue_bounce_slot(slot_key: Vector3i) -> void:
	_pending_bounces[slot_key] = true

func _hc(dq: int, dr: int) -> float:
	return _height_cache[(dq + 1) * _HC_STRIDE + (dr + 1)]


static func _det_angle(cell: Vector2i) -> float:
	var h: int = (cell.x * 1619 + cell.y * 31337) ^ (cell.x * 1619)
	return (h & 0xFFFF) / float(0xFFFF) * TAU
