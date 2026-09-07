extends GutTest

## The generators against the systems they have to survive: the baker, the save
## format, the cutting tools, and each other.
##
## Every winding claim goes through a real bake with an untouched control beside
## it, which is how the last two waves found the defects worth finding.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFArchBuilderScript = preload("res://addons/hammerforge/hf_arch_builder.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFCarveSystemScript = preload("res://addons/hammerforge/systems/hf_carve_system.gd")
const HFDuplicatorScript = preload("res://addons/hammerforge/hf_duplicator.gd")
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


## Fraction of baked triangles facing away from the mesh's own interior.
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


func _create_arch(overrides: Dictionary = {}, centre: Vector3 = Vector3.ZERO) -> PackedStringArray:
	var settings: Dictionary = HFArchBuilderScript.default_settings()
	for key in overrides:
		settings[key] = overrides[key]
	return brushes.create_brushes_from_face_sets(
		HFArchBuilderScript.build(settings), Transform3D(Basis.IDENTITY, centre)
	)


# ===========================================================================
# Controls
# ===========================================================================


func test_an_untouched_box_bakes_outward_facing_triangles():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 16, 8), "c1")
	assert_almost_eq(_outward_ratio(b), 1.0, 0.0001, "the control must pass")


func test_an_untouched_cylinder_bakes_outward_facing_triangles():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "c2", DraftBrush.BrushShape.CYLINDER)
	assert_almost_eq(_outward_ratio(b), 1.0, 0.0001, "the cylinder control must pass")


func test_an_untouched_sphere_bakes_outward_facing_triangles():
	# Worth its own control: shelling a sphere is what exposed that a primitive
	# mesh has faces whose own normal cannot be trusted.
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "c3", DraftBrush.BrushShape.SPHERE)
	assert_almost_eq(_outward_ratio(b), 1.0, 0.0001, "the sphere control must pass")


# ===========================================================================
# Hollow through a real bake
# ===========================================================================


func test_hollow_walls_bake_outward_facing_triangles():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_true(brushes.hollow_brush_by_id("b1", 8.0).ok)
	for wall in _pieces():
		assert_almost_eq(_outward_ratio(wall), 1.0, 0.0001, "a wall would bake inside out")


func test_hollowing_a_rotated_brush_bakes_correctly():
	var b := _make_brush(Vector3.ZERO, Vector3(64, 32, 48), "b1")
	b.rotation_degrees = Vector3(15, 30, 45)
	b.rebuild_preview()
	assert_true(brushes.hollow_brush_by_id("b1", 6.0).ok)
	assert_eq(_pieces().size(), 6)
	for wall in _pieces():
		assert_almost_eq(_outward_ratio(wall), 1.0, 0.0001)


func test_hollowing_a_cylinder_bakes_a_tube():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1", DraftBrush.BrushShape.CYLINDER)
	assert_true(brushes.hollow_brush_by_id("b1", 8.0).ok)
	var walls := _pieces()
	assert_gt(walls.size(), 6, "a tube has a wall per facet")
	for wall in walls:
		assert_almost_eq(_outward_ratio(wall), 1.0, 0.0001)


func test_no_hollow_wall_reaches_into_the_void():
	# The point of a hollow: the middle is empty.
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	var thickness := 8.0
	assert_true(brushes.hollow_brush_by_id("b1", thickness).ok)
	var limit := 32.0 - thickness - 0.01
	for wall in _pieces():
		var xform: Transform3D = wall.global_transform
		for face in wall.get_faces():
			for v in face.local_verts:
				var world: Vector3 = xform * v
				var inside: bool = (
					absf(world.x) < limit and absf(world.y) < limit and absf(world.z) < limit
				)
				assert_false(inside, "a wall vertex at %s is inside the void" % world)


func test_hollowing_a_clipped_piece_works():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	assert_true(brushes.clip_brush_by_plane("b1", Plane(Vector3(1, 1, 0).normalized(), 0.0)).ok)
	var piece: DraftBrush = _pieces()[0]
	var result = brushes.hollow_brush_by_id(str(piece.brush_id), 4.0)
	assert_true(result.ok, "an angled piece must be shellable: %s" % result.message)
	for wall in _pieces():
		assert_almost_eq(_outward_ratio(wall), 1.0, 0.0001)


func test_hollow_reports_the_wall_count_so_a_caller_can_warn():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1")
	var check = brushes.can_hollow_brush("b1", 8.0)
	assert_true(check.ok)
	assert_true(check.message.contains("6"), "the count belongs in the message: %s" % check.message)


# ===========================================================================
# Arch through a real bake
# ===========================================================================


func test_arch_segments_become_brushes():
	var created := _create_arch({"segments": 6})
	assert_eq(created.size(), 6)
	assert_eq(_pieces().size(), 6)


func test_arch_segments_bake_outward_facing_triangles():
	_create_arch({"segments": 6})
	for segment in _pieces():
		assert_almost_eq(
			_outward_ratio(segment), 1.0, 0.0001, "an arch segment would bake inside out"
		)


