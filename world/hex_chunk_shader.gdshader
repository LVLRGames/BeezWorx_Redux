shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform float tint_noise_scale = 0.05;
uniform sampler2D tint_noise : filter_nearest; // Prevents "blurring" between tiles
uniform sampler2D atlas_texture : filter_nearest_mipmap, repeat_disable; // Prevents "blurring" between tiles
uniform float emission_strength : hint_range(0.0, 1.0) = 0.0;

varying vec2 wuv;

void vertex() {
	wuv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec4 tex = texture(atlas_texture, UV);
	vec4 nsx = texture(tint_noise, wuv * tint_noise_scale);
	ALBEDO = mix(tex , tex - 0.15 , nsx).rgb;
	//ALPHA = tex.a;
	
	// Optional: Slight emission if you want the colors to pop
	//EMISSION = ALBEDO * emission_strength;
}
