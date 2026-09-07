extends GutTest
## The in-progress preview brush must never be a pick target.
##
## `update_drag` places the drag point with `root._raycast`, which falls back to
## `pick_face_from_ray` when nothing has a physics body — and draft brushes never
## do. The preview brush is parented under `draft_brushes_node` the moment a drag
## starts and stands a full grid step tall, so a ray aimed near the corner the
## user is dragging hits the preview's own top face instead of the construction
## plane. The hit sits closer to the camera, the box shrinks away from the
## cursor, the next ray misses it, and the box grows back: one edge oscillating
## every frame the mouse moves. The snap system already excludes the preview for
## the same reason; picking did not.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot
var camera: Camera3D


func before_each() -> void:
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	camera = Camera3D.new()
	add_child_autoqfree(camera)
	# A raised, tilted view is the ordinary building camera, and it is the angle
	# that gives a preview's top face any screen area to steal the ray with.
	camera.global_position = Vector3(0, 12, 12)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func after_each() -> void:
	root = null
	camera = null


func _preview_box(center: Vector3, size: Vector3) -> DraftBrush:
	var brush := DraftBrush.new()
	brush.name = "PreviewBrush"
	brush.shape = LevelRootType.BrushShape.BOX
	brush.size = size
	root.draft_brushes_node.add_child(brush)
	brush.global_position = center
	root.preview_brush = brush
	return brush


# --- the pick chokepoint -------------------------------------------------


func test_face_pick_ignores_the_preview_brush() -> void:
	var preview := _preview_box(Vector3(0, 1, 0), Vector3(4, 2, 4))
	assert_not_null(preview)
	var hit := root.brush_system.pick_face_from_ray(Vector3(0, 8, 0), Vector3(0, -1, 0))
	assert_true(
		hit.is_empty(), "A ray straight down the preview's top face must not pick the preview"
	)


func test_face_pick_still_sees_a_committed_brush_behind_the_preview() -> void:
	var real := (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRootType.BrushShape.BOX,
					"size": Vector3(4, 2, 4),
					"center": Vector3(0, -3, 0),
					"operation": CSGShape3D.OPERATION_UNION,
					"brush_id": "committed",
				}
			)
		)
		as DraftBrush
	)
	_preview_box(Vector3(0, 1, 0), Vector3(4, 2, 4))
	var hit := root.brush_system.pick_face_from_ray(Vector3(0, 8, 0), Vector3(0, -1, 0))
	assert_same(hit.get("brush"), real, "Excluding the preview must not hide real geometry")


func test_raycast_falls_through_the_preview_to_the_construction_plane() -> void:
	_preview_box(Vector3(0, 1, 0), Vector3(4, 2, 4))
	var hit := root._raycast(camera, _screen_point_for(Vector3(0, 0, 0)))
	assert_false(hit.is_empty())
	var pos: Vector3 = hit.get("position", Vector3.ONE * 999.0)
	assert_almost_eq(pos.y, 0.0, 0.001, "The drag point belongs on the plane, not on the preview")


func _screen_point_for(world: Vector3) -> Vector2:
	return camera.unproject_position(world)


# --- the symptom the user sees -------------------------------------------


func test_repeated_drag_updates_at_one_position_do_not_oscillate() -> void:
	# Dragging *away* from the camera is what puts the growing box between the
	# eye and the corner under the cursor, so the ray meets the preview's roof
	# before it ever reaches the construction plane. Drag towards the camera and
	# nothing is in the way — which is why this only bites sometimes.
	root.grid_snap = 0.5
	var drag = root.drag_system
	var near_corner := _screen_point_for(Vector3(4, 0, 4))
	assert_true(
		drag.begin_drag(camera, near_corner, CSGShape3D.OPERATION_UNION, Vector3(2, 2, 2), 0),
		"The drag has to start for the rest of this to mean anything"
	)
	var far_corner := _screen_point_for(Vector3(-4, 0, -4))
	var sizes: Array = []
	for i in range(6):
		drag.update_drag(camera, far_corner)
		sizes.append(root.preview_brush.size)
	gut.p("observed preview sizes: %s" % str(sizes))
	for i in range(1, sizes.size()):
		assert_eq(
			sizes[i], sizes[0], "A still cursor must give one answer. Sizes seen: %s" % str(sizes)
		)
