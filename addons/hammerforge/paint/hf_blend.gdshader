shader_type spatial;
render_mode blend_mix, cull_back;

uniform sampler2D material_a : source_color, filter_linear_mipmap;
uniform sampler2D material_b : source_color, filter_linear_mipmap;
uniform sampler2D material_c : source_color, filter_linear_mipmap;
uniform sampler2D material_d : source_color, filter_linear_mipmap;
uniform sampler2D blend_map : filter_linear;
uniform float uv_scale_a : hint_range(0.01, 100.0) = 1.0;
uniform float uv_scale_b : hint_range(0.01, 100.0) = 1.0;
uniform float uv_scale_c : hint_range(0.01, 100.0) = 1.0;
uniform float uv_scale_d : hint_range(0.01, 100.0) = 1.0;
uniform vec3 color_a : source_color = vec3(0.35, 0.55, 0.25);
uniform vec3 color_b : source_color = vec3(0.55, 0.45, 0.3);
uniform vec3 color_c : source_color = vec3(0.45, 0.5, 0.55);
uniform vec3 color_d : source_color = vec3(0.5, 0.5, 0.5);
uniform float grid_opacity : hint_range(0.0, 1.0) = 0.25;
uniform vec3 grid_color : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
	vec3 blend = texture(blend_map, UV2).rgb;
	float w1 = clamp(blend.r, 0.0, 1.0);
	float w2 = clamp(blend.g, 0.0, 1.0);
	float w3 = clamp(blend.b, 0.0, 1.0);
	float w0 = max(0.0, 1.0 - (w1 + w2 + w3));
	float total = w0 + w1 + w2 + w3;
	if (total > 0.0001) {
		w0 /= total;
		w1 /= total;
		w2 /= total;
		w3 /= total;
	}
	vec3 col_a = texture(material_a, UV * uv_scale_a).rgb * color_a;
	vec3 col_b = texture(material_b, UV * uv_scale_b).rgb * color_b;
	vec3 col_c = texture(material_c, UV * uv_scale_c).rgb * color_c;
	vec3 col_d = texture(material_d, UV * uv_scale_d).rgb * color_d;
	vec3 base = col_a * w0 + col_b * w1 + col_c * w2 + col_d * w3;

	// Grid lines at cell boundaries (UV is 0-1 per cell)
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float grid_line = 1.0 - smoothstep(0.0, 0.04, edge);
	base = mix(base, grid_color, grid_line * grid_opacity);

	ALBEDO = base;
	ROUGHNESS = 0.8;
}
