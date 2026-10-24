extends GutTest

## Wrap (#1428): the texture one face shows, carried over an edge it shares with
## the next face, so it runs on round a pillar, down a step's lip or across two
## brushes rather than restarting at every edge. The target's offset, rotation and
## the sign of its scale are solved so the UVs either side of the edge agree.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const HFUVWrapScript = preload("res://addons/hammerforge/hf_uv_wrap.gd")

const EPS := 0.0001
const BOX := FaceDataScript.UVProjection.BOX_UV
const FACE := FaceDataScript.UVProjection.FACE
## Round a pillar from the front, the way U runs along each side seen from outside.
const ROUND_THE_PILLAR := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])


func after_each():
	root = null


# ===========================================================================
# Fixtures
# ===========================================================================


func _brush(brush_id: String, center: Vector3, size: Vector3, shape := 0) -> DraftBrush:
	var b := (
		root.create_brush_from_info(
			{"shape": shape, "size": size, "center": center, "brush_id": brush_id}
		)
		as DraftBrush
	)
	if b.get_faces().is_empty():
		b.rebuild_preview()
	b.sync_face_world_transform()
	return b


static func _face_idx(brush: DraftBrush, direction: Vector3) -> int:
	var basis := brush.global_transform.basis
	for i in brush.faces.size():
		if brush.faces[i].normal_through(basis).dot(direction.normalized()) > 0.99:
			return i
	return -1


static func _face(brush: DraftBrush, direction: Vector3) -> FaceData:
	var idx := _face_idx(brush, direction)
	return brush.faces[idx] if idx >= 0 else null


static func _dress(face: FaceData, projection: int) -> void:
	face.material_idx = 1
	face.uv_projection = projection
	face.uv_offset = Vector2(0.3, -0.2)
	face.uv_scale = Vector2(0.25, -0.125)
	face.uv_rotation = 0.3
	face.custom_uvs = PackedVector2Array()


func _wrap(source: DraftBrush, from: Vector3, target: DraftBrush, onto: Vector3) -> Dictionary:
	return root.wrap_face_texture(
		source.brush_id, _face_idx(source, from), target.brush_id, _face_idx(target, onto)
	)


## The UV a face of `brush` shows at a point of the level on it.
static func _uv_at(brush: DraftBrush, face: FaceData, world: Vector3) -> Vector2:
	brush.sync_face_world_transform()
	return (
		face.shown_uvs_at(PackedVector3Array([brush.global_transform.affine_inverse() * world]))[0]
	)


## The two faces show the same UV at both ends of the edge they share and at its
## middle.
func _assert_seamless(
	source: DraftBrush, from: Vector3, target: DraftBrush, onto: Vector3, what: String
) -> void:
	var edge := HFUVWrapScript.shared_edge(
		_corners(source, _face(source, from)), _corners(target, _face(target, onto))
	)
	assert_eq(edge.size(), 2, "%s: the faces share an edge" % what)
	if edge.size() != 2:
		return
	for point in [edge[0], edge[1], (edge[0] + edge[1]) * 0.5]:
		assert_almost_eq(
			_uv_at(target, _face(target, onto), point),
			_uv_at(source, _face(source, from), point),
			Vector2(EPS, EPS),
			"%s: either side of the edge at %s" % [what, point]
		)


static func _corners(brush: DraftBrush, face: FaceData) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in face.local_verts:
		out.append(brush.global_transform * point)
	return out


## Where the source's texture would be at `point` on the target, were the target
## folded flat beside the source over their edge: what it has to show there for
## the texture to run on.
func _assert_runs_on(
	source: DraftBrush, from: Vector3, target: DraftBrush, onto: Vector3, what: String
) -> void:
	var target_face := _face(target, onto)
	var corners := _corners(target, target_face)
	var middle := Vector3.ZERO
	for point in corners:
		middle += point
	middle /= corners.size()
	var edge := HFUVWrapScript.shared_edge(_corners(source, _face(source, from)), corners)
	var along := (edge[1] - edge[0]).normalized()
	var offset := middle - edge[0]
	var down := offset.dot(along)
	var off := (offset - along * down).length()
	# Away from the source face, in its plane.
	var away := from.cross(along).normalized()
	var source_middle := Vector3.ZERO
	for point in _corners(source, _face(source, from)):
		source_middle += point
	if (source_middle / 4.0 - edge[0]).dot(away) > 0.0:
		away = -away
	var folded := edge[0] + along * down + away * off
	assert_almost_eq(
		_uv_at(target, target_face, middle),
		_uv_at(source, _face(source, from), folded),
		Vector2(EPS, EPS),
		"%s: the texture runs on over the edge rather than folding back" % what
	)


