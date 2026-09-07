@tool
class_name HFPluginVertexInput
extends RefCounted
## Vertex/edge mode pointer and shortcut dispatch extracted from plugin.gd.

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS


static func handle(
	plugin: Object, event: InputEvent, root: Node, cam: Camera3D, pos: Vector2
) -> int:
	if plugin == null or event == null or root == null:
		return PASS
	var vs = root.vertex_system
	if not vs:
		return PASS
	var keymap = plugin.get("_keymap")

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		# Escape exits vertex mode
		if event.keycode == KEY_ESCAPE:
			if plugin._vertex_drag_active:
				plugin._vertex_drag_active = false
				vs.cancel_drag()
				plugin._update_vertex_overlay(root, cam)
				return STOP
			if vs.has_selection():
				vs.clear_selection()
				plugin._update_vertex_overlay(root, cam)
				return STOP
			plugin._toggle_vertex_mode(root)
			return STOP
		# E toggles edge sub-mode (without modifiers)
		if keymap and keymap.matches("vertex_edge_mode", event):
			if vs.sub_mode == vs.VertexSubMode.VERTEX:
				vs.sub_mode = vs.VertexSubMode.EDGE
				vs.clear_selection()
			else:
				vs.sub_mode = vs.VertexSubMode.VERTEX
				vs.clear_selection()
			plugin._update_vertex_overlay(root, cam)
			plugin._update_hud_context()
			return STOP
		# Ctrl+W: merge vertices
		if keymap and keymap.matches("vertex_merge", event):
			if vs.get_selection_count() >= 2:
				# Merge in first brush that has selected verts
				for brush_id in vs.selected_vertices:
					var indices: PackedInt32Array = vs.selected_vertices[brush_id]
					if indices.size() >= 2:
						var ok: bool = vs.merge_vertices(brush_id, indices)
						if ok and plugin.undo_redo_manager:
							var snapshots: Dictionary = vs.get_pre_op_snapshots()
							if not snapshots.is_empty():
								plugin._commit_vertex_op(root, snapshots, "Merge Vertices")
						vs.clear_selection()
						break
			plugin._update_vertex_overlay(root, cam)
			return STOP
		# Ctrl+E: split edge
		if keymap and keymap.matches("vertex_split_edge", event):
			var single: Array = vs.get_single_selected_edge()
			if single.size() == 2:
				var split_ok: bool = vs.split_edge(single[0], single[1])
				if split_ok and plugin.undo_redo_manager:
					var split_snapshots: Dictionary = vs.get_pre_op_snapshots()
					if not split_snapshots.is_empty():
						plugin._commit_vertex_op(root, split_snapshots, "Split Edge")
				vs.clear_selection()
			plugin._update_vertex_overlay(root, cam)
			return STOP

	# Mouse click — select or begin drag
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if vs.sub_mode == vs.VertexSubMode.EDGE:
				# Edge sub-mode: pick edges
				var pick: Dictionary = vs.pick_edge(cam, pos)
				if pick.is_empty():
					if not event.shift_pressed:
						vs.clear_selection()
					plugin._update_vertex_overlay(root, cam)
					return PASS
				vs.select_edge(pick.brush_id, pick.edge, event.shift_pressed)
				# Begin drag using edge midpoint
				plugin._vertex_drag_active = true
				plugin._vertex_drag_start = pos
				vs.begin_drag(pick.world_midpoint)
				plugin._update_vertex_overlay(root, cam)
				return STOP
			# Vertex sub-mode: pick vertices
			var pick = vs.pick_vertex(cam, pos)
			if pick.is_empty():
				if not event.shift_pressed:
					vs.clear_selection()
				plugin._update_vertex_overlay(root, cam)
				return PASS
			vs.select_vertex(pick.brush_id, pick.vertex_index, event.shift_pressed)
			# Begin drag
			plugin._vertex_drag_active = true
			plugin._vertex_drag_start = pos
			vs.begin_drag(pick.world_pos)
			plugin._update_vertex_overlay(root, cam)
			return STOP
		# A canceled release means the OS/editor broke pointer capture. Restore the
		# pre-drag geometry instead of recording a partial move.
		if plugin.is_canceled_vertex_drag_release(event) and plugin._vertex_drag_active:
			plugin._vertex_drag_active = false
			vs.cancel_drag()
			plugin._update_vertex_overlay(root, cam)
			return STOP
		# Mouse release — end drag
		if plugin._vertex_drag_active:
			plugin._vertex_drag_active = false
			var snapshots = vs.end_drag()
			if not snapshots.is_empty() and plugin.undo_redo_manager:
				plugin._commit_vertex_move(root, snapshots)
			plugin._update_vertex_overlay(root, cam)
			return STOP

	# Right click cancels drag
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and plugin._vertex_drag_active
	):
		plugin._vertex_drag_active = false
		vs.cancel_drag()
		plugin._update_vertex_overlay(root, cam)
		return STOP

	# Mouse motion — update drag or hover
	if event is InputEventMouseMotion:
		if plugin._vertex_drag_active and vs.is_dragging():
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
				plugin._vertex_drag_active = false
				vs.cancel_drag()
				plugin._update_vertex_overlay(root, cam)
				return PASS
			var projection: Dictionary = vs.project_drag_screen_delta(
				cam, plugin._vertex_drag_start, pos, root.input_state.axis_lock
			)
			if bool(projection.get("valid", false)):
				var delta: Vector3 = projection.get("delta", Vector3.ZERO)
				if root.grid_snap > 0.0:
					delta = delta.snapped(Vector3.ONE * root.grid_snap)
				# Absolute updates include Vector3.ZERO so returning to the origin
				# or the same snap cell cannot leave a stale prior movement applied.
				vs.update_drag_absolute(delta)
			else:
				vs.update_drag_absolute(Vector3.ZERO)
			plugin._update_vertex_overlay(root, cam)
			return STOP
		if vs.sub_mode == vs.VertexSubMode.EDGE:
			vs.update_edge_hover(cam, pos)
		else:
			vs.update_hover(cam, pos)
		plugin._update_vertex_overlay(root, cam)

	return PASS
