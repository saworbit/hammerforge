@tool
extends RefCounted
## An overlay to draw on in the viewport: an `ImmediateMesh` under a parent,
## unshaded, coloured by its vertices, see-through, drawn over everything and
## casting no shadow. The path, polygon and measure tools draw on one (#904), and
## so does the snap target marker on a drag (#1399).
##
## Kept apart from `HFEditorTool`, which names `EditorPlugin`: the snap system is
## loaded by a level, and a script a level can load must not name an editor class
## (#1175).


static func make(parent: Node, node_name: String) -> MeshInstance3D:
	var overlay := MeshInstance3D.new()
	overlay.name = node_name
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.material_override = material
	overlay.mesh = ImmediateMesh.new()
	parent.add_child(overlay)
	return overlay


## Lets an overlay from make() go: out of the tree at once, so a redraw in the
## same frame cannot find it, then freed.
static func release(overlay: MeshInstance3D) -> void:
	if overlay.get_parent():
		overlay.get_parent().remove_child(overlay)
	overlay.queue_free()
