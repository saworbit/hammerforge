shader_type spatial;
render_mode blend_mix, cull_back;

uniform sampler2D material_a : source_color, filter_linear_mipmap;
uniform sampler2D material_b : source_color, filter_linear_mipmap;
uniform sampler2D blend_map : filter_linear;
uniform float uv_scale_a : hint_range(0.01, 100.0) = 1.0;
uniform float uv_scale_b : hint_range(0.01, 100.0) = 1.0;
uniform vec3 color_a : source_color = vec3(0.35, 0.55, 0.25);
uniform vec3 color_b : source_color = vec3(0.55, 0.45, 0.3);
uniform float grid_opacity : hint_range(0.0, 1.0) = 0.25;
uniform vec3 grid_color : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
	float blend = texture(blend_map, UV2).r;
	vec3 col_a = texture(material_a, UV * uv_scale_a).rgb * color_a;
	vec3 col_b = texture(material_b, UV * uv_scale_b).rgb * color_b;
	vec3 base = mix(col_a, col_b, blend);

	// Grid lines at cell boundaries (UV is 0-1 per cell)
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float grid_line = 1.0 - smoothstep(0.0, 0.04, edge);
	base = mix(base, grid_color, grid_line * grid_opacity);

	ALBEDO = base;
	ROUGHNESS = 0.8;
}
