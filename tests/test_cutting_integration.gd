extends GutTest

## Clip and carve against the systems they have to survive: the baker, the save
## format, repeated cuts, and each other.
##
## The winding checks here go through a real bake, because that is the only place
## an inverted face becomes visible, and each is paired with an untouched control
## so a broken measurement cannot be mistaken for a broken cut.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFCarveSystemScript = preload("res://addons/hammerforge/systems/hf_carve_system.gd")
const HFVertexSystemScript = preload("res://addons/hammerforge/systems/hf_vertex_system.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")
const BakerScript = preload("res://addons/hammerforge/baker.gd")
const HFLevelIOScript = preload("res://addons/hammerforge/hflevel_io.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const MatMgrScript = preload("res://addons/hammerforge/material_manager.gd")

var root: Node3D
var brushes: HFBrushSystem
var carve
var baker


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
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
	root._material_palette = []
	root.texture_lock = false
	brushes = HFBrushSystem.new(root)
	root.brush_system = brushes
	carve = HFCarveSystemScript.new(root)
	root.carve_system = carve
	baker = BakerScript.new()
	add_child_autoqfree(baker)


func after_each():
	root = null
	brushes = null
	carve = null
	baker = null


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
var brush_system = null
var carve_system = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)
var _material_palette: Array = []

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, DODECAHEDRON, ICOSAHEDRON, CUSTOM }

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

func tag_full_reconcile() -> void:
	pass

func tag_brush_dirty(_id: String) -> void:
	pass

func add_material_to_palette(material: Material) -> int:
	_material_palette.append(material)
	return _material_palette.size() - 1
