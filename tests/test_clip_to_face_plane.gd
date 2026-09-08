extends GutTest

## Clip to Face Plane against the two things it has to survive: the undo stack,
## and the Face Select mode transitions the user actually goes through.
##
## The undo checks run on a real LevelRoot and drive `capture_state()` and
## `restore_state()` directly, because that is the pair the editor action is
## built from. An EditorUndoRedoManager cannot be constructed outside the
## editor, so the manager itself is not what is under test here — the do method
## being replayable and the undo snapshot being taken are.

const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const HFPluginToolModes = preload("res://addons/hammerforge/plugin_tool_modes.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _make_brush(position: Vector3, size: Vector3) -> DraftBrush:
	var brush = (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, position),
			}
		)
	)
	return brush as DraftBrush


func _brush_id(brush: DraftBrush) -> String:
	return str(root.get_brush_info_from_node(brush).get("brush_id", ""))


func _draft_brushes() -> Array:
	var out: Array = []
	for node in root._iter_pick_nodes():
		if node is DraftBrush:
			out.append(node)
	return out


## The plane through world X = 0, facing +X.
func _yz_plane() -> Plane:
	return Plane(Vector3.RIGHT, 0.0)


# ===========================================================================
# The batch is one replayable operation (#197)
# ===========================================================================


func test_one_call_cuts_every_named_brush():
	var a := _make_brush(Vector3.ZERO, Vector3(64, 64, 64))
	var b := _make_brush(Vector3(0, 96, 0), Vector3(64, 64, 64))

	var cut := root.clip_brushes_by_plane([_brush_id(a), _brush_id(b)], _yz_plane())

	assert_eq(cut, 2, "both brushes straddle the plane, so both are cut")
	assert_eq(_draft_brushes().size(), 4, "two brushes become four pieces")


func test_the_batch_survives_undo_and_redo_as_one_step():
	var a := _make_brush(Vector3.ZERO, Vector3(64, 64, 64))
	var b := _make_brush(Vector3(0, 96, 0), Vector3(64, 64, 64))
	var ids := [_brush_id(a), _brush_id(b)]
	var plane := _yz_plane()

	# This pair is exactly what the editor action registers: restore_state as the
	# undo method against a snapshot taken before the first cut, and the batch
	# call as the do method.
	var before := root.capture_state()
	root.clip_brushes_by_plane(ids, plane)
	assert_eq(_draft_brushes().size(), 4)

	root.restore_state(before)
	assert_eq(_draft_brushes().size(), 2, "undo has to bring back every original brush")
	for brush in _draft_brushes():
		assert_almost_eq(brush.size.x, 64.0, 0.001, "an undone piece is a whole brush again")

	root.clip_brushes_by_plane(ids, plane)
	assert_eq(_draft_brushes().size(), 4, "redo replays the whole batch, not just the last brush")


func test_a_redo_still_works_when_the_reference_brush_was_one_of_the_targets():
	# The cut is carried as a plane rather than a brush and face index, so the
	# reference disappearing into its own pieces cannot break the replay.
	var reference := _make_brush(Vector3(0, 0, 0), Vector3(64, 64, 64))
	var reference_id := _brush_id(reference)
	var plane: Plane = root.face_world_plane(reference_id, 0)
	assert_gt(plane.normal.length_squared(), 0.5, "the reference face has to give a plane")

	var target := _make_brush(Vector3(16, 0, 0), Vector3(64, 64, 64))
	var ids := [reference_id, _brush_id(target)]

	var before := root.capture_state()
	assert_eq(root.clip_brushes_by_plane(ids, plane), 1, "only the target straddles that plane")
	root.restore_state(before)
	assert_eq(root.clip_brushes_by_plane(ids, plane), 1, "the replay does not need the reference")


func test_a_plane_that_misses_a_brush_is_reported_before_anything_is_cut():
	var away := _make_brush(Vector3(500, 0, 0), Vector3(64, 64, 64))

	assert_false(
		root.plane_splits_brush(_brush_id(away), _yz_plane()),
		"a plane outside the brush must be refused before the undo action opens"
	)
	assert_eq(_draft_brushes().size(), 1, "asking must not change anything")


# ===========================================================================
# The Face Select round trip (#196)
# ===========================================================================


class FakeButton:
	extends RefCounted

	var button_pressed := false

	func set_pressed_no_signal(value: bool) -> void:
		button_pressed = value


class FakeDock:
	extends RefCounted

	var paint_mode := FakeButton.new()
	var tool_select := FakeButton.new()
	var face_select_mode := FakeButton.new()
	var toasts: Array = []

	func show_toast(text: String, level: int = 0) -> void:
		toasts.append({"text": text, "level": level})

	func is_face_select_mode_enabled() -> bool:
		return face_select_mode.button_pressed


class FakeGizmoPlugin:
	extends RefCounted

	func cancel_active_handle_action() -> void:
		pass


class FakeToolRegistry:
	extends RefCounted

	func has_active_external_tool() -> bool:
		return false

	func deactivate_current() -> void:
		pass


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var brush_gizmo_plugin := FakeGizmoPlugin.new()
	var _tool_registry := FakeToolRegistry.new()
	var _radial_menu = null
	var active_root: Node = null
	var undo_redo_manager = null
	var hf_selection: Array = []
	var _face_mode_saved_object_selection: Array = []
	var _vertex_mode := false
	var _vertex_drag_active := false
	var _texture_picker_active := false
	var _applying_hf_selection := false
	var history: Array = []
	var closed_face_select := 0

	func _get_level_root() -> Node:
		return active_root

	func _brush_gizmo_action_active() -> bool:
		return false

	func _finish_stale_paint_strokes(_root, _input_state, _paint_tool) -> bool:
		return false

	func _cancel_selection_gesture() -> bool:
		return false

	func _toggle_vertex_mode(_root: Node) -> void:
		_vertex_mode = false

	func _update_hud_context() -> void:
		pass

	func _ensure_selection_runtime_state() -> void:
		pass

	func _current_selection_nodes() -> Array:
		return hf_selection.duplicate()

	func _apply_hf_selection(_selection) -> void:
		pass

	func _managed_entity_owner(_root: Node, _node: Node) -> Node:
		return null

	func _get_undo_redo():
		return null

	func _record_history(action_name: String) -> void:
		history.append(action_name)

	func _close_face_select_mode(_message: String = "") -> bool:
		closed_face_select += 1
		dock.face_select_mode.button_pressed = false
		return true

	func get_editor_interface():
		return self

	func get_selection():
		return null


