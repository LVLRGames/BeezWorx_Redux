shader_type canvas_item;

group_uniforms Mask_Settings;
uniform float inner_radius : hint_range(0.0, 2.0) = 0.0;
uniform float outer_radius : hint_range(0.0, 2.0) = 1.0;
// Higher values (4.0-10.0) make it conform to the corners (Squircle)
uniform float corner_shape : hint_range(1.0, 10.0) = 2.0;

group_uniforms Heavy_Darken;
// Controls the absolute "blackness" at the edges (0.0 to 1.0)
uniform float vignette_intensity : hint_range(0.0, 1.0) = 1.0;
// Higher values (2.0+) crush the shadows to be much heavier/thicker
uniform float darkness_power : hint_range(0.1, 10.0) = 3.0;
// Higher values pull the effect further away from the edges
uniform float edge_clamping : hint_range(0.5, 2.0) = 1.0;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 1. Calculate the Squircle Shape
    vec2 uv = (UV - 0.5) * 2.0;
    float dist = pow(pow(abs(uv.x), corner_shape) + pow(abs(uv.y), corner_shape), 1.0 / corner_shape);
    dist *= edge_clamping; // Push the whole effect inward or outward
    
    // 2. Heavy Darkening (Exponential Multiplier)
    // We use 'dist' to create a darkening factor that grows exponentially
    float dark_factor = clamp(dist, 0.0, 1.0);
    dark_factor = pow(dark_factor, darkness_power);
    
    // Mix original color with pure black based on our heavy dark_factor
    vec3 heavy_black = mix(tex_color.rgb, vec3(0.0), dark_factor * vignette_intensity);
    
    // 3. Alpha Mask (Transparency)
    float mask = 1.0 - smoothstep(inner_radius, outer_radius, dist);
    
    COLOR = vec4(heavy_black, tex_color.a * mask);
}
