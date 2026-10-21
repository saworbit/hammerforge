@tool
class_name HFEditorTool
extends RefCounted

## Base class for custom editor tools.
##
## Subclass this to create tools that integrate with HammerForge's tool system.
## Register instances with HFToolRegistry. The registry activates/deactivates
## tools and routes input events to the active tool.

## The LevelRoot this tool operates on (set by registry on activate).
var root: Node3D

## Whether this tool is currently active.
var is_active := false

## Undo/redo manager — set by plugin on activation for tools that create brushes.
var undo_redo: Object = null

## Optional callback to record actions in the dock history panel.
## Set by plugin on activation. Signature: func(action_name: String) -> void
var history_callback: Callable = Callable()


## Returns true if this tool can execute in the current state.
## Override in subclass to add specific requirements.
## An overlay for a tool to draw on: an `ImmediateMesh` under `parent`, unshaded,
## coloured by its vertices, see-through, drawn over everything and casting no
## shadow. The path, polygon and measure tools each draw on one, and only the
## name differs (#904).
static func make_overlay_mesh(parent: Node, node_name: String) -> MeshInstance3D:
	return _overlay_mesh_script().make(parent, node_name)


## Lets an overlay from make_overlay_mesh() go: out of the tree at once, so a
## redraw in the same frame cannot find it, then freed.
static func free_overlay_mesh(overlay: MeshInstance3D) -> void:
	_overlay_mesh_script().release(overlay)


## The overlay's own script, which a level can load where this class cannot (it
## names `EditorPlugin`). Returned rather than held in a constant, as a member
## here would clash with one of the same name in a project tool.
static func _overlay_mesh_script() -> GDScript:
	return preload("hf_overlay_mesh.gd")


## A label for a tool to write a number on, in the Measure tool's style: facing
## the camera, drawn over everything and outlined so it reads on any surface.
## Measure's rulers and the Polygon and Path tools' segment lengths are all made
## here, so the three cannot drift apart (#1408). No owner is set, so a label is
## never saved with the scene.
static func make_overlay_label(parent: Node, node_name: String, color: Color) -> Label3D:
	# Preloaded where used: a project tool extends this class, and a member
	# here would clash with one of the same name there.
	var label: Label3D = preload("hf_size_labels.gd").make_label("", color)
	label.name = node_name
	parent.add_child(label)
	return label


## How far above a segment's middle its length sits, as a Measure ruler's does.
const LENGTH_LABEL_LIFT := Vector3(0, 0.5, 0)


## Label each segment with its length at its middle (#1408). `segments` holds
## `[from, to, colour]` entries. `labels` is the caller's own list, kept from one
## call to the next so a redraw on every mouse motion moves the labels it has
## rather than making new ones; any left over are let go. A length is measured
## across the ground, X and Z, which is the length the Polygon and Path tools
## build a brush to. Positions are local to `parent`, as the tools' outlines are.
static func show_segment_lengths(parent: Node, labels: Array, segments: Array, step: float) -> void:
	while labels.size() > segments.size():
		_free_overlay_label(labels.pop_back())
	for i in segments.size():
		var from: Vector3 = segments[i][0]
		var to: Vector3 = segments[i][1]
		var color: Color = segments[i][2]
		if i >= labels.size():
			labels.append(make_overlay_label(parent, "SegmentLength_%d" % i, color))
		var label: Label3D = labels[i]
		label.text = length_text(Vector2(to.x - from.x, to.z - from.z).length(), step)
		label.modulate = color
		label.position = (from + to) * 0.5 + LENGTH_LABEL_LIFT


## Let every label in `labels` go, out of the tree at once as an overlay is.
static func free_overlay_labels(labels: Array) -> void:
	for label in labels:
		_free_overlay_label(label)
	labels.clear()


static func _free_overlay_label(label: Variant) -> void:
	if not is_instance_valid(label):
		return
	if label.get_parent():
		label.get_parent().remove_child(label)
	label.queue_free()


## A length with as many decimals as the grid step needs: 12 on a grid of 1,
## 3.25 on a grid of 0.25. With no grid to go by, two.
static func length_text(length: float, step: float) -> String:
	# The rule every length in the editor is printed by, so a segment and a
	# selection's size read alike.
	return preload("hf_number_format.gd").number(length, step)


## The level's grid step, or 0 when it has none.
func grid_step() -> float:
	if root and root.get("grid_snap") and root.grid_snap > 0.0:
		return float(root.grid_snap)
	return 0.0


## Where a point the tool places lands. LevelRoot's snap, so the grid and the
## vertex and other snap toggles apply as they do to a draw; a root without one
## rounds to its grid. Every tool snaps here, so one switch reaches them all (#1468).
func snap_point(pos: Vector3) -> Vector3:
	if root and root.has_method("_snap_point"):
		return root._snap_point(pos)
	if root and root.get("grid_snap") and root.grid_snap > 0.0:
		var g: float = root.grid_snap
		return Vector3(snappedf(pos.x, g), snappedf(pos.y, g), snappedf(pos.z, g))
	return pos


