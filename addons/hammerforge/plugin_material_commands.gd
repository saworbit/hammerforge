@tool
class_name HFPluginMaterialCommands
extends RefCounted
## Assigning and picking materials from the editor side.
##
## The material data itself belongs to MaterialManager and the faces belong to
## DraftBrush. What lives here is the editor half: which brushes or faces a
## command lands on, how the change reaches undo, and what the dock is told
## afterwards. Every surface that applies a material, the context toolbar, the
## paint stroke, the texture picker and the selection commands, comes through
## here so they all use the same undo boundary.

const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")


## Assign a material to one brush as an undoable action.
##
## Prefers the by-id form: the brush node can be replaced by a later operation,
## but the stable id still resolves, so undo and redo keep working across one.
static func paint_brush_with_undo(plugin: Object, root: Node, brush: Node, mat: Material) -> void:
	if not root or not brush:
		return
	var prev = (
		brush.get("material_override") if brush.get("material_override") else brush.get("material")
	)
	if prev == mat:
		return
	var brush_id := ""
	if root.has_method("get_brush_info_from_node"):
		var info = root.get_brush_info_from_node(brush)
		brush_id = str(info.get("brush_id", ""))
	var method_name = "apply_material_to_brush"
	var args: Array = [brush, mat]
	if brush_id != "":
		method_name = "apply_material_to_brush_by_id"
		args = [brush_id, mat]
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Paint Brush",
		method_name,
		args,
		false,
		Callable(plugin, "_record_history"),
		"paint_brush"
	)


## Read the material off the face under the cursor and make it the dock's
## current one. This is a picker, not an edit, so nothing here is undoable.
static func pick_face_material(plugin: Object, root: Node) -> void:
	var dock = plugin.dock
	if not plugin.last_3d_camera or not dock:
		return
	var hit: Dictionary = root.pick_face(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
	if hit.is_empty():
		dock.show_toast("No face under cursor", 1)
		return
	var brush: DraftBrush = hit.get("brush") as DraftBrush
	var face_idx: int = int(hit.get("face_idx", -1))
	if brush == null or face_idx < 0 or face_idx >= brush.faces.size():
		return
	var face: FaceData = brush.faces[face_idx]
	var mat_idx: int = face.material_idx if face else -1
	if mat_idx < 0:
		dock.show_toast("Face has no material assigned", 1)
		return
	dock._selected_material_index = mat_idx
	plugin._last_picked_material_index = mat_idx
	if dock.material_browser:
		dock.material_browser.set_selected_index(mat_idx)
	dock.show_toast("Picked material #%d" % mat_idx, 0)


## Apply one of the context toolbar's material swatches.
##
## Selected faces win over selected brushes: picking faces is the more specific
## thing the user did, so a whole-brush repaint would throw that work away.
static func apply_context_material(plugin: Object, mat_index: int) -> void:
	var root: Node = plugin.active_root if plugin.active_root else plugin._get_level_root()
	var dock = plugin.dock
	if not root or not dock:
		return
	if not plugin._managed_action_surface_allowed(root, "apply_context_material"):
		return
	dock._selected_material_index = mat_index
	if dock._count_selected_faces() > 0:
		dock._on_face_assign_material()
		return
	var mat = root.material_manager.get_material(mat_index) if root.material_manager else null
	if not mat:
		return
	for node in plugin.hf_selection:
		if node is DraftBrush:
			paint_brush_with_undo(plugin, root, node, mat)