# ===========================================================================
# Round a pillar, over a lip, across brushes
# ===========================================================================


func test_wrapping_round_a_box_pillar_leaves_no_seam_at_three_corners():
	for projection in [BOX, FACE]:
		root.clear_brushes()
		var pillar := _brush("p", Vector3(40, 8, -24), Vector3(32, 64, 16))
		for face in pillar.get_faces():
			face.uv_projection = projection
		_dress(_face(pillar, ROUND_THE_PILLAR[0]), projection)
		for i in 3:
			var from: Vector3 = ROUND_THE_PILLAR[i]
			var onto: Vector3 = ROUND_THE_PILLAR[i + 1]
			var what := "projection %d, %s onto %s" % [projection, from, onto]

			var result := _wrap(pillar, from, pillar, onto)

			assert_true(bool(result.get("ok", false)), "%s is wrapped" % what)
			assert_eq(int(result.get("adjusted", 0)), -1, "%s: no scale had to change" % what)
			_assert_seamless(pillar, from, pillar, onto, what)
			_assert_runs_on(pillar, from, pillar, onto, what)
			var target := _face(pillar, onto)
			assert_eq(target.material_idx, 1, "%s: the material came too" % what)
			assert_almost_eq(target.uv_scale.abs(), Vector2(0.25, 0.125), Vector2(EPS, EPS))


func test_wrapping_from_a_floor_carries_the_texture_down_the_wall_below_its_edge():
	var step := _brush("s", Vector3(-8, 4, 12), Vector3(32, 16, 48))
	_dress(_face(step, Vector3.UP), BOX)

	var result := _wrap(step, Vector3.UP, step, Vector3.BACK)

	assert_true(bool(result.get("ok", false)))
	_assert_seamless(step, Vector3.UP, step, Vector3.BACK, "the lip")
	_assert_runs_on(step, Vector3.UP, step, Vector3.BACK, "the lip")


func test_wrapping_across_two_touching_brushes_is_as_on_one():
	# A's east wall meets B's south wall in an inside corner along x = 16, z = -16.
	var a := _brush("a", Vector3.ZERO, Vector3(32, 32, 32))
	var b := _brush("b", Vector3(32, 0, -32), Vector3(32, 32, 32))
	_dress(_face(a, Vector3.RIGHT), BOX)

	var result := _wrap(a, Vector3.RIGHT, b, Vector3.BACK)

	assert_true(bool(result.get("ok", false)), "the corner between two brushes")
	_assert_seamless(a, Vector3.RIGHT, b, Vector3.BACK, "the inside corner")
	_assert_runs_on(a, Vector3.RIGHT, b, Vector3.BACK, "the inside corner")


func test_a_narrower_brush_on_top_shares_part_of_the_edge_and_keeps_the_look():
	# B stands on A, narrower, its front in A's front's plane. Carried on in one
	# plane the texture is the one A's front shows, so B's front takes its look.
	var a := _brush("a", Vector3.ZERO, Vector3(32, 32, 32))
	var b := _brush("b", Vector3(0, 32, 0), Vector3(16, 32, 32))
	_dress(_face(a, Vector3.BACK), BOX)

	var result := _wrap(a, Vector3.BACK, b, Vector3.BACK)

	assert_true(bool(result.get("ok", false)), "part of an edge is an edge")
	var source := _face(a, Vector3.BACK)
	var target := _face(b, Vector3.BACK)
	assert_almost_eq(target.uv_scale, source.uv_scale, Vector2(EPS, EPS), "the same scale")
	assert_almost_eq(target.uv_offset, source.uv_offset, Vector2(EPS, EPS), "the same offset")
	assert_almost_eq(
		angle_difference(target.uv_rotation, source.uv_rotation), 0.0, EPS, "the same rotation"
	)


