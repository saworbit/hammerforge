shader_type spatial;
render_mode unshaded, cull_disabled, wireframe, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 1.0, 0.0, 0.5);

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
