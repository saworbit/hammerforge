@tool
class_name HFPluginTransformTools
extends RefCounted
## Offset and Pick Pivot: the transform tools that take a number or a point from
## the mapper rather than a step.
##
## Offset (Alt+G) opens the quick property popup with X, Y and Z and a World or
## Local choice, and Enter moves what is selected by exactly that, as one undo
## step: brushes and entities by the nudge path, vertices and the faces Face
## Select picked by the vertex move path and its solid check.
##
## Pick Pivot arms one click in the viewport. The click snaps to the nearest
## brush vertex, edge midpoint or face centre and makes it the level's pivot. It
## is a one-shot mode like the Texture Picker, and nothing leaves it armed out of
## sight: Escape, a right click, a tool or mode change, focus leaving the editor
## and a scene switch all cancel it, and the mode banner says it is armed.

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFPluginEditActions = preload("plugin_edit_actions.gd")
const HFPluginSelectionState = preload("plugin_selection_state.gd")
const HFPluginVertexOps = preload("plugin_vertex_ops.gd")
const HFTransformSystem = preload("systems/hf_transform_system.gd")
const HFUndoHelper = preload("undo_helper.gd")
const HFNumberFormat = preload("hf_number_format.gd")
@warning_ignore_restore("shadowed_global_identifier")

## How near a click must land, in pixels: `pick_vertex()`'s own reach.
const PICK_RADIUS_PX := 12.0

# ---------------------------------------------------------------------------
# Offset
# ---------------------------------------------------------------------------


## What Offset would move now, as `{"kind", "brush_ids", "entity_paths",
## "corners", "refusal"}`. In vertex mode it is the selected vertices; with faces
## picked, their corners; otherwise the selected brushes and entities. `kind` is
## "vertices", "faces", "objects", or "" with nothing to move, when `refusal`
## says so.
static func offset_targets(plugin: Object, root: Node) -> Dictionary:
	var out := {"kind": "", "brush_ids": [], "entity_paths": [], "corners": {}, "refusal": ""}
	if plugin._vertex_mode:
		var vs = root.vertex_system
		if vs == null or not vs.has_selection():
			out["refusal"] = "Offset: select vertices first"
			return out
		out["kind"] = "vertices"
		out["brush_ids"] = vs.selected_vertices.keys()
		return out
	var faces = root.get("face_selection")
	if faces is Dictionary and not (faces as Dictionary).is_empty():
		var corners := {}
		for key in faces:
			var brush := root.call("_find_brush_by_key", str(key)) as DraftBrush
			if brush == null or brush.brush_id == "":
				continue
			var picked: PackedVector3Array = corners.get(brush.brush_id, PackedVector3Array())
			for index in faces[key]:
				var face_idx := int(index)
				if face_idx >= 0 and face_idx < brush.faces.size() and brush.faces[face_idx]:
					picked.append_array(brush.faces[face_idx].local_verts)
			corners[brush.brush_id] = picked
		if not corners.is_empty():
			out["kind"] = "faces"
			out["brush_ids"] = corners.keys()
			out["corners"] = corners
			return out
	# The popup can stay open while the Scene tree changes the selection, so Enter
	# asks again rather than move the HammerForge half of a mixed one.
	var nodes: Array = plugin._current_selection_nodes()
	var scope := HFPluginSelectionState.classify_selection_scope(nodes, root)
	if scope == HFPluginSelectionState.SCOPE_MIXED:
		out["refusal"] = "Edit HammerForge and Godot nodes separately"
		return out
	var targets := HFPluginEditActions.collect_managed_targets(plugin, root)
	if targets["brush_ids"].is_empty() and targets["entity_paths"].is_empty():
		out["refusal"] = "Offset: select brushes, entities, vertices or faces first"
		return out
	out["kind"] = "objects"
	out["brush_ids"] = targets["brush_ids"]
	out["entity_paths"] = targets["entity_paths"]
	return out


## Whether a draw, an extrude or a vertex drag is under way. Typed numbers are
## theirs then, and Offset waits.
static func _gesture_under_way(plugin: Object, root: Node) -> bool:
	if plugin._vertex_drag_active:
		return true
	var state = root.get("input_state")
	return state != null and (state.is_dragging() or state.is_extruding())


## The axes Local offsets along: the way every target faces, or null when they
## do not all face one way, which leaves the world's.
static func _local_basis(root: Node, targets: Dictionary) -> Variant:
	if not root.transform_system:
		return null
	return root.transform_system.shared_selection_basis(
		targets["brush_ids"], targets["entity_paths"]
	)


## Open the Offset popup on what is selected, with the last offset in it. False,
## with nothing shown, during a draw or an extrude, and with nothing to move,
## which is said.
static func open_offset(plugin: Object, root: Node) -> bool:
	if root == null or plugin._quick_property == null:
		return false
	if not is_instance_valid(plugin._quick_property) or _gesture_under_way(plugin, root):
		return false
	var targets := offset_targets(plugin, root)
	if targets["kind"] == "":
		root.user_message.emit(targets["refusal"], 1)
		return false
	plugin._quick_property.show_offset(
		plugin._get_current_overlay_mouse_pos(),
		plugin._offset_last,
		plugin._offset_local,
		_local_basis(root, targets) != null
	)
	return true


