shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float snap_size = 16.0;
uniform vec4 grid_color : source_color = vec4(0.85, 0.95, 1.0, 0.15);
uniform float major_line_frequency = 4.0;

varying vec2 v_pos;

float grid_line(float coord, float spacing, float thickness) {
    float half = thickness * 0.5;
    float dist = abs(mod(coord + spacing * 0.5, spacing) - spacing * 0.5);
    float aa = fwidth(coord) * 1.5;
    return 1.0 - smoothstep(half, half + aa, dist);
}

void vertex() {
    v_pos = VERTEX.xz;
}

void fragment() {
    float size = max(snap_size, 0.001);
    float major_spacing = size * max(major_line_frequency, 1.0);
    float minor_thickness = max(size * 0.05, 0.2);
    float major_thickness = max(size * 0.1, 0.35);

    float minor_x = grid_line(v_pos.x, size, minor_thickness);
    float minor_y = grid_line(v_pos.y, size, minor_thickness);
    float major_x = grid_line(v_pos.x, major_spacing, major_thickness);
    float major_y = grid_line(v_pos.y, major_spacing, major_thickness);

    float minor = max(minor_x, minor_y);
    float major = max(major_x, major_y);

    float alpha = grid_color.a * clamp(minor, 0.0, 1.0);
    alpha = max(alpha, grid_color.a * 2.0 * clamp(major, 0.0, 1.0));

    ALBEDO = grid_color.rgb;
    ALPHA = alpha;
}
