extends GutTest
## The extrude ghost and the ids the tool mints.
##
## A preview is the one node the editor puts in the scene that is not part of the
## level, so the contract is about what it must not do: never be counted as a
## brush, never reach a state capture, never be offered as a snap target. And an
## id has to come from the session scheme, or two brushes end up sharing one.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot
var tool


func before_each() -> void:
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	tool = root.extrude_tool


func after_each() -> void:
	root = null
	tool = null


func _make_box(brush_id: String, position: Vector3, rotation_y: float = 0.0) -> DraftBrush:
	var brush := (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRootType.BrushShape.BOX,
					"size": Vector3(64, 64, 64),
					"center": position,
					"operation": CSGShape3D.OPERATION_UNION,
					"brush_id": brush_id,
				}
			)
		)
		as DraftBrush
	)
	assert_not_null(brush)
	if brush and rotation_y != 0.0:
		brush.rotation.y = rotation_y
	return brush


## Put the tool into a live extrusion on the top face of the given brush without
## going through the camera, which a headless test has none of.
func _begin_on_top_face(brush: DraftBrush, height: float) -> void:
	var face_idx := -1
	for i in range(brush.faces.size()):
		var face = brush.faces[i]
		face.ensure_geometry()
		if (brush.global_transform.basis * face.normal).normalized().dot(Vector3.UP) > 0.9:
			face_idx = i
			break
	assert_true(face_idx >= 0, "The box has a top face")
	var face = brush.faces[face_idx]
	tool.source_brush = brush
	tool.source_face_idx = face_idx
	tool.source_face_normal = (brush.global_transform.basis * face.normal).normalized()
	tool.source_face_center = tool._compute_face_center(brush, face)
	tool.source_face_size = tool._compute_face_extents(face)
	tool.direction = tool.Direction.UP
	tool.active = true
	tool._current_height = height
	tool._update_preview(height)


func test_the_ghost_is_not_a_brush_in_the_level() -> void:
	var brush := _make_box("box_a", Vector3.ZERO)
	var managed_before := root._iter_managed_brush_nodes().size()
	var pick_before := root._iter_pick_nodes().size()
	_begin_on_top_face(brush, 32.0)
	assert_not_null(tool._preview_brush, "There is a ghost")
	assert_eq(
		root._iter_managed_brush_nodes().size(),
		managed_before,
		"The ghost is not one of the level's brushes"
	)
	assert_eq(root._iter_pick_nodes().size(), pick_before, "and it is not a pick or snap candidate")
	var state: Dictionary = root.capture_state(true)
	assert_eq(state["brushes"].size(), managed_before, "and a state capture does not store it")
	tool.cancel_extrude()


func test_the_ghost_leaves_nothing_behind() -> void:
	var brush := _make_box("box_b", Vector3.ZERO)
	_begin_on_top_face(brush, 32.0)
	tool.cancel_extrude()
	assert_null(tool._preview_brush, "The ghost is gone")
	assert_null(root.get_node_or_null("ExtrudePreview"), "and so is its container")


func test_the_ghost_sits_on_the_face_being_extruded() -> void:
	# The transform used to be written before add_child, which both errors and
	# leaves the ghost at the origin.
	var brush := _make_box("box_c", Vector3(128, 0, 128), deg_to_rad(45.0))
	_begin_on_top_face(brush, 32.0)
	assert_not_null(tool._preview_brush)
	var expected: Vector3 = tool.source_face_center + Vector3.UP * 16.0
	assert_almost_eq(
		tool._preview_brush.global_position.x, expected.x, 0.01, "Ghost is on the face, not at 0"
	)
	assert_almost_eq(tool._preview_brush.global_position.y, expected.y, 0.01)
	assert_almost_eq(tool._preview_brush.global_position.z, expected.z, 0.01)
	assert_almost_eq(
		tool._preview_brush.global_transform.basis.get_euler().y,
		brush.global_transform.basis.get_euler().y,
		0.01,
		"and turned the way the source brush is"
	)
	tool.cancel_extrude()


func test_two_extrusions_in_one_frame_get_different_ids() -> void:
	# Ids used to be minted from the direction and the millisecond clock, so two
	# commits in the same millisecond claimed the same id.
	var brush := _make_box("box_d", Vector3.ZERO)
	_begin_on_top_face(brush, 32.0)
	var first: String = str(tool._build_brush_info(32.0)["brush_id"])
	var second: String = str(tool._build_brush_info(32.0)["brush_id"])
	assert_ne(first, "", "An extrusion gets an id")
	assert_ne(first, second, "and two of them do not share it")
	tool.cancel_extrude()


func test_an_extrusion_id_comes_from_the_session_scheme() -> void:
	var brush := _make_box("box_e", Vector3.ZERO)
	_begin_on_top_face(brush, 32.0)
	var counter_before: int = root._brush_id_counter
	var brush_id: String = str(tool._build_brush_info(32.0)["brush_id"])
	assert_false(brush_id.begins_with("extrude_"), "Not a scheme of its own")
	var parts := brush_id.split("_")
	assert_eq(parts.size(), 2, "A session prefix and a counter: %s" % brush_id)
	assert_true(parts[1].is_valid_int(), "and the counter is a number")
	assert_eq(
		root._brush_id_counter, counter_before + 1, "Minting one advances the level's id counter"
	)
	tool.cancel_extrude()