var plugin: FakePlugin


## Walk the real mode transitions: select the targets, then open Face Select,
## then pick the reference face. Nothing here assigns the two selection stores
## by hand, which is the whole point of the issue.
func _enter_face_select_with(targets: Array, reference: DraftBrush, face_index: int) -> void:
	plugin = FakePlugin.new()
	plugin.active_root = root
	plugin.hf_selection = targets.duplicate()
	plugin.dock.face_select_mode.button_pressed = true
	HFPluginToolModes.on_face_select_mode_toggled(plugin, true)
	root.face_selection = {_brush_id(reference): [face_index]}


func test_face_select_hides_the_object_selection_but_the_cut_still_finds_it():
	var target := _make_brush(Vector3.ZERO, Vector3(64, 64, 64))
	# Turned 45 degrees about Z and set aside on Z, so its +X face plane still
	# runs diagonally through the target.
	var reference := _make_brush(Vector3(0, 0, 64), Vector3(32, 32, 32))
	reference.rotation_degrees = Vector3(0, 0, 45)
	reference.rebuild_preview()
	_enter_face_select_with([target], reference, 0)

	assert_eq(plugin._current_selection_nodes().size(), 0, "Face Select empties the selection")
	assert_eq(
		plugin._face_mode_saved_object_selection.size(), 1, "and saves what was selected first"
	)

	var cut := HFPluginEditActions.clip_to_face_plane_selected(plugin, root)

	assert_true(cut, "the command has to find the targets Face Select put away")
	assert_eq(plugin.history, ["Clip to Face Plane"], "one history entry for the whole cut")
	assert_eq(_draft_brushes().size(), 3, "the target became two pieces beside the reference")


func test_the_cut_leaves_no_stale_selection_behind():
	var target := _make_brush(Vector3.ZERO, Vector3(64, 64, 64))
	# Turned 45 degrees about Z and set aside on Z, so its +X face plane still
	# runs diagonally through the target.
	var reference := _make_brush(Vector3(0, 0, 64), Vector3(32, 32, 32))
	reference.rotation_degrees = Vector3(0, 0, 45)
	reference.rebuild_preview()
	_enter_face_select_with([target], reference, 0)

	assert_true(HFPluginEditActions.clip_to_face_plane_selected(plugin, root))

	assert_true(root.face_selection.is_empty(), "the reference face is released")
	assert_eq(
		plugin._face_mode_saved_object_selection.size(),
		0,
		"the saved objects were replaced by the cut, so they must not be restored"
	)
	assert_eq(plugin.closed_face_select, 1, "Face Select closes once the cut is done")


func test_more_than_one_saved_target_is_cut_in_one_step():
	var first := _make_brush(Vector3.ZERO, Vector3(64, 64, 64))
	var second := _make_brush(Vector3(0, 96, 0), Vector3(64, 64, 64))
	# Far above both targets, but its +X face plane is vertical and crosses both.
	var reference := _make_brush(Vector3(0, 200, 0), Vector3(32, 32, 32))
	_enter_face_select_with([first, second], reference, 0)

	assert_true(HFPluginEditActions.clip_to_face_plane_selected(plugin, root))

	assert_eq(plugin.history.size(), 1, "a multi-brush cut is one undo step, not one per brush")
	assert_eq(_draft_brushes().size(), 5, "both targets split, the reference is untouched")


func test_a_plane_that_cuts_nothing_records_no_history():
	var away := _make_brush(Vector3(500, 0, 0), Vector3(16, 16, 16))
	var reference := _make_brush(Vector3.ZERO, Vector3(32, 32, 32))
	_enter_face_select_with([away], reference, 0)

	assert_false(HFPluginEditActions.clip_to_face_plane_selected(plugin, root))

	assert_eq(plugin.history, [], "a cut that does nothing must not reach the undo history")
	assert_eq(_draft_brushes().size(), 2, "and must not delete anything")


# ===========================================================================
# Wiring contracts
# ===========================================================================


func test_the_command_commits_through_the_undo_helper():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_edit_actions.gd")
	var start := source.find("static func clip_to_face_plane_selected")
	assert_gt(start, -1, "the command must exist")
	var body := source.substr(start, source.find("\nstatic func", start + 1) - start)
	assert_true(body.contains("HFUndoHelper.commit("), "the cut has to open an undo action")
	assert_true(body.contains('"clip_brushes_by_plane"'), "and dispatch the whole batch by name")
	assert_false(
		body.contains("plugin._record_history("), "a history label on its own is not an undo action"
	)


func test_the_viewport_routes_the_advertised_shortcut():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_input_router.gd")
	assert_true(
		source.contains('keymap.matches("clip_to_face", event)'),
		"Alt+Shift+X is advertised, so the viewport has to dispatch it"
	)
	assert_true(source.contains("plugin._clip_to_face_plane_selected(root)"))


func test_level_root_exposes_the_method_undo_dispatches_by_name():
	assert_true(root.has_method("clip_brushes_by_plane"))
