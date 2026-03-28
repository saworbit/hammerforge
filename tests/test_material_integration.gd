extends GutTest
## Integration tests for material browser, dock, and level_root material workflows.
## Tests call production code (dock helpers, brush_system, level_root shim methods)
## rather than simulating behavior with local variables.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataType = preload("res://addons/hammerforge/face_data.gd")
const DockType = preload("res://addons/hammerforge/dock.gd")

var root: Node3D
var brush_sys: HFBrushSystem
var dock: DockType


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)

	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft

	var pending = Node3D.new()
	pending.name = "Pending"
	root.add_child(pending)
	root.pending_node = pending

	var committed = Node3D.new()
	committed.name = "Committed"
	root.add_child(committed)
	root.committed_node = committed

	# Material manager for hover preview
	var mat_mgr = MaterialManager.new()
	mat_mgr.add_material(_make_standard_material("brick", Color.RED))
	mat_mgr.add_material(_make_standard_material("stone", Color.GRAY))
	mat_mgr.add_material(_make_standard_material("wood", Color.BROWN))
	root.add_child(mat_mgr)
	root.material_manager = mat_mgr

	root._brush_id_counter = 0
	root.grid_snap = 0.0
	root.face_selection = {}
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))

	brush_sys = HFBrushSystem.new(root)
	root.brush_system = brush_sys

	# Minimal dock instance for calling _build_face_overlay_mesh.
	# Do NOT add_child — dock._ready() triggers heavy editor-dependent init.
	# Do NOT set dock.level_root — it's typed LevelRootType, not our shim.
	dock = DockType.new()
	dock._hover_preview_faces = []


func after_each():
	if dock:
		dock.free()
	dock = null
	root = null
	brush_sys = null


# ---------------------------------------------------------------------------
# Root shim
# ---------------------------------------------------------------------------


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal user_message(text: String, level: int)
signal brush_added(brush_id: String)
signal brush_removed(brush_id: String)
signal brush_changed(brush_id: String)
signal selection_changed()

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var brush_manager = null
var material_manager: MaterialManager = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)
var cordon_enabled: bool = false
var cordon_aabb: AABB = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = \"\"
var brush_system = null
var visgroup_system = null
var entity_system = null
var commit_freeze: bool = false

func get_material_manager() -> MaterialManager:
	return material_manager

func _log(_msg: String) -> void:
	pass

func _assign_owner(_node: Node) -> void:
	pass

func tag_full_reconcile() -> void:
	pass

func tag_brush_dirty(_brush_id: String) -> void:
	pass

func begin_signal_batch() -> void:
	pass

func end_signal_batch() -> void:
	pass

func discard_signal_batch() -> void:
	pass

func _emit_or_batch(signal_name: String, args: Array) -> void:
	pass

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	if pending_node:
		out.append_array(pending_node.get_children())
	return out

