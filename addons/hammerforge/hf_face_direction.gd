@tool
extends RefCounted
## Face Direction (#1869): every brush face drawn in one colour from the front
## and another from the back, with culling off, so a face wound into its brush
## shows as a patch of the back colour from outside rather than as a hole, which
## looks the same as a culled face, a hidden one or one left out of the bake.
##
## The editor's own view, like View Filters: the level's `face_direction_view` is
## never saved, a brush draws its faces through this material only while it is
## on, and a bake reads the faces, never the look. The two colours are overlay
## colours (`HFOverlayColors.FACE_FRONT`, `FACE_BACK`), so High Contrast and
## Settings > Colours reach them.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFOverlayColors = preload("hf_overlay_colors.gd")
@warning_ignore_restore("shadowed_global_identifier")

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 front_color : source_color = vec4(0.25, 0.5, 1.0, 1.0);
uniform vec4 back_color : source_color = vec4(1.0, 0.15, 0.15, 1.0);

void fragment() {
	ALBEDO = FRONT_FACING ? front_color.rgb : back_color.rgb;
}
"""

static var _material: ShaderMaterial = null


## The one material every brush draws with while Face Direction is on, in the
## overlay colours as they are now.
static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
	_material.set_shader_parameter(
		"front_color", HFOverlayColors.get_color(HFOverlayColors.FACE_FRONT)
	)
	_material.set_shader_parameter(
		"back_color", HFOverlayColors.get_color(HFOverlayColors.FACE_BACK)
	)
	return _material
