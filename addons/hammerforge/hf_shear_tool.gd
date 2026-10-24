@tool
class_name HFShearTool
extends "hf_editor_tool.gd"

## Lean the selection by dragging a handle on a side of its box (#1718).
##
## Leaning walls, a sloped buttress or a parallelogram floor were made one brush
## at a time, and the pieces drifted apart where they met. The handle in the
## middle of each side of the selection's box drags along that side: the side
## moves, the opposite side stays put, and everything between leans by one shear.
## The drag is held to the grid, Ctrl lets it go free, and Escape lets it go. A
## typed shear is the Shear command; both make the same step.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFTransformSystem = preload("res://addons/hammerforge/systems/hf_transform_system.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFPluginEditActionsType = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const HFOutlineUtilType = preload("res://addons/hammerforge/hf_outline_util.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
## How near a press must be to a handle on screen to take it, in pixels.
const HANDLE_REACH := 14.0
## How big a handle's cross is drawn, as a share of the box's smallest side.
const HANDLE_SIZE := 0.08
const BOX_COLOR := Color(0.95, 0.75, 0.3, 0.7)
const LEAN_COLOR := Color(0.3, 0.9, 0.3, 0.8)

## The selection as nodes, which the plugin hands over. Without it nothing leans.
var selection_source := Callable()

## The handle being dragged: `{"over", "high", "at", "pivot"}`, the axis the side
## faces along, whether it is the high side, where its middle is, and where the
## opposite side stands on that axis. Empty while nothing is dragged.
var _drag: Dictionary = {}
var _along := -1
var _amount := 0.0
var _mesh_instance: MeshInstance3D = null


func tool_name() -> String:
	return "Shear"


func tool_id() -> int:
	return 106


func keymap_action() -> String:
	return "tool_shear"


func activate(p_root: Node3D, p_camera: Camera3D) -> void:
	super.activate(p_root, p_camera)
	_drag = {}
	_update_preview()


func deactivate() -> void:
	_drag = {}
	_clear_visuals()
	super.deactivate()


func has_work_in_progress() -> bool:
	return not _drag.is_empty()


func shows_draw_hover() -> bool:
	return false


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Shear Tool --")
	if _drag.is_empty():
		lines.append("Drag a side's handle: lean the selection")
		lines.append("Ctrl: off the grid")
	else:
		lines.append("Lean: %s m per m" % length_text(_amount, 0.0))
		lines.append("Esc: let it go")
	return lines


## The selected brushes' ids and entities' paths: `{"brush_ids", "entity_paths"}`.
func targets() -> Dictionary:
	var nodes: Array = selection_source.call() if selection_source.is_valid() else []
	var paths: Array = []
	for node in nodes:
		if node is Node and is_instance_valid(node) and root.is_entity_node(node):
			paths.append(root.get_path_to(node))
	return {"brush_ids": Array(root.brush_system.brush_ids_of(nodes)), "entity_paths": paths}


## The box round the selection, or an empty one with nothing selected.
func bounds() -> AABB:
	var picked := targets()
	if (picked["brush_ids"] as Array).is_empty() and (picked["entity_paths"] as Array).is_empty():
		return AABB()
	return root.transform_system.selection_bounds(picked["brush_ids"], picked["entity_paths"])


## Each side's handle, `{"over", "high", "at", "pivot"}`, for a box with room on
## that axis.
static func handles_of(box: AABB) -> Array:
	var out: Array = []
	var centre := box.get_center()
	for over in 3:
		if box.size[over] <= 0.0001:
			continue
		for high in [false, true]:
			var at := centre
			at[over] = box.end[over] if high else box.position[over]
			var pivot: float = box.position[over] if high else box.end[over]
			out.append({"over": over, "high": high, "at": at, "pivot": pivot})
	return out


func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if not root or not camera:
		return PASS
	if event is InputEventKey:
		return handle_keyboard(event as InputEventKey)
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return PASS
		if button.pressed:
			return _press(camera, mouse_pos)
		if not _drag.is_empty():
			_release()
			return STOP
		return PASS
	if event is InputEventMouseMotion:
		if _drag.is_empty():
			# The selection may have changed since the box was drawn.
			_update_preview()
			return PASS
		_lean_to(camera, mouse_pos, (event as InputEventMouseMotion).ctrl_pressed)
		return STOP
	return PASS


