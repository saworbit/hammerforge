@tool
class_name HFPluginVertexInput
extends RefCounted
## Vertex/edge mode pointer and shortcut dispatch extracted from plugin.gd.

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFPluginVertexOps = preload("plugin_vertex_ops.gd")
@warning_ignore_restore("shadowed_global_identifier")


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
			HFPluginVertexOps.merge_selected(plugin, root)
			return STOP
		# Ctrl+B: snap the selected vertices to the grid
		if keymap and keymap.matches("vertex_snap_to_grid", event):
			HFPluginVertexOps.snap_selected_to_grid(plugin, root)
			return STOP
		# Ctrl+E: split edge
		if keymap and keymap.matches("vertex_split_edge", event):
			HFPluginVertexOps.split_selected_edge(plugin, root)
			return STOP

	# Mouse click — select or begin drag
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if vs.sub_mode == vs.VertexSubMode.EDGE:
				# Edge sub-mode: pick edges
				var edge_pick: Dictionary = vs.pick_edge(cam, pos)
				if edge_pick.is_empty():
					if not event.shift_pressed:
						vs.clear_selection()
					plugin._update_vertex_overlay(root, cam)
					return PASS
				vs.select_edge(edge_pick.brush_id, edge_pick.edge, event.shift_pressed)
				# Begin drag using edge midpoint
				plugin._vertex_drag_active = true
				plugin._vertex_drag_start = pos
				vs.begin_drag(edge_pick.world_midpoint)
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
