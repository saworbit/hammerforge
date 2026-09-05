extends GutTest
## Boundary coverage for the extracted editor-side material commands.

const HFPluginMaterialCommands = preload("res://addons/hammerforge/plugin_material_commands.gd")
const DraftBrushScript = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")


class FakeMaterialBrowser:
	extends RefCounted

	var selected: Array = []

	func set_selected_index(index: int) -> void:
		selected.append(index)


class FakeDock:
	extends RefCounted

	var _selected_material_index := -1
	var material_browser := FakeMaterialBrowser.new()
	var toasts: Array = []
	var face_count := 0
	var face_assigns := 0

	func show_toast(text: String, level: int = 0) -> void:
		toasts.append({"text": text, "level": level})

	func _count_selected_faces() -> int:
		return face_count

	func _on_face_assign_material() -> void:
		face_assigns += 1

	func toast_texts() -> Array:
		var out: Array = []
		for toast in toasts:
			out.append(toast["text"])
		return out


class FakeMaterialManager:
	extends RefCounted

	var materials: Dictionary = {}

	func get_material(index: int) -> Material:
		return materials.get(index, null)


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var hf_selection: Array = []
	var active_root: Node = null
	var last_3d_camera = null
	var last_3d_mouse_pos := Vector2(10, 20)
	var _last_picked_material_index := -1

	var surface_allowed := true
	var surface_checks: Array = []
	var commits: Array = []

	func _get_level_root() -> Node:
		return active_root

	func _get_undo_redo():
		return null

	func _record_history(_action: String) -> void:
		pass

	func _managed_action_surface_allowed(_root: Node, action: String) -> bool:
		surface_checks.append(action)
		return surface_allowed


var plugin: FakePlugin


func before_each():
	plugin = FakePlugin.new()


func after_each():
	plugin = null


func _make_root(hit: Dictionary = {}) -> Node3D:
	var script := GDScript.new()
	script.source_code = """
extends Node3D

var material_manager = null
var face_hit: Dictionary = {}
var pick_calls := 0
var applied: Array = []

func pick_face(_camera, _pos) -> Dictionary:
	pick_calls += 1
	return face_hit

func get_brush_info_from_node(node) -> Dictionary:
	return {"brush_id": str(node.get("brush_id"))}

func apply_material_to_brush_by_id(brush_id, mat) -> void:
	applied.append({"brush_id": brush_id, "mat": mat})

# HFUndoHelper keeps collation state even on the direct-call path, so a level
# that can be committed against has to be able to snapshot itself.
func capture_state() -> Dictionary:
	return {"applied": applied.size()}

func capture_full_state() -> Dictionary:
	return capture_state()
"""
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	node.face_hit = hit
	add_child_autofree(node)
	return node


func _make_brush(brush_id: String, material_index: int = -1) -> DraftBrushScript:
	var brush = DraftBrushScript.new()
	brush.brush_id = brush_id
	add_child_autofree(brush)
	if material_index >= 0:
		var face = FaceDataScript.new()
		face.material_idx = material_index
		var faces: Array[FaceDataScript] = [face]
		brush.faces = faces
	return brush


# ---------------------------------------------------------------------------
# Picking
# ---------------------------------------------------------------------------


func test_picking_an_empty_spot_says_so_and_changes_nothing():
	plugin.last_3d_camera = Camera3D.new()
	add_child_autofree(plugin.last_3d_camera)
	var root := _make_root()

	HFPluginMaterialCommands.pick_face_material(plugin, root)

	assert_eq(plugin.dock.toast_texts(), ["No face under cursor"])
	assert_eq(plugin._last_picked_material_index, -1)


func test_picking_an_unpainted_face_says_so_and_changes_nothing():
	plugin.last_3d_camera = Camera3D.new()
	add_child_autofree(plugin.last_3d_camera)
	var brush := _make_brush("b1", -1)
	var root := _make_root({"brush": brush, "face_idx": 0})

	HFPluginMaterialCommands.pick_face_material(plugin, root)

	assert_eq(plugin.dock.toast_texts(), ["Face has no material assigned"])
	assert_eq(plugin._last_picked_material_index, -1)


func test_picking_a_painted_face_selects_it_in_the_dock_and_the_browser():
	plugin.last_3d_camera = Camera3D.new()
	add_child_autofree(plugin.last_3d_camera)
	var brush := _make_brush("b1", 4)
	var root := _make_root({"brush": brush, "face_idx": 0})

	HFPluginMaterialCommands.pick_face_material(plugin, root)

	assert_eq(plugin.dock._selected_material_index, 4)
	assert_eq(plugin._last_picked_material_index, 4, "Apply Last Texture reuses this")
	assert_eq(plugin.dock.material_browser.selected, [4], "The grid follows the pick")
	assert_eq(plugin.dock.toast_texts(), ["Picked material #4"])


