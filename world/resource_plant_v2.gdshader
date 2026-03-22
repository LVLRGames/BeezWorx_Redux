// resource_plant.gdshader
// Single-pass MultiMesh shader for all resource plant archetypes.
// One 6-quad mesh. Variant drives per-vertex geometry at runtime.
//
// ── INSTANCE DATA LAYOUT ────────────────────────────────────────────
// INSTANCE_CUSTOM.r = variant×16384 + stem×512 + flower×64 + fruit×8 + stage
//   variant : 0=NORMAL  1=WILD  2=LUSH  3=ROYAL
//   stem    : 0–15  (stem atlas row)
//   flower  : 0–7   (flower atlas layer)
//   fruit   : 0–7   (fruit atlas column)
//   stage   : 0–7
//
// INSTANCE_CUSTOM.g = primary_idx×1024 + secondary_idx×32 + accent_idx
// INSTANCE_CUSTOM.b = leaf_idx×32 + fruit_idx
// INSTANCE_CUSTOM.a = bounce_start_time (world seconds, 0 = no bounce)
// COLOR.r           = thirst (0=hydrated → 1=wilting)
//
// ── BASE MESH TOPOLOGY ──────────────────────────────────────────────
// 6 quads, 4 verts each (24 total), sequential in index buffer.
// All quads: 1 unit wide × 2 units tall, Y=0 at bottom, Y=2 at top.
// Quad index = VERTEX_ID / 4
//
//   Q0  verts  0– 3 :  0°  base arm
//   Q1  verts  4– 7 :  90° base arm
//   Q2  verts  8–11 :  60° baked rotation
//   Q3  verts 12–15 : 120° baked rotation
//   Q4  verts 16–19 : 180° baked rotation
//   Q5  verts 20–23 : 270° baked rotation
//
// ── VARIANT GEOMETRY ────────────────────────────────────────────────
// NORMAL : Q0(0°) + Q1(90°) at centre. Q2–Q5 → scale 0.
//
// ROYAL  : Q0(0°) + Q1(60°) + Q2(120°) at centre. Q3–Q5 → scale 0.
//          60° and 120° match baked rotations in Q1/Q2, so no shader
//          rotation needed — just collapse Q3–Q5.
//          NOTE: The base mesh bakes Q1 at 90°, but ROYAL needs 60°.
//          The shader re-rotates Q1 by -30° (from 90° to 60°) at runtime.
//
// LUSH   : Q0(0°) + Q1(90°) centre cross.
//          Q2–Q5 offset outward at 45°/135°/225°/315°, standing straight.
//          Offset distance = 0.5 units from centre. All 6 quads visible.
//
// WILD   : Q0–Q(N-1) each randomly rotated on Y and offset on XZ.
//          N = 3–6, determined deterministically from instance_pos.
//          Q(N) through Q5 → scale 0.
//          Rotation: full 0–360°.  Offset: 0–0.5 units from centre.
//
// ── ATLAS LAYOUT ────────────────────────────────────────────────────
// All atlases: 8 cols × 16 rows, 16×16 px tiles → 128×256 px.

shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_toon, specular_toon;

// ── Debug ─────────────────────────────────────────────────────────────
group_uniforms debug;
uniform bool debug_mode     = false;
uniform int  debug_variant  = 0;
uniform int  debug_row      = 0;
uniform int  debug_stage    = 0;
uniform int  debug_fruit    = 0;
uniform int  debug_primary  = 0;
uniform int  debug_secondary = 1;
uniform int  debug_accent   = 2;
uniform int  debug_leaf     = 3;
uniform int  debug_fruit_color = 4;

// ── Atlases ───────────────────────────────────────────────────────────
group_uniforms atlases;
uniform sampler2D      stem_atlas   : source_color, filter_nearest, repeat_disable;
uniform sampler2D      flower_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D      fruit_atlas  : source_color, filter_nearest, repeat_disable;

// ── Palette ───────────────────────────────────────────────────────────
group_uniforms palette_settings;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;

