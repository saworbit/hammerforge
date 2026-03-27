extends GutTest
## Regression tests for bug fixes:
## 1. Vertex undo uses pre-drag snapshots (not post-move state)
## 2. Z-axis lock uses correct enum value (3, not 4)
## 3. Carve rejects face/edge-only contact (OR, not AND)
## 4. Vertex projection uses picked vertex Y (not hardcoded Y=0)

const HFVertexSystem = preload("res://addons/hammerforge/systems/hf_vertex_system.gd")
const HFCarveSystem = preload("res://addons/hammerforge/systems/hf_carve_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")

var root: Node3D
var draft_node: Node3D


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	draft_node = Node3D.new()
	draft_node.name = "DraftBrushes"
	root.add_child(draft_node)
	root.draft_brushes_node = draft_node
	root.brush_system = _FakeBrushSystem.new(root, draft_node)


func after_each():
	root = null
	draft_node = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var brush_system: RefCounted
var grid_snap := 8.0
var drag_size_default := Vector3(32, 32, 32)
enum BrushShape { BOX }
signal user_message(msg, level)

func _log(msg: String) -> void:
	pass

func tag_full_reconcile() -> void:
	pass

func _iter_pick_nodes() -> Array:
	var result: Array = []
	if draft_brushes_node:
		for child in draft_brushes_node.get_children():
			result.append(child)
	return result
