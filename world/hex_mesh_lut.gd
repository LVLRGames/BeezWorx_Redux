# hex_mesh_lut.gd
# Static mesh Look-Up Table for hex terrain.
#
# A hex has 6 edges; each can be FLUSH (neighbor same/higher height) or
# SKIRT (this hex is taller → draw a downward wall face on that edge).
# That gives 2^6 = 64 canonical configurations.
#
# For each of the 64 configs we also bake 6 ramp variants (one per edge),
# giving 64 * 6 = 384 extra entries.  A ramp replaces the skirt on its edge
# with an outward-sloping quad bridging to the lower neighbour.
#
# WHAT IS STORED
# ──────────────
# The LUT stores index *patterns* — compact arrays that the mesh builder
# stamps actual world-space vertices into at draw-time.  No geometry math
# happens inside the LUT; it only answers "which triangles do I need, and
# in what order should I reference the pre-computed corner / neighbour data?"
#
# VERTEX SLOTS
# ─────────────
# Each hex has a fixed pool of named vertex slots.  All positions are
# computed by HexChunk and passed as a PackedVector3Array:
#
#   slots[0]  = hex centre          (y = h)
#   slots[1…6]= 6 flat-top corners  (y = h), index i = corner i
#   slots[7…12]= 6 corners stepped  (y = h - HEIGHT_STEP), for skirts
#   slots[13…18]= 6 ramp outer verts (y = low neighbour h), for ramps
#               13 = ramp centre of neighbour hex
#               14…19 = 2 outer corners per ramp edge (varies per config)
#
# In practice HexChunk fills this array once per hex and then the LUT
# index lists are used as indices into it via PackedInt32Array.
#
# TRIANGLE WINDING
# ─────────────────
# All triangles are wound counter-clockwise when viewed from above.

class_name HexMeshLUT
extends RefCounted

# ── Flat-top corner angles (edge i is between corner i and corner (i+1)%6) ──
# Corner i angle (degrees, -30 offset for flat-top):  60*i - 30
# We don't store angles here — they are computed once in HexChunk._init.

# ── Slot index constants ─────────────────────────────────────────────
const SLOT_CENTER   := 0           # hex centre
const SLOT_C0       := 1           # corner 0
const SLOT_C1       := 2
const SLOT_C2       := 3
const SLOT_C3       := 4
const SLOT_C4       := 5
const SLOT_C5       := 6
# Skirt lower-row corners — same XZ as corners, but y = h - HEIGHT_STEP
const SLOT_S0       := 7           # skirt bottom for corner 0 side
const SLOT_S1       := 8
const SLOT_S2       := 9
const SLOT_S3       := 10
const SLOT_S4       := 11
const SLOT_S5       := 12
# Ramp outer vertices — 2 per edge (far corners of neighbour hex projected)
# Plus the neighbour hex centre.  Layout per ramp edge e:
#   SLOT_R_BASE + e*3 + 0  = neighbour centre (at low_y)
#   SLOT_R_BASE + e*3 + 1  = left  outer corner of neighbour at that edge
#   SLOT_R_BASE + e*3 + 2  = right outer corner of neighbour at that edge
const SLOT_R_BASE   := 13          # 13 … 30  (6 edges × 3 slots = 18)

# ── LUT storage ─────────────────────────────────────────────────────
# key   = config_key(skirt_mask, ramp_edge)
#         skirt_mask: int 0…63 (bit i = edge i has a skirt)
#         ramp_edge:  int -1 = no ramp, 0…5 = ramp on that edge
# value = PackedInt32Array of slot indices forming triangles (triplets)
var table: Dictionary = {}

# ── Build ────────────────────────────────────────────────────────────
func _init() -> void:
	_build_table()

static func config_key(skirt_mask: int, ramp_edge: int) -> int:
	# Pack into a single int: upper 8 bits = skirt_mask, lower 8 = ramp_edge+1
	return (skirt_mask << 8) | (ramp_edge + 1)

func _build_table() -> void:
	for mask in 64:
		# No-ramp variant
		table[config_key(mask, -1)] = _build_indices(mask, -1)
		# Ramp variants — only meaningful when that edge is in the skirt mask
		for edge in 6:
			if mask & (1 << edge):
				table[config_key(mask, edge)] = _build_indices(mask, edge)

func _build_indices(skirt_mask: int, ramp_edge: int) -> PackedInt32Array:
	var idx := PackedInt32Array()

	# ── Top face: 6 triangles fan from centre ──────────────────────
	for i in 6:
		idx.append(SLOT_CENTER)
		idx.append(SLOT_C0 + i)
		idx.append(SLOT_C0 + (i + 1) % 6)

	# ── Per-edge: skirt or ramp ────────────────────────────────────
	for e in 6:
		if not (skirt_mask & (1 << e)):
			continue  # flush edge — nothing to draw

		var ca := SLOT_C0 + e              # corner A (top-left of edge)
		var cb := SLOT_C0 + (e + 1) % 6   # corner B (top-right of edge)
		var sa := SLOT_S0 + e
		var sb := SLOT_S0 + (e + 1) % 6

		if e == ramp_edge:
			# Ramp: three triangles spanning from edge corners to the
			# projected neighbour-hex low-Y positions.
			# Slot layout for this edge:
			#   rc  = SLOT_R_BASE + e*3 + 0   (neighbour centre, low_y)
			#   rl  = SLOT_R_BASE + e*3 + 1   (outer left,  low_y)
			#   rr  = SLOT_R_BASE + e*3 + 2   (outer right, low_y)
			var rc := SLOT_R_BASE + e * 3 + 0
			var rl := SLOT_R_BASE + e * 3 + 1
			var rr := SLOT_R_BASE + e * 3 + 2
			# Triangle 1: centre–A side
			idx.append(rc); idx.append(ca); idx.append(rr)
			# Triangle 2: centre–centre
			idx.append(ca); idx.append(rc); idx.append(cb)
			# Triangle 3: centre–B side
			idx.append(rl); idx.append(cb); idx.append(rc)
		else:
			# Standard skirt quad (2 triangles, can stack multiple HEIGHT_STEPs)
			# We only encode one step here.  HexChunk loops and re-uses the
			# same skirt pattern by sliding sa/sb down by HEIGHT_STEP each pass.
			# For the LUT we store the single-step pattern; HexChunk drives
			# the loop.
			idx.append(ca); idx.append(sa); idx.append(sb)
			idx.append(ca); idx.append(sb); idx.append(cb)

	return idx

# ── Convenience lookup ───────────────────────────────────────────────
## Returns the index array for the given config, or null if not found.
## skirt_mask: bit i set means edge i needs a skirt/ramp.
## ramp_edge:  -1 for no ramp, 0…5 for a ramp on that edge.
func get_indices(skirt_mask: int, ramp_edge: int) -> PackedInt32Array:
	var key := config_key(skirt_mask, ramp_edge)
	if table.has(key):
		return table[key]
	# Fallback: no ramp, plain skirt
	return table[config_key(skirt_mask, -1)]
