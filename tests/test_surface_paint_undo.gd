extends GutTest

## A surface paint stroke is one undo step, and Alt takes paint off (#989).
##
## Ctrl+Z did not put a stroke's paint back: the only way to take a bad stroke
## off was to paint over it, and nothing painted at less than full. Each test
## drives strokes through the plugin's paint input, the way the viewport sends
## them, with the undo step landing in the stand-in `test_undo_collation.gd`
## uses. An `EditorUndoRedoManager` cannot be built outside the editor.

const CollationTests = preload("res://tests/test_undo_collation.gd")
const PaintInput = preload("res://addons/hammerforge/plugin_paint_input.gd")
const GestureRecovery = preload("res://addons/hammerforge/plugin_gesture_recovery.gd")


class FakeDock:
	extends RefCounted

	func get_paint_target() -> int:
		return 1

	func get_operation() -> int:
		return CSGShape3D.OPERATION_UNION

	func get_brush_size() -> Vector3:
		return Vector3.ONE

	func get_surface_paint_radius() -> float:
		return 0.1

	func get_surface_paint_strength() -> float:
		return 1.0

	func get_surface_paint_layer() -> int:
		return 0


class FakePlugin:
	extends RefCounted

	var dock = FakeDock.new()
	var undo_redo_manager = CollationTests.FakeUndoRedo.new()
	var history: Array = []
	var _disp_paint_active := false

	func _record_history(action_name: String) -> void:
		history.append(action_name)

	func _commit_floor_paint_undo(_root: Node) -> void:
		pass


var root: LevelRoot
var camera: Camera3D
var plugin: FakePlugin


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	var floor_info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(4, 1, 4),
		"center": Vector3(0, -0.5, 0),
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": "floor",
	}
	assert_not_null(root.create_brush_from_info(floor_info), "fixture: the floor")
	camera = Camera3D.new()
	add_child_autoqfree(camera)
	camera.global_position = Vector3(0, 10, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	plugin = FakePlugin.new()


func after_each() -> void:
	root = null
	camera = null
	plugin = null


func _send(event: InputEvent) -> void:
	PaintInput.handle_paint(plugin, event, root, camera, event.position)


func _press(point: Vector3, alt: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.alt_pressed = alt
	event.position = camera.unproject_position(point)
	_send(event)


func _drag(point: Vector3) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = camera.unproject_position(point)
	_send(event)


func _release(point: Vector3) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = camera.unproject_position(point)
	_send(event)


func _stroke(alt: bool = false) -> void:
	_press(Vector3(-1, 0, 0), alt)
	_drag(Vector3(0, 0, 0))
	_drag(Vector3(1, 0, 0))
	_release(Vector3(1, 0, 0))


## How much paint the floor's top face holds: the sum of its first layer.
func _paint() -> float:
	var brush = root.find_brush_by_id("floor")
	var hit: Dictionary = root.pick_face(camera, camera.unproject_position(Vector3.ZERO))
	assert_eq(hit.get("brush"), brush, "fixture: the camera sees the floor's top")
	var face: FaceData = brush.faces[int(hit.get("face_idx", -1))]
	if face.paint_layers.is_empty() or face.paint_layers[0].weight_image == null:
		return 0.0
	var image: Image = face.paint_layers[0].weight_image
	var total := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			total += image.get_pixel(x, y).r
	return total


func test_a_stroke_is_one_undo_step_that_takes_its_paint_back():
	_stroke()
	var painted := _paint()
	assert_gt(painted, 0.0, "the stroke painted the floor")
	var steps: Array = plugin.undo_redo_manager.entries
	assert_eq(steps.size(), 1, "a press, two drags and a release are one step")
	assert_eq(steps[0]["name"], "Surface Paint")
	assert_eq(plugin.history, ["Surface Paint"], "and the history names it")

	plugin.undo_redo_manager.undo()
	assert_eq(_paint(), 0.0, "undo puts the face back as it was")
	plugin.undo_redo_manager.redo()
	assert_almost_eq(_paint(), painted, 0.01, "redo puts the stroke back")


func test_alt_takes_paint_off_where_a_stroke_put_it():
	_stroke()
	var painted := _paint()
	_stroke(true)
	assert_lt(_paint(), painted * 0.5, "the same stroke with Alt takes the paint off")
	assert_eq(plugin.undo_redo_manager.entries.size(), 2, "each stroke is its own step")

	plugin.undo_redo_manager.undo()
	assert_almost_eq(_paint(), painted, 0.01, "undoing the erase puts the paint back")


func test_a_stroke_after_an_erase_paints_again():
	_stroke(true)
	_stroke()
	assert_gt(_paint(), 0.0, "Alt lasts one stroke, as it does in Floor Paint")


func test_a_stroke_that_misses_every_brush_is_no_step():
	_press(Vector3(40, 0, 0))
	_drag(Vector3(41, 0, 0))
	_release(Vector3(41, 0, 0))
	assert_eq(plugin.undo_redo_manager.entries.size(), 0, "nothing was painted")


func test_a_stroke_that_loses_its_release_still_gets_its_step():
	# Focus left the editor mid stroke, so the release never came. The recovery
	# that closes the stroke closes its undo step as well.
	_press(Vector3(-1, 0, 0))
	_drag(Vector3(0, 0, 0))
	var finished := GestureRecovery.finish_stale_paint_strokes(
		plugin, root, root.input_state, root.paint_tool
	)
	assert_true(finished, "the stroke was still open")
	assert_eq(plugin.undo_redo_manager.entries.size(), 1)
	plugin.undo_redo_manager.undo()
	assert_eq(_paint(), 0.0)
