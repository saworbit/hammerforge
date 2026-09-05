extends GutTest
## Boundary coverage for the extracted bulk selection commands.

const HFPluginSelectionCommands = preload("res://addons/hammerforge/plugin_selection_commands.gd")
const DraftBrushScript = preload("res://addons/hammerforge/brush_instance.gd")


class FakeDock:
	extends RefCounted

	signal selection_clear_requested

	var toasts: Array = []
	var selection_count := -1
	var selection_nodes: Array = []
	var clear_requests := 0
	var assign_calls := 0
	var face_count := 0
	var _selected_material_index := -1

	func _init() -> void:
		selection_clear_requested.connect(_count_clear_request)

	func _count_clear_request() -> void:
		clear_requests += 1

	func show_toast(message: String, level: int = 0) -> void:
		toasts.append({"message": message, "level": level})

	func set_selection_count(count: int) -> void:
		selection_count = count

	func set_selection_nodes(nodes: Array) -> void:
		selection_nodes = nodes.duplicate()

	func _count_selected_faces() -> int:
		return face_count

	func _on_face_assign_material() -> void:
		assign_calls += 1

	func last_toast() -> Dictionary:
		return toasts[-1] if not toasts.is_empty() else {}


class FakeMaterialManager:
	extends RefCounted

	var material := StandardMaterial3D.new()

	func get_material(_index: int) -> Material:
		return material


class FakeRoot:
	extends Node3D

	signal face_selection_changed

	var face_selection: Dictionary = {}
	var brush_system = null
	var material_manager = FakeMaterialManager.new()
	var pick_nodes: Array = []
	var brushes_by_key: Dictionary = {}
	var face_clears := 0

	func _iter_pick_nodes() -> Array:
		return pick_nodes

	func clear_face_selection() -> void:
		face_clears += 1
		face_selection = {}

	func _find_brush_by_key(key: String):
		return brushes_by_key.get(key, null)


class FakeSelection:
	extends RefCounted

	var clears := 0

	func clear() -> void:
		clears += 1


class FakeEditorInterface:
	extends RefCounted

	var selection := FakeSelection.new()

	func get_selection() -> FakeSelection:
		return selection


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var hf_selection: Array = []
	var active_root: Node = null
	var last_3d_mouse_pos := Vector2.ZERO
	var _selection_filter = null
	var _last_picked_material_index := -1
	var _editor_interface := FakeEditorInterface.new()
	var hud_updates := 0
	var applied_hf_selection := 0
	var selection_lists: Array = []
	var painted: Array = []

	func get_editor_interface() -> FakeEditorInterface:
		return _editor_interface

	func _update_hud_context() -> void:
		hud_updates += 1

	func _apply_hf_selection(_selection) -> void:
		applied_hf_selection += 1

	func _apply_selection_list(nodes: Array, _additive: bool, _toggle: bool = false) -> void:
		selection_lists.append(nodes.duplicate())

	func _paint_brush_with_undo(_root: Node, brush: Node, mat: Material) -> void:
		painted.append({"brush": brush, "material": mat})

	func _get_level_root() -> Node:
		return active_root


var plugin: FakePlugin
var root: FakeRoot


func before_each():
	plugin = FakePlugin.new()
	root = FakeRoot.new()
	add_child_autoqfree(root)
	plugin.active_root = root


func after_each():
	plugin = null
	root = null


func _make_brush(size: Vector3, brush_id: String = "") -> DraftBrush:
	var brush = DraftBrushScript.new()
	brush.size = size
	if brush_id != "":
		brush.brush_id = brush_id
	root.add_child(brush)
	return brush


func _make_face(normal: Vector3, material_idx: int) -> FaceData:
	var face := FaceData.new()
	face.normal = normal
	face.material_idx = material_idx
	return face


func _face_list(faces: Array) -> Array[FaceData]:
	# DraftBrush.faces is Array[FaceData], so an untyped literal cannot be assigned.
	var typed: Array[FaceData] = []
	for face in faces:
		typed.append(face)
	return typed


# ---------------------------------------------------------------------------
# Similarity math
# ---------------------------------------------------------------------------


func test_sorted_vec_orders_components_ascending():
	assert_eq(HFPluginSelectionCommands.sorted_vec(Vector3(30, 10, 20)), [10.0, 20.0, 30.0])


