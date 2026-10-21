extends GutTest

## Smoothing groups (#1429). A face in a group above 0 shares the average of its
## normal with the faces of its group it meets at a corner, across brushes and
## materials, and shades with that. Group 0 shades flat, as every face did. The
## face bake, the CSG bake, Bake Selected and a textured brush's preview all give
## a brush the same normals.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const HFSmoothingScript = preload("res://addons/hammerforge/hf_smoothing.gd")
const HFBakeSystemScript = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const HFDomeBuilderScript = preload("res://addons/hammerforge/hf_dome_builder.gd")

## Two normals this close are the same normal.
const SAME := 0.9999
const CYLINDER_SIZE := Vector3(32, 64, 32)

var root: LevelRoot


func before_each() -> void:
	root = _level()


func _level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func _brush(
	shape: int,
	size: Vector3 = CYLINDER_SIZE,
	center: Vector3 = Vector3.ZERO,
	level: LevelRoot = null,
	extra: Dictionary = {}
) -> DraftBrush:
	var info := {"shape": shape, "size": size, "center": center, "sides": 16}
	info.merge(extra, true)
	return (level if level else root).create_brush_from_info(info) as DraftBrush


## Every baked triangle of `level` in the level: its corners and the normal each
## shades with.
func _baked_triangles(level: LevelRoot = null) -> Array:
	var from: LevelRoot = level if level else root
	var out: Array = []
	if from.baked_container == null:
		return out
	for node in from.baked_container.find_children("*", "MeshInstance3D", true, false):
		var drawn := node as MeshInstance3D
		if drawn.mesh == null:
			continue
		out.append_array(_triangles_of(drawn.mesh, drawn.global_transform))
	return out


static func _triangles_of(mesh: Mesh, xform: Transform3D) -> Array:
	var out: Array = []
	var to_normal := FaceDataScript.normal_basis(xform.basis)
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var corners := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			corners = arrays[Mesh.ARRAY_INDEX]
		if corners.is_empty():
			for i in verts.size():
				corners.append(i)
		for t in range(0, corners.size() - 2, 3):
			var points: Array[Vector3] = []
			var shaded: Array[Vector3] = []
			for k in 3:
				points.append(xform * verts[corners[t + k]])
				shaded.append((to_normal * normals[corners[t + k]]).normalized())
			out.append({"points": points, "normals": shaded})
	return out


## Which way a triangle faces: clockwise from outside, as Godot draws it.
static func _facing(tri: Dictionary) -> Vector3:
	var p: Array = tri["points"]
	return ((p[2] - p[0]) as Vector3).cross(p[1] - p[0]).normalized()


static func _centroid(tri: Dictionary) -> Vector3:
	var p: Array = tri["points"]
	return (p[0] + p[1] + p[2]) / 3.0


## Straight out from a cylinder standing on `axis` at `point`.
static func _radial(point: Vector3, axis: Vector3) -> Vector3:
	return Vector3(point.x - axis.x, 0.0, point.z - axis.z).normalized()


static func _is_cap(tri: Dictionary) -> bool:
	return absf(_facing(tri).y) > 0.99


## A cylinder side never faces along an axis: its sixteen sides face halfway
## between the corners of a ring that starts on +Z. A cut's walls do.
static func _is_side(tri: Dictionary) -> bool:
	var facing := _facing(tri)
	return absf(facing.y) < 0.01 and not _axis_aligned(facing)


static func _axis_aligned(direction: Vector3) -> bool:
	var a := direction.abs()
	return maxf(a.x, maxf(a.y, a.z)) > 0.999


## Assert a cylinder's sides shade round and its caps flat, and return how many
## side corners were checked.
func _assert_round_sides_flat_caps(tris: Array, axis: Vector3, what: String) -> int:
	var sides := 0
	var caps := 0
	for tri in tris:
		var facing := _facing(tri)
		for k in 3:
			var normal: Vector3 = tri["normals"][k]
			if _is_cap(tri):
				caps += 1
				assert_gt(normal.dot(facing), SAME, "%s: a cap shades flat" % what)
			elif _is_side(tri):
				sides += 1
				var radial := _radial(tri["points"][k], axis)
				assert_gt(
					normal.dot(radial),
					SAME,
					"%s: a side shades straight out from the axis at %s" % [what, tri["points"][k]]
				)
	assert_gt(caps, 0, "fixture: %s has caps" % what)
	assert_gt(sides, 0, "fixture: %s has sides" % what)
	return sides


