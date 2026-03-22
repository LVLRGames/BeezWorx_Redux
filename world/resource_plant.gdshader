// resource_plant.gdshader
// Single-pass MultiMesh shader for all resource plant archetypes.
// Quad layout is reconfigured per-vertex based on plant variant.
//
// ── INSTANCE DATA LAYOUT ────────────────────────────────────────────
// INSTANCE_CUSTOM.r = variant×16384 + stem×512 + flower×64 + fruit×8 + stage
//   variant : 0=NORMAL, 1=WILD, 2=LUSH, 3=ROYAL
//   stem    : 0–15  (stem atlas row)
//   flower  : 0–7   (flower atlas layer)
//   fruit   : 0–7   (fruit atlas column)
//   stage   : 0–7   (HexWorldState.Stage)
//
// INSTANCE_CUSTOM.g = primary_idx×1024 + secondary_idx×32 + accent_idx
// INSTANCE_CUSTOM.b = leaf_idx×32 + fruit_idx
// INSTANCE_CUSTOM.a = bounce_start_time (world seconds, 0.0 = no bounce)
// COLOR.r           = thirst (0=hydrated, 1=wilting)
//
// ── MESH TOPOLOGY ────────────────────────────────────────────────────
// Base mesh: 6 quads (24 vertices, 36 indices), all unit quads centred
// at origin in the XY plane. Each quad is identified by vertex index
// range (4 verts per quad):
//
//   Quad 0 (verts  0– 3): primary cross arm  — used by ALL variants
//   Quad 1 (verts  4– 7): perpendicular arm  — NORMAL, LUSH, WILD
//   Quad 2 (verts  8–11): tri-cross third arm — ROYAL only
//   Quad 3 (verts 12–15): lush extra A        — LUSH only
//   Quad 4 (verts 16–19): lush extra B        — LUSH only
//   Quad 5 (verts 20–23): wild scatter        — WILD only (repositioned)
//
// Quads not belonging to the active variant are collapsed to zero scale.
//
// ── VARIANT QUAD CONFIGURATIONS ─────────────────────────────────────
// NORMAL  (0): Q0+Q1 crossed at 90°. Standard cross-quad.
// WILD    (1): Q0+Q1+Q5 with random rotations/offsets. Irregular cluster.
// LUSH    (2): Q0+Q1+Q3+Q4 with Q3/Q4 offset outward. Fuller bush.
// ROYAL   (3): Q0+Q1+Q2 at 120° spacing. Symmetric tri-cross.
//
// ── PALETTE ─────────────────────────────────────────────────────────
// 32×1 pixel texture. Index 0–27 = hue wheel, 28–31 = neutrals.
//
// ── ATLAS LAYOUT ────────────────────────────────────────────────────
// All atlases: 8 columns × 16 rows, 16×16 px tiles → 128×256 px.

shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_toon, specular_toon;

// ── Debug ─────────────────────────────────────────────────────────────
group_uniforms debug;
uniform bool debug_mode = false;
uniform int debug_variant  = 0;
uniform int debug_row      = 0;
uniform int debug_stage    = 0;
uniform int debug_fruit    = 0;
uniform int debug_primary  = 0;
uniform int debug_secondary = 1;
uniform int debug_accent   = 2;
uniform int debug_leaf     = 3;
uniform int debug_fruit_color = 4;

// ── Atlases ───────────────────────────────────────────────────────────
group_uniforms atlases;
uniform sampler2D      stem_atlas   : source_color, filter_nearest, repeat_disable;
uniform sampler2DArray flower_atlas : source_color, filter_nearest, repeat_disable;
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
varying vec3  v_flower_uvw;
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

float bounce_curve(float t) {
	float decay  = exp(-4.0 * t);
	float wobble = sin(t * 15.0);
	return decay * wobble;
}

