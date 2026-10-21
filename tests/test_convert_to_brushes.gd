extends GutTest

## Convert to Brushes (#1440): Godot meshes and CSG shapes made into brushes where
## they stand, through the real plugin, with the sources hidden in the same undo
## step.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const HFBrushConversion = preload("res://addons/hammerforge/hf_brush_conversion.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")

const EPS := 0.001

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _pick(action: String) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit(action)


## A node in the edited scene, beside the level.
func _place(node: Node3D, xform := Transform3D.IDENTITY) -> Node3D:
	rig.scene_root.add_child(node)
	node.owner = rig.scene_root
	node.global_transform = xform
	return node


func _brushes(root: Node) -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush:
			out.append(child)
	return out


func _world_corners(brush: DraftBrush) -> PackedVector3Array:
	var out := PackedVector3Array()
	for face in brush.faces:
		for v in face.local_verts:
			out.append(brush.global_transform * v)
	return out


## Every corner of the mesh Godot built for a CSG node, in the world.
func _csg_corners(node: CSGShape3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var meshes: Array = node.get_meshes()
	if meshes.size() < 2:
		return out
	var mesh: Mesh = meshes[1]
	for surface in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			out.append(node.global_transform * v)
	return out


## Whether each of `points` lies inside `brush` or on its surface: behind every
## face's plane. With every corner of the brush one of the points, the two are
## the same solid, whatever extra points a mesh puts in the middle of a face.
static func _all_inside(points: PackedVector3Array, brush: DraftBrush) -> bool:
	var xform := brush.global_transform
	for face in brush.faces:
		var normal: Vector3 = face.normal_through(xform.basis)
		var on: Vector3 = xform * face.local_verts[0]
		for point in points:
			if (point - on).dot(normal) > EPS:
				return false
	return true


## Whether each point of `points` has one of `others` within `EPS`.
static func _all_near(points: PackedVector3Array, others: PackedVector3Array) -> bool:
	for point in points:
		var found := false
		for other in others:
			if other.distance_to(point) < EPS:
				found = true
				break
		if not found:
			return false
	return true


func _box_triangles(size: Vector3, centre := Vector3.ZERO) -> PackedVector3Array:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	for i in arrays[Mesh.ARRAY_INDEX]:
		out.append(verts[i] + centre)
	return out


## A 2 x 2 x 2 box whose top is a surface of its own.
func _two_surface_box() -> ArrayMesh:
	var triangles := _box_triangles(Vector3(2, 2, 2))
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, triangles.size(), 3):
		var into: SurfaceTool = (
			top
			if triangles[t].y > 0.5 and triangles[t + 1].y > 0.5 and triangles[t + 2].y > 0.5
			else sides
		)
		for k in 3:
			into.add_vertex(triangles[t + k])
	var mesh := sides.commit()
	top.commit(mesh)
	return mesh


## An L-shaped prism: one closed mesh, not convex. Each triangle is wound to face
## out, so only the shape is wrong with it.
func _l_prism() -> ArrayMesh:
	var outline := PackedVector2Array(
		[Vector2(0, 0), Vector2(4, 0), Vector2(4, 1), Vector2(1, 1), Vector2(1, 3), Vector2(0, 3)]
	)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var caps := Geometry2D.triangulate_polygon(outline)
	for z in [0.0, 1.0]:
		var outward := Vector3.BACK if z > 0.5 else Vector3.FORWARD
		for t in range(0, caps.size(), 3):
			var tri: Array = []
			for k in 3:
				var p := outline[caps[t + k]]
				tri.append(Vector3(p.x, p.y, z))
			_add_outward(st, tri, outward)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var outward := Vector3(b.y - a.y, a.x - b.x, 0.0).normalized()
		var quad := [
			Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), Vector3(b.x, b.y, 1), Vector3(a.x, a.y, 1)
		]
		_add_outward(st, [quad[0], quad[1], quad[2]], outward)
		_add_outward(st, [quad[0], quad[2], quad[3]], outward)
	return st.commit()


## A triangle added clockwise seen from `outward`, as Godot draws a front face.
func _add_outward(st: SurfaceTool, tri: Array, outward: Vector3) -> void:
	var a: Vector3 = tri[0]
	var b: Vector3 = tri[1]
	var c: Vector3 = tri[2]
	if (c - a).cross(b - a).dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# ===========================================================================
# CSG shapes
# ===========================================================================


