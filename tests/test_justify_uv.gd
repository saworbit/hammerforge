extends GutTest

const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFBrushSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.pending_node = null
	root.committed_node = null
	root._brush_id_counter = 0
	root.grid_snap = 0.0
	root.face_selection = {}
	root.brush_manager = null
	sys = HFBrushSystem.new(root)


func after_each():
	root.queue_free()
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var brush_manager = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, ICOSAHEDRON, DODECAHEDRON }

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out

func is_entity_node(_node: Node) -> bool:
	return false

func _log(msg: String) -> void:
	pass

func _assign_owner(node: Node) -> void:
	pass

func _record_last_brush(_pos: Vector3) -> void:
	pass
"""
	s.reload()
	return s


func _make_face_with_uvs(uvs: PackedVector2Array) -> FaceData:
	var face = FaceData.new()
	# Build matching local_verts (same count as UVs, 3D positions don't matter for justify)
	var verts = PackedVector3Array()
	for uv in uvs:
		verts.append(Vector3(uv.x, uv.y, 0.0))
	face.local_verts = verts
	face.custom_uvs = uvs
	face.normal = Vector3.FORWARD
	face.uv_scale = Vector2.ONE
	face.uv_offset = Vector2.ZERO
	return face


func _make_brush_with_face(face: FaceData, brush_id: String = "") -> DraftBrush:
	var b = DraftBrush.new()
	b.size = Vector3(32, 32, 32)
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "test_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	sys._register_brush_id(brush_id, b)
	return b


# ===========================================================================
# _justify_face: direct unit tests on the internal method
# ===========================================================================


func test_justify_fit():
	# Face with UVs spanning 0.2 to 0.6 → after fit should span 0..1
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.2, 0.3), Vector2(0.6, 0.3), Vector2(0.6, 0.8), Vector2(0.2, 0.8)]
		)
	)
	var uv_min = Vector2(0.2, 0.3)
	var uv_max = Vector2(0.6, 0.8)
	sys._justify_face(face, "fit", uv_min, uv_max)
	# After fit: scale should map (0.4, 0.5) → (1.0, 1.0)
	# uv_scale.x should be 1.0 * (1/0.4) = 2.5
	# uv_scale.y should be 1.0 * (1/0.5) = 2.0
	assert_almost_eq(face.uv_scale.x, 2.5, 0.01, "Fit X scale")
	assert_almost_eq(face.uv_scale.y, 2.0, 0.01, "Fit Y scale")
	# custom_uvs should be cleared (forces re-projection)
	assert_eq(face.custom_uvs.size(), 0, "Fit should clear custom_uvs")


func test_justify_center():
	# Face with UVs centered at (0.3, 0.4) → after center, center should be (0.5, 0.5)
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.1, 0.2), Vector2(0.5, 0.2), Vector2(0.5, 0.6), Vector2(0.1, 0.6)]
		)
	)
	var uv_min = Vector2(0.1, 0.2)
	var uv_max = Vector2(0.5, 0.6)
	sys._justify_face(face, "center", uv_min, uv_max)
	# Center of (0.1,0.2)-(0.5,0.6) is (0.3, 0.4). Shift = (0.5-0.3, 0.5-0.4) = (0.2, 0.1)
	assert_almost_eq(face.uv_offset.x, 0.2, 0.01, "Center X offset")
	assert_almost_eq(face.uv_offset.y, 0.1, 0.01, "Center Y offset")


func test_justify_left():
	# UVs from 0.3 to 0.7 in X → after left, min X should be at 0
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.3, 0.0), Vector2(0.7, 0.0), Vector2(0.7, 1.0), Vector2(0.3, 1.0)]
		)
	)
	var uv_min = Vector2(0.3, 0.0)
	var uv_max = Vector2(0.7, 1.0)
	sys._justify_face(face, "left", uv_min, uv_max)
	assert_almost_eq(face.uv_offset.x, -0.3, 0.01, "Left should shift min X to 0")


func test_justify_right():
	# UVs from 0.3 to 0.7 in X → after right, max X should be at 1
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.3, 0.0), Vector2(0.7, 0.0), Vector2(0.7, 1.0), Vector2(0.3, 1.0)]
		)
	)
	var uv_min = Vector2(0.3, 0.0)
	var uv_max = Vector2(0.7, 1.0)
	sys._justify_face(face, "right", uv_min, uv_max)
	assert_almost_eq(face.uv_offset.x, 0.3, 0.01, "Right should shift max X to 1")


func test_justify_top():
	# UVs from 0.2 to 0.8 in Y → after top, min Y should be at 0
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.0, 0.2), Vector2(1.0, 0.2), Vector2(1.0, 0.8), Vector2(0.0, 0.8)]
		)
	)
	var uv_min = Vector2(0.0, 0.2)
	var uv_max = Vector2(1.0, 0.8)
	sys._justify_face(face, "top", uv_min, uv_max)
	assert_almost_eq(face.uv_offset.y, -0.2, 0.01, "Top should shift min Y to 0")


func test_justify_bottom():
	# UVs from 0.2 to 0.8 in Y → after bottom, max Y should be at 1
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.0, 0.2), Vector2(1.0, 0.2), Vector2(1.0, 0.8), Vector2(0.0, 0.8)]
		)
	)
	var uv_min = Vector2(0.0, 0.2)
	var uv_max = Vector2(1.0, 0.8)
	sys._justify_face(face, "bottom", uv_min, uv_max)
	assert_almost_eq(face.uv_offset.y, 0.2, 0.01, "Bottom should shift max Y to 1")


# ===========================================================================
# Justify: zero-size UV range is a no-op
# ===========================================================================


func test_justify_zero_range_noop():
	# All UVs at same point → range is zero → should not crash or change anything
	var face = _make_face_with_uvs(
		PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)])
	)
	var original_scale = face.uv_scale
	var original_offset = face.uv_offset
	sys._justify_face(face, "fit", Vector2(0.5, 0.5), Vector2(0.5, 0.5))
	assert_eq(face.uv_scale, original_scale, "Zero-range fit should not change scale")
	assert_eq(face.uv_offset, original_offset, "Zero-range fit should not change offset")


# ===========================================================================
# justify_selected_faces via face_selection
# ===========================================================================


func test_justify_selected_faces_empty_selection():
	root.face_selection = {}
	# Should not crash
	sys.justify_selected_faces("center", false)
	assert_true(true, "Empty selection should not crash")


func test_justify_clears_custom_uvs():
	# All justify modes should clear custom_uvs to force re-projection
	var modes = ["fit", "center", "left", "right", "top", "bottom"]
	for mode in modes:
		var face = _make_face_with_uvs(
			PackedVector2Array(
				[Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.9, 0.9), Vector2(0.1, 0.9)]
			)
		)
		sys._justify_face(face, mode, Vector2(0.1, 0.1), Vector2(0.9, 0.9))
		assert_eq(face.custom_uvs.size(), 0, "Mode '%s' should clear custom_uvs" % mode)


func test_justify_preserves_existing_offset():
	# Center justify should ADD to existing offset, not replace
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.0, 0.0), Vector2(0.4, 0.0), Vector2(0.4, 0.4), Vector2(0.0, 0.4)]
		)
	)
	face.uv_offset = Vector2(0.1, 0.1)  # Pre-existing offset
	sys._justify_face(face, "center", Vector2(0.0, 0.0), Vector2(0.4, 0.4))
	# Center of (0,0)-(0.4,0.4) is (0.2, 0.2). Shift = (0.3, 0.3)
	# Final offset = (0.1 + 0.3, 0.1 + 0.3) = (0.4, 0.4)
	assert_almost_eq(face.uv_offset.x, 0.4, 0.01, "Center should add to existing offset X")
	assert_almost_eq(face.uv_offset.y, 0.4, 0.01, "Center should add to existing offset Y")
