@tool
class_name HFClipTool
extends "hf_editor_tool.gd"

## Cut the selected brushes along a plane placed with two or three points (#1711).
##
## Two points make a plane through them that runs along the axis the view looks
## down most, so two clicks in a top view make an upright cut. A third point makes
## the plane through all three. A drag places the first two at the press and the
## release. A placed point can be dragged, and the cut follows it.
##
## Which pieces stay is the Keep setting: both, the piece in front of the plane
## (the side its normal faces) or the piece behind. Tab steps through them. The
## piece that would go draws faded red, a kept one cyan. Enter cuts every selected
## brush the plane passes through, as one undo step named "Clip". Backspace takes
## off the last point, and Escape clears them, or leaves the tool when there are
## none.
##
## The new faces take the material of the face the first point was placed on. A
## first point on the grid gives them the Active Material when it is in the
## palette, and otherwise the material of the face beside them, as Clip does.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFConvexClipType = preload("hf_convex_clip.gd")
const HFUndoHelperType = preload("undo_helper.gd")

const KEEP_BOTH := 0
const KEEP_FRONT := 1
const KEEP_BACK := 2
const KEEP_OPTIONS := ["Both", "Front", "Back"]
## How near, in pixels, a press must land to a placed point to pick it up.
const HANDLE_PIXELS := 10.0
## How far, in pixels, a press must travel before it is a drag that places the
## second point.
const DRAG_PIXELS := 4.0
const KEPT_COLOR := Color(0.3, 0.85, 1.0)
const GONE_COLOR := Color(1.0, 0.35, 0.3, 0.45)
const POINT_COLOR := Color.YELLOW
const MESH_NAME := "ClipToolMesh"

## The selection as nodes, which the plugin hands over. Without it nothing is
## cut.
var selection_source := Callable()

var _points: Array[Vector3] = []
## The palette slot the new faces take, or -1 for the face beside them.
var _cap_material := -1
## The axis the view looks down most, which a two point plane runs along.
var _view_axis := Vector3.UP
var _dragging := -1
var _press_position := Vector2.ZERO
var _press_places_second := false
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null


func tool_name() -> String:
	return "Clip"


func tool_id() -> int:
	return 104


func keymap_action() -> String:
	return "tool_clip"


func get_settings_schema() -> Array:
	return [
		{
			"name": "keep",
			"type": "enum",
			"label": "Keep",
			"options": PackedStringArray(KEEP_OPTIONS),
			"default": KEEP_BOTH,
		},
	]


## Which piece a cut keeps: an index into `KEEP_OPTIONS`.
func keep() -> int:
	return int(get_setting("keep"))


func activate(p_root: Node3D, p_camera: Camera3D) -> void:
	super.activate(p_root, p_camera)
	_reset()


func deactivate() -> void:
	_reset()
	super.deactivate()