// ── Atlas dimensions ──────────────────────────────────────────────────
const float ATLAS_COLS = 8.0;
const float ATLAS_ROWS = 16.0;
const float TILE_U     = 1.0 / ATLAS_COLS;
const float TILE_V     = 1.0 / ATLAS_ROWS;

// ── Stage constant ────────────────────────────────────────────────────
const float STAGE_FRUITING = 4.0;

// ── Variant constants ─────────────────────────────────────────────────
const int VARIANT_NORMAL = 0;
const int VARIANT_WILD   = 1;
const int VARIANT_LUSH   = 2;
const int VARIANT_ROYAL  = 3;

// ── Geometry constants ────────────────────────────────────────────────
const float QUAD_HALF_W   = 1.0;   // half of 1-unit width
const float LUSH_OFFSET   = 1.0;   // XZ offset for outer lush quads
const float WILD_MAX_OFF  = 2.0;   // max XZ offset for wild quads

// ── Wind ──────────────────────────────────────────────────────────────
global uniform float wind_strength;
global uniform float wind_speed;
global uniform float wind_scale;
global uniform float gust_strength;
global uniform float gust_speed;
global uniform float shiver_strength;
global uniform sampler2D wind_noise;

// ── Bending ───────────────────────────────────────────────────────────
group_uniforms Bending;
global uniform sampler2D bender_texture;
global uniform int       bender_count;
global uniform float     bend_radius;
global uniform float     bend_strength;
global uniform vec4      bend_highlight_color;
global uniform float     bend_highlight_strength : hint_range(0.0, 10.0) = 0.66;
uniform float bend_emission_strength : hint_range(0.0, 10.0) = 6.0;

// ── Bounce ────────────────────────────────────────────────────────────
group_uniforms Bounce;
global uniform float bounce_duration;
global uniform float bounce_squash;
global uniform float bounce_stretch;
global uniform float engine_time;

// ── Varying ───────────────────────────────────────────────────────────
varying vec2  v_stem_uv;
varying vec2  v_flower_uv;
varying vec2  v_fruit_uv;
varying float v_stage;
varying float v_primary_idx;
varying float v_secondary_idx;
varying float v_accent_idx;
varying float v_leaf_idx;
varying float v_fruit_color_idx;
varying float bend_influence;

// ══════════════════════════════════════════════════════════════════════ //
//  Helpers
// ══════════════════════════════════════════════════════════════════════ //

vec2 tile_uv(float col, float row, vec2 local_uv) {
	float u = (col + clamp(local_uv.x, 0.001, 0.999)) * TILE_U;
	float v = (row + clamp(local_uv.y, 0.001, 0.999)) * TILE_V;
	return vec2(u, v);
}

vec3 palette_color(float idx) {
	return texelFetch(palette, ivec2(int(idx + 0.5), 0), 0).rgb;
}

// Rotate XZ components of a vec3 around Y axis by angle (radians)
vec3 rot_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

// Deterministic float 0–1 from two integer seeds
float hash2(int a, int b) {
	int h = (a * 92821 + b * 68917) ^ (a * 1237 + 5);
	return float(h & 0xFFFF) / 65535.0;
}

// ══════════════════════════════════════════════════════════════════════ //
//  Variant geometry
//
//  Each function receives:
//    v         — the raw vertex in local mesh space
//    quad_idx  — which quad this vertex belongs to (0–5)
//    seed_a/b  — integer seeds derived from instance_pos for determinism
//
//  Returns the repositioned vertex, or vec3(0) to collapse/hide the quad.
// ══════════════════════════════════════════════════════════════════════ //

vec3 variant_normal(vec3 v, int qi) {
	// Q0: keep as baked (0°)
	// Q1: keep as baked (90°)
	// Q2–Q5: collapse
	if (qi <= 1) return v;
	return vec3(0.0);
}

