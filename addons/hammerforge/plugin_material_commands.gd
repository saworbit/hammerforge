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

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFMaterialBrowserType = preload("ui/hf_material_browser.gd")


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
		note_material_used(root, mat)
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
	(
		HFUndoHelper
		. commit(
			plugin._get_undo_redo(),
			root,
			"Paint Brush",
			method_name,
			args,
			false,
			Callable(plugin, "_record_history"),
			# Named after the brush. Painting a run of brushes quickly used to merge
			# them all into one entry whose redo only repainted the last one.
			"paint_brush|%s" % (brush_id if brush_id != "" else str(brush.get_instance_id())),
			false,
			# The paint writes `material_override` on the node. It does not reach
			# the palette, not even for a material no slot holds, so the brush is
			# the whole of the change and the undo step is that brush (#761).
			[brush_id] if brush_id != "" else []
		)
	)
	note_material_used(root, mat)


## Paint every brush in `brushes` with `mat` as one undo step, the way a
## favourite is applied to a brush selection (#1439). The step names those brushes
## and nothing else, as one brush's paint does (#761), and a selection that
## already has the material records none. Returns how many brushes were painted.
static func paint_brushes_with_undo(
	plugin: Object, root: Node, brushes: Array, mat: Material
) -> int:
	if not root or not mat:
		return 0
	var ids: Array = []
	var targets: Array = []
	for brush in brushes:
		if not is_instance_valid(brush):
			continue
		targets.append(brush)
		var brush_id := str(root.get_brush_info_from_node(brush).get("brush_id", ""))
		if brush_id != "":
			ids.append(brush_id)
	if targets.is_empty():
		return 0
	# A brush with no id cannot be named in a scope, so the step takes the level.
	var scope_ids: Array = ids if ids.size() == targets.size() else []
	var before := HFUndoHelper.capture_scope_or_state(root, scope_ids)
	for i in targets.size():
		if scope_ids.is_empty():
			root.apply_material_to_brush(targets[i], mat)
		else:
			root.apply_material_to_brush_by_id(scope_ids[i], mat)
	HFUndoHelper.commit_completed_if_changed(
		plugin._get_undo_redo(),
		root,
		"Paint Brushes",
		before["state"],
		Callable(plugin, "_record_history"),
		before["scope_ids"]
	)
	note_material_used(root, mat)
	return targets.size()


## Tell the level `mat` was just applied, for the material browser's Recent row
## (#1422). Every route that applies one says so, once it has; an undo or a redo
## does not.
static func note_material_used(root: Node, mat: Material) -> void:
	if root and mat and root.has_signal("material_used"):
		root.material_used.emit(mat)


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
	# The whole look as well, for Apply Picked Look. Apply Last Texture still
	# reads the slot alone.
	dock.remember_picked_look(face)
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
	var brushes: Array = []
	for node in plugin.hf_selection:
		if node is DraftBrush:
			brushes.append(node)
	# One step for the selection. Each brush used to commit its own, so a swatch
	# on three brushes took three Ctrl+Z to take back.
	var painted := paint_brushes_with_undo(plugin, root, brushes, mat)
	if painted > 0:
		dock.show_toast(
			(
				"Applied %s to %d brush%s"
				% [MaterialManager.material_label(mat), painted, "" if painted == 1 else "es"]
			),
			0
		)


## Apply favourite `slot`, 1 to `HFMaterialBrowser.FAVORITE_SLOTS`: the material
## on the context toolbar's button of that number, which Alt+1 to Alt+9 press
## (#1439). It goes where the button's does, the selected faces or else the
## selected brushes. An empty slot says so and changes nothing.
static func apply_favorite(plugin: Object, slot: int) -> void:
	var dock = plugin.dock
	if not dock:
		return
	var favourites: Array = (
		dock.material_browser.get_favorite_infos(HFMaterialBrowserType.FAVORITE_SLOTS)
		if dock.material_browser
		else []
	)
	if slot < 1 or slot > favourites.size():
		dock.show_toast(
			"Favorite %d is empty: star a material in Paint > Materials to fill it" % slot, 1
		)
		return
	apply_context_material(plugin, int(favourites[slot - 1].get("index", -1)))