func test_size_similar_ignores_axis_order():
	assert_true(
		HFPluginSelectionCommands.size_similar(Vector3(10, 20, 30), Vector3(30, 10, 20), 0.2),
		"A rotated brush of the same dimensions should still count as similar"
	)


func test_size_similar_rejects_outside_tolerance():
	assert_false(
		HFPluginSelectionCommands.size_similar(Vector3(10, 10, 10), Vector3(20, 20, 20), 0.2),
		"Doubling every dimension is well outside a 20 percent tolerance"
	)


func test_size_similar_guards_against_zero_reference():
	# maxf(ref, 0.01) keeps a flat brush from dividing by zero.
	assert_false(HFPluginSelectionCommands.size_similar(Vector3(1, 1, 1), Vector3.ZERO, 0.2))


# ---------------------------------------------------------------------------
# Face keys
# ---------------------------------------------------------------------------


func test_face_key_prefers_brush_id():
	var brush = _make_brush(Vector3.ONE, "brush_7")
	assert_eq(HFPluginSelectionCommands.face_key_for(brush), "brush_7")


func test_face_key_falls_back_to_instance_id():
	var brush = _make_brush(Vector3.ONE)
	assert_eq(HFPluginSelectionCommands.face_key_for(brush), str(brush.get_instance_id()))


func test_face_key_is_null_safe_now_that_it_routes_through_the_owner():
	# face_key_for had no null guard of its own. It shares HFBrushSystem's now.
	assert_eq(HFPluginSelectionCommands.face_key_for(null), "")


func test_face_key_agrees_with_the_brush_system():
	var brush := DraftBrush.new()
	brush.brush_id = "brush_9"
	assert_eq(HFPluginSelectionCommands.face_key_for(brush), HFBrushSystem.face_key(brush))
	brush.free()


# ---------------------------------------------------------------------------
# Select Similar routing
# ---------------------------------------------------------------------------


func test_select_similar_prefers_faces_when_faces_are_selected():
	# A brush is selected too, but a live face selection wins.
	var brush = _make_brush(Vector3(32, 32, 32), "b1")
	plugin.hf_selection = [brush]
	root.pick_nodes = [brush]
	root.face_selection = {"b1": [0]}
	root.brushes_by_key = {}  # reference lookup fails, so the face path bails out

	HFPluginSelectionCommands.select_similar(plugin, root)

	assert_eq(
		plugin.selection_lists.size(), 0, "The brush path must not run while faces are selected"
	)


func test_select_similar_matches_brushes_by_size():
	var reference = _make_brush(Vector3(32, 32, 32), "b1")
	var same = _make_brush(Vector3(32, 32, 32), "b2")
	var different = _make_brush(Vector3(128, 8, 8), "b3")
	plugin.hf_selection = [reference]
	root.pick_nodes = [reference, same, different]

	HFPluginSelectionCommands.select_similar(plugin, root)

	assert_eq(plugin.selection_lists.size(), 1, "The brush path should apply one selection list")
	var picked: Array = plugin.selection_lists[0]
	assert_eq(picked.size(), 2, "Both same-sized brushes should be picked")
	assert_false(picked.has(different), "The differently sized brush must be left out")


func test_select_similar_with_nothing_selected_warns():
	HFPluginSelectionCommands.select_similar(plugin, root)
	assert_eq(plugin.dock.last_toast().get("message"), "Select a face or brush first")
	assert_eq(plugin.dock.last_toast().get("level"), 1)


func test_select_similar_faces_matches_material_and_world_normal():
	var reference = _make_brush(Vector3(32, 32, 32), "b1")
	reference.faces = _face_list([_make_face(Vector3.UP, 2), _make_face(Vector3.RIGHT, 2)])
	var other = _make_brush(Vector3(32, 32, 32), "b2")
	other.faces = _face_list(
		[
			_make_face(Vector3.UP, 2),  # same material and normal
			_make_face(Vector3.UP, 5),  # same normal, wrong material
			_make_face(Vector3.DOWN, 2),  # same material, opposite normal
		]
	)
	root.pick_nodes = [reference, other]
	root.brushes_by_key = {"b1": reference}
	root.face_selection = {"b1": [0]}

	HFPluginSelectionCommands.select_similar_faces(plugin, root)

	assert_eq(root.face_selection.get("b1"), [0], "The reference up face should stay selected")
	assert_eq(root.face_selection.get("b2"), [0], "Only the matching face on b2 should be added")
	assert_eq(plugin.dock.last_toast().get("message"), "Selected 2 similar faces")