vec3 variant_royal(vec3 v, int qi) {
	// Q0: 0°   — keep as baked
	// Q1: 60°  — base mesh has this at 90°, rotate back -30°
	// Q2: 120° — base mesh has this at 60°, rotate forward +60°
	// Q3–Q5: collapse
	if (qi == 0) return v;
	if (qi == 1) return rot_y(v, radians(-30.0));  // 90° → 60°
	if (qi == 2) return rot_y(v, radians( 60.0));  // 60° → 120°
	return vec3(0.0);
}

vec3 variant_lush(vec3 v, int qi, int sa, int sb) {
	// Q0: 0°  centre arm — keep
	// Q1: 90° centre arm — keep
	// Q2–Q5: outer quads at 45°/135°/225°/315°, offset 0.5u outward, upright.
	//   The base mesh has Q2–Q5 at 60°/120°/180°/270°.
	//   We re-orient them to 45°/135°/225°/315° and apply the offset.
	if (qi <= 1) return v;

	// Outer quad angles (index maps: qi=2→45°, qi=3→135°, qi=4→225°, qi=5→315°)
	float angle = radians(45.0 + float(qi - 2) * 90.0);

	// Offset direction on XZ
	float ox = cos(angle) * LUSH_OFFSET;
	float oz = sin(angle) * LUSH_OFFSET;

	// Re-orient quad to face outward at its angle, then translate
	// Base mesh Q2–Q5 already have baked rotations — remove them first,
	// then apply the correct lush angle.
	float baked_angles[4];
	baked_angles[0] = radians(60.0);   // Q2 baked
	baked_angles[1] = radians(120.0);  // Q3 baked
	baked_angles[2] = radians(180.0);  // Q4 baked
	baked_angles[3] = radians(270.0);  // Q5 baked

	vec3 unrotated = rot_y(v, -baked_angles[qi - 2]);
	vec3 reoriented = rot_y(unrotated, angle);
	return reoriented + vec3(ox, 0.0, oz);
}

vec3 variant_wild(vec3 v, int qi, int sa, int sb) {
	// N = 3–6 visible quads, determined by hash of instance seed.
	// First N quads (Q0 through Q(N-1)) are visible with random rot+offset.
	// Q(N) through Q5 are collapsed.

	// Derive N from seed: hash → 0–1 → remap to 3–6
	float n_f = hash2(sa, sb + 9991);
	int n = 3 + int(n_f * 3.999);  // 3, 4, 5, or 6

	if (qi >= n) return vec3(0.0);

	// Each quad gets its own random rotation and XZ offset
	int qi_seed_a = sa + qi * 1337;
	int qi_seed_b = sb + qi * 7919;

	float rot_angle = hash2(qi_seed_a, qi_seed_b) * TAU;
	float off_dist  = hash2(qi_seed_a + 1, qi_seed_b + 1) * WILD_MAX_OFF;
	float off_angle = hash2(qi_seed_a + 2, qi_seed_b + 2) * TAU;

	float ox = cos(off_angle) * off_dist;
	float oz = sin(off_angle) * off_dist;

	// Remove baked rotation from base mesh, apply random rotation
	float baked[6];
	baked[0] = 0.0;
	baked[1] = radians(90.0);
	baked[2] = radians(60.0);
	baked[3] = radians(120.0);
	baked[4] = radians(180.0);
	baked[5] = radians(270.0);

	vec3 unrotated  = rot_y(v, -baked[qi]);
	vec3 reoriented = rot_y(unrotated, rot_angle);
	return reoriented + vec3(ox, 0.0, oz);
}

