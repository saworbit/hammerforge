extends GutTest
## Boundary coverage for extracted vertex edit mode and vertex undo wiring.

const HFPluginVertexOps = preload("res://addons/hammerforge/plugin_vertex_ops.gd")
const DraftBrushScript = preload("res://addons/hammerforge/brush_instance.gd")


class FakeInputState:
	extends RefCounted

	var begun := 0
	var ended := 0

	func begin_vertex_edit() -> void:
		begun += 1

	func end_vertex_edit() -> void:
		ended += 1


class FakeVertexSystem:
	extends RefCounted

	var selected_vertices: Dictionary = {}
	var single_edge: Array = []
	var convex_results: Dictionary = {}
	var merges: Array = []
	var splits: Array = []
	var clips: Array = []
	var clear_calls := 0
	var cancel_calls := 0
	var last_selection: Array = []

	func clear_selection() -> void:
		clear_calls += 1

	func cancel_drag() -> void:
		cancel_calls += 1

	func set_selection(nodes: Array) -> void:
		last_selection = nodes.duplicate()

	func merge_vertices(brush_id, indices: PackedInt32Array) -> void:
		merges.append({"brush_id": brush_id, "indices": indices})

	func get_single_selected_edge() -> Array:
		return single_edge

	func split_edge(brush_id, edge) -> void:
		splits.append({"brush_id": brush_id, "edge": edge})

	func clip_to_convex(brush_id) -> bool:
		clips.append(brush_id)
		return bool(convex_results.get(brush_id, false))


class FakeBrushSystem:
	extends RefCounted

	var brushes: Dictionary = {}

	func find_brush_by_id(brush_id):
		return brushes.get(brush_id, null)


class FakeRoot:
	extends Node3D

	signal user_message(text: String, level: int)

	var vertex_system := FakeVertexSystem.new()
	var brush_system := FakeBrushSystem.new()
	var input_state := FakeInputState.new()
	var messages: Array = []

	func _init() -> void:
		user_message.connect(_record_message)

	func _record_message(text: String, level: int) -> void:
		messages.append({"text": text, "level": level})


class FakePaintMode:
	extends RefCounted

	var button_pressed := false


class FakeDock:
	extends RefCounted

	var paint_mode := FakePaintMode.new()
	var highlighted: Array = []
	var vertex_mode_states: Array = []

	func highlight_tab(name: String) -> void:
		highlighted.append(name)

	func set_vertex_mode(enabled: bool) -> void:
		vertex_mode_states.append(enabled)


class FakeUndoRedo:
	extends RefCounted

	var actions: Array = []
	var do_calls: Array = []
	var undo_calls: Array = []
	var commits := 0

	func create_action(name: String, _mode: int = 0, _obj = null, _backward: bool = false) -> void:
		actions.append(name)

	func add_do_method(_target, method: String, arg) -> void:
		do_calls.append({"method": method, "arg": arg})

	func add_undo_method(_target, method: String, arg) -> void:
		undo_calls.append({"method": method, "arg": arg})

	func commit_action(_execute: bool = true) -> void:
		commits += 1


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var hf_selection: Array = []
	var undo_redo_manager = null
	var _vertex_mode := false
	var _vertex_drag_active := false
	var face_select_closes: Array = []
	var tool_transitions := 0
	var external_deactivations := 0
	var overlay_clears := 0
	var hud_updates := 0
	var history: Array = []

	func _close_face_select_mode(message: String = "") -> bool:
		face_select_closes.append(message)
		return true

	func _prepare_tool_transition(_root: Node, _notify: bool = true, _settle: bool = true) -> void:
		tool_transitions += 1

	func _deactivate_external_tool() -> void:
		external_deactivations += 1

	func _clear_vertex_overlay() -> void:
		overlay_clears += 1

	func _update_hud_context() -> void:
		hud_updates += 1

	func _record_history(action_name: String) -> void:
		history.append(action_name)


var plugin: FakePlugin
var root: FakeRoot


func before_each():
	plugin = FakePlugin.new()
	root = FakeRoot.new()
	add_child_autoqfree(root)


func after_each():
	plugin = null
	root = null


func _make_brush(brush_id: String) -> DraftBrush:
	var brush = DraftBrushScript.new()
	brush.brush_id = brush_id
	root.add_child(brush)
	root.brush_system.brushes[brush_id] = brush
	return brush


# ---------------------------------------------------------------------------
# Mode lifecycle
# ---------------------------------------------------------------------------


func test_enabling_closes_competing_pointer_owners_first():
	var brush = _make_brush("b1")
	plugin.hf_selection = [brush]

	HFPluginVertexOps.toggle_mode(plugin, root)

	assert_true(plugin._vertex_mode, "Vertex mode should be on")
	assert_eq(plugin.face_select_closes.size(), 1, "Face Select must be closed on the way in")
	assert_eq(plugin.tool_transitions, 1, "In-progress gestures must be settled")
	assert_eq(plugin.external_deactivations, 1, "External tools must give up the pointer")
	assert_eq(root.input_state.begun, 1)
	assert_eq(root.vertex_system.last_selection, [brush], "The brush selection is handed over")
	assert_eq(plugin.dock.vertex_mode_states, [true])


