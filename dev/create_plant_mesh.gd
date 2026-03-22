@tool
# create_plant_mesh.gd
# res://dev/create_plant_mesh.gd
#
# Attach to any Node in the editor and press "Create Plant Mesh" in the
# Inspector to generate res://world/plant_mesh.res — the 6-quad base mesh
# used by the resource_plant shader.
#
# MESH TOPOLOGY
# ─────────────────────────────────────────────────────────────────────
# 6 quads, 4 vertices each, 24 total vertices.
# All quads are 1 unit wide × 2 units tall, centred at origin.
# Bottom edge sits at Y=0, top edge at Y=2.
# All quads face along +Z before any rotation.
#
# Quad layout (vertex index ranges):
#   Quad 0  (verts  0– 3)  : 0°   — NORMAL arm A / base for all variants
#   Quad 1  (verts  4– 7)  : 90°  — NORMAL arm B / LUSH center arm B
#   Quad 2  (verts  8–11)  : 60°  — ROYAL arm B / LUSH outer NE
#   Quad 3  (verts 12–15)  : 120° — ROYAL arm C / LUSH outer NW
#   Quad 4  (verts 16–19)  : 180° — LUSH outer SW / WILD Q4
#   Quad 5  (verts 20–23)  : 270° — LUSH outer SE / WILD Q5
#
# VARIANT ROUTING (handled entirely in the shader)
# ─────────────────────────────────────────────────────────────────────
# NORMAL : Q0(0°) + Q1(90°)             | Q2–Q5 collapsed to zero
# ROYAL  : Q0(0°) + Q1(60°) + Q2(120°) | Q3–Q5 collapsed
# LUSH   : Q0(0°) + Q1(90°) center cross
#          Q2 offset at 45°, Q3 at 135°, Q4 at 225°, Q5 at 315°
#          outer quads stand straight, bottom edges at 0.5u from center
# WILD   : Q0–Q(N-1) each randomly rotated + offset (N = 3–6 per instance)
#          Remaining quads collapsed
#
# UV LAYOUT
# ─────────────────────────────────────────────────────────────────────
# Every quad gets full UV 0→1 in both axes (atlas tile selection is
# done in the shader, not baked into the mesh UVs).
#   BL = (0,1), BR = (1,1), TL = (0,0), TR = (1,0)
# This matches the atlas tile_uv() convention in resource_plant.gdshader.

extends Node

const OUTPUT_PATH := "res://world/plant_mesh.res"

const QUAD_W : float = 2.0   # half-width  (full width  = 1.0 unit)
const QUAD_H : float = 4.0   # full height (bottom Y=0, top Y=2)

# Outer quad offset for LUSH — distance from centre to bottom edge of outer quad
const LUSH_OFFSET : float = 1.5

@export_tool_button("Create Plant Mesh") var _btn := _create_mesh