func test_a_full_arch_ring_bakes_correctly():
	_create_arch({"arc_degrees": 360.0, "segments": 16})
	assert_eq(_pieces().size(), 16)
	for segment in _pieces():
		assert_almost_eq(_outward_ratio(segment), 1.0, 0.0001)


func test_an_arch_lands_where_it_is_placed():
	var centre := Vector3(500, 100, -250)
	_create_arch({"segments": 4, "arc_degrees": 360.0, "radius": 64.0}, centre)
	var bounds := AABB()
	var seeded := false
	for segment in _pieces():
		for tri in _baked_triangles(segment):
			for v in tri:
				if seeded:
					bounds = bounds.expand(v)
				else:
					bounds = AABB(v, Vector3.ZERO)
					seeded = true
	assert_almost_eq(bounds.get_center().x, centre.x, 1.0, "the arch must land where it is put")
	assert_almost_eq(bounds.get_center().y, centre.y, 1.0)
	assert_almost_eq(bounds.get_center().z, centre.z, 1.0)


func test_an_arch_segment_survives_the_save_format():
	_create_arch({"segments": 4})
	var segment: DraftBrush = _pieces()[0]
	var info: Dictionary = brushes.get_brush_info_from_node(segment)
	var decoded = HFLevelIOScript.decode_variant(HFLevelIOScript.encode_variant(info))
	assert_true(decoded is Dictionary)
	assert_true((decoded as Dictionary).has("faces"), "a voussoir must save its faces")
	assert_eq((decoded as Dictionary)["faces"].size(), 6)


func test_an_arch_segment_round_trips_through_brush_info():
	_create_arch({"segments": 4})
	var segment: DraftBrush = _pieces()[0]
	var before := _outward_ratio(segment)
	var info: Dictionary = brushes.get_brush_info_from_node(segment)
	info["brush_id"] = "restored"
	var restored = brushes.create_brush_from_info(info)
	assert_not_null(restored)
	assert_almost_eq(_outward_ratio(restored), before, 0.0001, "undo must not invert a segment")


func test_an_arch_segment_can_be_clipped():
	_create_arch({"segments": 4})
	var segment: DraftBrush = _pieces()[0]
	var result = brushes.clip_brush_by_plane(str(segment.brush_id), Plane(Vector3.BACK, 0.0))
	assert_true(result.ok, "a voussoir must be cuttable: %s" % result.message)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


func test_an_arch_segment_can_be_carved():
	_create_arch({"segments": 4, "radius": 128.0})
	_make_brush(Vector3(128, 0, 0), Vector3(24, 24, 400), "carver")
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok, "an arch must be carvable: %s" % result.message)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


func test_an_invalid_arch_creates_nothing():
	var created := _create_arch({"segments": 0})
	assert_eq(created.size(), 0)
	assert_eq(_pieces().size(), 0, "a refused arch must not leave debris")


# ===========================================================================
# Radial arrays that climb
# ===========================================================================


func test_a_radial_array_with_rise_climbs():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 8, 32), "step")
	var dup = brushes.create_radial_array(
		PackedStringArray(["step"]), 3, 1, 30.0, Vector3.ZERO, 12.0
	)
	assert_not_null(dup)
	var heights: Array = []
	for brush_id in dup.get_all_instance_ids():
		heights.append(brushes.find_brush_by_id(brush_id).global_position.y)
	assert_eq(heights.size(), 3)
	assert_almost_eq(heights[0], 12.0, 0.001, "the first copy climbs one rise")
	assert_almost_eq(heights[1], 24.0, 0.001)
	assert_almost_eq(heights[2], 36.0, 0.001)


func test_a_radial_array_with_rise_still_turns():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 8, 32), "step")
	var dup = brushes.create_radial_array(
		PackedStringArray(["step"]), 1, 1, 90.0, Vector3.ZERO, 10.0
	)
	var copy = brushes.find_brush_by_id(dup.get_all_instance_ids()[0])
	assert_almost_eq(copy.global_position.z, -100.0, 0.001, "a quarter turn about Y")
	assert_almost_eq(copy.global_position.y, 10.0, 0.001, "and one rise up")


func test_a_zero_rise_is_the_flat_ring_it_always_was():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 8, 32), "step")
	var dup = brushes.create_radial_array(
		PackedStringArray(["step"]), 3, 1, 90.0, Vector3.ZERO, 0.0
	)
	for brush_id in dup.get_all_instance_ids():
		assert_almost_eq(brushes.find_brush_by_id(brush_id).global_position.y, 0.0, 0.001)


func test_rise_climbs_the_axis_it_turns_about():
	_make_brush(Vector3(0, 100, 0), Vector3(32, 32, 8), "step")
	var dup = brushes.create_radial_array(
		PackedStringArray(["step"]), 1, 0, 90.0, Vector3.ZERO, 10.0
	)
	var copy = brushes.find_brush_by_id(dup.get_all_instance_ids()[0])
	assert_almost_eq(copy.global_position.x, 10.0, 0.001, "an X-axis helix climbs along X")