# ---------------------------------------------------------------------------
# Apply Last Texture
# ---------------------------------------------------------------------------


func test_apply_last_texture_without_a_pick_warns_and_changes_nothing():
	HFPluginSelectionCommands.apply_last_texture(plugin, root)
	assert_eq(plugin.dock.last_toast().get("level"), 1)
	assert_eq(plugin.dock._selected_material_index, -1, "The dock material must not be touched")
	assert_eq(plugin.painted.size(), 0)


func test_apply_last_texture_uses_the_face_path_when_faces_are_selected():
	plugin._last_picked_material_index = 3
	plugin.dock.face_count = 2

	HFPluginSelectionCommands.apply_last_texture(plugin, root)

	assert_eq(plugin.dock.assign_calls, 1, "Face assignment should run once")
	assert_eq(plugin.painted.size(), 0, "Brush painting must not also run")
	assert_eq(plugin.dock.last_toast().get("message"), "Applied last texture to 2 faces")


func test_apply_last_texture_paints_selected_brushes_when_no_faces():
	plugin._last_picked_material_index = 3
	var brush = _make_brush(Vector3.ONE, "b1")
	plugin.hf_selection = [brush]

	HFPluginSelectionCommands.apply_last_texture(plugin, root)

	assert_eq(plugin.dock.assign_calls, 0)
	assert_eq(plugin.painted.size(), 1, "The selected brush should be painted")
	assert_eq(plugin.dock.last_toast().get("message"), "Applied last texture to 1 brush")


# ---------------------------------------------------------------------------
# Select All / Deselect All
# ---------------------------------------------------------------------------


func test_select_all_collects_pick_nodes_and_clears_faces():
	var first = _make_brush(Vector3.ONE, "b1")
	var second = _make_brush(Vector3.ONE, "b2")
	root.pick_nodes = [first, second]
	root.face_selection = {"b1": [0]}

	HFPluginSelectionCommands.select_all(plugin, root)

	assert_eq(root.face_clears, 1, "Face selection is cleared so the toolbar shows object context")
	assert_eq(plugin.hf_selection.size(), 2)
	assert_eq(plugin.applied_hf_selection, 1)
	assert_eq(plugin.dock.selection_count, 2)


func test_deselect_all_requests_the_clear_before_clearing_selection():
	var brush = _make_brush(Vector3.ONE, "b1")
	plugin.hf_selection = [brush]
	root.face_selection = {"b1": [0]}

	HFPluginSelectionCommands.deselect_all(plugin, root)

	assert_eq(
		plugin.dock.clear_requests, 1, "The dock must be told before the empty-selection guard runs"
	)
	assert_eq(plugin.hf_selection.size(), 0)
	assert_eq(plugin._editor_interface.selection.clears, 1)
	assert_eq(root.face_clears, 1)
	assert_eq(plugin.dock.selection_count, 0)


# ---------------------------------------------------------------------------
# Selection filter results
# ---------------------------------------------------------------------------


func test_filter_applied_with_nodes_clears_stale_face_selection_first():
	var brush = _make_brush(Vector3.ONE, "b1")
	root.face_selection = {"b1": [0]}

	HFPluginSelectionCommands.on_filter_applied(plugin, [brush], {})

	assert_eq(root.face_selection, {}, "A node-only filter must drop the old face selection")
	assert_eq(plugin.selection_lists.size(), 1)
	assert_eq(plugin.dock.last_toast().get("message"), "Selected 1 node")


func test_filter_applied_with_faces_does_not_touch_the_node_selection():
	var brush = _make_brush(Vector3.ONE, "b1")
	root.pick_nodes = [brush]

	HFPluginSelectionCommands.on_filter_applied(plugin, [brush], {"b1": [0, 1]})

	assert_eq(root.face_selection, {"b1": [0, 1]})
	assert_eq(plugin.selection_lists.size(), 0, "Faces win, so no node list is applied")
	assert_eq(plugin.dock.last_toast().get("message"), "Selected 2 faces")