func test_a_turned_csg_box_becomes_a_box_brush_of_its_size_and_transform():
	var root = await rig.make_level()
	var csg := CSGBox3D.new()
	csg.size = Vector3(4, 2, 6)
	var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(3, 1, -2))
	_place(csg, xform)
	rig.select([csg])
	_pick("convert_to_brushes")
	var made := _brushes(root)
	assert_eq(made.size(), 1, "one brush")
	var brush: DraftBrush = made[0]
	assert_eq(brush.shape, LevelRoot.BrushShape.BOX, "a box brush")
	assert_almost_eq(brush.size, Vector3(4, 2, 6), Vector3.ONE * EPS, "of the box's size")
	assert_true(brush.global_transform.is_equal_approx(xform), "standing where the node stood")
	assert_false(csg.visible, "the node is hidden")
	assert_true(is_instance_valid(csg) and csg.is_inside_tree(), "not deleted")
	assert_eq(rig.plugin.hf_selection, [brush], "and the brush is what is selected")
	await rig.leave_level(root)


func test_a_csg_cone_becomes_a_cone_brush_with_the_same_sides_and_corners():
	var root = await rig.make_level()
	var cone := CSGCylinder3D.new()
	cone.cone = true
	cone.sides = 6
	cone.radius = 2.0
	cone.height = 3.0
	_place(cone, Transform3D(Basis(), Vector3(-4, 2, 0)))
	var cylinder := CSGCylinder3D.new()
	cylinder.sides = 7
	cylinder.radius = 1.5
	cylinder.height = 4.0
	_place(cylinder, Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(5, 2, 1)))
	await rig.frame()
	await rig.frame()
	var cone_corners := _csg_corners(cone)
	var cylinder_corners := _csg_corners(cylinder)
	assert_gt(cone_corners.size(), 0, "Godot built the cone")
	rig.select([cone, cylinder])
	_pick("convert_to_brushes")
	var made := _brushes(root)
	assert_eq(made.size(), 2)
	var cone_brush: DraftBrush = made[0]
	var cylinder_brush: DraftBrush = made[1]
	assert_eq(cone_brush.shape, LevelRoot.BrushShape.CONE, "a cone brush")
	assert_eq(cone_brush.sides, 6, "with the cone's sides")
	assert_eq(cylinder_brush.shape, LevelRoot.BrushShape.CYLINDER)
	assert_eq(cylinder_brush.sides, 7)
	assert_true(_all_near(_world_corners(cone_brush), cone_corners), "every corner on the cone's")
	assert_true(_all_inside(cone_corners, cone_brush), "and the cone's are all in the brush")
	assert_true(
		_all_near(_world_corners(cylinder_brush), cylinder_corners),
		"a cylinder's land on its node's"
	)
	assert_true(_all_inside(cylinder_corners, cylinder_brush))
	await rig.leave_level(root)


func test_a_three_sided_csg_cylinder_becomes_a_custom_prism_on_its_corners():
	var root = await rig.make_level()
	var prism := CSGCylinder3D.new()
	prism.sides = 3
	_place(prism, Transform3D(Basis(), Vector3(0, 1, 0)))
	await rig.frame()
	await rig.frame()
	var corners := _csg_corners(prism)
	rig.select([prism])
	_pick("convert_to_brushes")
	var brush: DraftBrush = _brushes(root)[0]
	assert_eq(brush.shape, LevelRoot.BrushShape.CUSTOM, "fewer sides than a round brush has")
	assert_eq(brush.faces.size(), 5, "two ends and three sides")
	assert_true(_all_near(_world_corners(brush), corners))
	assert_true(_all_inside(corners, brush))
	await rig.leave_level(root)


## A scale is folded into the brush and its turn kept, so a stretched box stays
## a box of the size it shows, and its faces read their Box UV as a box drawn
## there would.
func test_a_stretched_turned_csg_box_keeps_its_turn_and_takes_its_scale_as_size():
	var root = await rig.make_level()
	var csg := CSGBox3D.new()
	csg.size = Vector3(4, 2, 6)
	# A quarter turn puts four faces on another Box UV axis than they read square,
	# so a fold that took the turn for a new one would flip their textures.
	var turn := Basis(Vector3.UP, PI / 2.0)
	_place(csg, Transform3D(turn * Basis.from_scale(Vector3(2, 1, 1)), Vector3(1, 1, 1)))
	var mirrored := CSGBox3D.new()
	mirrored.size = Vector3(2, 2, 2)
	_place(mirrored, Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3(9, 1, 0)))
	rig.select([csg, mirrored])
	_pick("convert_to_brushes")
	var made := _brushes(root)
	var brush: DraftBrush = made[0]
	assert_eq(brush.shape, LevelRoot.BrushShape.BOX)
	assert_almost_eq(brush.size, Vector3(8, 2, 6), Vector3.ONE * EPS, "the scale is in its size")
	assert_true(brush.global_basis.is_equal_approx(turn), "and its turn on the node")
	var drawn = root.create_brush_from_info(
		{
			"size": Vector3(8, 2, 6),
			"brush_id": "drawn",
			"transform": Transform3D(turn, Vector3(1, 1, 1))
		}
	)
	for i in brush.faces.size():
		assert_eq(brush.faces[i].uv_scale, drawn.faces[i].uv_scale, "face %d reads as drawn" % i)
		var shown: PackedVector2Array = brush.faces[i].shown_uvs()
		var expected: PackedVector2Array = drawn.faces[i].shown_uvs()
		for k in shown.size():
			assert_almost_eq(shown[k], expected[k], Vector2.ONE * EPS, "face %d shows it" % i)
	var flipped: DraftBrush = made[1]
	assert_gt(
		flipped.global_basis.determinant(), 0.0, "a mirrored node gives a brush the right way out"
	)
	assert_almost_eq(flipped.size, Vector3(2, 2, 2), Vector3.ONE * EPS)
	await rig.leave_level(root)


