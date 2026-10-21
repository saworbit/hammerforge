extends GutTest

## Paint > UV Editor's x2 and /2 buttons and the link between the U and V scale
## boxes (#1418).
##
## The boxes edit the one face on show, so doubling a texture took two typed
## numbers, and on a run of selected faces it took them face by face. x2 and /2
## act on every face in the face selection as one undo step, keep each axis's
## sign, and stop at the boxes' range rather than reach zero. With the link on,
## typing one box sets the other to the same size, and the link is kept in the
## user prefs.
##
## Each test drives the real dock and its real handlers against a real level.
## Only where the undo step lands is swapped for the stand-in in
## `test_undo_collation.gd`: an `EditorUndoRedoManager` cannot be built outside
## the editor.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const CollationTests = preload("res://tests/test_undo_collation.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")


## The stand-in, answering the two calls the dock's history list makes of the
## editor's manager. With no scene history the list counts its own entries.
class DockUndo:
	extends CollationTests.FakeUndoRedo

	func get_object_history_id(_object: Object) -> int:
		return 0

	func get_history_undo_redo(_id: int) -> UndoRedo:
		return null


var root: LevelRoot
var dock: Node
var prefs: HFUserPrefs
var undo


func before_each():
	HFUndoHelper._reset_collation()
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	prefs = _quiet_prefs()
	dock = _make_dock(prefs)
	undo = DockUndo.new()
	dock.undo_redo = undo


func after_each():
	HFUndoHelper._reset_collation()
	dock = null
	root = null
	prefs = null
	undo = null


## Preferences that never reach the user's own file.
func _quiet_prefs() -> HFUserPrefs:
	var quiet := HFUserPrefsType.new()
	quiet.persistence_enabled = false
	quiet.data = HFUserPrefsType._defaults()
	quiet.data["show_welcome"] = false
	return quiet


func _make_dock(with_prefs: HFUserPrefs) -> Node:
	var made = DockScene.instantiate()
	add_child_autoqfree(made)
	made.set_user_prefs(with_prefs)
	made.level_root = root
	made.connected_root = root
	made._connect_root_signals()
	return made


## What a restart reads back: the prefs written out as JSON and loaded through
## the schema, without the file.
func _restarted(written: HFUserPrefs) -> HFUserPrefs:
	var reread := HFUserPrefsType.new()
	reread.persistence_enabled = false
	reread.data = HFUserPrefsType._validated(JSON.parse_string(JSON.stringify(written.data)))
	return reread


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"size": Vector3(2, 2, 2), "brush_id": brush_id, "transform": Transform3D()}
		)
		as DraftBrush
	)


func _face(brush_id: String) -> FaceData:
	var brush: DraftBrush = root.brush_system.find_brush_by_id(brush_id)
	return brush.faces[0]


## Two faces selected, each on its own brush, at the scales given. The first is the
## one on show in the UV editor, which gives it a layout of its own; the second
## has none and draws from its projection.
func _two_faces(scale_a: Vector2, scale_b: Vector2) -> void:
	_box("a")
	_box("b")
	root.set_face_uv_params("a", 0, scale_a, Vector2(0.25, 0.5), 0.0)
	root.set_face_uv_params("b", 0, scale_b, Vector2.ZERO, 0.0)
	_face("b").custom_uvs = PackedVector2Array()
	root.toggle_face_selection(root.brush_system.find_brush_by_id("a"), 0, false)
	root.toggle_face_selection(root.brush_system.find_brush_by_id("b"), 0, true)


func _assert_draws_from_its_scale(face: FaceData, message: String) -> void:
	var projected: PackedVector2Array = face._project_uvs_for_vertices(face.local_verts)
	var shown := face.shown_uvs()
	for i in projected.size():
		assert_almost_eq(shown[i].x, projected[i].x, 0.0001, "%s: u of corner %d" % [message, i])
		assert_almost_eq(shown[i].y, projected[i].y, 0.0001, "%s: v of corner %d" % [message, i])


func test_x2_and_halve_change_every_selected_face_as_one_step():
	_two_faces(Vector2(1, 1), Vector2(0.5, 2))
	assert_true(_face("a").has_uv_layout(), "the face on show has a layout")
	assert_false(_face("b").has_uv_layout(), "the other draws from its projection")
	var steps: int = undo.entries.size()

	dock.uv_scale_up_btn.pressed.emit()

	assert_eq(_face("a").uv_scale, Vector2(2, 2))
	assert_eq(_face("b").uv_scale, Vector2(1, 4))
	assert_eq(_face("a").uv_offset, Vector2(0.25, 0.5), "x2 keeps the offset, as typing does")
	_assert_draws_from_its_scale(_face("a"), "the layout moved with the scale")
	assert_false(_face("b").has_uv_layout(), "x2 gives no face a layout")
	assert_eq(undo.entries.size(), steps + 1, "both faces are one step")
	assert_eq(undo.entries[-1]["name"], "UV Scale x2")
	assert_eq(dock.uv_scale_x.value, 2.0, "the boxes follow the face on show")

	undo.undo()
	assert_eq(_face("a").uv_scale, Vector2(1, 1), "one undo takes both back")
	assert_eq(_face("b").uv_scale, Vector2(0.5, 2))

	undo.redo()
	steps = undo.entries.size()
	dock.uv_scale_down_btn.pressed.emit()
	assert_eq(_face("a").uv_scale, Vector2(1, 1))
	assert_eq(_face("b").uv_scale, Vector2(0.5, 2))
	assert_eq(undo.entries.size(), steps + 1)
	assert_eq(undo.entries[-1]["name"], "UV Scale /2")
	await get_tree().process_frame