# -- FaceData ------------------------------------------------------------------


func test_a_new_face_shades_flat():
	assert_eq(FaceDataScript.new().smoothing_group, 0)


func test_a_face_keeps_its_group_through_a_save():
	var face := FaceDataScript.new()
	face.smoothing_group = 3
	var back := FaceDataScript.from_dict(face.to_dict())
	assert_eq(back.smoothing_group, 3, "the group goes into the record and comes back")


func test_a_record_from_before_reads_flat():
	var data := FaceDataScript.new().to_dict()
	data.erase("smoothing_group")
	assert_eq(FaceDataScript.from_dict(data).smoothing_group, 0, "no group is flat")
	for bad in [-4, "two", NAN, null]:
		data["smoothing_group"] = bad
		assert_eq(FaceDataScript.from_dict(data).smoothing_group, 0, "%s reads as flat" % [bad])
	data["smoothing_group"] = 2.0
	assert_eq(FaceDataScript.from_dict(data).smoothing_group, 2, "JSON's 2.0 is group 2")


# -- New brushes ---------------------------------------------------------------


func test_a_new_cylinder_smooths_its_sides_and_not_its_caps():
	var cylinder := _brush(LevelRoot.BrushShape.CYLINDER)
	var sides := 0
	var caps := 0
	for face in cylinder.faces:
		if absf(face.normal.y) > 0.99:
			caps += 1
			assert_eq(face.smoothing_group, 0, "a cap is flat")
		else:
			sides += 1
			assert_eq(face.smoothing_group, 1, "a side is in group 1")
	assert_eq(caps, 2, "fixture: two caps")
	assert_eq(sides, 16, "fixture: sixteen sides")


func test_a_new_cone_smooths_its_sides_and_not_its_base():
	var cone := _brush(LevelRoot.BrushShape.CONE)
	var base := 0
	for face in cone.faces:
		if absf(face.normal.y) > 0.99:
			base += 1
			assert_eq(face.smoothing_group, 0, "the base is flat")
		else:
			assert_eq(face.smoothing_group, 1, "a side is in group 1")
	assert_eq(base, 1, "fixture: one base")


func test_every_face_of_a_new_sphere_ellipsoid_capsule_and_torus_is_smoothed():
	for shape in [
		LevelRoot.BrushShape.SPHERE,
		LevelRoot.BrushShape.ELLIPSOID,
		LevelRoot.BrushShape.CAPSULE,
		LevelRoot.BrushShape.TORUS,
	]:
		var brush := _brush(shape, Vector3(32, 48, 32))
		assert_gt(brush.faces.size(), 0, "fixture: shape %d has faces" % shape)
		for face in brush.faces:
			assert_eq(face.smoothing_group, 1, "shape %d is round all over" % shape)


func test_flat_shapes_stay_flat():
	for shape in [
		LevelRoot.BrushShape.BOX, LevelRoot.BrushShape.WEDGE, LevelRoot.BrushShape.PYRAMID
	]:
		for face in _brush(shape, Vector3(32, 32, 32)).faces:
			assert_eq(face.smoothing_group, 0, "shape %d is flat" % shape)


func test_a_resize_keeps_the_group_a_mapper_gave_a_face():
	var cylinder := _brush(LevelRoot.BrushShape.CYLINDER)
	for face in cylinder.faces:
		face.smoothing_group = 0
	cylinder.faces[3].smoothing_group = 5
	cylinder.size = Vector3(48, 80, 48)
	var groups := {}
	for face in cylinder.faces:
		groups[face.smoothing_group] = int(groups.get(face.smoothing_group, 0)) + 1
	assert_eq(groups, {0: 17, 5: 1}, "the rebuilt faces keep the groups they had")


func test_a_box_made_a_cylinder_shades_round():
	var brush := _brush(LevelRoot.BrushShape.BOX, Vector3(32, 32, 32))
	brush.shape = LevelRoot.BrushShape.CYLINDER
	var sides := 0
	for face in brush.faces:
		if absf(face.normal.y) <= 0.99:
			sides += 1
			assert_eq(face.smoothing_group, 1, "a side the box became is round")
	assert_gt(sides, 0, "fixture: the brush is a cylinder now")