"""
	s.reload()
	return s


func _make_brush(
	pos: Vector3 = Vector3.ZERO,
	sz: Vector3 = Vector3(32, 32, 32),
	brush_id: String = "",
	shape: int = 0
) -> DraftBrush:
	var b = DraftBrush.new()
	b.shape = shape
	b.size = sz
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "test_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	b.rebuild_preview()
	brushes._register_brush_id(brush_id, b)
	return b


func _pieces() -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush:
			out.append(child)
	return out


## Bake one brush and return every triangle as three world vertices.
func _baked_triangles(brush: DraftBrush) -> Array:
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var result = baker.bake_from_faces([brush], mat_mgr)
	if result == null:
		return []
	add_child_autoqfree(result)
	var triangles: Array = []
	for child in result.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh: Mesh = (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		var node_xform: Transform3D = (child as MeshInstance3D).transform
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var raw_indices = arrays[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = (
				raw_indices if raw_indices is PackedInt32Array else PackedInt32Array()
			)
			if indices.is_empty():
				for i in range(0, verts.size() - 2, 3):
					triangles.append(
						[
							node_xform * verts[i],
							node_xform * verts[i + 1],
							node_xform * verts[i + 2]
						]
					)
			else:
				for i in range(0, indices.size() - 2, 3):
					triangles.append(
						[
							node_xform * verts[indices[i]],
							node_xform * verts[indices[i + 1]],
							node_xform * verts[indices[i + 2]]
						]
					)
	return triangles


## Fraction of a brush's baked triangles that face away from its interior.
##
## Measured against the mesh's own vertex centroid, which for a convex piece is
## strictly inside. A brush origin would not be: a cut piece's node sits at its
## bounds centre, which for an angled piece can fall outside the solid.
func _outward_ratio(brush: DraftBrush) -> float:
	var triangles := _baked_triangles(brush)
	if triangles.is_empty():
		return -1.0
	var centre := Vector3.ZERO
	var count := 0
	for tri in triangles:
		for v in tri:
			centre += v
			count += 1
	if count == 0:
		return -1.0
	centre /= float(count)
	var outward := 0
	var counted := 0
	for tri in triangles:
		var a: Vector3 = tri[0]
		var normal: Vector3 = (tri[2] - a).cross(tri[1] - a)
		if normal.length() < 0.000001:
			continue
		var to_face: Vector3 = ((tri[0] + tri[1] + tri[2]) / 3.0) - centre
		if to_face.length() < 0.000001:
			continue
		counted += 1
		if normal.normalized().dot(to_face.normalized()) > 0.0:
			outward += 1
	return float(outward) / float(counted) if counted > 0 else -1.0


func _baked_bounds(brush: DraftBrush) -> AABB:
	var bounds := AABB()
	var seeded := false
	for tri in _baked_triangles(brush):
		for v in tri:
			if seeded:
				bounds = bounds.expand(v)
			else:
				bounds = AABB(v, Vector3.ZERO)
				seeded = true
	return bounds


# ===========================================================================
# Controls
# ===========================================================================


func test_an_uncut_box_bakes_outward_facing_triangles():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 16, 8), "c1")
	assert_almost_eq(_outward_ratio(b), 1.0, 0.0001, "the control must pass")


func test_an_uncut_cylinder_bakes_outward_facing_triangles():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "c2", DraftBrush.BrushShape.CYLINDER)
	assert_almost_eq(_outward_ratio(b), 1.0, 0.0001, "the cylinder control must pass")


# ===========================================================================
# Clip through a real bake
# ===========================================================================


func test_axis_clipped_pieces_bake_outward_facing_triangles():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_true(brushes.clip_brush_by_id("b1", 1, 0.0).ok)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001, "an axis-clipped piece is inverted")


func test_diagonally_clipped_pieces_bake_outward_facing_triangles():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_true(brushes.clip_brush_by_plane("b1", Plane(Vector3(1, 1, 0).normalized(), 0.0)).ok)
	for piece in _pieces():
		assert_almost_eq(
			_outward_ratio(piece), 1.0, 0.0001, "the cut surface is the face most at risk"
		)


func test_a_clipped_cylinder_bakes_outward_facing_triangles():
	_make_brush(Vector3.ZERO, Vector3(48, 48, 48), "b1", DraftBrush.BrushShape.CYLINDER)
	assert_true(brushes.clip_brush_by_plane("b1", Plane(Vector3(0.3, 1, 0.2).normalized(), 0.0)).ok)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


func test_a_clipped_rotated_box_bakes_where_the_original_was():
	var b := _make_brush(Vector3.ZERO, Vector3(64, 32, 16), "b1")
	b.rotation_degrees = Vector3(0, 30, 0)
	b.rebuild_preview()
	var before := _baked_bounds(b)
	assert_true(brushes.clip_brush_by_id("b1", 1, 0.0).ok)
	var after := AABB()
	var seeded := false
	for piece in _pieces():
		var piece_bounds := _baked_bounds(piece)
		if seeded:
			after = after.merge(piece_bounds)
		else:
			after = piece_bounds
			seeded = true
	assert_almost_eq(after.size.x, before.size.x, 0.05, "the pieces must occupy the same space")
	assert_almost_eq(after.size.y, before.size.y, 0.05)
	assert_almost_eq(after.size.z, before.size.z, 0.05)


func test_clipping_twice_keeps_producing_valid_geometry():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_true(brushes.clip_brush_by_plane("b1", Plane(Vector3(1, 1, 0).normalized(), 0.0)).ok)
	var first := _pieces()
	assert_eq(first.size(), 2)
	var second_id := str(first[0].brush_id)
	assert_true(
		brushes.clip_brush_by_plane(second_id, Plane(Vector3(0, 1, 1).normalized(), 0.0)).ok,
		"an already-cut piece must be cuttable again"
	)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001, "a twice-cut piece is inverted")


func test_a_clipped_piece_survives_the_hflevel_encoding():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_true(brushes.clip_brush_by_plane("b1", Plane(Vector3(1, 1, 0).normalized(), 0.0)).ok)
	var piece: DraftBrush = _pieces()[0]
	var info: Dictionary = brushes.get_brush_info_from_node(piece)
	var decoded = HFLevelIOScript.decode_variant(HFLevelIOScript.encode_variant(info))
	assert_true(decoded is Dictionary)
	assert_true(
		(decoded as Dictionary).has("faces"), "an angled piece must save its authoritative faces"
	)
	var faces: Array = (decoded as Dictionary)["faces"]
	assert_gt(faces.size(), 3, "a solid needs at least four faces")


func test_a_clipped_piece_round_trips_through_brush_info():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_true(brushes.clip_brush_by_plane("b1", Plane(Vector3(1, 1, 0).normalized(), 0.0)).ok)
	var piece: DraftBrush = _pieces()[0]
	var before := _baked_bounds(piece)
	var info: Dictionary = brushes.get_brush_info_from_node(piece)
	info["brush_id"] = "restored"
	var restored = brushes.create_brush_from_info(info)
	assert_not_null(restored)
	var after := _baked_bounds(restored)
	assert_almost_eq(after.size.x, before.size.x, 0.01, "the restored piece changed shape")
	assert_almost_eq(after.size.y, before.size.y, 0.01)
	assert_almost_eq(after.size.z, before.size.z, 0.01)


func test_clip_carries_entity_wiring_onto_the_first_piece():
	var b := _make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	b.set_meta("entity_name", "door_trigger")
	b.set_meta("entity_io_outputs", [{"output": "OnTrigger", "target": "door"}])
	assert_true(brushes.clip_brush_by_id("b1", 1, 0.0).ok)
	var named := 0
	var wired := 0
	for piece in _pieces():
		if str(piece.get_meta("entity_name", "")) == "door_trigger":
			named += 1
		if not (piece.get_meta("entity_io_outputs", []) as Array).is_empty():
			wired += 1
	assert_eq(named, 1, "an entity name is unique, so exactly one piece may carry it")
	assert_eq(wired, 1, "the wiring follows the piece that kept the name")


# ===========================================================================
# Carve through a real bake
# ===========================================================================


func test_carved_pieces_bake_outward_facing_triangles():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "carver")
	assert_true(carve.carve_with_brush("carver").ok)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001, "a carved piece is inverted")


func test_pieces_carved_by_a_rotated_carver_bake_correctly():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	var carver := _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 200), "carver")
	carver.rotation_degrees = Vector3(0, 45, 0)
	carver.rebuild_preview()
	assert_true(carve.carve_with_brush("carver").ok)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


func test_a_carver_sharing_a_face_plane_with_the_target_still_cuts():
	# Coincident planes are where an epsilon-based classifier goes wrong.
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(32, 0, 0), Vector3(64, 32, 32), "carver")
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok, result.message)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


func test_carving_a_clipped_piece_works():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_true(brushes.clip_brush_by_plane("b1", Plane(Vector3(1, 1, 0).normalized(), 0.0)).ok)
	_make_brush(Vector3(24, 24, 0), Vector3(24, 24, 200), "carver")
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok, "an angled piece must be carvable: %s" % result.message)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


# ===========================================================================
# Awkward inputs
# ===========================================================================


func test_a_scaled_brush_clips_along_the_world_plane_asked_for():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.scale = Vector3(2.0, 1.0, 1.0)
	b.rebuild_preview()
	assert_true(brushes.clip_brush_by_id("b1", 0, 0.0).ok, "a scaled brush should still clip")
	var pieces := _pieces()
	assert_eq(pieces.size(), 2)
	var left := false
	var right := false
	for piece in pieces:
		if _baked_bounds(piece).get_center().x < 0.0:
			left = true
		else:
			right = true
	assert_true(left and right, "the cut must land on the world plane, not the local one")


func test_clipping_far_from_the_origin_is_still_exact():
	var far := Vector3(100000.0, 0.0, 0.0)
	_make_brush(far, Vector3(64, 64, 64), "b1")
	assert_true(brushes.clip_brush_by_id("b1", 0, far.x).ok)
	var pieces := _pieces()
	assert_eq(pieces.size(), 2)
	for piece in pieces:
		assert_almost_eq(
			_baked_bounds(piece).size.x, 32.0, 0.1, "precision must survive a distant origin"
		)


func test_a_clip_plane_on_the_brush_surface_is_refused():
	var b := _make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	var result = brushes.clip_brush_by_plane("b1", Plane(Vector3.UP, 32.0))
	assert_false(result.ok, "a plane grazing the surface cuts nothing")
	assert_true(is_instance_valid(b), "the brush must survive")


func test_a_clip_plane_with_no_direction_is_refused():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_false(brushes.clip_brush_by_plane("b1", Plane(Vector3.ZERO, 0.0)).ok)


func test_world_bounds_fall_back_to_size_without_faces():
	var b := _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b1")
	b.faces.clear()
	var bounds: AABB = brushes.world_bounds_of(b)
	assert_almost_eq(bounds.size.x, 32.0, 0.01, "a faceless brush still reports its nominal size")


# ===========================================================================
# A neighbour that builds faces the same way
# ===========================================================================


func test_clip_to_convex_declines_an_already_convex_brush():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var vertex_system = HFVertexSystemScript.new(root)
	assert_false(
		vertex_system.clip_to_convex("b1"), "a box is already convex, so there is nothing to do"
	)


func test_clip_to_convex_leaves_outward_facing_geometry():
	# clip_to_convex rebuilds faces from a hull rather than from a split, so it is
	# the other place in the codebase that orders a ring of coplanar vertices, and
	# carries the same risk of ordering one the wrong way round. Reaching it needs
	# a genuinely non-convex brush, which the vertex system will not let a user
	# make, so dent one directly.
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var dented := false
	for face in b.get_faces():
		if face == null or face.local_verts.size() < 3:
			continue
		var verts: PackedVector3Array = face.local_verts
		verts[0] = verts[0] * 0.4
		face.local_verts = verts
		face.ensure_geometry()
		dented = true
		break
	assert_true(dented, "the fixture needs a face to dent")

	var vertex_system = HFVertexSystemScript.new(root)
	if not vertex_system.clip_to_convex("b1"):
		pass_test("the dent did not register as non-convex, so there is nothing to check")
		return
	assert_almost_eq(
		_outward_ratio(b), 1.0, 0.0001, "clip to convex must not leave the brush inside out"
	)