func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if not root or not camera:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	_view_axis = view_axis_of(camera)
	if event is InputEventKey and event.pressed:
		return handle_keyboard(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return _press(camera, mouse_pos)
		return _release()
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		return _drag(camera, mouse_pos)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func handle_keyboard(event: InputEventKey) -> int:
	if not event.pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			apply()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_BACKSPACE, KEY_DELETE:
			remove_last_point()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_TAB:
			set_setting("keep", (keep() + 1) % KEEP_OPTIONS.size())
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_ESCAPE:
			if _points.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_reset()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func has_work_in_progress() -> bool:
	return not _points.is_empty() or _dragging >= 0 or _press_places_second


func recover_lost_pointer_capture() -> bool:
	return cancel_pointer_capture()


func cancel_pointer_capture() -> bool:
	var had := _dragging >= 0 or _press_places_second
	_dragging = -1
	_press_places_second = false
	return had


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray(["-- Clip Tool --"])
	match _points.size():
		0:
			lines.append("Click: First point  |  Drag: First two")
		1:
			lines.append("Click: Second point")
		2:
			lines.append("Click: Third point, or Enter to cut")
		_:
			lines.append("Enter: Cut")
	lines.append("Keep: %s  |  Tab: Change" % KEEP_OPTIONS[keep()])
	lines.append("Drag a point to move it")
	lines.append("Backspace: Remove last  |  Esc: Clear  |  C: Exit")
	return lines


# ---------------------------------------------------------------------------
# Points
# ---------------------------------------------------------------------------


## The points placed so far, a copy.
func points() -> Array[Vector3]:
	return _points.duplicate()


## Place a point. The first sets the material the new faces take: `material` is
## the palette slot of the face it was placed on, or -1 for a point on the grid.
func add_point(point: Vector3, material: int = -1) -> void:
	if _points.size() >= 3:
		return
	if _points.is_empty():
		_cap_material = material if material >= 0 else _active_material_slot()
	_points.append(point)
	_update_preview()


## Move a placed point, as a drag does.
func move_point(index: int, point: Vector3) -> void:
	if index < 0 or index >= _points.size():
		return
	_points[index] = point
	_update_preview()


## Take back the last point, as Backspace does.
func remove_last_point() -> void:
	if _points.is_empty():
		return
	_points.pop_back()
	_update_preview()


## The axis a view looks down most, as a unit vector along it.
static func view_axis_of(camera: Camera3D) -> Vector3:
	var forward := -camera.global_transform.basis.z
	var size := forward.abs()
	if size.x >= size.y and size.x >= size.z:
		return Vector3.RIGHT
	if size.y >= size.z:
		return Vector3.UP
	return Vector3.BACK


## The axis the view looks down. With two points, the cut runs through the
## line between them and along this axis.
func set_view_axis(axis: Vector3) -> void:
	_view_axis = axis
	_update_preview()


## The cut, or null when the points do not make one yet: fewer than two, two
## along the view's axis, or three on one line.
func plane() -> Variant:
	var normal := Vector3.ZERO
	if _points.size() == 2:
		normal = (_points[1] - _points[0]).cross(_view_axis)
	elif _points.size() == 3:
		normal = (_points[1] - _points[0]).cross(_points[2] - _points[0])
	if normal.length() < 0.0001:
		return null
	return Plane(normal.normalized(), _points[0])


# ---------------------------------------------------------------------------
# The cut
# ---------------------------------------------------------------------------


## The selected brushes the plane passes through, by id. A locked brush is left
## out, as every tool leaves it (#1697).
func targets() -> Array:
	var cut: Variant = plane()
	if not (cut is Plane) or root == null or not selection_source.is_valid():
		return []
	var ids: Array = []
	for node in selection_source.call():
		if not (node is DraftBrush) or not is_instance_valid(node):
			continue
		if root.visgroup_system and root.visgroup_system.is_locked(node):
			continue
		var brush_id := str(node.brush_id)
		if brush_id != "" and root.brush_system.plane_splits_brush(brush_id, cut):
			ids.append(brush_id)
	return ids


## Cut, as one undo step. Says why in a message when it cannot.
func apply() -> bool:
	var cut: Variant = plane()
	if not (cut is Plane):
		_tell("Clip: place two points, or three, to say where the cut goes")
		return false
	var ids := targets()
	if ids.is_empty():
		_tell("Clip: the plane does not pass through any selected brush")
		return false
	HFUndoHelperType.commit(
		undo_redo,
		root,
		"Clip",
		"clip_brushes_keeping",
		[ids, cut, keep(), _cap_material],
		false,
		history_callback,
		"",
		true
	)
	_reset()
	return true


func _active_material_slot() -> int:
	if root == null or root.material_manager == null:
		return -1
	var active: Variant = root.get("active_material")
	if not (active is Material):
		return -1
	return root.material_manager.materials.find(active)


func _tell(message: String) -> void:
	if root and root.has_signal("user_message"):
		root.user_message.emit(message, 1)


# ---------------------------------------------------------------------------
# Pointer
# ---------------------------------------------------------------------------


func _press(camera: Camera3D, mouse_pos: Vector2) -> int:
	_press_position = mouse_pos
	var near := _point_near(camera, mouse_pos)
	if near >= 0:
		_dragging = near
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _points.size() >= 3:
		_tell("Clip: three points are placed. Enter cuts, Backspace takes one off")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	var picked := _pick(camera, mouse_pos)
	if picked.is_empty():
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	add_point(picked["point"], int(picked["material"]))
	_press_places_second = _points.size() == 1
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _drag(camera: Camera3D, mouse_pos: Vector2) -> int:
	if _dragging >= 0:
		var picked := _pick(camera, mouse_pos)
		if not picked.is_empty():
			move_point(_dragging, picked["point"])
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if not _press_places_second:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if _points.size() == 1 and mouse_pos.distance_to(_press_position) < DRAG_PIXELS:
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	var second := _pick(camera, mouse_pos)
	if second.is_empty():
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _points.size() == 1:
		add_point(second["point"])
	else:
		move_point(1, second["point"])
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _release() -> int:
	var handled := _dragging >= 0 or _press_places_second
	_dragging = -1
	_press_places_second = false
	return EditorPlugin.AFTER_GUI_INPUT_STOP if handled else EditorPlugin.AFTER_GUI_INPUT_PASS


## Where a click lands: on a visible face, with that face's material, or on the
## grid the editor builds on. Snapped as any placed point is.
func _pick(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	var hit: Dictionary = root.pick_face(camera, mouse_pos) if root.has_method("pick_face") else {}
	if hit.get("position") is Vector3:
		var material := -1
		var brush = hit.get("brush")
		var face_idx := int(hit.get("face_idx", -1))
		if brush is DraftBrush and face_idx >= 0 and face_idx < brush.faces.size():
			material = int(brush.faces[face_idx].material_idx)
		return {"point": snap_point(hit["position"]), "material": material}
	var start := first_point_start(camera, mouse_pos)
	if start.is_empty():
		return {}
	return {"point": start["point"], "material": -1}


func _point_near(camera: Camera3D, mouse_pos: Vector2) -> int:
	for i in _points.size():
		if camera.is_position_behind(_points[i]):
			continue
		if camera.unproject_position(_points[i]).distance_to(mouse_pos) <= HANDLE_PIXELS:
			return i
	return -1


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------


## What the cut would leave of each brush it passes through: the pieces' edges in
## world space, and whether each piece stays.
func preview_pieces() -> Array:
	var cut: Variant = plane()
	var out: Array = []
	if not (cut is Plane):
		return out
	for brush_id in targets():
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		if not (brush is DraftBrush):
			continue
		var xform: Transform3D = brush.global_transform
		var halves: Dictionary = HFConvexClipType.split(
			brush.get_faces(), xform.affine_inverse() * cut
		)
		out.append({"faces": halves["front"], "xform": xform, "kept": keep() != KEEP_BACK})
		out.append({"faces": halves["back"], "xform": xform, "kept": keep() != KEEP_FRONT})
	return out


func _update_preview() -> void:
	if root == null or not root.is_inside_tree():
		return
	if _points.is_empty():
		_clear_visuals()
		return
	_ensure_mesh()
	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var size := maxf(grid_step(), 1.0) * 0.5
	for point in _points:
		_line_cross(point, size)
	for i in _points.size():
		_line(_points[i], _points[(i + 1) % _points.size()], POINT_COLOR)
	for piece in preview_pieces():
		var color: Color = KEPT_COLOR if piece["kept"] else GONE_COLOR
		var xform: Transform3D = piece["xform"]
		for face in piece["faces"]:
			var verts: PackedVector3Array = face.local_verts
			for i in verts.size():
				_line(xform * verts[i], xform * verts[(i + 1) % verts.size()], color)
	_immediate_mesh.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(a)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(b)


func _line_cross(point: Vector3, size: float) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(point - axis * size, point + axis * size, POINT_COLOR)


func _ensure_mesh() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = make_overlay_mesh(root, MESH_NAME)
	_immediate_mesh = _mesh_instance.mesh as ImmediateMesh


func _clear_visuals() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		free_overlay_mesh(_mesh_instance)
	_mesh_instance = null
	_immediate_mesh = null


func _reset() -> void:
	_points.clear()
	_cap_material = -1
	_dragging = -1
	_press_places_second = false
	_clear_visuals()