func test_a_cylinder_saved_before_groups_stays_flat():
	var made := _brush(LevelRoot.BrushShape.CYLINDER)
	var records: Array = made.serialize_faces()
	for record: Dictionary in records:
		record.erase("smoothing_group")
	var info := {
		"shape": LevelRoot.BrushShape.CYLINDER,
		"size": CYLINDER_SIZE,
		"center": Vector3(100, 0, 0),
		"sides": 16,
		"faces": records,
	}
	var old := root.create_brush_from_info(info) as DraftBrush
	old.size = Vector3(40, 64, 40)
	for face in old.faces:
		assert_eq(face.smoothing_group, 0, "a level from before keeps shading as it did")


# -- HFSmoothing -----------------------------------------------------------------


static func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, b, c, d])


func test_faces_of_one_group_share_the_corners_they_meet_at():
	var shading := HFSmoothingScript.new()
	var floor_ := shading.add(
		_quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)), Vector3.UP, 1
	)
	var wall := shading.add(
		_quad(Vector3(1, 0, 0), Vector3(1, -1, 0), Vector3(1, -1, 1), Vector3(1, 0, 1)),
		Vector3.RIGHT,
		1
	)
	var shared := (Vector3.UP + Vector3.RIGHT).normalized()
	var floor_normals := shading.corner_normals(floor_)
	assert_true(floor_normals[0].is_equal_approx(Vector3.UP), "a corner of its own is its own")
	assert_true(floor_normals[1].is_equal_approx(shared), "a corner they share is the average")
	assert_true(floor_normals[2].is_equal_approx(shared), "both shared corners")
	var wall_normals := shading.corner_normals(wall)
	assert_true(wall_normals[0].is_equal_approx(shared), "the same on the other face")
	assert_true(wall_normals[1].is_equal_approx(Vector3.RIGHT), "and its own corner")


func test_faces_share_only_with_their_own_group_and_side():
	var floor_corners := _quad(
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)
	)
	var wall_corners := _quad(
		Vector3(1, 0, 0), Vector3(1, -1, 0), Vector3(1, -1, 1), Vector3(1, 0, 1)
	)
	var shading := HFSmoothingScript.new()
	var a := shading.add(floor_corners, Vector3.UP, 1)
	shading.add(wall_corners, Vector3.RIGHT, 2)
	assert_true(shading.corner_normals(a)[1].is_equal_approx(Vector3.UP), "another group")
	var cuts := HFSmoothingScript.new()
	var solid := cuts.add(floor_corners, Vector3.UP, 1)
	cuts.add(wall_corners, Vector3.RIGHT, 1, true)
	assert_true(cuts.corner_normals(solid)[1].is_equal_approx(Vector3.UP), "a cut and a solid")
	assert_eq(shading.add(floor_corners, Vector3.UP, 0), -1, "group 0 is not added")


func test_brushes_a_rounding_error_apart_still_meet():
	var shading := HFSmoothingScript.new()
	var a := shading.add(
		_quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)), Vector3.UP, 1
	)
	var nudge := Vector3(0.0003, -0.0002, 0.0001)
	shading.add(
		_quad(
			Vector3(1, 0, 0) + nudge,
			Vector3(1, -1, 0) + nudge,
			Vector3(1, -1, 1) + nudge,
			Vector3(1, 0, 1) + nudge
		),
		Vector3.RIGHT,
		1
	)
	assert_true(
		shading.corner_normals(a)[1].is_equal_approx((Vector3.UP + Vector3.RIGHT).normalized()),
		"corners a ten-thousandth apart are one corner"
	)


func test_reshading_leaves_a_mesh_with_nothing_on_a_smoothed_face_as_it_was():
	var shading := HFSmoothingScript.new()
	shading.add(
		_quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)), Vector3.UP, 1
	)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4, 4, 4)
	var arrays := mesh.get_mesh_arrays()
	var box := ArrayMesh.new()
	box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assert_same(shading.reshade(box), box, "nothing of a box far away lies on the face")


# -- The face bake -------------------------------------------------------------


