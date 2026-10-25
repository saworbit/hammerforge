@tool
extends RefCounted
## Dimensions over the viewport, and keeping a ruler as one (#1699). The model is
## `hf_dimensions.gd`.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("undo_helper.gd")
const HFNumberFormat = preload("hf_number_format.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFDimensions = preload("hf_dimensions.gd")

## How a dimension is drawn: as it should be, with an end detached, and with its
## check failing.
const COLOR_OK := Color(0.95, 0.95, 0.95)
const COLOR_DETACHED := Color(1.0, 0.7, 0.15)
const COLOR_FAILING := Color(1.0, 0.3, 0.25)
## Half the length of the tick across each end, in screen pixels.
const TICK := 6.0


## Draw every dimension in the level over the viewport, unless the Show
## dimensions preference is off. One hidden by a visgroup is not drawn.
static func draw(plugin: Object, overlay: Control) -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var prefs = plugin.get("_user_prefs")
	if prefs != null and not bool(prefs.get_pref("show_dimensions", true)):
		return
	var root = plugin.get("active_root")
	var camera = plugin.get("last_3d_camera")
	if (
		root == null
		or not is_instance_valid(root)
		or camera == null
		or not is_instance_valid(camera)
	):
		return
	var font: Font = overlay.get_theme_default_font()
	var font_size: int = overlay.get_theme_default_font_size()
	for dimension in HFDimensions.dimensions(root):
		if not (dimension as Node3D).is_visible_in_tree():
			continue
		var measured := HFDimensions.measure(root, dimension)
		var a: Vector3 = measured["a"]
		var b: Vector3 = measured["b"]
		if camera.is_position_behind(a) or camera.is_position_behind(b):
			continue
		var color := COLOR_OK
		if not bool(measured["passes"]):
			color = COLOR_FAILING
		elif bool(measured["detached"]):
			color = COLOR_DETACHED
		var at_a: Vector2 = camera.unproject_position(a)
		var at_b: Vector2 = camera.unproject_position(b)
		overlay.draw_line(at_a, at_b, Color(0, 0, 0, 0.6), 3.0)
		overlay.draw_line(at_a, at_b, color, 1.5)
		var across := (at_b - at_a).orthogonal().normalized() * TICK
		for end in [at_a, at_b]:
			overlay.draw_line(end - across, end + across, color, 1.5)
		if font == null:
			continue
		var text := "%s m" % HFNumberFormat.number(float(measured["length"]), 0.01)
		var middle := (at_a + at_b) * 0.5 + Vector2(4, -4)
		overlay.draw_string_outline(
			font, middle, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8)
		)
		overlay.draw_string(font, middle, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Keep a ruler from `a` to `b` as a dimension, as one undo step: each end
## attached to the vertex, edge middle or face centre it lies on. The dimension,
## or null.
static func keep(
	root: Node, a: Vector3, b: Vector3, undo_redo: Object, history: Callable = Callable()
) -> Node:
	if root == null or not root.get("entity_system") or a.is_equal_approx(b):
		return null
	var before: Dictionary = root.capture_state()
	var info := HFDimensions.info_between(root, a, b, "Dimension")
	var dimension: Node = root.entity_system.restore_entity_from_info(info)
	if dimension == null:
		return null
	if root.get("visgroup_system") and root.visgroup_system.has_method("join_current"):
		root.visgroup_system.join_current(dimension)
	HFUndoHelper.commit_completed(undo_redo, root, "Keep Dimension", before, history)
	return dimension


## The palette's Keep Ruler as Dimension: the Measure tool's last ruler.
static func keep_last_ruler(plugin: Object) -> bool:
	var registry = plugin.get("_tool_registry")
	var tool = (
		registry.get_active_tool() if registry and registry.has_method("get_active_tool") else null
	)
	if tool == null or not tool.has_method("keep_last_ruler"):
		_say(plugin, "Measure a ruler with the Measure tool first", 1)
		return false
	return tool.keep_last_ruler()


static func _say(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and dock.has_method("show_toast"):
		dock.show_toast(message, level)
