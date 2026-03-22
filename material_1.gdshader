// NOTE: Shader automatically converted from Godot Engine 4.6.stable.double's StandardMaterial3D.
// Added: wind, entity bending, bend highlight
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

group_uniforms albedo;
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_enable;
uniform ivec2 albedo_texture_size;

group_uniforms alpha;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.001);
uniform float distance_fade_min : hint_range(0.0, 4096.0, 0.01);
uniform float distance_fade_max : hint_range(0.0, 4096.0, 0.01);

group_uniforms surface;
uniform float point_size : hint_range(0.1, 128.0, 0.1);
uniform float roughness : hint_range(0.0, 1.0);
uniform float specular : hint_range(0.0, 1.0, 0.01);
uniform float metallic : hint_range(0.0, 1.0, 0.01);
uniform sampler2D texture_metallic : hint_default_white, filter_nearest, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r, filter_nearest, repeat_enable;

group_uniforms normal;
uniform sampler2D texture_normal : hint_roughness_normal, filter_nearest, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0);

group_uniforms ao;
uniform sampler2D texture_ambient_occlusion : hint_default_white, filter_nearest, repeat_enable;
uniform vec4 ao_texture_channel;
uniform float ao_light_affect : hint_range(0.0, 1.0, 0.01);

group_uniforms heightmap;
uniform sampler2D texture_heightmap : hint_default_black, filter_linear, repeat_enable;
uniform float heightmap_scale : hint_range(-16.0, 16.0, 0.001);
uniform int heightmap_min_layers : hint_range(1, 64);
uniform int heightmap_max_layers : hint_range(1, 64);
uniform vec2 heightmap_flip;

group_uniforms uv;
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

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

group_uniforms;

// --- VARYINGS ---
varying float bend_influence;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;

	// Sway mask — higher vertices move more
	//float sway_mask = clamp(VERTEX.y * 0.3, 0.0, 1.0);
	float sway_mask = clamp(VERTEX.y * 0.3, 0.0, 1.0);

	// Instance origin for bending
	vec3 instance_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// Per-vertex world position for wind variation
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Wind — use per-vertex position so leaves move independently
	vec2 gust_uv = (world_pos.xz * wind_scale) + (TIME * gust_speed * 0.1);
	float gust = texture(wind_noise, gust_uv).r;
	float phase_offset = world_pos.x * 0.3 + world_pos.z * 0.2;
	float base_sway = sin(TIME * wind_speed + phase_offset) * wind_strength;
	vec2 shiver_uv = (world_pos.xz * 0.6) + (TIME * wind_speed * 1.2);
	float shiver = (texture(wind_noise, shiver_uv).r - 0.5) * shiver_strength;
	float wind_offset = (base_sway * gust) + (gust * gust_strength) + shiver;

	// Bending from entities — use instance origin
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

	VERTEX.x += (wind_offset + bend_offset.x) * sway_mask;
	VERTEX.z += (wind_offset + bend_offset.z) * sway_mask;
}

void fragment() {
	vec2 base_uv = UV;
	{
		// Height: Enabled
		vec3 view_dir = normalize(normalize(-VERTEX + EYE_OFFSET) * mat3(TANGENT * heightmap_flip.x, -BINORMAL * heightmap_flip.y, NORMAL));
		float depth = 1.0 - texture(texture_heightmap, base_uv).r;
		vec2 ofs = base_uv - view_dir.xy * depth * heightmap_scale * 0.01;
		base_uv = ofs;
	}
	vec4 albedo_tex = texture(texture_albedo, base_uv);
	// Vertex Color Use as Albedo: Enabled
	albedo_tex *= COLOR;
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	// Bend highlight
	//ALBEDO = mix(ALBEDO, ALBEDO * 1.3, bend_influence * bend_highlight_strength);
	ALBEDO = mix(ALBEDO, ALBEDO * bend_highlight_color.rgb, bend_influence * bend_highlight_strength);
	vec3 e = ALBEDO * bend_highlight_color.rgb * bend_influence * bend_highlight_strength;
    EMISSION = bend_emission_strength * e;
    
	float metallic_tex = dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;
	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;
	// Normal Map: Enabled
	NORMAL_MAP = texture(texture_normal, base_uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	ALPHA *= albedo.a * albedo_tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	// Distance Fade: Pixel Alpha
	ALPHA *= clamp(smoothstep(distance_fade_min, distance_fade_max, length(VERTEX)), 0.0, 1.0);
	// Ambient Occlusion: Enabled
	AO = dot(texture(texture_ambient_occlusion, base_uv), ao_texture_channel);
	AO_LIGHT_AFFECT = ao_light_affect;
}