func test_a_sixteen_sided_cylinder_bakes_round_sides_and_flat_caps():
	var axis := Vector3(10, 32, -6)
	_brush(LevelRoot.BrushShape.CYLINDER, CYLINDER_SIZE, axis)
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	_assert_round_sides_flat_caps(_baked_triangles(), axis, "the face bake")


func test_a_face_in_group_0_bakes_exactly_as_before():
	var cylinder := _brush(LevelRoot.BrushShape.CYLINDER, CYLINDER_SIZE, Vector3(0, 32, 0))
	for face in cylinder.faces:
		face.smoothing_group = 0
	var flat := []
	for face in cylinder.faces:
		flat.append(face.normal_through(cylinder.global_transform.basis))
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var tris := _baked_triangles()
	assert_gt(tris.size(), 0, "fixture: something baked")
	for tri in tris:
		for normal: Vector3 in tri["normals"]:
			assert_gt(normal.dot(_facing(tri)), SAME, "each corner shades with its triangle")
			# Within what a mesh keeps of a normal: it packs each into two numbers.
			var one_of_the_faces := false
			for face_normal: Vector3 in flat:
				one_of_the_faces = one_of_the_faces or normal.dot(face_normal) > SAME
			assert_true(one_of_the_faces, "and with its face's own normal, as it always did")


## The arch's centre is where it was built, and it lies across X and Y.
static func _arch_radial(point: Vector3, centre: Vector3) -> Vector3:
	return Vector3(point.x - centre.x, point.y - centre.y, 0.0).normalized()


## Assert every corner on the arch's curve, inside and out, shades straight out
## from its centre, and return how many corners at a joint were checked.
func _assert_round_arch(tris: Array, centre: Vector3, what: String) -> int:
	var joints := 0
	for tri in tris:
		var facing := _facing(tri)
		var across := facing.dot(_arch_radial(_centroid(tri), centre))
		if absf(facing.z) > 0.01 or absf(across) < 0.9:
			continue
		for k in 3:
			var point: Vector3 = tri["points"][k]
			# The two ends of the arch meet nothing.
			if absf(point.y - centre.y) < 0.01:
				continue
			var radial := _arch_radial(point, centre) * signf(across)
			assert_gt(
				(tri["normals"][k] as Vector3).dot(radial),
				SAME,
				"%s: the curve shades round at %s" % [what, point]
			)
			joints += 1
	assert_gt(joints, 0, "fixture: %s has corners on its curve" % what)
	return joints


func test_an_arch_of_separate_brushes_bakes_smooth_across_its_joints():
	var centre := Vector3(4, 2, -3)
	var built: HFOpResult = root.create_arch({"segments": 8}, centre)
	assert_true(built.ok, "fixture: the arch is built")
	assert_eq(root.draft_brushes_node.get_child_count(), 8, "fixture: one brush per segment")
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	_assert_round_arch(_baked_triangles(), centre, "the face bake")


## A dome's shell, outside and in, is one curve across every panel; the joints
## between rings and between meridians are flat.
func test_a_dome_smooths_its_shell_and_not_its_joints():
	var shell := 0
	var joints := 0
	for panel: Array in HFDomeBuilderScript.build(HFDomeBuilderScript.default_settings()):
		for face: FaceData in panel:
			var centre := Vector3.ZERO
			for corner in face.local_verts:
				centre += corner
			centre /= float(face.local_verts.size())
			var out_from_axis := Vector3(centre.x, 0.0, centre.z).normalized()
			var round_face := absf(face.normal.dot(out_from_axis)) > 0.01
			if face.smoothing_group == 1:
				shell += 1
				assert_true(round_face, "a face on the shell faces out from the axis")
			else:
				joints += 1
				assert_eq(face.smoothing_group, 0, "a joint is flat")
				assert_true(
					absf(face.normal.y) > 0.99 or not round_face,
					"a joint lies level or along a meridian"
				)
	assert_gt(shell, 0, "fixture: the dome has a shell")
	assert_gt(joints, 0, "fixture: and joints")


# -- The CSG bake --------------------------------------------------------------