func test_a_face_with_no_shared_edge_is_refused_and_left_alone():
	var a := _brush("a", Vector3.ZERO, Vector3(32, 32, 32))
	var b := _brush("b", Vector3(80, 0, 0), Vector3(32, 32, 32))
	_dress(_face(a, Vector3.BACK), BOX)
	var before := _face(b, Vector3.BACK).to_dict()
	var opposite := _face(a, Vector3.FORWARD).to_dict()

	var far := _wrap(a, Vector3.BACK, b, Vector3.BACK)
	var across := _wrap(a, Vector3.BACK, a, Vector3.FORWARD)
	var itself := _wrap(a, Vector3.BACK, a, Vector3.BACK)

	assert_false(bool(far.get("ok", true)), "a face on another brush apart from it")
	assert_eq(far.get("reason"), "no_shared_edge")
	assert_false(bool(across.get("ok", true)), "the face across the brush")
	assert_eq(itself.get("reason"), "same_face", "the face itself")
	assert_eq(_face(b, Vector3.BACK).to_dict(), before, "nothing changed on the far face")
	assert_eq(_face(a, Vector3.FORWARD).to_dict(), opposite, "nor on the opposite one")


func test_a_slope_that_reads_the_edge_short_has_that_scale_changed_and_says_so():
	# The wedge's end is a wall and reads the diagonal edge it shares with the
	# slope at its length. Box UV takes the slope as its east wall and reads that
	# edge as only its height, so V has to stretch to meet it.
	var wedge := _brush("w", Vector3(8, 0, -8), Vector3(32, 32, 32), LevelRootType.BrushShape.WEDGE)
	var slope := Vector3(1, 1, 0)
	_dress(_face(wedge, Vector3.BACK), BOX)
	_face(wedge, slope).uv_projection = BOX

	var result := _wrap(wedge, Vector3.BACK, wedge, slope)

	assert_true(bool(result.get("ok", false)))
	assert_eq(int(result["adjusted"]), 1, "the V scale was changed")
	_assert_seamless(wedge, Vector3.BACK, wedge, slope, "Box UV slope")
	# Laid in its own plane the slope measures the edge as the wall does.
	_face(wedge, slope).uv_projection = FACE
	var own := _wrap(wedge, Vector3.BACK, wedge, slope)
	assert_eq(int(own["adjusted"]), -1, "on the Face projection nothing had to change")
	_assert_seamless(wedge, Vector3.BACK, wedge, slope, "Face projected slope")


func test_a_hand_layout_is_replaced_and_only_the_texture_changes():
	var box := _brush("b", Vector3.ZERO, Vector3(32, 32, 32))
	_dress(_face(box, Vector3.BACK), BOX)
	var target := _face(box, Vector3.RIGHT)
	target.ensure_custom_uvs()
	for i in target.custom_uvs.size():
		target.custom_uvs[i] += Vector2(0.37, -0.21)
	target.paint_layers.append(FaceData.PaintLayer.new())
	var corners := target.local_verts.duplicate()

	assert_true(bool(_wrap(box, Vector3.BACK, box, Vector3.RIGHT).get("ok", false)))

	target = _face(box, Vector3.RIGHT)
	assert_false(target.has_uv_layout(), "the hand layout gave way to the wrap")
	assert_eq(target.local_verts, corners, "no corner moved")
	assert_eq(target.paint_layers.size(), 1, "the paint stayed")


func test_a_cylindrical_target_is_wrapped_on_the_face_projection():
	var box := _brush("b", Vector3.ZERO, Vector3(32, 32, 32))
	_dress(_face(box, Vector3.BACK), BOX)
	_face(box, Vector3.RIGHT).uv_projection = FaceDataScript.UVProjection.CYLINDRICAL

	var result := _wrap(box, Vector3.BACK, box, Vector3.RIGHT)

	assert_true(bool(result.get("ok", false)))
	assert_eq(_face(box, Vector3.RIGHT).uv_projection, FACE, "a projection that lies flat on it")
	_assert_seamless(box, Vector3.BACK, box, Vector3.RIGHT, "a cylindrical side")