func test_each_axis_keeps_its_sign():
	_two_faces(Vector2(-1, 2), Vector2(4, -0.5))

	dock.uv_scale_up_btn.pressed.emit()
	assert_eq(_face("a").uv_scale, Vector2(-2, 4), "a mirrored U stays mirrored")
	assert_eq(_face("b").uv_scale, Vector2(8, -1), "a mirrored V stays mirrored")

	dock.uv_scale_down_btn.pressed.emit()
	dock.uv_scale_down_btn.pressed.emit()
	assert_eq(_face("a").uv_scale, Vector2(-0.5, 1))
	assert_eq(_face("b").uv_scale, Vector2(2, -0.25))
	_assert_draws_from_its_scale(_face("a"), "a mirrored layout")


func test_halve_stops_at_the_smallest_step_and_never_writes_zero():
	_two_faces(Vector2(0.01, -0.01), Vector2(0.015, 1))
	var steps: int = undo.entries.size()

	dock.uv_scale_down_btn.pressed.emit()
	var a := _face("a").uv_scale
	var b := _face("b").uv_scale
	assert_almost_eq(a.x, 0.01, 0.00001, "already at the smallest step, it stays there")
	assert_almost_eq(a.y, -0.01, 0.00001)
	assert_almost_eq(b.x, 0.01, 0.00001, "halving past the step stops at it")
	assert_almost_eq(b.y, 0.5, 0.00001)
	assert_eq(undo.entries.size(), steps + 1)

	steps = undo.entries.size()
	for _i in 4:
		dock.uv_scale_down_btn.pressed.emit()
	assert_ne(_face("b").uv_scale.y, 0.0, "never zero")
	assert_almost_eq(_face("b").uv_scale.y, 0.03125, 0.00001)
	assert_almost_eq(_face("a").uv_scale.x, 0.01, 0.00001)

	# Both now at the step on every axis but one, which halves to it as well.
	dock.uv_scale_down_btn.pressed.emit()
	dock.uv_scale_down_btn.pressed.emit()
	var stuck: int = undo.entries.size()
	dock.uv_scale_down_btn.pressed.emit()
	assert_eq(undo.entries.size(), stuck, "a press that changes nothing leaves no step")
	for face in [_face("a"), _face("b")]:
		assert_false(is_zero_approx(face.uv_scale.x) or is_zero_approx(face.uv_scale.y))


func test_x2_stops_at_the_largest_scale_the_boxes_hold():
	_two_faces(Vector2(64, 1), Vector2(100, -100))
	dock.uv_scale_up_btn.pressed.emit()
	assert_eq(_face("a").uv_scale, Vector2(100, 2))
	assert_eq(_face("b").uv_scale, Vector2(100, -100))
	assert_eq(dock.uv_scale_x.max_value, HFBrushSystem.UV_SCALE_LIMIT, "the limit is the box's")
	assert_eq(dock.uv_scale_x.step, HFBrushSystem.UV_SCALE_STEP, "and the step is the box's")


## The brush system on its own, with no dock: the level command the buttons run.
func test_the_level_command_changes_the_whole_face_selection():
	_two_faces(Vector2(1, 1), Vector2(-2, 3))
	root.edit_selected_face_uvs("scale_up")
	assert_eq(_face("a").uv_scale, Vector2(2, 2))
	assert_eq(_face("b").uv_scale, Vector2(-4, 6))
	root.clear_face_selection()
	root.edit_selected_face_uvs("scale_down")
	assert_eq(_face("a").uv_scale, Vector2(2, 2), "no selection, no change")


func test_with_the_link_on_typing_one_box_sets_the_other_to_the_same_size():
	_two_faces(Vector2(1, -2), Vector2(1, 1))
	dock.uv_scale_link.button_pressed = true

	dock.uv_scale_x.value = 3.0
	assert_eq(_face("a").uv_scale, Vector2(3, -3), "V takes U's size and keeps its own sign")
	assert_eq(dock.uv_scale_y.value, -3.0, "and its box shows it")

	dock.uv_scale_y.value = 0.5
	assert_eq(_face("a").uv_scale, Vector2(0.5, 0.5), "and the other way round")
	assert_eq(dock.uv_scale_x.value, 0.5)

	dock.uv_scale_x.value = -4.0
	assert_eq(_face("a").uv_scale, Vector2(-4, 4), "each keeps its own sign")

	dock.uv_scale_link.button_pressed = false
	dock.uv_scale_x.value = 2.0
	assert_eq(_face("a").uv_scale, Vector2(2, 4), "unlinked, V is left alone")
	assert_eq(_face("b").uv_scale, Vector2(1, 1), "the boxes reach only the face on show")


## The other boxes are what the face holds, not what they round it to: /2 makes
## a scale of 0.125, which a box with a step of 0.01 shows as 0.13.
func test_typing_one_box_leaves_what_the_others_cannot_show():
	_two_faces(Vector2(0.25, 1), Vector2(1, 1))
	dock.uv_scale_down_btn.pressed.emit()
	assert_eq(_face("a").uv_scale, Vector2(0.125, 0.5))

	dock.uv_offset_x.value = 2.0
	assert_eq(_face("a").uv_offset.x, 2.0)
	assert_eq(_face("a").uv_scale, Vector2(0.125, 0.5), "the offset did not round the scale")


func test_the_link_survives_a_restart():
	assert_false(dock.uv_scale_link.button_pressed, "off by default")
	dock.uv_scale_link.button_pressed = true
	assert_eq(prefs.get_pref("uv_scale_linked"), true, "the toggle is written to the prefs")

	var next_dock := _make_dock(_restarted(prefs))
	assert_true(next_dock.uv_scale_link.button_pressed, "and read back after a restart")

	var bad := HFUserPrefsType._validated({"uv_scale_linked": "yes"})
	assert_eq(bad["uv_scale_linked"], false, "a value that is not a switch falls back to off")