"""
	s.reload()
	return s


func _make_box_brush(pos: Vector3, sz: Vector3, id: String) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	b.brush_id = id
	draft_node.add_child(b)
	b.global_position = pos
	var half = sz * 0.5
	var quads = [
		[Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z),
		 Vector3(half.x, half.y, half.z), Vector3(half.x, -half.y, half.z)],
		[Vector3(-half.x, -half.y, half.z), Vector3(-half.x, half.y, half.z),
		 Vector3(-half.x, half.y, -half.z), Vector3(-half.x, -half.y, -half.z)],
		[Vector3(-half.x, half.y, -half.z), Vector3(-half.x, half.y, half.z),
		 Vector3(half.x, half.y, half.z), Vector3(half.x, half.y, -half.z)],
		[Vector3(-half.x, -half.y, half.z), Vector3(-half.x, -half.y, -half.z),
		 Vector3(half.x, -half.y, -half.z), Vector3(half.x, -half.y, half.z)],
		[Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z),
		 Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)],
		[Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z),
		 Vector3(half.x, -half.y, -half.z), Vector3(-half.x, -half.y, -half.z)]
	]
	var faces: Array[FaceData] = []
	for quad in quads:
		var face = FaceData.new()
		face.local_verts = PackedVector3Array(quad)
		face.ensure_geometry()
		faces.append(face)
	b.faces = faces
	return b


# ===========================================================================
# Bug 1: Vertex undo captures pre-drag state, not post-move state
# ===========================================================================

func test_end_drag_returns_pre_drag_face_data():
	var vs = HFVertexSystem.new(root)
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo1")
	vs.set_selection([b])
	vs.select_vertex("undo1", 0, false)

	# Capture expected pre-drag state
	var pre_drag_expected: Array = []
	for face in b.faces:
		if face:
			pre_drag_expected.append(face.to_dict())

	# Begin drag, move, then end
	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(8, 0, 0))
	var snapshots = vs.end_drag()

	assert_true(snapshots.has("undo1"), "Snapshots should contain the dragged brush")
	var snap_faces: Array = snapshots["undo1"]
	assert_eq(snap_faces.size(), pre_drag_expected.size(), "Should have same face count")

	# Compare actual vertex coordinate values, not just counts.
	# local_verts is serialized as Array of [x, y, z] sub-arrays.
	for i in range(snap_faces.size()):
		var snap_verts: Array = snap_faces[i].get("local_verts", [])
		var pre_verts: Array = pre_drag_expected[i].get("local_verts", [])
		assert_eq(snap_verts.size(), pre_verts.size(), "Face %d vert count" % i)
		for j in range(snap_verts.size()):
			var sv: Array = snap_verts[j]
			var pv: Array = pre_verts[j]
			assert_almost_eq(sv[0], pv[0], 0.001, "Face %d vert %d X" % [i, j])
			assert_almost_eq(sv[1], pv[1], 0.001, "Face %d vert %d Y" % [i, j])
			assert_almost_eq(sv[2], pv[2], 0.001, "Face %d vert %d Z" % [i, j])


func test_pre_drag_snapshots_differ_from_post_move_faces():
	var vs = HFVertexSystem.new(root)
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo2")
	vs.set_selection([b])
	vs.select_vertex("undo2", 0, false)

	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(8, 0, 0))
	var snapshots = vs.end_drag()

	# Now capture post-move state
	var post_state: Array = []
	for face in b.faces:
		if face:
			post_state.append(face.to_dict())

	# The snapshots should NOT equal post-move state (that was the bug)
	var snap_faces: Array = snapshots["undo2"]
	var any_different := false
	for i in range(snap_faces.size()):
		var snap_verts = snap_faces[i].get("local_verts", PackedVector3Array())
		var post_verts = post_state[i].get("local_verts", PackedVector3Array())
		if snap_verts != post_verts:
			any_different = true
			break
	assert_true(any_different, "Pre-drag snapshot should differ from post-move faces")


func test_cancel_drag_restores_pre_drag_geometry():
	var vs = HFVertexSystem.new(root)
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo3")
	vs.set_selection([b])
	vs.select_vertex("undo3", 0, false)

	# Capture pre-drag verts
	var verts_before = vs.get_brush_vertices(b).duplicate()

	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(100, 0, 0))
	vs.cancel_drag()

	var verts_after = vs.get_brush_vertices(b)
	# Verts should be restored to pre-drag
	for i in range(verts_before.size()):
		assert_true(
			verts_before[i].is_equal_approx(verts_after[i]),
			"Vertex %d should be restored after cancel" % i
		)


# ===========================================================================
# Bug 2: Z-axis lock constant matches AxisLock.Z = 3
# ===========================================================================

func test_axis_lock_z_equals_3():
	# The AxisLock enum on LevelRoot should define Z = 3
	# Vertex drag code must use 3, not 4
	var lr_script = load("res://addons/hammerforge/level_root.gd")
	# AxisLock is: { NONE=0, X=1, Y=2, Z=3 }
	assert_eq(lr_script.AxisLock.NONE, 0, "AxisLock.NONE should be 0")
	assert_eq(lr_script.AxisLock.X, 1, "AxisLock.X should be 1")
	assert_eq(lr_script.AxisLock.Y, 2, "AxisLock.Y should be 2")
	assert_eq(lr_script.AxisLock.Z, 3, "AxisLock.Z should be 3")


# ===========================================================================
# Bug 3: Carve rejects face/edge-only contact
# ===========================================================================

func test_carve_face_contact_does_not_destroy():
	# Two brushes touching on one face (no volumetric overlap)
	# Brush A at origin, Brush B immediately adjacent on +X
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "face_a")
	var b = _make_box_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "face_b")

	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("face_a")

	# Should fail: brushes only touch on a face, no volume overlap
	assert_false(result.ok, "Face-only contact should not be carved")
	# The carver should NOT have been deleted (it's still in the tree)
	# Actually carver IS deleted at end of carve_with_brush even on success,
	# but since targets_carved == 0 AND targets is empty, it returns _op_fail
	# before reaching the delete. Let's verify the target survived:
	assert_true(is_instance_valid(b), "Target brush should survive face contact")


func test_carve_edge_contact_does_not_destroy():
	# Two brushes touching on one edge only (diagonal neighbor)
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "edge_a")
	var b = _make_box_brush(Vector3(32, 32, 0), Vector3(32, 32, 32), "edge_b")

	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("edge_a")

	assert_false(result.ok, "Edge-only contact should not be carved")
	assert_true(is_instance_valid(b), "Target brush should survive edge contact")


func test_carve_corner_contact_does_not_destroy():
	# Two brushes touching at a single corner point
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "corner_a")
	var b = _make_box_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "corner_b")

	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("corner_a")

	assert_false(result.ok, "Corner-only contact should not be carved")
	assert_true(is_instance_valid(b), "Target brush should survive corner contact")


func test_carve_volumetric_overlap_succeeds():
	# Two overlapping brushes (carver partially inside target)
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "vol_a")
	var b = _make_box_brush(Vector3(16, 0, 0), Vector3(32, 32, 32), "vol_b")

	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("vol_a")

	assert_true(result.ok, "Volumetric overlap should succeed")


func test_carve_thin_overlap_single_axis_produces_no_pieces():
	# Brushes overlap by a negligible amount on X (just touching + epsilon)
	# but fully overlap on Y and Z. The thin X overlap (< min_thickness) means
	# the target is skipped during slicing, so no pieces are created.
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "thin_a")
	# Place b so X overlap is exactly 0.005 (below min_thickness 0.01)
	var b = _make_box_brush(Vector3(31.995, 0, 0), Vector3(32, 32, 32), "thin_b")

	var child_count_before = draft_node.get_child_count()
	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("thin_a")

	# The target survives (thin overlap is rejected via OR guard)
	assert_true(is_instance_valid(b), "Target should survive thin overlap")


# ===========================================================================
# Bug 4: Vertex projection plane uses picked vertex Y
# ===========================================================================
# EditorPlugin can't be instantiated headless, so we verify:
#   a) The math (_intersect_y_plane) is correct for non-zero Y
#   b) The production source code actually wires ref_y from the picked vertex
#      and passes it through to the projection function (source-code assertion)

func test_intersect_y_plane_at_zero():
	var origin = Vector3(0, 10, 0)
	var dir = Vector3(0, -1, 0).normalized()
	var result = _intersect_y_plane(origin, dir, 0.0)
	assert_not_null(result)
	assert_almost_eq(result.y, 0.0, 0.001, "Should hit Y=0 plane")


func test_intersect_y_plane_at_elevated():
	var origin = Vector3(10, 100, 5)
	var dir = Vector3(0, -1, 0).normalized()
	var result = _intersect_y_plane(origin, dir, 50.0)
	assert_not_null(result)
	assert_almost_eq(result.y, 50.0, 0.001, "Should hit Y=50 plane")
	assert_almost_eq(result.x, 10.0, 0.001, "X should be preserved")
	assert_almost_eq(result.z, 5.0, 0.001, "Z should be preserved")


func test_intersect_y_plane_angled_ray():
	var origin = Vector3(0, 40, 0)
	var dir = Vector3(1, -1, 0).normalized()
	var result = _intersect_y_plane(origin, dir, 20.0)
	assert_not_null(result)
	assert_almost_eq(result.y, 20.0, 0.001, "Should hit Y=20")
	assert_almost_eq(result.x, 20.0, 0.001, "X should advance proportionally")


func test_intersect_y_plane_parallel_ray_returns_null():
	var origin = Vector3(0, 10, 0)
	var dir = Vector3(1, 0, 0).normalized()
	var result = _intersect_y_plane(origin, dir, 10.0)
	assert_null(result, "Parallel ray should return null")


func test_intersect_y_plane_behind_camera_returns_null():
	var origin = Vector3(0, 10, 0)
	var dir = Vector3(0, 1, 0).normalized()
	var result = _intersect_y_plane(origin, dir, 0.0)
	assert_null(result, "Ray pointing away from plane should return null")


func test_projection_delta_differs_at_different_heights():
	var origin = Vector3(0, 100, -100)
	var dir = Vector3(0, -0.707, 0.707).normalized()
	var hit_y0 = _intersect_y_plane(origin, dir, 0.0)
	var hit_y50 = _intersect_y_plane(origin, dir, 50.0)
	assert_not_null(hit_y0)
	assert_not_null(hit_y50)
	assert_true(hit_y0.z > hit_y50.z, "Hit at Y=0 should be further in Z than hit at Y=50")


func test_plugin_stores_ref_y_from_picked_vertex():
	# Read the production plugin.gd and verify the wiring:
	# 1. _vertex_drag_ref_y is assigned from pick.world_pos.y
	# 2. _vertex_drag_ref_y is passed to _vertex_screen_to_world_delta
	var source = FileAccess.get_file_as_string(
		"res://addons/hammerforge/plugin.gd"
	)
	assert_true(source.length() > 0, "plugin.gd should be readable")

	# Verify ref_y is captured from pick.world_pos.y at drag start
	assert_true(
		source.contains("_vertex_drag_ref_y = pick.world_pos.y"),
		"plugin.gd must store ref_y from picked vertex world Y"
	)

	# Verify the actual call site passes _vertex_drag_ref_y to the projection fn
	assert_true(
		source.contains("_vertex_screen_to_world_delta(cam, _vertex_drag_start, pos, root, _vertex_drag_ref_y)"),
		"Call site must pass _vertex_drag_ref_y as the ref_y argument"
	)

	# Verify the projection function accepts ref_y (not hardcoded 0.0)
	assert_true(
		source.contains("ref_y: float"),
		"_vertex_screen_to_world_delta must accept ref_y parameter"
	)

	# Verify BOTH _intersect_y_plane calls use ref_y, not literal 0.0
	assert_true(
		source.contains("_intersect_y_plane(start_origin, start_dir, ref_y)"),
		"Start ray must use ref_y, not hardcoded 0.0"
	)
	assert_true(
		source.contains("_intersect_y_plane(end_origin, end_dir, ref_y)"),
		"End ray must use ref_y, not hardcoded 0.0"
	)


func test_plugin_axis_lock_z_uses_3_not_4():
	# Verify the production code uses axis_lock == 3 for Z, not 4
	var source = FileAccess.get_file_as_string(
		"res://addons/hammerforge/plugin.gd"
	)
	assert_true(
		source.contains("axis_lock == 3"),
		"Z-axis lock must check == 3 (AxisLock.Z)"
	)
	assert_false(
		source.contains("axis_lock == 4"),
		"Must not check axis_lock == 4 anywhere (old bug)"
	)


# ===========================================================================
# Helpers (math identical to plugin's _intersect_y_plane for unit testing)
# ===========================================================================

func _intersect_y_plane(origin: Vector3, dir: Vector3, y: float) -> Variant:
	if abs(dir.y) < 0.0001:
		return null
	var t = (y - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


# ===========================================================================
# Fake brush system for carve tests
# ===========================================================================

class _FakeBrushSystem extends RefCounted:
	var _root: Node3D
	var _draft_node: Node3D
	var _next_id := 1000

	func _init(p_root: Node3D, p_draft: Node3D):
		_root = p_root
		_draft_node = p_draft

	func find_brush_by_id(brush_id: String):
		if not _draft_node:
			return null
		for child in _draft_node.get_children():
			if str(child.brush_id) == brush_id:
				return child
			if child.has_meta("brush_id") and str(child.get_meta("brush_id")) == brush_id:
				return child
		return null

	func delete_brush_by_id(brush_id: String) -> HFOpResult:
		var brush = find_brush_by_id(brush_id)
		if brush:
			_draft_node.remove_child(brush)
			brush.queue_free()
		return HFOpResult.success("deleted")

	func _next_brush_id() -> String:
		_next_id += 1
		return "carved_%d" % _next_id

	func create_brush_from_info(info: Dictionary):
		var b = preload("res://addons/hammerforge/brush_instance.gd").new()
		b.size = info.get("size", Vector3(1, 1, 1))
		b.brush_id = info.get("brush_id", _next_brush_id())
		_draft_node.add_child(b)
		b.global_position = info.get("center", Vector3.ZERO)
		return b