// Rotate a 2D vector by angle (radians)
vec2 rot2(vec2 v, float a) {
	float c = cos(a); float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Deterministic hash → float 0–1 from ivec2 seed
float hash21(ivec2 seed) {
	int h = (seed.x * 92821 + seed.y * 68917) ^ (seed.x * 1237 + 5);
	return float(h & 0xFFFF) / 65535.0;
}

// ══════════════════════════════════════════════════════════════════════ //
//  Variant geometry
//
//  Each function takes the raw VERTEX (local space, base mesh pose) and
//  the quad index (0–5), and returns the repositioned vertex.
//  Quads not active for a variant are collapsed to vec3(0) — they become
//  degenerate triangles and are discarded by the rasteriser.
//
//  Instance position is used as a deterministic seed for WILD offsets.
// ══════════════════════════════════════════════════════════════════════ //

vec3 apply_normal_variant(vec3 v, int quad_idx) {
	// Q0: keep as-is (0° arm)
	// Q1: rotate 90° (perpendicular arm)
	// Q2,Q3,Q4,Q5: collapse
	if (quad_idx == 0) return v;
	if (quad_idx == 1) {
		vec2 xz = rot2(v.xz, PI * 0.5);
		return vec3(xz.x, v.y, xz.y);
	}
	return vec3(0.0);
}

vec3 apply_royal_variant(vec3 v, int quad_idx) {
	// Three arms at 0°, 120°, 240° — symmetric tri-cross.
	// Q0: 0°, Q1: 120°, Q2: 240°. Q3,Q4,Q5: collapse.
	if (quad_idx == 0) return v;
	if (quad_idx == 1) {
		vec2 xz = rot2(v.xz, PI * 2.0 / 3.0);
		return vec3(xz.x, v.y, xz.y);
	}
	if (quad_idx == 2) {
		vec2 xz = rot2(v.xz, PI * 4.0 / 3.0);
		return vec3(xz.x, v.y, xz.y);
	}
	return vec3(0.0);
}

vec3 apply_lush_variant(vec3 v, int quad_idx, vec3 instance_pos) {
	// Q0: 0° arm. Q1: 90° arm. Q3+Q4: extra quads offset outward and tilted.
	// Q2,Q5: collapse.
	ivec2 seed = ivec2(int(instance_pos.x * 10.0), int(instance_pos.z * 10.0));

	if (quad_idx == 0) return v;
	if (quad_idx == 1) {
		vec2 xz = rot2(v.xz, PI * 0.5);
		return vec3(xz.x, v.y, xz.y);
	}
	if (quad_idx == 3) {
		// Offset ~45° outward, slight tilt inward
		float angle = PI * 0.25 + hash21(seed) * PI * 0.5;
		float dist  = 0.25 + hash21(seed + ivec2(1, 0)) * 0.15;
		vec2 xz = rot2(v.xz, angle);
		xz += vec2(cos(angle), sin(angle)) * dist;
		return vec3(xz.x, v.y * 0.9, xz.y);
	}
	if (quad_idx == 4) {
		float angle = PI * 1.25 + hash21(seed + ivec2(0, 1)) * PI * 0.5;
		float dist  = 0.25 + hash21(seed + ivec2(1, 1)) * 0.15;
		vec2 xz = rot2(v.xz, angle);
		xz += vec2(cos(angle), sin(angle)) * dist;
		return vec3(xz.x, v.y * 0.9, xz.y);
	}
	return vec3(0.0);
}

vec3 apply_wild_variant(vec3 v, int quad_idx, vec3 instance_pos) {
	// Q0: anchored cross arm. Q1: rotated arm. Q5: scattered at random offset.
	// Q2,Q3,Q4: collapse.
	ivec2 seed = ivec2(int(instance_pos.x * 10.0 + float(quad_idx) * 7.3),
	                   int(instance_pos.z * 10.0 + float(quad_idx) * 3.7));

	if (quad_idx == 0) {
		float rot = hash21(seed) * PI * 2.0;
		vec2 xz = rot2(v.xz, rot);
		return vec3(xz.x, v.y, xz.y);
	}
	if (quad_idx == 1) {
		float rot = hash21(seed + ivec2(2, 0)) * PI * 2.0;
		vec2 xz = rot2(v.xz, rot);
		return vec3(xz.x, v.y, xz.y);
	}
	if (quad_idx == 5) {
		// Random scatter: offset + rotation + slight scale variation
		float rot    = hash21(seed + ivec2(0, 3)) * PI * 2.0;
		float off_x  = (hash21(seed + ivec2(1, 2)) - 0.5) * 0.6;
		float off_z  = (hash21(seed + ivec2(3, 1)) - 0.5) * 0.6;
		float scale  = 0.7 + hash21(seed + ivec2(2, 2)) * 0.4;
		vec2 xz = rot2(v.xz * scale, rot);
		xz += vec2(off_x, off_z);
		return vec3(xz.x, v.y * scale, xz.y);
	}
	return vec3(0.0);
}

// ══════════════════════════════════════════════════════════════════════ //
//  Vertex
// ══════════════════════════════════════════════════════════════════════ //
void vertex() {
	// ── Unpack INSTANCE_CUSTOM.r ───────────────────────────────────────
	float packed_r   = INSTANCE_CUSTOM.r;
	float variant_f  = floor(packed_r / 16384.0);
	float remainder  = packed_r - variant_f * 16384.0;
	float stem_row   = floor(remainder / 512.0);
	remainder        = remainder - stem_row * 512.0;
	float flower_layer = floor(remainder / 64.0);
	remainder        = remainder - flower_layer * 64.0;
	float fruit_col  = floor(remainder / 8.0);
	float stage      = remainder - fruit_col * 8.0;
	int   variant    = int(variant_f + 0.5);

	// ── Unpack INSTANCE_CUSTOM.g ───────────────────────────────────────
	float packed_g  = INSTANCE_CUSTOM.g;
	float primary   = floor(packed_g / 1024.0);
	float r2        = packed_g - primary * 1024.0;
	float secondary = floor(r2 / 32.0);
	float accent    = r2 - secondary * 32.0;

	// ── Unpack INSTANCE_CUSTOM.b ───────────────────────────────────────
	float packed_b  = INSTANCE_CUSTOM.b;
	float leaf       = floor(packed_b / 32.0);
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
	v_flower_uvw = vec3(tile_uv(stage_col, stem_row, UV), flower_layer);
	v_fruit_uv   = tile_uv(fruit_col, stem_row, UV);

	// ── Determine quad index from vertex index ─────────────────────────
	// 4 vertices per quad, sequential in the index buffer.
	int quad_idx = VERTEX_ID / 4;

	// ── Instance world position (used for deterministic wild/lush offsets)
	vec3 instance_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// ── Apply variant geometry ─────────────────────────────────────────
	vec3 v = VERTEX;
	if (variant == VARIANT_NORMAL) {
		v = apply_normal_variant(v, quad_idx);
	} else if (variant == VARIANT_ROYAL) {
		v = apply_royal_variant(v, quad_idx);
	} else if (variant == VARIANT_LUSH) {
		v = apply_lush_variant(v, quad_idx, instance_pos);
	} else { // WILD
		v = apply_wild_variant(v, quad_idx, instance_pos);
	}
	VERTEX = v;

	// ── Sway mask (height-based, computed after variant transform) ─────
	float height_t = clamp(VERTEX.y / 1.0, 0.0, 1.0);
	height_t = height_t * height_t;

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// ── Wind ───────────────────────────────────────────────────────────
	vec2 gust_uv   = (world_pos.xz * wind_scale) + (TIME * gust_speed * 0.1);
	float gust     = texture(wind_noise, gust_uv).r;
	float phase_off = world_pos.x * 0.3 + world_pos.z * 0.2;
	float base_sway = sin(TIME * wind_speed + phase_off) * wind_strength;
	vec2 shiver_uv  = (world_pos.xz * 0.6) + (TIME * wind_speed * 1.2);
	float shiver    = (texture(wind_noise, shiver_uv).r - 0.5) * shiver_strength;
	float wind_offset = (base_sway * gust) + (gust * gust_strength) + shiver;

	// ── Bending ────────────────────────────────────────────────────────
	vec3 bend_offset = vec3(0.0);
	float total_influence = 0.0;
	int count = min(bender_count, textureSize(bender_texture, 0).x);
	for (int i = 0; i < count; i++) {
		vec3 bender_pos = texelFetch(bender_texture, ivec2(i, 0), 0).rgb;
		vec3 to_vert    = instance_pos - bender_pos;
		float dist_xz   = length(to_vert.xz);
		float dist_y    = abs(to_vert.y);
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

	// ── Apply wind + bend displacement ─────────────────────────────────
	VERTEX.x += (wind_offset + bend_offset.x) * height_t;
	VERTEX.z += (wind_offset + bend_offset.z) * height_t;

	// ── Bounce ─────────────────────────────────────────────────────────
	float bounce_start = INSTANCE_CUSTOM.a;
	float bounce_val   = 0.0;
	if (bounce_start > 0.0) {
		float elapsed = engine_time - bounce_start;
		if (elapsed > 0.0 && elapsed < bounce_duration) {
			float t   = elapsed / bounce_duration;
			float decay  = exp(-4.0 * t);
			float wobble = sin(t * 15.0);
			bounce_val   = decay * wobble;
		}
	}
	float squash_factor  = 1.0 + bounce_val * bounce_squash;
	float stretch_factor = 1.0 - bounce_val * bounce_stretch;
	VERTEX.y *= squash_factor;
	VERTEX.x *= stretch_factor;
	VERTEX.z *= stretch_factor;
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
	vec4 flower_sample = texture(flower_atlas, v_flower_uvw);
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
	out_a   = flower_a + out_a * (1.0 - flower_a);

	out_rgb = fruit_rgb * fruit_a + out_rgb * (1.0 - fruit_a);
	out_a   = fruit_a + out_a * (1.0 - fruit_a);

	if (out_a < 0.1) discard;

	float thirst     = COLOR.r;
	float luminance  = dot(out_rgb, vec3(0.299, 0.587, 0.114));
	vec3 desaturated = vec3(luminance);
	out_rgb = mix(out_rgb, desaturated, thirst * 0.8);

	vec3 e = out_rgb * bend_highlight_color.rgb * bend_influence * bend_highlight_strength;

	EMISSION  = bend_emission_strength * e;
	ALBEDO    = out_rgb;
	ALPHA     = out_a;
	ROUGHNESS = 0.85;
	METALLIC  = 0.0;
}