## A cylinder standing on `axis` with a slot cut through its +X side.
func _cut_cylinder(level: LevelRoot, axis: Vector3) -> DraftBrush:
	var cylinder := _brush(LevelRoot.BrushShape.CYLINDER, CYLINDER_SIZE, axis, level)
	_brush(
		LevelRoot.BrushShape.BOX,
		Vector3(16, 16, 64),
		axis + Vector3(16, 0, 0),
		level,
		{"operation": CSGShape3D.OPERATION_SUBTRACTION}
	)
	return cylinder


func test_a_cut_cylinder_on_the_csg_path_bakes_the_normals_of_the_face_path():
	var axis := Vector3(0, 32, 0)
	_brush(LevelRoot.BrushShape.CYLINDER, CYLINDER_SIZE, axis)
	assert_true(await root.bake(true, false), "fixture: the uncut level bakes")
	var by_place := {}
	for tri in _baked_triangles():
		if not _is_side(tri):
			continue
		for k in 3:
			by_place[(tri["points"][k] as Vector3).snapped(Vector3.ONE * 0.01)] = tri["normals"][k]

	var cut := _level()
	_cut_cylinder(cut, axis)
	assert_true(await cut.bake(true, false), "fixture: the cut level bakes")
	var tris := _baked_triangles(cut)
	var matched := 0
	var cut_faces := 0
	for tri in tris:
		var facing := _facing(tri)
		if _axis_aligned(facing):
			# A cap, and the slot's floor, ceiling and back.
			if not _is_cap(tri):
				cut_faces += 1
			for normal: Vector3 in tri["normals"]:
				assert_gt(normal.dot(facing), SAME, "a flat face shades flat, the cut's too")
			continue
		if not _is_side(tri):
			continue
		for k in 3:
			var point: Vector3 = tri["points"][k]
			var normal: Vector3 = tri["normals"][k]
			assert_gt(
				normal.dot(_radial(point, axis)),
				SAME,
				"a side shades round, up to the cut, at %s" % point
			)
			var place := point.snapped(Vector3.ONE * 0.01)
			if by_place.has(place):
				matched += 1
				assert_gt(normal.dot(by_place[place]), SAME, "as the face bake shades it")
	assert_gt(cut_faces, 0, "fixture: the cut made faces of its own")
	assert_gt(matched, 0, "fixture: corners the cut left alone were compared")


## Godot's own sphere is not the sphere a brush is: a smoothed brush goes into the
## boolean as its faces, so a cut leaves the sphere the face bake makes, shaded as
## it shades.
func test_a_cut_sphere_on_the_csg_path_is_the_sphere_the_face_path_bakes():
	var centre := Vector3(0, 32, 0)
	var size := Vector3(32, 32, 32)
	_brush(LevelRoot.BrushShape.SPHERE, size, centre)
	assert_true(await root.bake(true, false), "fixture: the whole sphere bakes")
	var by_place := {}
	for tri in _baked_triangles():
		for k in 3:
			by_place[(tri["points"][k] as Vector3).snapped(Vector3.ONE * 0.01)] = tri["normals"][k]

	var cut := _level()
	_brush(LevelRoot.BrushShape.SPHERE, size, centre, cut)
	_brush(
		LevelRoot.BrushShape.BOX,
		Vector3(8, 8, 8),
		centre + Vector3(16, 0, 0),
		cut,
		{"operation": CSGShape3D.OPERATION_SUBTRACTION}
	)
	assert_true(await cut.bake(true, false), "fixture: the cut sphere bakes")
	var found := {}
	for tri in _baked_triangles(cut):
		for k in 3:
			var place := (tri["points"][k] as Vector3).snapped(Vector3.ONE * 0.01)
			if not by_place.has(place):
				continue
			found[place] = true
			assert_gt(
				(tri["normals"][k] as Vector3).dot(by_place[place]),
				SAME,
				"the cut sphere shades %s as the whole one does" % place
			)
	# The notch takes a few corners away and leaves the rest where they were.
	assert_gt(float(found.size()), by_place.size() * 0.8, "the corners of the sphere are its own")


func test_bake_selected_shades_a_brush_as_the_whole_level_does():
	var centre := Vector3(0, 0, 0)
	assert_true(root.create_arch({"segments": 8}, centre).ok, "fixture: the arch is built")
	var middle := root.draft_brushes_node.get_child(3) as DraftBrush
	assert_true(await root.bake_selected([middle]), "fixture: Bake Selected bakes it")
	var joints := _assert_round_arch(_baked_triangles(), centre, "Bake Selected")
	assert_gt(joints, 0, "its joints with the segments it left out shade round")


