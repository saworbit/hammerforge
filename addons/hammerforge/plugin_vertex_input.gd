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
const HFKeymapType = preload("hf_keymap.gd")


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
		# Undo, Redo, Save and Run are Godot's, as in the router (#1617).
		if HFKeymapType.godot_editor_uses(event):
			return PASS
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
		# With corners selected, Delete, the arrows and the turn keys edit them
		# rather than the whole brush (#1713).
		if vs.has_selection() and not vs.is_dragging():
			if keymap and keymap.matches("delete", event):
				HFPluginVertexOps.delete_selected(plugin, root)
				return STOP
			if HFKeymapType.fixed_key(event) == "nudge" and not event.ctrl_pressed:
				var step: float = root.grid_snap if root.grid_snap > 0.0 else 1.0
				if event.alt_pressed:
					step *= 0.1
				var direction: Vector3 = plugin._get_nudge_direction(event.keycode)
				HFPluginVertexOps.nudge_selected(plugin, root, direction * step)
				return STOP
			if keymap and keymap.matches("rotate_ccw", event):
				HFPluginVertexOps.turn_selected(plugin, root, 1)
				return STOP
			if keymap and keymap.matches("rotate_cw", event):
				HFPluginVertexOps.turn_selected(plugin, root, -1)
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
				# Alt on a face or the grid adds a corner there (#1713).
				if event.alt_pressed:
					_add_corner_at(plugin, root, cam, pos)
					return STOP
				# A drag from empty space selects every corner in its box.
				if _begin_marquee(plugin, root, cam, event, pos):
					return STOP
				if not event.shift_pressed:
					vs.clear_selection()
				plugin._update_vertex_overlay(root, cam)
				return PASS
			if event.alt_pressed:
				# Just this brush's corner.
				vs.select_vertex(pick.brush_id, pick.vertex_index, event.shift_pressed)
				plugin._vertex_shared_count = 1
			elif event.ctrl_pressed:
				# Take the corner, and its partners, away; nothing is dragged.
				if (
					vs.selected_vertices.has(pick.brush_id)
					and ((vs.selected_vertices[pick.brush_id] as PackedInt32Array).has(
						pick.vertex_index
					))
				):
					vs.select_shared_corner(pick.brush_id, pick.vertex_index, true)
				plugin._update_vertex_overlay(root, cam)
				return STOP
			else:
				# Every selected brush's corner at this spot (#1713).
				plugin._vertex_shared_count = vs.select_shared_corner(
					pick.brush_id, pick.vertex_index, event.shift_pressed
				)
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
		if plugin._vertex_marquee_active:
			_end_marquee(plugin, root, cam, pos)
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
		if plugin._vertex_marquee_active:
			plugin._update_marquee_overlay(plugin._vertex_marquee_start, pos, true)
			return STOP
		if plugin._vertex_drag_active and vs.is_dragging():
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
				plugin._vertex_drag_active = false
				vs.cancel_drag()
				plugin._update_vertex_overlay(root, cam)
				return PASS
			vs.drag_to(cam, plugin._vertex_drag_start, pos, root.input_state.axis_lock)
			plugin._update_vertex_overlay(root, cam)
			return STOP
		if vs.sub_mode == vs.VertexSubMode.EDGE:
			vs.update_edge_hover(cam, pos)
		else:
			vs.update_hover(cam, pos)
		plugin._update_vertex_overlay(root, cam)

	return PASS


## How far the pointer has to travel before a press on empty space is a box.
const MARQUEE_PX := 4.0


## A press on empty space in vertex mode starts a box over the corners: Shift
## adds what it holds and Ctrl takes it away. Over a brush that is not a corner
## the press goes on to Godot, which picks the brush to edit. True when a box
## began.
static func _begin_marquee(
	plugin: Object, root: Node, cam: Camera3D, event: InputEventMouseButton, pos: Vector2
) -> bool:
	if root.has_method("pick_face") and not root.pick_face(cam, pos).is_empty():
		return false
	plugin._vertex_marquee_active = true
	plugin._vertex_marquee_start = pos
	plugin._vertex_marquee_mode = 1 if event.shift_pressed else (2 if event.ctrl_pressed else 0)
	return true


static func _end_marquee(plugin: Object, root: Node, cam: Camera3D, pos: Vector2) -> void:
	var vs = root.vertex_system
	plugin._vertex_marquee_active = false
	plugin._update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
	var start: Vector2 = plugin._vertex_marquee_start
	if start.distance_to(pos) < MARQUEE_PX:
		if int(plugin._vertex_marquee_mode) == 0:
			vs.clear_selection()
	else:
		vs.select_in_rect(cam, Rect2(start, pos - start).abs(), int(plugin._vertex_marquee_mode))
	plugin._update_vertex_overlay(root, cam)
	plugin._update_hud_context()


## Add a corner where an Alt click lands: one grid step out from the face of a
## selected brush it lands on, or on the grid for the one brush selected.
static func _add_corner_at(plugin: Object, root: Node, cam: Camera3D, pos: Vector2) -> void:
	var vs = root.vertex_system
	var step: float = root.grid_snap if root.grid_snap > 0.0 else 1.0
	var hit: Dictionary = root.pick_face(cam, pos) if root.has_method("pick_face") else {}
	var brush = hit.get("brush", null)
	var selected: Array = vs._get_selected_brushes()
	if brush != null and selected.has(brush):
		var face = brush.faces[int(hit.get("face_idx", 0))]
		var normal: Vector3 = face.normal_through(brush.global_transform.basis)
		var on: Vector3 = root._snap_point(hit.get("position", Vector3.ZERO))
		HFPluginVertexOps.add_corner(plugin, root, str(brush.brush_id), on + normal * step)
		return
	if selected.size() != 1:
		root.emit_signal(
			"user_message",
			"Add Vertex: Alt+click a face of a selected brush, or select one brush",
			1
		)
		return
	var ground: Dictionary = root._raycast(cam, pos) if root.has_method("_raycast") else {}
	if ground.get("position") is Vector3:
		HFPluginVertexOps.add_corner(
			plugin, root, str(selected[0].brush_id), root._snap_point(ground["position"])
		)