func test_a_cut_inside_a_csg_parent_becomes_a_cutting_brush_after_what_it_cuts():
	var root = await rig.make_level()
	var parent := CSGCombiner3D.new()
	_place(parent)
	var solid := CSGBox3D.new()
	solid.size = Vector3(4, 4, 4)
	parent.add_child(solid)
	solid.owner = rig.scene_root
	var cut := CSGBox3D.new()
	cut.size = Vector3(2, 2, 2)
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(cut)
	cut.owner = rig.scene_root
	var lone := CSGBox3D.new()
	lone.operation = CSGShape3D.OPERATION_SUBTRACTION
	_place(lone, Transform3D(Basis(), Vector3(8, 0, 0)))
	rig.select([cut, lone, solid])
	_pick("convert_to_brushes")
	var made := _brushes(root)
	assert_eq(made.size(), 3)
	assert_eq(made[0].operation, CSGShape3D.OPERATION_UNION, "the solid first")
	assert_eq(made[1].operation, CSGShape3D.OPERATION_SUBTRACTION, "then the cut")
	assert_eq(made[2].operation, CSGShape3D.OPERATION_UNION, "a root shape draws solid, so it adds")
	await rig.leave_level(root)


func test_a_csg_node_with_csg_children_is_refused_by_name():
	var root = await rig.make_level()
	var parent := CSGBox3D.new()
	parent.name = "Blockout"
	_place(parent)
	var child := CSGSphere3D.new()
	parent.add_child(child)
	child.owner = rig.scene_root
	rig.clear_toasts()
	rig.select([parent])
	_pick("convert_to_brushes")
	assert_eq(_brushes(root).size(), 0, "no brush is made")
	assert_true(parent.visible, "and the node is left as it was")
	assert_eq(rig.undo().step_count(), 0, "with no undo step")
	assert_has(
		rig.toasts(),
		"Convert to Brushes made no brushes. Left alone: Blockout (it has CSG children)"
	)
	await rig.leave_level(root)


func test_a_convex_depth_polygon_is_a_custom_prism_and_a_concave_one_is_refused():
	var root = await rig.make_level()
	var wedge := CSGPolygon3D.new()
	wedge.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 2), Vector2(1, 2), Vector2(3, 0)])
	wedge.depth = 4.0
	_place(wedge, Transform3D(Basis(), Vector3(0, 0, 3)))
	var notch := CSGPolygon3D.new()
	notch.name = "Notch"
	notch.polygon = PackedVector2Array(
		[Vector2(0, 0), Vector2(0, 2), Vector2(1, 1), Vector2(2, 2), Vector2(2, 0)]
	)
	_place(notch, Transform3D(Basis(), Vector3(6, 0, 0)))
	await rig.frame()
	await rig.frame()
	var corners := _csg_corners(wedge)
	rig.clear_toasts()
	rig.select([wedge, notch])
	_pick("convert_to_brushes")
	var made := _brushes(root)
	assert_eq(made.size(), 1, "only the convex one converts")
	assert_eq(made[0].shape, LevelRoot.BrushShape.CUSTOM)
	assert_eq(made[0].faces.size(), 6, "two caps and four sides")
	assert_true(_all_near(_world_corners(made[0]), corners))
	assert_true(_all_inside(corners, made[0]))
	assert_true(notch.visible)
	assert_has(
		rig.toasts(), "Converted 1 node to brushes. Left alone: Notch (its polygon is not convex)"
	)
	await rig.leave_level(root)


# ===========================================================================
# Meshes
# ===========================================================================


