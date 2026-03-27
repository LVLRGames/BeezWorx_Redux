shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_toon;

// --- ATLAS SETTINGS ---
uniform vec2 atlas_pixel_size = vec2(64.0, 256.0);
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform sampler2D grass_atlas : filter_nearest_mipmap, repeat_disable;

group_uniforms wind;
global uniform sampler2D wind_noise : repeat_enable;
global uniform float wind_speed : hint_range(0.0, 5.0) = 0.8;
global uniform float wind_strength : hint_range(0.0, 1.0) = 0.08;
global uniform float wind_scale : hint_range(0.0, 1.0) = 0.03;
global uniform float gust_strength : hint_range(0.0, 1.0) = 0.2;
global uniform float gust_speed : hint_range(0.0, 5.0) = 0.3;
global uniform float shiver_strength : hint_range(0.0, 1.0) = 0.03;

group_uniforms bending;
global uniform int bender_count : hint_range(0, 8) = 0;
global uniform sampler2D bender_texture: filter_nearest;
global uniform float bend_radius : hint_range(0.1, 20.0) = 5.0;
global uniform float bend_strength : hint_range(0.0, 2.0) = 0.5;
global uniform vec4 bend_highlight_color : source_color;
global uniform float bend_highlight_strength : hint_range(0.0, 1.0) = 0.66;
uniform float bend_emission_strength : hint_range(0.0, 10.0) = 6.0;

// Bridge data between vertex and fragment functions
varying vec2 custom_data;
varying float sway_mask;
varying float bend_influence;


void vertex() {
    sway_mask = 1.0 - UV.y; 

    // 1. TILE LOGIC
    custom_data = INSTANCE_CUSTOM.xy;
    vec2 tile_size = vec2(0.25, 0.0625);
    vec2 tile_offset = vec2(custom_data.x * 0.25, custom_data.y * 0.0625);
    UV = (UV * tile_size) + tile_offset;

    // 2. GET UNIQUE INSTANCE POSITION
    // MODEL_MATRIX[3].xyz gives the world position of each individual grass blade
    vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

    // 3. LAYERED WIND WITH VARIANCE
    // Use world_pos.xz instead of NODE_POSITION_WORLD to break the unison
    vec2 gust_uv = (world_pos.xz * wind_scale) + (TIME * gust_speed * 0.1);
    float gust = texture(wind_noise, gust_uv).r;
    
    // Add a unique phase offset for each blade's sin wave based on its ID or Position
    float phase_offset = world_pos.x * 0.5 + world_pos.z * 0.3;
    float base_sway = sin(TIME * wind_speed + phase_offset) * wind_strength;
    
    // Shiver layer with a unique offset so they don't all vibrate together
    vec2 shiver_uv = (world_pos.xz * 0.8) + (TIME * wind_speed * 1.5);
    float shiver = (texture(wind_noise, shiver_uv).r - 0.5) * shiver_strength;

    float final_sway = (base_sway * gust) + (gust * gust_strength) + shiver;

	// 5. GRASS BENDING FROM ENTITIES
    vec3 bend_offset = vec3(0.0);
    float total_influence = 0.0;
    int count = min(bender_count, textureSize(bender_texture, 0).x);
    for (int i = 0; i < count; i++) {
        vec3 bender_pos = texelFetch(bender_texture, ivec2(i, 0), 0).rgb;
        vec3 to_vert = world_pos - bender_pos;
        float dist_xz = length(to_vert.xz);
        float dist_y = abs(to_vert.y);
        if (dist_xz < bend_radius && dist_y < bend_radius && dist_xz > 0.01) {
            float influence = 1.0 - (dist_xz / bend_radius);
            float y_fade = 1.0 - (dist_y / bend_radius);
            influence = influence * influence * y_fade;
            vec2 push_dir = normalize(to_vert.xz);
            bend_offset.x += push_dir.x * influence * bend_strength;
            bend_offset.z += push_dir.y * influence * bend_strength;
            total_influence = max(total_influence, influence);
        }
    }
    bend_influence = total_influence;
    
    VERTEX.x += (final_sway + bend_offset.x) * sway_mask;
    VERTEX.z += (final_sway + bend_offset.z) * sway_mask;
    VERTEX.y += bend_offset.y * sway_mask;
}


void fragment() {
    // 1. RECALCULATE TILE BOUNDS (for precision clamping)
    vec2 tile_size = vec2(0.25, 0.0625);
    vec2 tile_offset = vec2(custom_data.x * 0.25, custom_data.y * 0.0625);
    
    // 2. ANTI-BLEED CLAMP
    // Forces the sampler to stay 0.5 pixels away from neighbor tiles
    vec2 pixel_size = 1.0 / atlas_pixel_size;
    vec2 low_bound = tile_offset + (pixel_size * 0.5);
    vec2 high_bound = tile_offset + tile_size - (pixel_size * 0.5);
    vec2 clamped_uv = clamp(UV, low_bound, high_bound);

    // 3. TEXTURE & COLOR
    vec4 tex = texture(grass_atlas, clamped_uv);
    ALBEDO = tex.rgb * COLOR.rgb - 0.15;
	vec3 e = ALBEDO * bend_highlight_color.rgb * bend_influence * bend_highlight_strength;
    EMISSION = bend_emission_strength * e;
    
    if (tex.a < 0.5) {
        discard;
    }
    
    // Simple upward normal for consistent lighting on flat planes
    NORMAL = vec3(0.0, 1.0, 0.0);
}
