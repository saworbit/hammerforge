@tool
class_name HFPluginVertexOps
extends RefCounted
## Vertex edit mode lifecycle and the undoable vertex operations.
##
## Pointer handling for the mode lives in HFPluginVertexInput and the ImmediateMesh
## overlay lives in HFPluginOverlays. This module owns entering and leaving the
## mode, the merge/split/clip commands, and how a vertex change reaches undo.

# ---------------------------------------------------------------------------
# Mode lifecycle
# ---------------------------------------------------------------------------


## Enter or leave vertex edit mode. Vertex editing is reached from Select, so
## turning it on has to close whatever else owns the pointer first.
static func toggle_mode(plugin: Object, root: Node) -> void:
	# `plugin` is untyped here, so the bool needs to be declared, not inferred.
	var enabling: bool = not plugin._vertex_mode
	if enabling:
		plugin._close_face_select_mode("Face Select closed for vertex editing")
	plugin._prepare_tool_transition(root)
	if (
		enabling
		and plugin.dock
		and plugin.dock.paint_mode
		and plugin.dock.paint_mode.button_pressed
	):
		plugin.dock.highlight_tab("Brush")
	plugin._vertex_mode = enabling
	if plugin._vertex_mode:
		plugin._deactivate_external_tool()
		if root and root.vertex_system:
			root.vertex_system.clear_selection()
			# Pass current brush selection
			var brushes: Array = []
			for node in plugin.hf_selection:
				if node is DraftBrush:
					brushes.append(node)
			root.vertex_system.set_selection(brushes)
			root.input_state.begin_vertex_edit()
	else:
		if root and root.vertex_system:
			if plugin._vertex_drag_active:
				root.vertex_system.cancel_drag()
				plugin._vertex_drag_active = false
			root.vertex_system.clear_selection()
			root.input_state.end_vertex_edit()
		plugin._clear_vertex_overlay()
	if plugin.dock:
		plugin.dock.set_vertex_mode(plugin._vertex_mode)
	plugin._update_hud_context()


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


## Merge Vertices, from its key and from the palette and toolbar alike: in each
## brush with two or more vertices selected, those vertices go to their centroid,
## every brush in one undo step. A brush the merge would break is left as it was
## and the vertex system says why. The selection is cleared after, as a merge
## renumbers the brush's vertices. True when any brush changed.
static func merge_selected(plugin: Object, root: Node) -> bool:
	var vs = root.vertex_system if root else null
	if not vs:
		return false
	var brush_ids: Array = []
	for brush_id in vs.selected_vertices:
		if vs.selected_vertices[brush_id].size() >= 2:
			brush_ids.append(brush_id)
	if brush_ids.is_empty():
		root.emit_signal(
			"user_message", "Merge Vertices: select two or more vertices of one brush", 1
		)
		return false
	var snapshots: Dictionary = {}
	for brush_id in brush_ids:
		var merged: bool = vs.merge_vertices(brush_id, vs.selected_vertices[brush_id])
		# Each merge snapshots only its own brush, and a refused one leaves its
		# snapshot behind, so take it either way and keep the ones that merged.
		var taken: Dictionary = vs.get_pre_op_snapshots()
		if merged:
			snapshots.merge(taken)
	vs.clear_selection()
	if plugin._vertex_mode:
		plugin._update_vertex_overlay(root, null)
	if snapshots.is_empty():
		return false
	commit_op(plugin, root, snapshots, "Merge Vertices")
	return true


## Split Edge, from its key and from the palette and toolbar alike: a vertex at
## the middle of the one selected edge, as one undo step. True when it split.
static func split_selected_edge(plugin: Object, root: Node) -> bool:
	var vs = root.vertex_system if root else null
	if not vs:
		return false
	var sel: Array = vs.get_single_selected_edge()
	if sel.size() != 2:
		root.emit_signal("user_message", "Split Edge: select one edge first", 1)
		return false
	var split: bool = vs.split_edge(sel[0], sel[1])
	var snapshots: Dictionary = vs.get_pre_op_snapshots()
	vs.clear_selection()
	if plugin._vertex_mode:
		plugin._update_vertex_overlay(root, null)
	if not split:
		root.emit_signal("user_message", "Split Edge: the edge is no longer on its brush", 1)
		return false
	commit_op(plugin, root, snapshots, "Split Edge")
	return true


## Clip to Convex, from the palette and toolbar: each brush with vertices
## selected that is not convex is rebuilt from its convex hull, every brush in
## one undo step. True when any brush changed.
static func clip_to_convex(plugin: Object, root: Node) -> bool:
	var vs = root.vertex_system if root else null
	if not vs:
		return false
	if not vs.has_selection():
		root.emit_signal("user_message", "Clip to Convex: select vertices of the brush first", 1)
		return false
	var snapshots: Dictionary = {}
	for brush_id in vs.selected_vertices.keys():
		var clipped: bool = vs.clip_to_convex(brush_id)
		var taken: Dictionary = vs.get_pre_op_snapshots()
		if clipped:
			snapshots.merge(taken)
	if snapshots.is_empty():
		root.emit_signal("user_message", "Brush is already convex", 0)
		return false
	# The hull renumbers the brush's vertices, so the selection would name others.
	vs.clear_selection()
	if plugin._vertex_mode:
		plugin._update_vertex_overlay(root, null)
	commit_op(plugin, root, snapshots, "Clip to Convex")
	root.emit_signal("user_message", "Clipped to convex hull", 0)
	return true