func test_a_convex_mesh_with_two_materials_becomes_one_brush_carrying_both():
	var root = await rig.make_level()
	var mesh := _two_surface_box()
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()
	mesh.surface_set_material(0, red)
	var crate := MeshInstance3D.new()
	crate.mesh = mesh
	crate.set_surface_override_material(1, blue)
	_place(crate, Transform3D(Basis.from_scale(Vector3(1, 3, 1)), Vector3(0, 3, 0)))
	rig.select([crate])
	_pick("convert_to_brushes")
	var made := _brushes(root)
	assert_eq(made.size(), 1, "one brush")
	var brush: DraftBrush = made[0]
	assert_eq(brush.shape, LevelRoot.BrushShape.CUSTOM)
	assert_eq(brush.faces.size(), 6, "a face per side")
	var palette: Array = root.material_manager.materials
	assert_has(palette, red, "the side material joins the palette")
	assert_has(palette, blue, "and so does the top's")
	for face in brush.faces:
		var expected := blue if face.normal.y > 0.5 else red
		assert_eq(palette[face.material_idx], expected, "each face wears its surface's material")
	assert_true(brush.global_basis.is_equal_approx(Basis()), "the scale is folded in")
	var expected_corners := PackedVector3Array()
	for point in _box_triangles(Vector3(2, 6, 2), Vector3(0, 3, 0)):
		expected_corners.append(point)
	assert_true(_all_near(_world_corners(brush), expected_corners), "where the mesh was drawn")
	await rig.leave_level(root)


func test_a_concave_mesh_and_an_open_one_are_refused_and_make_nothing():
	var root = await rig.make_level()
	var l_shape := MeshInstance3D.new()
	l_shape.name = "Ell"
	l_shape.mesh = _l_prism()
	_place(l_shape)
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	sheet.mesh = PlaneMesh.new()
	_place(sheet)
	rig.clear_toasts()
	rig.select([l_shape, sheet])
	_pick("convert_to_brushes")
	assert_eq(_brushes(root).size(), 0, "no brush is made")
	assert_true(l_shape.visible and sheet.visible)
	assert_has(
		rig.toasts(),
		(
			"Convert to Brushes made no brushes. Left alone: Ell (not convex), "
			+ "Sheet (not a closed solid)"
		)
	)
	await rig.leave_level(root)


func test_is_closed_mesh_reads_a_box_as_closed_and_a_box_missing_a_side_as_open():
	assert_true(HFBrushConversion.is_closed_mesh(BoxMesh.new()))
	var triangles := _box_triangles(Vector3(1, 1, 1))
	var open := SurfaceTool.new()
	open.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(6, triangles.size()):
		open.add_vertex(triangles[t])
	assert_false(HFBrushConversion.is_closed_mesh(open.commit()))


# ===========================================================================
# Undo and the menus
# ===========================================================================


func test_one_ctrl_z_removes_the_brushes_and_shows_the_nodes_again():
	var root = await rig.make_level()
	var csg := CSGBox3D.new()
	_place(csg, Transform3D(Basis(), Vector3(2, 0, 0)))
	var crate := MeshInstance3D.new()
	crate.mesh = BoxMesh.new()
	_place(crate, Transform3D(Basis(), Vector3(-2, 0, 0)))
	var undo = rig.undo()
	undo.clear()
	rig.select([csg, crate])
	_pick("convert_to_brushes")
	assert_eq(_brushes(root).size(), 2)
	assert_false(csg.visible or crate.visible, "both nodes hidden")
	assert_eq(undo.step_count(), 1, "in one step")
	undo.press_undo()
	assert_eq(_brushes(root).size(), 0, "Ctrl+Z takes the brushes away")
	assert_true(csg.visible and crate.visible, "and shows the nodes again")
	undo.press_redo()
	assert_eq(_brushes(root).size(), 2, "Ctrl+Shift+Z brings them back")
	assert_false(csg.visible or crate.visible, "and hides the nodes")
	await rig.leave_level(root)


func test_the_space_menu_offers_convert_to_brushes_for_a_csg_or_mesh_selection():
	var root = await rig.make_level()
	var csg := CSGBox3D.new()
	_place(csg)
	rig.select([csg])
	var state := HFPluginOverlays.build_viewport_state(rig.plugin, root, 0)
	assert_eq(int(state.get("convertible_count", 0)), 1)
	var menu = rig.plugin._viewport_context_menu
	menu.show_at(Vector2.ZERO, state)
	var labels: Array = []
	for i in menu.item_count:
		labels.append(menu.get_item_text(i))
	menu.hide()
	assert_has(labels, "Convert to Brushes")
	rig.select([rig.native_node()])
	state = HFPluginOverlays.build_viewport_state(rig.plugin, root, 0)
	menu.show_at(Vector2.ZERO, state)
	labels.clear()
	for i in menu.item_count:
		labels.append(menu.get_item_text(i))
	menu.hide()
	assert_does_not_have(labels, "Convert to Brushes", "a plain node is not offered it")
	await rig.leave_level(root)