func test_picking_needs_a_camera():
	var root := _make_root({"brush": _make_brush("b1", 4), "face_idx": 0})

	HFPluginMaterialCommands.pick_face_material(plugin, root)

	assert_eq(root.pick_calls, 0, "There is no ray to cast without a viewport camera")


func test_picking_an_out_of_range_face_is_ignored():
	plugin.last_3d_camera = Camera3D.new()
	add_child_autofree(plugin.last_3d_camera)
	var brush := _make_brush("b1", 4)
	var root := _make_root({"brush": brush, "face_idx": 99})

	HFPluginMaterialCommands.pick_face_material(plugin, root)

	assert_true(plugin.dock.toasts.is_empty())
	assert_eq(plugin._last_picked_material_index, -1)


# ---------------------------------------------------------------------------
# Painting one brush
# ---------------------------------------------------------------------------


func test_repainting_a_brush_with_what_it_already_has_is_not_an_undo_entry():
	var root := _make_root()
	var brush := _make_brush("b1")
	var mat := StandardMaterial3D.new()
	brush.material_override = mat

	HFPluginMaterialCommands.paint_brush_with_undo(plugin, root, brush, mat)

	assert_true(root.applied.is_empty(), "Nothing changed, so there is nothing to undo")


func test_painting_a_brush_goes_through_its_stable_id():
	var root := _make_root()
	var brush := _make_brush("b1")

	HFPluginMaterialCommands.paint_brush_with_undo(plugin, root, brush, StandardMaterial3D.new())

	assert_eq(root.applied.size(), 1, "The change is applied through the level, not the node")
	assert_eq(
		root.applied[0]["brush_id"],
		"b1",
		"By id, so undo still resolves if the node is replaced by a later operation"
	)


func test_painting_needs_both_a_level_and_a_brush():
	var root := _make_root()
	HFPluginMaterialCommands.paint_brush_with_undo(plugin, root, null, StandardMaterial3D.new())
	HFPluginMaterialCommands.paint_brush_with_undo(
		plugin, null, _make_brush("b1"), StandardMaterial3D.new()
	)
	assert_true(root.applied.is_empty())


# ---------------------------------------------------------------------------
# The context toolbar swatches
# ---------------------------------------------------------------------------


func test_context_material_prefers_selected_faces_over_selected_brushes():
	var root := _make_root()
	root.material_manager = FakeMaterialManager.new()
	root.material_manager.materials[2] = StandardMaterial3D.new()
	plugin.active_root = root
	plugin.hf_selection = [_make_brush("b1")]
	plugin.dock.face_count = 3

	HFPluginMaterialCommands.apply_context_material(plugin, 2)

	assert_eq(plugin.dock.face_assigns, 1, "Picking faces is the more specific thing the user did")
	assert_true(root.applied.is_empty(), "A whole-brush repaint would throw that work away")


func test_context_material_paints_every_selected_brush():
	var root := _make_root()
	root.material_manager = FakeMaterialManager.new()
	root.material_manager.materials[2] = StandardMaterial3D.new()
	plugin.active_root = root
	plugin.hf_selection = [_make_brush("b1"), _make_brush("b2")]

	HFPluginMaterialCommands.apply_context_material(plugin, 2)

	assert_eq(root.applied.size(), 2)
	assert_eq(plugin.dock._selected_material_index, 2)


func test_context_material_asks_the_shared_scope_guard_first():
	var root := _make_root()
	root.material_manager = FakeMaterialManager.new()
	root.material_manager.materials[2] = StandardMaterial3D.new()
	plugin.active_root = root
	plugin.hf_selection = [_make_brush("b1")]
	plugin.surface_allowed = false

	HFPluginMaterialCommands.apply_context_material(plugin, 2)

	assert_eq(plugin.surface_checks, ["apply_context_material"])
	assert_true(root.applied.is_empty(), "A Godot selection is not ours to repaint")
	assert_eq(plugin.dock._selected_material_index, -1, "And the dock is not changed either")


func test_context_material_ignores_an_index_with_no_material():
	var root := _make_root()
	root.material_manager = FakeMaterialManager.new()
	plugin.active_root = root
	plugin.hf_selection = [_make_brush("b1")]

	HFPluginMaterialCommands.apply_context_material(plugin, 9)

	assert_true(root.applied.is_empty())