## Snap Vertices to Grid, from its key and from the palette and toolbar alike, as
## one undo step. Vertices already on the grid move nothing and record no step.
## True when the vertices moved.
static func snap_selected_to_grid(plugin: Object, root: Node) -> bool:
	var vs = root.vertex_system if root else null
	if not vs:
		return false
	var check: HFOpResult = root.can_snap_to_grid()
	if not check.ok:
		root.emit_signal("user_message", check.user_text(), 1)
		return false
	if not vs.has_selection():
		root.emit_signal("user_message", "Snap Vertices to Grid: select vertices first", 1)
		return false
	var snapshots: Dictionary = vs.snap_selected_to_grid(root.grid_snap)
	if plugin._vertex_mode:
		plugin._update_vertex_overlay(root, null)
	if snapshots.is_empty():
		return false
	commit_op(plugin, root, snapshots, "Snap Vertices to Grid")
	return true


## Put the one selected vertex at [param target], typed in Selection Info (#1404):
## in world space, or with [param local] in its brush's own space. The brush is
## judged as a drag's release judges it, bent faces split along their outward
## fold and a dent refused, and the move is one undo step under the drag's name.
## A refused place leaves the brush as it was and the vertex system says why.
## True when the vertex moved.
##
## A typed place has no path to follow, so it goes straight to the release's
## check.
static func move_selected_vertex_to(
	plugin: Object, root: Node, target: Vector3, local: bool
) -> bool:
	var vs = root.vertex_system if root else null
	if not vs:
		return false
	if vs.is_dragging():
		root.emit_signal("user_message", "Move rejected: finish the drag first", 1)
		return false
	if vs.get_selection_count() != 1:
		root.emit_signal("user_message", "Type a place for one selected vertex at a time", 1)
		return false
	var brush_id: String = vs.selected_vertices.keys()[0]
	var index: int = vs.selected_vertices[brush_id][0]
	var brush = root.find_brush_by_id(brush_id)
	var verts: PackedVector3Array = vs.get_brush_vertices(brush) if brush else PackedVector3Array()
	if index < 0 or index >= verts.size() or not brush.is_inside_tree():
		root.emit_signal("user_message", "Move rejected: the vertex is no longer on its brush", 1)
		return false
	var xform: Transform3D = brush.global_transform
	if absf(xform.basis.determinant()) < 0.000001:
		root.emit_signal("user_message", "Move rejected: the brush is squashed flat", 1)
		return false
	var goal: Vector3 = target if local else xform.affine_inverse() * target
	if not goal.is_finite():
		root.emit_signal("user_message", "Move rejected: that place is not a number", 1)
		return false
	if goal.is_equal_approx(verts[index]):
		return false
	# `move_vertices()` takes its delta in the brush's own space.
	var moved: bool = vs.move_vertices(goal - verts[index])
	# Taken either way: a refused move leaves its snapshot behind.
	var snapshots: Dictionary = vs.get_pre_op_snapshots()
	if plugin._vertex_mode:
		plugin._update_vertex_overlay(root, null)
	if not moved or snapshots.is_empty():
		return false
	commit_move(plugin, root, snapshots)
	return true


# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------


## Wire an undo action for a vertex edit that has already been applied.
##
## HFUndoHelper.commit() cannot be used for any of these: it captures undo state
## at commit time, which is after the edit, so undo would replay the edit instead
## of reverting it. The caller hands us the state it snapshotted beforehand.
##
## The vertex selection goes in the step beside the faces. A selected vertex is
## an index into the brush's vertices as its faces number them, and an edit that
## splits a face can renumber them (#1561), so each side of the step needs the
## selection that names its own faces' vertices.
static func commit_op(
	plugin: Object, root: Node, pre_op_snapshots: Dictionary, action_name: String
) -> void:
	if not plugin.undo_redo_manager:
		return
	var post_state := capture_state(root, pre_op_snapshots.keys())
	var vs = root.vertex_system if root else null
	var keeps_selection: bool = vs != null and vs.has_method("selection_state")
	plugin.undo_redo_manager.create_action(action_name, 0, null, false)
	plugin.undo_redo_manager.add_do_method(root, "_apply_vertex_faces", post_state)
	plugin.undo_redo_manager.add_undo_method(root, "_apply_vertex_faces", pre_op_snapshots)
	if keeps_selection:
		plugin.undo_redo_manager.add_do_method(
			root, "_apply_vertex_selection", vs.selection_state()
		)
		plugin.undo_redo_manager.add_undo_method(
			root, "_apply_vertex_selection", vs.selection_before_edit(pre_op_snapshots.keys())
		)
	plugin.undo_redo_manager.commit_action()
	plugin._record_history(action_name)


static func commit_move(plugin: Object, root: Node, pre_drag_snapshots: Dictionary) -> void:
	commit_op(plugin, root, pre_drag_snapshots, "Move Vertices")


## Each of the given brushes as it stands, read straight off the tree: its faces
## and the shape they belong to, the same `geometry_state()` the vertex system
## snapshots before an edit, so undo and redo both put the shape back (#1538).
static func capture_state(root: Node, brush_ids: Array) -> Dictionary:
	var state: Dictionary = {}
	for brush_id in brush_ids:
		var brush = root.brush_system.find_brush_by_id(brush_id) if root.brush_system else null
		if brush and brush.get("faces") and brush.has_method("geometry_state"):
			state[brush_id] = brush.geometry_state()
	return state
