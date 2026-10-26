@tool
class_name HFPluginBrushStamp
extends RefCounted
## Repeat: the brush the last Draw made, placed again with one click (#1407).
##
## Pillars, crates and fence posts are one brush many times over, and each was a
## fresh two stage drag that had to hit the same size again, or a Duplicate and a
## move. The drag system keeps what the last Draw made (`HFDragSystem.last_drawn`).
## The context toolbar's Repeat button, or Shift+D, arms a stamp of it: a ghost
## follows the cursor, standing where a Draw would start, and each left click
## places a copy as one Place Brush step and stays armed, so a row of pillars is
## a row of clicks. Esc, a right click or another tool lets go of it.

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
const DRAW_TOOL := 0
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFOutlineUtil = preload("hf_outline_util.gd")
const HFPreviewSystem = preload("systems/hf_preview_system.gd")
const HFNumberFormat = preload("hf_number_format.gd")
const HFPluginToolModes = preload("plugin_tool_modes.gd")
const LevelRootType = preload("level_root.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The structure ghost's colour, for a brush that does not exist yet, and a red
## for a Cutout, as the subtract preview draws one.
const GHOST_COLOR := Color(0.9, 0.95, 1.0, 0.5)
const CUT_GHOST_COLOR := Color(1.0, 0.35, 0.3, 0.6)
## The context toolbar's own names for the shapes it has buttons for.
const SHORT_NAMES := {"BOX": "Box", "CYLINDER": "Cyl", "SPHERE": "Sph", "CONE": "Cone"}

## Whether a left click in the viewport places a copy.
var armed := false
## What is armed: a copy of `last_drawn` as it was when armed.
var _brush: Dictionary = {}
## The level it was armed in, by instance id: a stamp does not follow the mapper
## into another scene.
var _root_id := 0
## The outline that follows the cursor, a child of the level owned by nothing,
## so it is never saved.
var _ghost: MeshInstance3D = null


## What the Repeat button says for `brush`: the shape's short name and its size,
## "Cyl 2 x 3 x 2", to the precision of grid `step`. Empty for no brush.
static func label(brush: Dictionary, step: float = 0.0) -> String:
	if brush.is_empty():
		return ""
	var key := shape_key(brush)
	var shape_name: String = SHORT_NAMES.get(key, key.capitalize())
	return "%s %s" % [shape_name, HFNumberFormat.dimensions(brush["size"], step)]


## The name of `brush`'s shape in `LevelRoot.BrushShape`, for its icon.
static func shape_key(brush: Dictionary) -> String:
	var key = LevelRootType.BrushShape.find_key(int(brush.get("shape", -1)))
	return str(key) if key != null else ""


## Arm a stamp of the brush the last Draw made in `root`, with Draw taking the
## pointer from whatever had it. False, with a toast, before the first Draw.
func arm(plugin: Object, root: Node) -> bool:
	if root == null or root.get("drag_system") == null:
		return false
	var brush: Dictionary = root.drag_system.last_drawn
	if brush.is_empty():
		_toast(plugin, "Nothing to repeat yet: draw a brush first", 1)
		return false
	HFPluginToolModes.close_face_select(plugin, "Face Select closed for Repeat")
	# Settles any gesture, lets go of an external tool and of a stamp already
	# armed, and presses Draw.
	HFPluginToolModes.switch_to_tool(plugin, DRAW_TOOL)
	if plugin._vertex_mode:
		plugin._toggle_vertex_mode(root)
	var dock = plugin.dock
	if dock and dock.is_paint_mode_enabled():
		dock.paint_mode.button_pressed = false
	armed = true
	_brush = brush.duplicate()
	_root_id = root.get_instance_id()
	if plugin.last_3d_camera:
		follow(root, plugin.last_3d_camera, plugin.last_3d_mouse_pos)
	_toast(
		plugin,
		"Repeat %s: click to place, Esc or right-click to stop" % label(_brush, root.grid_snap),
		0
	)
	plugin._update_hud_context()
	return true


## Let go of the stamp and take its ghost away. True when one was armed.
func disarm() -> bool:
	var was_armed := armed
	armed = false
	_brush = {}
	_root_id = 0
	if is_instance_valid(_ghost):
		if _ghost.get_parent():
			_ghost.get_parent().remove_child(_ghost)
		_ghost.free()
	_ghost = null
	return was_armed


## The viewport's pointer while armed: the ghost follows the cursor, a left click
## places a copy, and a right click lets go. Anything that has taken the pointer
## since the stamp was armed, or a level other than its own, lets go of it too,
## and the event goes on as though it never was.
func handle_input(
	plugin: Object, event: InputEvent, root: Node, camera: Camera3D, mouse_pos: Vector2
) -> int:
	if not armed:
		return PASS
	if not _still_drawing(plugin, root):
		disarm()
		return PASS
	if event is InputEventMouseMotion:
		follow(root, camera, mouse_pos)
		return PASS
	if not (event is InputEventMouseButton):
		return PASS
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		disarm()
		_toast(plugin, "Repeat stopped", 0)
		plugin._update_hud_context()
		return STOP
	if button.button_index != MOUSE_BUTTON_LEFT:
		return PASS
	if button.pressed:
		place(plugin, root, camera, mouse_pos)
	# The release too, so Draw does not take it for the end of a drag.
	return STOP


## Place one copy where a Draw would start under `mouse_pos`, as one Place Brush
## step. False, with a toast, when there is nothing under the cursor to stand it on.
func place(plugin: Object, root: Node, camera: Camera3D, mouse_pos: Vector2) -> bool:
	var start: Dictionary = root.drag_system.draw_start(camera, mouse_pos)
	if start.is_empty():
		_toast(plugin, "Nothing under the cursor to stand the brush on", 1)
		return false
	plugin._commit_brush_placement(root, root.drag_system.repeat_info(_brush, start["point"]))
	plugin._update_hud_context()
	return true


## Stand the ghost where a click would place the copy, or hide it when the cursor
## is over nothing a Draw could start on.
func follow(root: Node, camera: Camera3D, mouse_pos: Vector2) -> void:
	var start: Dictionary = root.drag_system.draw_start(camera, mouse_pos) if camera else {}
	if start.is_empty():
		if is_instance_valid(_ghost):
			_ghost.visible = false
		return
	var ghost := _ensure_ghost(root)
	ghost.visible = true
	ghost.global_transform = root.drag_system.repeat_frame(_brush["size"], start["point"])


## The ghost, drawn once per arming from the outline the brush itself draws.
func _ensure_ghost(root: Node) -> MeshInstance3D:
	if is_instance_valid(_ghost):
		return _ghost
	# A brush that never enters the tree builds no mesh and no faces, and its
	# outline is drawn from its shape, size and Sides alone.
	var probe: DraftBrush = DraftBrush.new()
	probe.shape = int(_brush["shape"])
	probe.sides = int(_brush.get("sides", 4))
	probe.size = _brush["size"]
	var lines := probe.get_editor_outline_lines()
	probe.free()
	var cut := int(_brush["operation"]) == CSGShape3D.OPERATION_SUBTRACTION
	_ghost = MeshInstance3D.new()
	_ghost.name = "RepeatGhost"
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = HFPreviewSystem.ghost_material(
		CUT_GHOST_COLOR if cut else GHOST_COLOR
	)
	_ghost.mesh = HFOutlineUtil.line_mesh(lines)
	root.add_child(_ghost)
	return _ghost


## Whether Draw still has the pointer in the level the stamp was armed in.
func _still_drawing(plugin: Object, root: Node) -> bool:
	if root == null or root.get_instance_id() != _root_id:
		return false
	var dock = plugin.dock
	if dock == null or dock.get_tool() != DRAW_TOOL:
		return false
	if dock.is_paint_mode_enabled() or dock.is_face_select_mode_enabled():
		return false
	if plugin._vertex_mode:
		return false
	if plugin._tool_registry and plugin._tool_registry.has_active_external_tool():
		return false
	return root.input_state == null or root.input_state.is_idle()


static func _toast(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.dock
	if dock and dock.has_method("show_toast"):
		dock.show_toast(message, level)