func test_enabling_only_passes_brushes_from_the_selection():
	var brush = _make_brush("b1")
	var plain := Node3D.new()
	root.add_child(plain)
	plugin.hf_selection = [brush, plain]

	HFPluginVertexOps.toggle_mode(plugin, root)

	assert_eq(root.vertex_system.last_selection, [brush], "Non-brush nodes are not vertex editable")


func test_disabling_cancels_an_active_drag_and_clears_the_overlay():
	plugin._vertex_mode = true
	plugin._vertex_drag_active = true

	HFPluginVertexOps.toggle_mode(plugin, root)

	assert_false(plugin._vertex_mode)
	assert_eq(root.vertex_system.cancel_calls, 1, "A live drag must be cancelled, not left running")
	assert_false(plugin._vertex_drag_active)
	assert_eq(root.input_state.ended, 1)
	assert_eq(plugin.overlay_clears, 1)
	assert_eq(plugin.dock.vertex_mode_states, [false])


func test_disabling_does_not_reclose_face_select():
	plugin._vertex_mode = true

	HFPluginVertexOps.toggle_mode(plugin, root)

	assert_eq(plugin.face_select_closes.size(), 0, "Leaving the mode should not touch Face Select")


func test_enabling_over_paint_mode_pulls_the_brush_tab_forward():
	plugin.dock.paint_mode.button_pressed = true

	HFPluginVertexOps.toggle_mode(plugin, root)

	assert_eq(plugin.dock.highlighted, ["Brush"])


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


func test_merge_needs_at_least_two_vertices():
	root.vertex_system.selected_vertices = {
		"b1": PackedInt32Array([0]),
		"b2": PackedInt32Array([0, 3]),
	}

	HFPluginVertexOps.merge_selected(root)

	assert_eq(root.vertex_system.merges.size(), 1, "A lone vertex has nothing to merge with")
	assert_eq(root.vertex_system.merges[0]["brush_id"], "b2")


func test_split_needs_a_single_selected_edge():
	root.vertex_system.single_edge = []
	HFPluginVertexOps.split_selected_edge(root)
	assert_eq(root.vertex_system.splits.size(), 0)

	root.vertex_system.single_edge = ["b1", PackedInt32Array([0, 1])]
	HFPluginVertexOps.split_selected_edge(root)
	assert_eq(root.vertex_system.splits.size(), 1)
	assert_eq(root.vertex_system.splits[0]["brush_id"], "b1")


func test_clip_to_convex_reports_when_nothing_changed():
	root.vertex_system.selected_vertices = {"b1": PackedInt32Array([0])}
	root.vertex_system.convex_results = {"b1": false}

	HFPluginVertexOps.clip_to_convex(root)

	assert_eq(root.messages.size(), 1)
	assert_eq(root.messages[0]["text"], "Brush is already convex")


func test_clip_to_convex_reports_when_any_brush_changed():
	root.vertex_system.selected_vertices = {
		"b1": PackedInt32Array([0]),
		"b2": PackedInt32Array([0]),
	}
	root.vertex_system.convex_results = {"b1": false, "b2": true}

	HFPluginVertexOps.clip_to_convex(root)

	assert_eq(root.vertex_system.clips.size(), 2, "Every selected brush is visited")
	assert_eq(root.messages[0]["text"], "Clipped to convex hull")


# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------


func test_commit_is_a_no_op_without_an_undo_manager():
	HFPluginVertexOps.commit_op(plugin, root, {"b1": []}, "Merge Vertices")
	assert_eq(plugin.history.size(), 0)


func test_commit_undoes_to_the_pre_op_snapshot_not_the_current_state():
	# The whole point of the manual wiring: undo must restore what the caller
	# captured before the edit, not what is on the brush now.
	var brush = _make_brush("b1")
	brush.faces = _one_face()
	var undo_redo := FakeUndoRedo.new()
	plugin.undo_redo_manager = undo_redo
	var pre_snapshot := {"b1": [{"marker": "before"}]}

	HFPluginVertexOps.commit_op(plugin, root, pre_snapshot, "Split Edge")

	assert_eq(undo_redo.actions, ["Split Edge"])
	assert_eq(undo_redo.commits, 1)
	assert_eq(undo_redo.undo_calls[0]["arg"], pre_snapshot, "Undo restores the pre-op snapshot")
	assert_eq(undo_redo.do_calls[0]["method"], "_apply_vertex_faces")
	var do_state: Dictionary = undo_redo.do_calls[0]["arg"]
	assert_true(do_state.has("b1"), "Redo state is read off the brush as it stands now")
	assert_ne(do_state, pre_snapshot)
	assert_eq(plugin.history, ["Split Edge"])


func test_commit_move_uses_the_move_vertices_action_name():
	var undo_redo := FakeUndoRedo.new()
	plugin.undo_redo_manager = undo_redo

	HFPluginVertexOps.commit_move(plugin, root, {})

	assert_eq(undo_redo.actions, ["Move Vertices"])
	assert_eq(plugin.history, ["Move Vertices"])


func test_capture_face_state_skips_brushes_that_are_gone():
	var brush = _make_brush("b1")
	brush.faces = _one_face()

	var state := HFPluginVertexOps.capture_face_state(root, ["b1", "missing"])

	assert_true(state.has("b1"))
	assert_false(state.has("missing"), "A deleted brush must not land in the undo state")


func _one_face() -> Array[FaceData]:
	var face := FaceData.new()
	face.normal = Vector3.UP
	var typed: Array[FaceData] = [face]
	return typed