// ══════════════════════════════════════════════════════════════════════ //
//  Vertex
// ══════════════════════════════════════════════════════════════════════ //
void vertex() {
	// ── Unpack INSTANCE_CUSTOM.r ───────────────────────────────────────
	float packed_r    = INSTANCE_CUSTOM.r;
	float variant_f   = floor(packed_r / 16384.0);
	float remainder   = packed_r - variant_f * 16384.0;
	float stem_row    = floor(remainder / 512.0);
	remainder         = remainder - stem_row * 512.0;
	float flower_layer = floor(remainder / 64.0);
	remainder         = remainder - flower_layer * 64.0;
	float fruit_col   = floor(remainder / 8.0);
	float stage       = remainder - fruit_col * 8.0;
	int   variant     = int(variant_f + 0.5);

	// ── Unpack INSTANCE_CUSTOM.g ───────────────────────────────────────
	float packed_g  = INSTANCE_CUSTOM.g;
	float primary   = floor(packed_g / 1024.0);
	float r2        = packed_g - primary * 1024.0;
	float secondary = floor(r2 / 32.0);
	float accent    = r2 - secondary * 32.0;

	// ── Unpack INSTANCE_CUSTOM.b ───────────────────────────────────────
	float packed_b    = INSTANCE_CUSTOM.b;
	float leaf        = floor(packed_b / 32.0);
	float fruit_color = packed_b - leaf * 32.0;

	// ── Debug overrides ────────────────────────────────────────────────
	if (debug_mode) {
		variant      = debug_variant;
		stage        = float(debug_stage);
		stem_row     = float(debug_row);
		fruit_col    = float(debug_fruit);
		primary      = float(debug_primary);
		secondary    = float(debug_secondary);
		accent       = float(debug_accent);
		leaf         = float(debug_leaf);
		fruit_color  = float(debug_fruit_color);
	}

	// ── Pass to fragment ───────────────────────────────────────────────
	v_stage           = stage;
	v_primary_idx     = primary;
	v_secondary_idx   = secondary;
	v_accent_idx      = accent;
	v_leaf_idx        = leaf;
	v_fruit_color_idx = fruit_color;

	float stage_col = stage;
	v_stem_uv    = tile_uv(stage_col, stem_row, UV);
	v_flower_uv = tile_uv(stage_col, stem_row, UV);
	v_fruit_uv   = tile_uv(fruit_col, stem_row, UV);

	// ── Quad index from vertex index ───────────────────────────────────
	int quad_idx = VERTEX_ID / 4;

	// ── Instance position as deterministic seed ────────────────────────
	vec3 instance_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	int seed_a = int(instance_pos.x * 100.0);
	int seed_b = int(instance_pos.z * 100.0);

	// ── Apply variant geometry ─────────────────────────────────────────
	vec3 v = VERTEX;
	if (variant == VARIANT_NORMAL) {
		v = variant_normal(v, quad_idx);
	} else if (variant == VARIANT_ROYAL) {
		v = variant_royal(v, quad_idx);
	} else if (variant == VARIANT_LUSH) {
		v = variant_lush(v, quad_idx, seed_a, seed_b);
	} else {
		v = variant_wild(v, quad_idx, seed_a, seed_b);
	}
	VERTEX = v;

	// ── Sway mask (height-based) ───────────────────────────────────────
	float height_t = clamp(VERTEX.y / 4.0, 0.0, 1.0);
	height_t = height_t * height_t;

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// ── Wind ───────────────────────────────────────────────────────────
	vec2 gust_uv    = (instance_pos.xz * wind_scale) + (TIME * gust_speed * 0.1);
	float gust      = texture(wind_noise, gust_uv).r;
	float phase_off = instance_pos.x * 0.3 + instance_pos.z * 0.2;
	float base_sway = sin(TIME * wind_speed + phase_off) * wind_strength;
	vec2 shiver_uv  = (instance_pos.xz * 0.6) + (TIME * wind_speed * 1.2);
	float shiver    = (texture(wind_noise, shiver_uv).r - 0.5) * shiver_strength;
	float wind_offset = (base_sway * gust) + (gust * gust_strength) + shiver;

	// ── Bending ────────────────────────────────────────────────────────
	vec3  bend_offset    = vec3(0.0);
	float total_influence = 0.0;
	int count = min(bender_count, textureSize(bender_texture, 0).x);
	for (int i = 0; i < count; i++) {
		vec3  bender_pos = texelFetch(bender_texture, ivec2(i, 0), 0).rgb;
		vec3  to_vert    = instance_pos - bender_pos;
		float dist_xz    = length(to_vert.xz);
		float dist_y     = abs(to_vert.y);
		if (dist_xz < bend_radius && dist_y < bend_radius && dist_xz > 0.01) {
			float influence = 1.0 - (dist_xz / bend_radius);
			float y_fade    = 1.0 - (dist_y / bend_radius);
			influence       = influence * influence * y_fade;
			vec2 push_dir   = normalize(to_vert.xz);
			bend_offset.x  += push_dir.x * influence * bend_strength;
			bend_offset.z  += push_dir.y * influence * bend_strength;
			total_influence  = max(total_influence, influence);
		}
	}
	bend_influence = total_influence;

	// ── Apply wind + bend ──────────────────────────────────────────────
	VERTEX.x += (wind_offset + bend_offset.x) * height_t;
	VERTEX.z += (wind_offset + bend_offset.z) * height_t;

	// ── Bounce ─────────────────────────────────────────────────────────
	float bounce_start = INSTANCE_CUSTOM.a;
	float bounce_val   = 0.0;
	if (bounce_start > 0.0) {
		float elapsed = engine_time - bounce_start;
		if (elapsed > 0.0 && elapsed < bounce_duration) {
			float t      = elapsed / bounce_duration;
			bounce_val   = exp(-4.0 * t) * sin(t * 15.0);
		}
	}
	VERTEX.y *= 1.0 + bounce_val * bounce_squash;
	VERTEX.x *= 1.0 - bounce_val * bounce_stretch;
	VERTEX.z *= 1.0 - bounce_val * bounce_stretch;
}