func test_the_csg_bake_shades_an_untextured_round_brush_with_its_faces():
	var axis := Vector3(0, 32, 0)
	_cut_cylinder(root, axis)
	root.bake_use_face_materials = false
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	_assert_round_sides_flat_caps(_baked_triangles(), axis, "Use Face Materials off")


# -- Preview, clip and what the bake carries -----------------------------------


func test_a_textured_round_brush_previews_with_the_normals_it_bakes_with():
	var slot := root.material_manager.add_material(StandardMaterial3D.new())
	var axis := Vector3(7, 32, -5)
	var cylinder := _brush(LevelRoot.BrushShape.CYLINDER, CYLINDER_SIZE, axis)
	var every: Array[int] = []
	for i in cylinder.faces.size():
		every.append(i)
	cylinder.assign_material_to_faces(slot, every)
	var preview := _triangles_of(
		cylinder.mesh_instance.mesh, cylinder.mesh_instance.global_transform
	)
	_assert_round_sides_flat_caps(preview, axis, "the preview")
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var baked := {}
	for tri in _baked_triangles():
		for k in 3:
			var place := (tri["points"][k] as Vector3).snapped(Vector3.ONE * 0.01)
			if not baked.has(place):
				baked[place] = []
			baked[place].append(tri["normals"][k])
	for tri in preview:
		for k in 3:
			var place := (tri["points"][k] as Vector3).snapped(Vector3.ONE * 0.01)
			var found := false
			for normal: Vector3 in baked.get(place, []):
				found = found or normal.dot(tri["normals"][k]) > SAME
			assert_true(found, "the bake shades %s as the preview does" % place)


func test_a_painted_round_brush_keeps_its_paint_and_its_shading_through_a_cut():
	var axis := Vector3(0, 32, 0)
	var cylinder := _cut_cylinder(root, axis)
	var side: FaceData = null
	for face in cylinder.faces:
		if face.smoothing_group == 1:
			side = face
			break
	var layer := FaceDataScript.PaintLayer.new()
	layer.texture = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	layer.ensure_weight_image(Vector2i(4, 4))
	layer.weight_image.fill(Color.WHITE)
	side.paint_layers.append(layer)
	cylinder.rebuild_preview()
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var painted := 0
	for node in root.baked_container.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var drawn := mesh.surface_get_material(s) as BaseMaterial3D
			if drawn and drawn.albedo_texture:
				painted += 1
	assert_eq(painted, 1, "the painted side bakes with its paint")
	_assert_round_sides_flat_caps(_baked_triangles(), axis, "a painted cylinder with a cut")


func test_a_clip_through_a_round_brush_leaves_its_cut_flat():
	var cylinder := _brush(LevelRoot.BrushShape.CYLINDER, CYLINDER_SIZE, Vector3(0, 32, 0))
	var result: HFOpResult = root.clip_brush_by_plane(cylinder.brush_id, Plane(Vector3.RIGHT, 4.0))
	assert_true(result.ok, "fixture: the clip cuts")
	var cut_faces := 0
	for piece in root.draft_brushes_node.get_children():
		var brush := piece as DraftBrush
		if brush == null or brush.is_queued_for_deletion():
			continue
		for face in brush.faces:
			if absf(face.normal.x) > 0.999:
				cut_faces += 1
				assert_eq(face.smoothing_group, 0, "the face the clip made is flat")
		var preview := _triangles_of(brush.mesh_instance.mesh, brush.mesh_instance.global_transform)
		for tri in preview:
			if absf(_facing(tri).x) > 0.999:
				for normal: Vector3 in tri["normals"]:
					assert_gt(normal.dot(_facing(tri)), SAME, "and previews flat")
	assert_eq(cut_faces, 2, "fixture: one cut face on each piece")