func test_rise_round_trips_through_the_serialized_duplicator():
	var dup = HFDuplicatorScript.new()
	dup.mode = HFDuplicatorScript.ArrayMode.RADIAL
	dup.rise = 17.5
	var restored = HFDuplicatorScript.from_dict(dup.to_dict())
	assert_almost_eq(restored.rise, 17.5, 0.001)


func test_a_duplicator_saved_before_rise_existed_loads_flat():
	var restored = (
		HFDuplicatorScript
		. from_dict(
			{
				"duplicator_id": "dup_old",
				"source_brush_ids": ["a"],
				"count": 3,
				"mode": HFDuplicatorScript.ArrayMode.RADIAL,
				"step_degrees": 90.0,
				"instance_groups": [],
			}
		)
	)
	assert_almost_eq(restored.rise, 0.0, 0.001)


# ===========================================================================
# The plane machinery both boolean operations rest on
# ===========================================================================


func test_outward_planes_survive_a_face_whose_normal_is_backwards():
	# One unreliable face normal used to be enough to make shelling a sphere report
	# that there was no room inside it.
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var faces := b.get_faces()
	var victim = faces[0]
	var reversed_verts := PackedVector3Array()
	for i in range(victim.local_verts.size() - 1, -1, -1):
		reversed_verts.append(victim.local_verts[i])
	victim.local_verts = reversed_verts
	victim.ensure_geometry()
	var interior: Vector3 = HFConvexClipScript.interior_point(faces)
	for plane in HFConvexClipScript.outward_planes(faces, interior):
		assert_lt(
			plane.distance_to(interior), 0.0, "every bounding plane must have the solid behind it"
		)


func test_a_spheres_planes_all_face_outward_after_that_lesson():
	# A sphere is refused for being too many planes, not for facing the wrong way.
	# The orientation fix is still what makes its planes usable at all, so check it
	# where it can be checked: on the planes themselves.
	var b := _make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1", DraftBrush.BrushShape.SPHERE)
	var faces := b.get_faces()
	var interior: Vector3 = HFConvexClipScript.interior_point(faces)
	for plane in HFConvexClipScript.outward_planes(faces, interior):
		assert_lt(
			plane.distance_to(interior),
			0.0,
			"a sphere's own face normals cannot be trusted, so orientation must be measured"
		)


func test_duplicate_planes_are_collapsed_before_the_loop_runs():
	var plane := Plane(Vector3.UP, 4.0)
	var deduped: Array = HFConvexClipScript.dedupe_planes(
		[plane, plane, plane, Plane(Vector3.UP, 8.0)]
	)
	assert_eq(deduped.size(), 2, "a repeated plane cannot cut anything new")


func test_hollowing_a_sphere_is_refused_rather_than_taking_a_minute():
	# A sphere's every triangle is its own plane, so deduplication cannot help.
	# Shelling one used to take sixty seconds and produce two thousand brushes,
	# which is never what anybody meant by hollowing a sphere.
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1", DraftBrush.BrushShape.SPHERE)
	var started := Time.get_ticks_msec()
	var result = brushes.hollow_brush_by_id("b1", 8.0)
	var elapsed := Time.get_ticks_msec() - started
	assert_false(result.ok, "a brush with thousands of faces must be refused")
	assert_true(result.message.contains("faces"), result.message)
	assert_ne(result.fix_hint, "", "a refusal must say what does work")
	assert_lt(elapsed, 2000, "and it must refuse quickly, not after doing the work")
	assert_eq(_pieces().size(), 1, "the sphere must survive untouched")


func test_carving_with_a_sphere_is_refused_for_the_same_reason():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(32, 0, 0), Vector3(48, 48, 48), "carver", DraftBrush.BrushShape.SPHERE)
	var result = carve.carve_with_brush("carver")
	assert_false(result.ok, "a carver with thousands of planes would shatter its targets")
	assert_ne(result.fix_hint, "")
	assert_not_null(brushes.find_brush_by_id("target"), "the target must survive")


func test_a_cylinder_is_still_inside_the_budget():
	# The limit has to leave room for the shapes people actually shell and carve
	# with. A tube is a reasonable thing to ask for.
	var b := _make_brush(Vector3.ZERO, Vector3(64, 64, 64), "b1", DraftBrush.BrushShape.CYLINDER)
	var faces := b.get_faces()
	var budget: Dictionary = HFConvexClipScript.boolean_plane_budget(
		faces, HFConvexClipScript.interior_point(faces)
	)
	assert_true(
		budget["ok"], "a cylinder has %d planes, which must stay allowed" % budget["planes"]
	)
	assert_true(brushes.hollow_brush_by_id("b1", 8.0).ok)