## Move what is selected by `offset`, along the selection's own axes when `local`
## and they agree, as one undo step. The offset is kept for the next Alt+G either
## way. A vertex or face move that would leave a brush other than a convex solid
## changes nothing, and the vertex system says why. True when something moved.
static func apply_offset(plugin: Object, root: Node, offset: Vector3, local: bool) -> bool:
	plugin._offset_last = offset
	plugin._offset_local = local
	if root == null or not is_instance_valid(root) or _gesture_under_way(plugin, root):
		return false
	if not offset.is_finite() or offset.is_zero_approx():
		return false
	var targets := offset_targets(plugin, root)
	if targets["kind"] == "":
		root.user_message.emit(targets["refusal"], 1)
		return false
	var world_offset := offset
	if local:
		var basis: Variant = _local_basis(root, targets)
		if basis is Basis:
			world_offset = (basis as Basis) * offset
	match targets["kind"]:
		"objects":
			HFUndoHelper.commit(
				plugin._get_undo_redo(),
				root,
				"Offset HammerForge Objects",
				"nudge_managed_nodes",
				[targets["brush_ids"], targets["entity_paths"], world_offset],
				false,
				Callable(plugin, "_record_history"),
				"",
				true,
				targets["brush_ids"],
				targets["entity_paths"]
			)
			return true
		"vertices":
			var moved: Dictionary = root.vertex_system.offset_selected(world_offset)
			plugin._update_vertex_overlay(root, null)
			if moved.is_empty():
				return false
			HFPluginVertexOps.commit_op(plugin, root, moved, "Offset Vertices")
			return true
		"faces":
			var face_counts := _face_counts(root, targets["brush_ids"])
			var moved: Dictionary = root.vertex_system.offset_corners(
				targets["corners"], world_offset
			)
			if moved.is_empty():
				return false
			HFPluginVertexOps.commit_op(plugin, root, moved, "Offset Faces")
			# A face the move bent was cut into triangles, which renumbers the
			# brush's faces, so the picked indices would name other faces.
			if _face_counts(root, targets["brush_ids"]) != face_counts:
				root.clear_face_selection()
			return true
	return false


static func _face_counts(root: Node, brush_ids: Array) -> Array:
	var counts: Array = []
	for brush_id in brush_ids:
		var brush = root.find_brush_by_id(str(brush_id))
		counts.append(brush.faces.size() if brush is DraftBrush else -1)
	return counts


# ---------------------------------------------------------------------------
# Pick Pivot
# ---------------------------------------------------------------------------


## Arm one click in the viewport for the pivot. False without a level.
static func arm_pivot_pick(plugin: Object, root: Node) -> bool:
	if root == null:
		return false
	# One click cannot answer two pickers.
	plugin._texture_picker_active = false
	plugin._pivot_pick_armed = true
	if plugin.dock:
		plugin.dock.show_toast("Pick Pivot: click a brush vertex, edge or face. Esc cancels", 0)
	plugin._update_hud_context()
	return true


## Disarm the pick, saying so with `message` when there is one. True when it was
## armed.
static func cancel_pivot_pick(plugin: Object, message: String = "Pick Pivot cancelled") -> bool:
	if not plugin._pivot_pick_armed:
		return false
	plugin._pivot_pick_armed = false
	if message != "" and plugin.dock:
		plugin.dock.show_toast(message, 1)
	plugin._update_hud_context()
	return true


## The armed pick's share of viewport input, before any tool or mode sees it: a
## left click picks, a right click or Escape cancels, and the rest passes, so the
## camera still moves. PASS when the pick is not armed.
static func handle_pivot_pick_input(
	plugin: Object, event: InputEvent, root: Node, camera: Camera3D, pos: Vector2
) -> int:
	if not plugin._pivot_pick_armed:
		return PASS
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			pick_pivot_at(plugin, root, camera, pos)
			return STOP
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_pivot_pick(plugin)
			return STOP
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_pivot_pick(plugin)
		return STOP
	return PASS


## Set the pivot to the brush vertex, edge midpoint or face centre nearest `pos`
## and make Pick the level's Pivot. A click with none in reach says so and stays
## armed for another. True when the pivot was set.
static func pick_pivot_at(plugin: Object, root: Node, camera: Camera3D, pos: Vector2) -> bool:
	var hit := {}
	if root and root.vertex_system:
		hit = root.vertex_system.pick_snap_point(
			camera, pos, _pickable_brushes(root), PICK_RADIUS_PX
		)
	if hit.is_empty():
		if plugin.dock:
			plugin.dock.show_toast(
				"Pick Pivot: no brush vertex, edge or face there. Click nearer one, or Esc", 1
			)
		return false
	plugin._pivot_pick_armed = false
	var point: Vector3 = hit["world_pos"]
	root.transform_pivot_point = point
	root.transform_pivot_mode = HFTransformSystem.PivotMode.CUSTOM
	if plugin.dock:
		plugin.dock.show_toast(
			"Pivot set at a %s (%s)" % [hit["kind"], HFNumberFormat.point(point, root.grid_snap)], 0
		)
	plugin._update_hud_context()
	return true


## Clear Pivot: back to the selection's centre, and any armed pick put away.
static func clear_pivot(plugin: Object, root: Node) -> void:
	cancel_pivot_pick(plugin, "")
	if root == null:
		return
	root.transform_pivot_mode = HFTransformSystem.PivotMode.SELECTION_CENTER
	if plugin.dock:
		plugin.dock.show_toast("Pivot: back to the selection centre", 0)


## The brushes a pick may land on: the ones a click can select, as they are shown.
static func _pickable_brushes(root: Node) -> Array:
	var out: Array = []
	for node in root.call("_iter_pick_nodes"):
		if node is DraftBrush and (node as DraftBrush).is_visible_in_tree():
			out.append(node)
	return out