## Hollow cuts its walls with the brush's own planes pushed in. The faces that cut
## makes are flat, as a cut's are, apart from the walls inside, which lie behind a
## face of the brush and take its group: a round brush hollows into a tube that is
## round inside and out.
func test_hollow_makes_a_round_brush_a_tube_round_inside_and_out():
	var axis := Vector3(0, 32, 0)
	var cylinder := _brush(LevelRoot.BrushShape.CYLINDER, CYLINDER_SIZE, axis)
	assert_true(root.hollow_brush_by_id(cylinder.brush_id, 4.0).ok, "fixture: it hollows")
	var outside := 0
	var inside := 0
	for piece in root.draft_brushes_node.get_children():
		var wall := piece as DraftBrush
		if wall == null or wall.is_queued_for_deletion():
			continue
		for face in wall.faces:
			var centre := Vector3.ZERO
			for corner in face.local_verts:
				centre += wall.global_transform * corner
			centre /= float(face.local_verts.size())
			var normal: Vector3 = face.normal_through(wall.global_transform.basis)
			var across := normal.dot(_radial(centre, axis))
			var from_axis := Vector2(centre.x - axis.x, centre.z - axis.z).length()
			if across > 0.9 and from_axis > 15.0:
				outside += 1
				assert_eq(face.smoothing_group, 1, "the outside is still round")
			elif across < -0.9:
				inside += 1
				assert_eq(face.smoothing_group, 1, "and so is the inside")
			elif absf(normal.y) < 0.99:
				# Where one wall meets the next, and inside the ring where the top
				# and the bottom meet the walls: cuts, and flat.
				assert_eq(face.smoothing_group, 0, "a face the cut made is flat")
	assert_gt(outside, 16, "fixture: the sides face out, in pieces")
	assert_gt(inside, 0, "fixture: walls face in")


func test_a_smoothed_bake_keeps_its_lightmap_uv2():
	root.bake_lightmap_uv2 = true
	var axis := Vector3(0, 32, 0)
	_brush(LevelRoot.BrushShape.CYLINDER, CYLINDER_SIZE, axis)
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var with_uv2 := 0
	for node in root.baked_container.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var uv2 = mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV2]
			if uv2 is PackedVector2Array and not (uv2 as PackedVector2Array).is_empty():
				with_uv2 += 1
	assert_gt(with_uv2, 0, "the unwrap still ran")
	_assert_round_sides_flat_caps(_baked_triangles(), axis, "after the UV2 unwrap")


func test_occluders_take_a_smoothed_triangle_s_own_plane():
	var holder := Node3D.new()
	add_child_autofree(holder)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# One flat triangle facing +Y, its corners shaded leaning out as a smoothed
	# face's are.
	var corners := [Vector3(0, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 0)]
	var leaning := [Vector3(-1, 2, -1), Vector3(-1, 2, 1), Vector3(1, 2, -1)]
	for i in 3:
		st.set_normal((leaning[i] as Vector3).normalized())
		st.add_vertex(corners[i])
	var drawn := MeshInstance3D.new()
	drawn.mesh = st.commit()
	holder.add_child(drawn)
	var bake := HFBakeSystemScript.new(root)
	var tris: Array = bake._collect_occluder_triangles(holder)
	assert_eq(tris.size(), 1, "fixture: one triangle")
	assert_true((tris[0]["normal"] as Vector3).is_equal_approx(Vector3.UP), "its own plane")
	assert_almost_eq(float(tris[0]["dist"]), 0.0, 0.0001, "through its own corners")


# -- Setting a group -----------------------------------------------------------


func test_the_selected_faces_take_a_group():
	var box := _brush(LevelRoot.BrushShape.BOX, Vector3(8, 8, 8))
	var top := -1
	for i in box.faces.size():
		if box.faces[i].normal.is_equal_approx(Vector3.UP):
			top = i
	root.toggle_face_selection(box, top, true, false)
	root._dirty_brush_ids.clear()
	assert_eq(root.set_smoothing_group_on_selected_faces(3), 1, "one face took it")
	assert_eq(box.faces[top].smoothing_group, 3, "the selected face is in group 3")
	for i in box.faces.size():
		if i != top:
			assert_eq(box.faces[i].smoothing_group, 0, "the rest are not")
	assert_true(root._dirty_brush_ids.has(box.brush_id), "the brush needs baking again")
	assert_eq(root.set_smoothing_group_on_selected_faces(-1), 0, "-1 is not a group")
	assert_eq(box.faces[top].smoothing_group, 3, "and changed nothing")