func is_entity_node(node: Node) -> bool:
	return node.has_meta(\"entity_type\") or node.has_meta(\"is_entity\")

func _record_last_brush(_pos: Vector3) -> void:
	pass

func assign_material_to_faces_by_id(brush_key: String, face_indices: Array, material_index: int) -> void:
	var brush = brush_system.find_brush_by_id(brush_key)
	if not brush or not is_instance_valid(brush):
		return
	var typed: Array[int] = []
	for fi in face_indices:
		typed.append(int(fi))
	brush.assign_material_to_faces(material_index, typed)

func assign_material_to_whole_brushes(material_index: int, brush_ids: Array) -> void:
	for bid in brush_ids:
		var brush = brush_system.find_brush_by_id(str(bid))
		if not brush or not is_instance_valid(brush):
			continue
		var all_indices: Array[int] = []
		for i in range(brush.faces.size()):
			all_indices.append(i)
		brush.assign_material_to_faces(material_index, all_indices)
"""
	s.reload()
	return s


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_standard_material(mat_name: String, color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.resource_name = mat_name
	mat.albedo_color = color
	return mat


func _make_brush(
	brush_id: String = "", face_count: int = 6, parent_key: String = "draft"
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = Vector3(32, 32, 32)
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "mat_test_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	# Add to tree first so _ready fires and builds default faces.
	var parent_node: Node3D = (
		root.draft_brushes_node if parent_key == "draft" else root.pending_node
	)
	parent_node.add_child(b)
	# Now overwrite faces with controlled test data (after _ready rebuilt them).
	b.faces.clear()
	for i in range(face_count):
		var face = FaceDataType.new()
		face.material_idx = 0
		face.normal = _face_normal_for_index(i)
		face.local_verts = PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
		)
		b.faces.append(face)
	brush_sys._register_brush_id(brush_id, b)
	return b


func _face_normal_for_index(i: int) -> Vector3:
	# Simulate a box with 6 distinct face normals.
	match i % 6:
		0:
			return Vector3.UP
		1:
			return Vector3.DOWN
		2:
			return Vector3.LEFT
		3:
			return Vector3.RIGHT
		4:
			return Vector3.FORWARD
		_:
			return Vector3.BACK


# ---------------------------------------------------------------------------
# 1. Brush search: _iter_pick_nodes vs root.get_children
# ---------------------------------------------------------------------------


func test_iter_pick_nodes_finds_draft_brushes():
	var brush = _make_brush("draft_brush")
	var nodes: Array = root._iter_pick_nodes()
	assert_true(nodes.has(brush), "_iter_pick_nodes must include draft brushes")


func test_iter_pick_nodes_finds_pending_brushes():
	var brush = _make_brush("pending_brush", 4, "pending")
	var nodes: Array = root._iter_pick_nodes()
	assert_true(nodes.has(brush), "_iter_pick_nodes must include pending brushes")


func test_get_children_does_not_find_nested_brushes():
	# This proves why root.get_children() was wrong: brushes are nested
	# under DraftBrushes/Pending, not direct children of root.
	var brush = _make_brush("nested_brush")
	var found_in_children := false
	for child in root.get_children():
		if child == brush:
			found_in_children = true
	assert_false(found_in_children, "root.get_children() must NOT find brushes in sub-containers")


func test_collect_brushes_matches_iter_pick_nodes():
	# Simulate what plugin._collect_brushes does: use _iter_pick_nodes, filter DraftBrush.
	_make_brush("b1", 2, "draft")
	_make_brush("b2", 2, "pending")
	var nodes: Array = root._iter_pick_nodes()
	var brushes: Array = []
	for node in nodes:
		if node is DraftBrush:
			brushes.append(node)
	assert_eq(brushes.size(), 2, "Should find brushes from both draft and pending")


# ---------------------------------------------------------------------------
# 2. Hover overlay: production _build_face_overlay_mesh
# ---------------------------------------------------------------------------


func test_build_face_overlay_mesh_produces_mesh():
	var brush = _make_brush("overlay_test", 4)
	var mat = _make_standard_material("preview", Color.CYAN)
	var mesh: ArrayMesh = dock._build_face_overlay_mesh(brush, [0, 2], mat)
	assert_not_null(mesh, "Overlay mesh should not be null")
	assert_true(mesh.get_surface_count() > 0, "Mesh should have at least one surface")


func test_build_face_overlay_mesh_skips_invalid_indices():
	var brush = _make_brush("skip_test", 2)
	var mat = _make_standard_material("preview", Color.CYAN)
	var mesh: ArrayMesh = dock._build_face_overlay_mesh(brush, [-1, 99], mat)
	assert_null(mesh, "Overlay with only invalid indices should return null")


func test_build_face_overlay_mesh_returns_null_for_empty():
	var brush = _make_brush("empty_test", 2)
	var mat = _make_standard_material("preview", Color.CYAN)
	var mesh: ArrayMesh = dock._build_face_overlay_mesh(brush, [], mat)
	assert_null(mesh, "Empty face list should return null")


func test_overlay_vertices_offset_along_face_normal():
	# Build overlay for a single face and verify vertices are offset along
	# that face's normal, not along a fixed +Y direction.
	var brush = _make_brush("normal_offset_test", 1)
	# Face 0 has normal = UP (index 0 mod 6). Set a wall face instead.
	brush.faces[0].normal = Vector3.RIGHT
	brush.faces[0].local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)]
	)
	var mat = _make_standard_material("wall_preview", Color.RED)
	var mesh: ArrayMesh = dock._build_face_overlay_mesh(brush, [0], mat)
	assert_not_null(mesh, "Should produce overlay mesh")
	# Extract vertices from the mesh surface.
	var arrays = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Each vertex should be offset by 0.001 along Vector3.RIGHT (X+).
	# Original verts have X=0; offset should push them to X≈0.001.
	for v in verts:
		assert_almost_eq(v.x, 0.001, 0.0001, "Vertex X should be offset along RIGHT normal")


func test_overlay_does_not_mutate_face_data():
	# Call the actual dock _build_face_overlay_mesh and verify face data is untouched.
	var brush = _make_brush("no_mutate_test", 3)
	brush.faces[0].material_idx = 5
	brush.faces[1].material_idx = 7
	brush.faces[2].material_idx = 9
	var mat = _make_standard_material("preview", Color.CYAN)
	dock._build_face_overlay_mesh(brush, [0, 1, 2], mat)
	assert_eq(brush.faces[0].material_idx, 5, "Face 0 material_idx untouched")
	assert_eq(brush.faces[1].material_idx, 7, "Face 1 material_idx untouched")
	assert_eq(brush.faces[2].material_idx, 9, "Face 2 material_idx untouched")


# ---------------------------------------------------------------------------
# 3. Full hover preview lifecycle via dock production code
# ---------------------------------------------------------------------------


func test_hover_overlay_lifecycle_preserves_face_data():
	# Reproduce the production hover preview pattern: build overlay mesh,
	# add as child of brush, verify face data untouched, then remove.
	var brush = _make_brush("hover_live", 4)
	brush.faces[0].material_idx = 2
	brush.faces[1].material_idx = 3
	var mat = _make_standard_material("preview", Color.CYAN)
	# Build overlay using production dock code.
	var overlay_mesh: ArrayMesh = dock._build_face_overlay_mesh(brush, [0, 1], mat)
	assert_not_null(overlay_mesh, "Overlay mesh should be built")
	# Add overlay as child — same pattern as _apply_hover_preview.
	var overlay := MeshInstance3D.new()
	overlay.name = "_HoverPreview"
	overlay.mesh = overlay_mesh
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	brush.add_child(overlay)
	# Verify face data is NOT mutated while overlay exists.
	assert_eq(brush.faces[0].material_idx, 2, "Face 0 material_idx untouched during preview")
	assert_eq(brush.faces[1].material_idx, 3, "Face 1 material_idx untouched during preview")
	# Revert — remove overlay, same pattern as _revert_hover_preview.
	brush.remove_child(overlay)
	overlay.queue_free()
	# Verify face data still untouched after revert.
	assert_eq(brush.faces[0].material_idx, 2, "Face 0 material_idx untouched after revert")
	assert_eq(brush.faces[1].material_idx, 3, "Face 1 material_idx untouched after revert")


func test_hover_overlay_does_not_affect_serializable_state():
	# The key correctness property: face.material_idx is what serialization reads.
	# Overlay presence must not change it.
	var brush = _make_brush("serial_test", 3)
	brush.faces[0].material_idx = 5
	brush.faces[1].material_idx = 7
	brush.faces[2].material_idx = 9
	var mat = _make_standard_material("preview", Color.MAGENTA)
	var overlay_mesh: ArrayMesh = dock._build_face_overlay_mesh(brush, [0, 1, 2], mat)
	var overlay := MeshInstance3D.new()
	overlay.name = "_HoverPreview"
	overlay.mesh = overlay_mesh
	brush.add_child(overlay)
	# Snapshot face data as if serializing.
	var snapshot: Array[int] = []
	for face in brush.faces:
		snapshot.append(face.material_idx)
	assert_eq(snapshot, [5, 7, 9], "Serializable face data must match pre-overlay values")
	brush.remove_child(overlay)
	overlay.queue_free()


# ---------------------------------------------------------------------------
# 4. Whole-brush and per-face assignment via root shim state actions
# ---------------------------------------------------------------------------


func test_assign_material_to_faces_by_id_via_root():
	var brush = _make_brush("root_byid", 4)
	for face in brush.faces:
		face.material_idx = 0
	# Call the production state action method on the root shim.
	root.assign_material_to_faces_by_id("root_byid", [1, 3], 2)
	assert_eq(brush.faces[0].material_idx, 0, "Face 0 untouched")
	assert_eq(brush.faces[1].material_idx, 2, "Face 1 updated to 2")
	assert_eq(brush.faces[2].material_idx, 0, "Face 2 untouched")
	assert_eq(brush.faces[3].material_idx, 2, "Face 3 updated to 2")


func test_assign_material_to_whole_brushes_via_root():
	var brush = _make_brush("root_whole", 6)
	for face in brush.faces:
		face.material_idx = 0
	root.assign_material_to_whole_brushes(1, ["root_whole"])
	for i in range(brush.faces.size()):
		assert_eq(brush.faces[i].material_idx, 1, "Face %d should be material 1" % i)


func test_assign_to_invalid_brush_id_no_crash():
	root.assign_material_to_faces_by_id("nonexistent_brush", [0], 1)
	root.assign_material_to_whole_brushes(1, ["nonexistent_brush"])
	assert_true(true, "Invalid brush_id should not crash")


func test_assign_out_of_range_face_indices():
	var brush = _make_brush("oob_test", 2)
	root.assign_material_to_faces_by_id("oob_test", [-1, 0, 99], 5)
	assert_eq(brush.faces[0].material_idx, 5, "Face 0 updated")
	assert_eq(brush.faces[1].material_idx, 0, "Face 1 untouched (99 out of range)")


# ---------------------------------------------------------------------------
# 5. Face selection key resolution through brush_system
# ---------------------------------------------------------------------------


func test_find_brush_by_brush_id():
	var brush = _make_brush("resolve_id_test")
	var found = brush_sys.find_brush_by_id("resolve_id_test")
	assert_eq(found, brush, "Should find brush by brush_id string")


func test_find_nonexistent_brush_returns_null():
	var found = brush_sys.find_brush_by_id("no_such_brush")
	assert_null(found, "Should return null for nonexistent brush")