func handle_keyboard(event: InputEventKey) -> int:
	if event.pressed and event.keycode == KEY_ESCAPE and not _drag.is_empty():
		_drag = {}
		_update_preview()
		return STOP
	return PASS


func _press(camera: Camera3D, mouse_pos: Vector2) -> int:
	var nearest: Dictionary = {}
	var best := HANDLE_REACH
	for handle in handles_of(bounds()):
		var at: Vector3 = handle["at"]
		if camera.is_position_behind(at):
			continue
		var distance := camera.unproject_position(at).distance_to(mouse_pos)
		if distance <= best:
			best = distance
			nearest = handle
	if nearest.is_empty():
		return PASS
	_drag = nearest
	_along = -1
	_amount = 0.0
	_update_preview()
	return STOP


## Lean so the dragged side's middle follows the cursor across the side's plane,
## along whichever of the side's two axes the cursor has gone further.
func _lean_to(camera: Camera3D, mouse_pos: Vector2, free: bool) -> void:
	var over: int = _drag["over"]
	var at: Vector3 = _drag["at"]
	var plane := Plane(HFTransformSystem.axis_vector(over), at[over])
	var hit: Variant = plane.intersects_ray(
		camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos)
	)
	if not (hit is Vector3):
		return
	var delta: Vector3 = hit - at
	var best := -1
	for axis in 3:
		if axis != over and (best < 0 or absf(delta[axis]) > absf(delta[best])):
			best = axis
	var moved: float = delta[best]
	var step := grid_step()
	if not free and step > 0.0:
		moved = snappedf(moved, step)
	var reach: float = at[over] - float(_drag["pivot"])
	_along = best
	_amount = moved / reach if not is_zero_approx(reach) else 0.0
	_update_preview()


func _release() -> void:
	var drag := _drag
	_drag = {}
	if _along >= 0 and not is_zero_approx(_amount):
		var picked := targets()
		HFPluginEditActionsType.commit_shear(
			undo_redo,
			history_callback,
			root,
			picked["brush_ids"],
			picked["entity_paths"],
			_along,
			drag["over"],
			_amount,
			drag["pivot"]
		)
	_along = -1
	_amount = 0.0
	_update_preview()


## The shear the drag makes now, or the identity.
func leaning() -> Transform3D:
	if _drag.is_empty() or _along < 0:
		return Transform3D.IDENTITY
	return HFTransformSystem.shear_transform(_along, _drag["over"], _amount, _drag["pivot"])


func _update_preview() -> void:
	if not root:
		return
	var box := bounds()
	if box.size == Vector3.ZERO:
		_clear_visuals()
		return
	var lean := leaning()
	var lines := PackedVector3Array()
	var colors: Array[Color] = []
	var outline := HFOutlineUtilType.box_lines(box.size)
	for point in outline:
		lines.append(lean * (box.position + box.size * 0.5 + point))
		colors.append(BOX_COLOR)
	var mark := maxf(0.05, minf(box.size.x, minf(box.size.y, box.size.z)) * HANDLE_SIZE)
	for handle in handles_of(box):
		var at: Vector3 = lean * (handle["at"] as Vector3)
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			lines.append(at - axis * mark)
			lines.append(at + axis * mark)
			colors.append(BOX_COLOR)
			colors.append(BOX_COLOR)
	if not _drag.is_empty():
		for node in selection_source.call() if selection_source.is_valid() else []:
			if node is DraftBrush and is_instance_valid(node):
				var place: Transform3D = lean * (node as DraftBrush).global_transform
				for point in HFOutlineUtilType.face_boundary_lines(
					(node as DraftBrush).get_faces()
				):
					lines.append(place * point)
					colors.append(LEAN_COLOR)
	if _mesh_instance == null or not is_instance_valid(_mesh_instance):
		_mesh_instance = make_overlay_mesh(root, "_ShearToolPreview")
	var mesh := _mesh_instance.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in lines.size():
		mesh.surface_set_color(colors[i] if i < colors.size() else BOX_COLOR)
		mesh.surface_add_vertex(lines[i])
	mesh.surface_end()


func _clear_visuals() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		free_overlay_mesh(_mesh_instance)
	_mesh_instance = null