func _create_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# We need manual vertex index control for VERTEX_ID to work in the shader.
	# SurfaceTool doesn't expose raw indices cleanly for this, so we build
	# the arrays directly.

	var verts   : PackedVector3Array = PackedVector3Array()
	var normals : PackedVector3Array = PackedVector3Array()
	var uvs     : PackedVector2Array = PackedVector2Array()
	var indices : PackedInt32Array   = PackedInt32Array()

	# ── Quad definitions ──────────────────────────────────────────────
	# Each entry: [y_rotation_degrees, xz_offset_Vector2]
	# y_rotation rotates the quad around the Y axis.
	# xz_offset translates the quad's centre on the XZ plane.

	var quad_defs: Array = [
		# Quad 0 — 0°,   no offset  (NORMAL A)
		[  0.0, Vector2( 0.0,  0.0) ],
		# Quad 1 — 90°,  no offset  (NORMAL B / LUSH centre B)
		[ 90.0, Vector2( 0.0,  0.0) ],
		# Quad 2 — 60°,  no offset  (ROYAL B) / LUSH outer NE at 45°
		[ 60.0, Vector2( 0.0,  0.0) ],
		# Quad 3 — 120°, no offset  (ROYAL C) / LUSH outer NW at 135°
		[120.0, Vector2( 0.0,  0.0) ],
		# Quad 4 — 180°, no offset  / LUSH outer SW at 225°
		[180.0, Vector2( 0.0,  0.0) ],
		# Quad 5 — 270°, no offset  / LUSH outer SE at 315°
		[270.0, Vector2( 0.0,  0.0) ],
	]

	# NOTE: The LUSH outer quad offsets and the WILD random offsets/rotations
	# are applied entirely in the vertex shader at runtime using instance_pos
	# as a deterministic seed. The base mesh bakes in the rotation angles
	# only for NORMAL/ROYAL (quads 0–2). The shader overrides transforms for
	# LUSH quads 2–5 and all WILD quads.

	for qi: int in quad_defs.size():
		var rot_deg : float   = quad_defs[qi][0]
		var offset  : Vector2 = quad_defs[qi][1]
		var base_idx: int     = qi * 4

		var rot_rad: float = deg_to_rad(rot_deg)
		var cos_r: float   = cos(rot_rad)
		var sin_r: float   = sin(rot_rad)

		# Base quad in local space: faces +Z, centred at XZ origin
		# BL, BR, TL, TR  (bottom-left, bottom-right, top-left, top-right)
		var local_verts: Array[Vector3] = [
			Vector3(-QUAD_W, 0.0,    0.0),   # BL
			Vector3( QUAD_W, 0.0,    0.0),   # BR
			Vector3(-QUAD_W, QUAD_H, 0.0),   # TL
			Vector3( QUAD_W, QUAD_H, 0.0),   # TR
		]

		var local_uvs: Array[Vector2] = [
			Vector2(0.0, 1.0),   # BL
			Vector2(1.0, 1.0),   # BR
			Vector2(0.0, 0.0),   # TL
			Vector2(1.0, 0.0),   # TR
		]

		# Rotate around Y axis and apply XZ offset
		for vi: int in 4:
			var lv: Vector3 = local_verts[vi]
			var rx: float =  lv.x * cos_r + lv.z * sin_r
			var rz: float = -lv.x * sin_r + lv.z * cos_r
			verts.append(Vector3(rx + offset.x, lv.y, rz + offset.y))
			normals.append(Vector3(sin_r, 0.0, cos_r))  # normal points along quad face
			uvs.append(local_uvs[vi])

		# Two triangles per quad: BL-BR-TL and BR-TR-TL
		# Winding order: counter-clockwise from front face
		indices.append(base_idx + 0)  # BL
		indices.append(base_idx + 1)  # BR
		indices.append(base_idx + 2)  # TL

		indices.append(base_idx + 1)  # BR
		indices.append(base_idx + 3)  # TR
		indices.append(base_idx + 2)  # TL

	# ── Build ArrayMesh ───────────────────────────────────────────────
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]  = verts
	arrays[Mesh.ARRAY_NORMAL]  = normals
	arrays[Mesh.ARRAY_TEX_UV]  = uvs
	arrays[Mesh.ARRAY_INDEX]   = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# ── Save ──────────────────────────────────────────────────────────
	var err: int = ResourceSaver.save(mesh, OUTPUT_PATH)
	if err == OK:
		print("create_plant_mesh: saved to ", OUTPUT_PATH)
		print("  Vertices : ", verts.size(), " (6 quads × 4)")
		print("  Indices  : ", indices.size(), " (6 quads × 6)")
		print("  Quad 0   : 0°   — NORMAL arm A")
		print("  Quad 1   : 90°  — NORMAL arm B")
		print("  Quad 2   : 60°  — ROYAL arm B")
		print("  Quad 3   : 120° — ROYAL arm C")
		print("  Quad 4   : 180° — LUSH/WILD Q4")
		print("  Quad 5   : 270° — LUSH/WILD Q5")
	else:
		push_error("create_plant_mesh: failed to save — error code %d" % err)
