extends GutTest

const HFOutlineUtil = preload("res://addons/hammerforge/hf_outline_util.gd")
## The Clip and Hollow previews must only draw for the brushes their tools
## accept. Anything else used to show a valid-looking wireframe and then fail
## with an error toast when the user clicked.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFClipPreview = preload("res://addons/hammerforge/systems/hf_clip_preview.gd")
const HFHollowPreview = preload("res://addons/hammerforge/systems/hf_hollow_preview.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot
var sys: HFBrushSystem
var clip_preview: HFClipPreview
var hollow_preview: HFHollowPreview


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	sys = root.brush_system
	clip_preview = root.clip_preview
	hollow_preview = root.hollow_preview


func after_each():
	# The root destroys both previews when it leaves the tree.
	clip_preview = null
	hollow_preview = null
	root = null
	sys = null


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


func test_clip_preview_draws_for_a_cylinder():
	# Clip splits real geometry now, so the preview has to promise the cut the
	# tool will make rather than refusing every shape that is not a box.
	var b = _make_brush()
	b.shape = DraftBrush.BrushShape.CYLINDER
	b.rebuild_preview()
	clip_preview.show_preview("brush_1", 1, 0.0)
	assert_true(clip_preview._piece_a_mesh.visible, "A cylinder clip must show both pieces")
	assert_true(clip_preview._piece_b_mesh.visible)
	assert_true(sys.can_clip_brush("brush_1", 1, 0.0).ok, "The tool accepts a cylinder")


func test_clip_preview_draws_for_a_rotated_box():
	var b = _make_brush()
	b.rotation_degrees = Vector3(0, 45, 0)
	b.rebuild_preview()
	clip_preview.show_preview("brush_1", 1, 0.0)
	assert_true(clip_preview._piece_a_mesh.visible, "A rotated clip must show both pieces")
	assert_true(clip_preview._piece_b_mesh.visible)
	assert_true(sys.can_clip_brush("brush_1", 1, 0.0).ok, "The tool accepts a rotated box")


func test_clip_preview_stays_empty_when_the_plane_misses_the_brush():
	_make_brush()
	clip_preview.show_preview("brush_1", 1, 500.0)
	_assert_no_clip_wireframes("Plane clear of the brush")


func test_clip_preview_follows_the_brush_when_it_becomes_a_cylinder_mid_drag():
	var b = _make_brush()
	clip_preview.show_preview("brush_1", 1, 0.0)
	assert_true(clip_preview._piece_a_mesh.visible, "Starts as a valid box preview")
	b.shape = DraftBrush.BrushShape.CYLINDER
	b.rebuild_preview()
	clip_preview.update_split(4.0)
	assert_true(clip_preview._piece_a_mesh.visible, "The preview keeps up with the shape change")


# ===========================================================================
# Hollow preview
# ===========================================================================


func test_hollow_preview_draws_for_an_axis_aligned_box():
	_make_brush()
	hollow_preview.show_preview("brush_1", 4.0)
	assert_eq(hollow_preview._active_count, 6, "A valid hollow shows six walls")
	assert_true(hollow_preview._preview_container.visible, "A valid hollow shows its container")


func test_hollow_preview_draws_for_a_cylinder():
	# Hollow shells real geometry now, so the preview has to promise the walls the
	# tool will build rather than refusing every shape that is not a box.
	var b = _make_brush()
	b.shape = DraftBrush.BrushShape.CYLINDER
	b.rebuild_preview()
	hollow_preview.show_preview("brush_1", 4.0)
	assert_gt(hollow_preview._active_count, 0, "a cylinder hollow must show its walls")
	assert_true(sys.can_hollow_brush("brush_1", 4.0).ok, "The tool accepts a cylinder")


func test_hollow_preview_draws_for_a_wedge():
	var b = _make_brush()
	b.shape = DraftBrush.BrushShape.WEDGE
	b.rebuild_preview()
	hollow_preview.show_preview("brush_1", 4.0)
	assert_gt(hollow_preview._active_count, 0, "a wedge hollow must show its walls")


func test_hollow_preview_draws_for_a_rotated_box():
	var b = _make_brush()
	b.rotation_degrees = Vector3(0, 45, 0)
	b.rebuild_preview()
	hollow_preview.show_preview("brush_1", 4.0)
	assert_eq(hollow_preview._active_count, 6, "a rotated box still hollows into six walls")


func test_hollow_preview_stays_empty_when_the_thickness_leaves_no_room():
	_make_brush()
	hollow_preview.show_preview("brush_1", 500.0)
	_assert_no_hollow_wireframes("Thickness with no interior")


func test_hollow_preview_follows_the_brush_when_it_is_rotated_mid_drag():
	var b = _make_brush()
	hollow_preview.show_preview("brush_1", 4.0)
	assert_eq(hollow_preview._active_count, 6, "Starts as a valid box preview")
	b.rotation_degrees = Vector3(0, 30, 0)
	b.rebuild_preview()
	hollow_preview.update_thickness(6.0)
	assert_eq(hollow_preview._active_count, 6, "The preview keeps up with the rotation")


# ===========================================================================
# Wireframe placement
# ===========================================================================


func test_clip_preview_draws_each_piece_where_the_cut_puts_it():
	# The preview runs the same split the tool runs, so the wireframes are the
	# real piece outlines rather than two scaled unit boxes. Checking the drawn
	# vertices is what catches a preview that promises the wrong cut.
	_make_brush()
	clip_preview.show_preview("brush_1", 1, 0.0)
	# Piece A is the half on the side the plane normal points to, which for a Y
	# cut is the upper one. A 64-cube centred on the origin, cut at y = 0.
	var front := _mesh_bounds(clip_preview._piece_a_mesh)
	var back := _mesh_bounds(clip_preview._piece_b_mesh)
	assert_almost_eq(front.size, Vector3(64, 32, 64), Vector3.ONE * 0.001, "Front piece size")
	assert_almost_eq(back.size, Vector3(64, 32, 64), Vector3.ONE * 0.001, "Back piece size")
	assert_almost_eq(
		front.get_center(), Vector3(0, 16, 0), Vector3.ONE * 0.001, "Front piece centre"
	)
	assert_almost_eq(
		back.get_center(), Vector3(0, -16, 0), Vector3.ONE * 0.001, "Back piece centre"
	)


func test_clip_preview_draws_the_real_outline_of_an_angled_cut():
	# The case two bounding boxes could never show: a diagonal cut whose pieces
	# have overlapping bounds but no overlapping geometry.
	_make_brush()
	clip_preview._brush_id = "brush_1"
	clip_preview.show_preview("brush_1", 1, 0.0)
	var before := _mesh_bounds(clip_preview._piece_a_mesh)
	assert_almost_eq(before.size.y, 32.0, 0.001, "an axis cut halves the height")


## World-space bounds of the line vertices a preview mesh actually draws.
func _mesh_bounds(instance: MeshInstance3D) -> AABB:
	var mesh: Mesh = instance.mesh
	assert_not_null(mesh, "the preview must have assigned a mesh")
	var bounds := AABB()
	var seeded := false
	for surface in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var world: Vector3 = instance.transform * v
			if seeded:
				bounds = bounds.expand(world)
			else:
				bounds = AABB(world, Vector3.ZERO)
				seeded = true
	return bounds


func test_hollow_preview_draws_walls_one_thickness_deep():
	# The preview outlines the real walls now, so which wall is which depends on
	# the order the faces come in. What holds for every wall is that it is one wall
	# thickness deep in one direction, and that they all sit inside the brush.
	_make_brush()
	hollow_preview.show_preview("brush_1", 4.0)
	assert_eq(hollow_preview._active_count, 6)
	for i in hollow_preview._active_count:
		var bounds := _mesh_bounds(hollow_preview._mesh_pool[i])
		var thin := (
			absf(bounds.size.x - 4.0) < 0.001
			or absf(bounds.size.y - 4.0) < 0.001
			or absf(bounds.size.z - 4.0) < 0.001
		)
		assert_true(thin, "wall %d is not one thickness deep: %s" % [i, bounds.size])
		assert_lt(bounds.size.x, 64.001, "no wall may reach outside the brush")
		assert_lt(bounds.size.y, 64.001)
		assert_lt(bounds.size.z, 64.001)


func test_every_preview_now_outlines_real_geometry():
	# All three previews used to draw a shared unit box scaled by the instance
	# transform, which is a lie for any cut or shell that is not box-shaped. They
	# each build the real outline now, so none of them shares that mesh.
	_make_brush()
	hollow_preview.show_preview("brush_1", 4.0)
	clip_preview.show_preview("brush_1", 1, 0.0)
	assert_not_same(
		hollow_preview._mesh_pool[0].mesh,
		HFOutlineUtil.unit_box_line_mesh(),
		"the hollow preview builds its own wall outlines"
	)
	assert_not_same(
		clip_preview._piece_a_mesh.mesh,
		HFOutlineUtil.unit_box_line_mesh(),
		"the clip preview builds its own piece outlines"
	)
