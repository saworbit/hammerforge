extends GutTest
## The Clip and Hollow previews must only draw for the brushes their tools
## accept. Anything else used to show a valid-looking wireframe and then fail
## with an error toast when the user clicked.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFClipPreview = preload("res://addons/hammerforge/systems/hf_clip_preview.gd")
const HFHollowPreview = preload("res://addons/hammerforge/systems/hf_hollow_preview.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFBrushSystem
var clip_preview: HFClipPreview
var hollow_preview: HFHollowPreview


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.grid_snap = 0.0
	sys = HFBrushSystem.new(root)
	root.brush_system = sys
	clip_preview = HFClipPreview.new(root)
	hollow_preview = HFHollowPreview.new(root)


func after_each():
	clip_preview.destroy()
	hollow_preview.destroy()
	clip_preview = null
	hollow_preview = null
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var brush_system = null
var brush_manager = null
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, DODECAHEDRON, ICOSAHEDRON, CUSTOM }

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out

func is_entity_node(_node: Node) -> bool:
	return false

func _log(_msg: String) -> void:
	pass

func _assign_owner(_node: Node) -> void:
	pass

func _record_last_brush(_pos: Vector3) -> void:
	pass
"""
	s.reload()
	return s


func _make_brush(brush_id: String = "brush_1") -> DraftBrush:
	var b = DraftBrush.new()
	b.size = Vector3(64, 64, 64)
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_position = Vector3.ZERO
	sys._register_brush_id(brush_id, b)
	return b


func _assert_no_clip_wireframes(context: String) -> void:
	assert_false(clip_preview._piece_a_mesh.visible, "%s: first piece must be hidden" % context)
	assert_false(clip_preview._piece_b_mesh.visible, "%s: second piece must be hidden" % context)
	assert_false(clip_preview._plane_mesh.visible, "%s: split plane must be hidden" % context)
	assert_false(clip_preview._preview_container.visible, "%s: container must be hidden" % context)


func _assert_no_hollow_wireframes(context: String) -> void:
	assert_eq(hollow_preview._active_count, 0, "%s: no wall wireframes may be active" % context)
	assert_false(
		hollow_preview._preview_container.visible, "%s: container must be hidden" % context
	)


# ===========================================================================
# Clip preview
# ===========================================================================


func test_clip_preview_draws_for_an_axis_aligned_box():
	_make_brush()
	clip_preview.show_preview("brush_1", 1, 0.0)
	assert_true(clip_preview._piece_a_mesh.visible, "A valid clip must show both pieces")
	assert_true(clip_preview._piece_b_mesh.visible, "A valid clip must show both pieces")
	assert_true(clip_preview._preview_container.visible, "A valid clip must show its container")


func test_clip_preview_stays_empty_for_a_cylinder():
	var b = _make_brush()
	b.shape = DraftBrush.BrushShape.CYLINDER
	clip_preview.show_preview("brush_1", 1, 0.0)
	_assert_no_clip_wireframes("Cylinder")
	assert_false(sys.can_clip_brush("brush_1", 1, 0.0).ok, "The tool refuses a cylinder")


func test_clip_preview_stays_empty_for_a_rotated_box():
	var b = _make_brush()
	b.rotation_degrees = Vector3(0, 45, 0)
	clip_preview.show_preview("brush_1", 1, 0.0)
	_assert_no_clip_wireframes("Rotated box")
	assert_false(sys.can_clip_brush("brush_1", 1, 0.0).ok, "The tool refuses a rotated box")


func test_clip_preview_clears_when_the_brush_becomes_a_cylinder_mid_drag():
	var b = _make_brush()
	clip_preview.show_preview("brush_1", 1, 0.0)
	assert_true(clip_preview._piece_a_mesh.visible, "Starts as a valid box preview")
	b.shape = DraftBrush.BrushShape.CYLINDER
	clip_preview.update_split(4.0)
	_assert_no_clip_wireframes("Cylinder after update_split")


# ===========================================================================
# Hollow preview
# ===========================================================================


func test_hollow_preview_draws_for_an_axis_aligned_box():
	_make_brush()
	hollow_preview.show_preview("brush_1", 4.0)
	assert_eq(hollow_preview._active_count, 6, "A valid hollow shows six walls")
	assert_true(hollow_preview._preview_container.visible, "A valid hollow shows its container")


func test_hollow_preview_stays_empty_for_a_cylinder():
	var b = _make_brush()
	b.shape = DraftBrush.BrushShape.CYLINDER
	hollow_preview.show_preview("brush_1", 4.0)
	_assert_no_hollow_wireframes("Cylinder")
	assert_false(sys.can_hollow_brush("brush_1", 4.0).ok, "The tool refuses a cylinder")


func test_hollow_preview_stays_empty_for_a_wedge():
	var b = _make_brush()
	b.shape = DraftBrush.BrushShape.WEDGE
	hollow_preview.show_preview("brush_1", 4.0)
	_assert_no_hollow_wireframes("Wedge")


func test_hollow_preview_stays_empty_for_a_rotated_box():
	var b = _make_brush()
	b.rotation_degrees = Vector3(0, 45, 0)
	hollow_preview.show_preview("brush_1", 4.0)
	_assert_no_hollow_wireframes("Rotated box")
	assert_false(sys.can_hollow_brush("brush_1", 4.0).ok, "The tool refuses a rotated box")


func test_hollow_preview_clears_when_the_brush_is_rotated_mid_drag():
	var b = _make_brush()
	hollow_preview.show_preview("brush_1", 4.0)
	assert_eq(hollow_preview._active_count, 6, "Starts as a valid box preview")
	b.rotation_degrees = Vector3(0, 45, 0)
	hollow_preview.update_thickness(6.0)
	_assert_no_hollow_wireframes("Rotated box after update_thickness")