// ══════════════════════════════════════════════════════════════════════ //
//  Fragment  (unchanged from original)
// ══════════════════════════════════════════════════════════════════════ //
void fragment() {
	vec3 col_primary   = palette_color(v_primary_idx);
	vec3 col_secondary = palette_color(v_secondary_idx);
	vec3 col_accent    = palette_color(v_accent_idx);
	vec3 col_leaf      = palette_color(v_leaf_idx);
	vec3 col_fruit     = palette_color(v_fruit_color_idx);

	vec4 stem_sample   = texture(stem_atlas,   v_stem_uv);
	vec4 flower_sample = texture(flower_atlas, v_flower_uv);
	vec4 fruit_sample  = texture(fruit_atlas,  v_fruit_uv);

	vec3  stem_rgb = stem_sample.rgb * col_leaf;
	float stem_a   = stem_sample.a;

	vec3 flower_rgb =
		flower_sample.r * col_primary   +
		flower_sample.g * col_accent    +
		flower_sample.b * col_secondary;
	float flower_a = flower_sample.a;

	float is_fruiting = step(STAGE_FRUITING - 0.5, floor(v_stage + 0.5)) *
	                    step(floor(v_stage + 0.5), STAGE_FRUITING + 0.5);
	vec3  fruit_rgb   = fruit_sample.rgb * col_fruit;
	float fruit_a     = fruit_sample.a * is_fruiting;

	vec3  out_rgb = stem_rgb;
	float out_a   = stem_a;

	out_rgb = flower_rgb * flower_a + out_rgb * (1.0 - flower_a);
	out_a   = flower_a   + out_a   * (1.0 - flower_a);

	out_rgb = fruit_rgb * fruit_a + out_rgb * (1.0 - fruit_a);
	out_a   = fruit_a   + out_a   * (1.0 - fruit_a);

	if (out_a < 0.1) discard;

	float thirst     = COLOR.r;
	float luminance  = dot(out_rgb, vec3(0.299, 0.587, 0.114));
	out_rgb = mix(out_rgb, vec3(luminance), thirst * 0.8);

	vec3 e = out_rgb * bend_highlight_color.rgb * bend_influence * bend_highlight_strength;

	EMISSION  = bend_emission_strength * e;
	ALBEDO    = out_rgb;
	ALPHA     = out_a;
	ROUGHNESS = 0.85;
	METALLIC  = 0.0;
}