## Where a point placed after `from` lands with Shift held (#1408): on the X or
## Z line through `from`, whichever is nearer the direction to `pos`, and snapped
## along that line as any point is. The other coordinate is put back after the
## snap, so a vertex or edge snap beside the line cannot pull the point off it.
func snap_point_on_axis(from: Vector3, pos: Vector3) -> Vector3:
	var along_x := absf(pos.x - from.x) >= absf(pos.z - from.z)
	var on_line := pos
	if along_x:
		on_line.z = from.z
	else:
		on_line.x = from.x
	var landed := snap_point(on_line)
	if along_x:
		landed.z = from.z
	else:
		landed.x = from.x
	return landed


func can_activate(p_root: Node3D) -> bool:
	return p_root != null


## Returns a user-facing reason string when can_activate() is false.
## Override in subclass to provide specific failure reasons.
func get_poll_fail_reason(p_root: Node3D) -> String:
	if p_root == null:
		return "No LevelRoot in scene"
	return ""


## Display name for toolbar button.
func tool_name() -> String:
	return "Custom Tool"


## Unique numeric tool ID. Built-in IDs: 0=Draw, 1=Select, 2=ExtrudeUp, 3=ExtrudeDown.
## External tools should use IDs >= 100.
func tool_id() -> int:
	return -1


## KEY_* constant for keyboard shortcut, or 0 for none.
func tool_shortcut_key() -> int:
	return 0


## Called when tool becomes active.
func activate(p_root: Node3D, _p_camera: Camera3D) -> void:
	root = p_root
	is_active = true


## Called when tool is deactivated (another tool activated).
func deactivate() -> void:
	is_active = false
	root = null


## Handle mouse/key input. Return EditorPlugin.AFTER_GUI_INPUT_STOP to consume.
func handle_input(_event: InputEvent, _camera: Camera3D, _mouse_pos: Vector2) -> int:
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Handle keyboard shortcut. Return EditorPlugin.AFTER_GUI_INPUT_STOP to consume.
func handle_keyboard(_event: InputEventKey) -> int:
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Settle a pointer gesture when buttonless motion proves that LMB-up was lost.
## Return true when the tool closed an active capture.
func recover_lost_pointer_capture() -> bool:
	return false


## Cancel a transient pointer gesture after application/viewport focus loss.
## Return true when the tool closed an active capture.
func cancel_pointer_capture() -> bool:
	return false


## Lines for the shortcut HUD overlay.
func get_shortcut_hud_lines() -> PackedStringArray:
	return PackedStringArray()


# ---------------------------------------------------------------------------
# Declarative settings — subclasses override get_settings_schema() to expose
# configurable properties.  The dock auto-generates UI controls from the schema.
# ---------------------------------------------------------------------------

## Internal settings storage.
var _settings: Dictionary = {}


## Return an array of setting descriptors.  Each is a dict with keys:
## "name" (String), "type" ("bool"|"int"|"float"|"string"|"enum"|"color"|"vector3"),
## "label" (String, display name), "default" (Variant), and optionally:
## "min"/"max" (numeric), "options" (PackedStringArray for enum).
## Override in subclass to expose tool-specific settings.
func get_settings_schema() -> Array:
	return []


## Read a setting value by key.
func get_setting(key: String) -> Variant:
	# Fall back to schema default if not explicitly set
	if _settings.has(key):
		return _settings[key]
	for prop in get_settings_schema():
		if prop.get("name", "") == key:
			return prop.get("default")
	return null


## Write a setting value by key.
##
## A setting is held to its schema here rather than only in the control the dock
## generates from that schema, so a preset, a restore, a script or a control
## someone adds later cannot put a value into the tool that the tool itself says
## is illegal. A number is held to its min and max, an enum to its own options,
## and a value that is not a number is refused outright: the geometry built from
## one is not wrong in a way anything downstream can see.
func set_setting(key: String, value: Variant) -> void:
	var prop := _schema_for(key)
	var kind := str(prop.get("type", ""))
	# An enum's range is its `options` array. The dock builds an OptionButton from
	# it and has no item past the end to show, so an index the options do not have
	# is a setting nothing can display or correct, handed back to a tool that
	# indexes its own array with it.
	if kind == "enum" and (value is float or value is int):
		var options: Array = Array(prop.get("options", []))
		var index := int(value)
		if index < 0 or index >= options.size():
			HFLog.warn(
				"HammerForge: %s has no choice %d, keeping %s" % [key, index, str(get_setting(key))]
			)
			return
		_settings[key] = index
		return
	if (kind == "float" or kind == "int") and (value is float or value is int):
		var number := float(value)
		if not is_finite(number):
			HFLog.warn("HammerForge: %s is not a number, keeping %s" % [key, str(get_setting(key))])
			return
		if prop.has("min"):
			number = maxf(number, float(prop["min"]))
		if prop.has("max"):
			number = minf(number, float(prop["max"]))
		if kind == "int":
			_settings[key] = int(round(number))
		else:
			_settings[key] = number
		return
	_settings[key] = value


## The schema entry for a setting, or an empty dictionary if it has none.
func _schema_for(key: String) -> Dictionary:
	for prop in get_settings_schema():
		if prop is Dictionary and str(prop.get("name", "")) == key:
			return prop
	return {}
