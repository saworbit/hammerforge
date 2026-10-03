extends GutTest

## A cut keeps a sculpt only on a piece of its face with four corners. The
## confirmations for Clip, Carve and Hollow say beforehand when one will be
## dropped, rather than leaving the mapper to find the warning afterwards (#871).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFDisplacementData = preload("res://addons/hammerforge/displacement_data.gd")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")

var root: LevelRoot
var plugin: FakePlugin


## Just enough of the plugin for the three confirmations to be opened and read.
class FakePlugin:
	extends Node

	var dock = null
	var selection: Array = []
	var dialogs: Array = []

	func _current_selection_nodes() -> Array:
		return selection

	func _add_confirmable_dialog(dlg: ConfirmationDialog) -> void:
		dialogs.append(dlg)
		add_child(dlg)


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	plugin = FakePlugin.new()
	add_child_autofree(plugin)


func after_each():
	root = null
	plugin = null


func _box(
	brush_id: String, centre: Vector3, size: Vector3, turn: Basis = Basis.IDENTITY
) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRootType.BrushShape.BOX,
					"size": size,
					"transform": Transform3D(turn, centre),
					"brush_id": brush_id,
				}
			)
		)
		as DraftBrush
	)


func _sculpt(face: FaceData) -> void:
	var disp := HFDisplacementData.new()
	disp.init_flat(2)
	for row in disp.get_dim():
		for col in disp.get_dim():
			disp.set_distance(row, col, row + col * 0.5)
	face.displacement = disp


## The face of `brush` whose outward normal, in the brush's own frame, is `local`.
func _face_along(brush: DraftBrush, local: Vector3) -> FaceData:
	for face in brush.get_faces():
		face.ensure_geometry()
		if face.normal.dot(local) > 0.99:
			return face
	return null


func _dialog_text() -> String:
	assert_eq(plugin.dialogs.size(), 1, "one confirmation opened")
	return plugin.dialogs[0].dialog_text if plugin.dialogs.size() == 1 else ""


# -- The count --------------------------------------------------------------


## A box's sculpted top cut along a diagonal leaves two triangles. Cut straight
## across it leaves two quads. Only the first loses its sculpt.
func test_the_count_reads_corners_and_resamples_nothing():
	var brush := _box("b1", Vector3.ZERO, Vector3(32, 32, 32))
	var top := _face_along(brush, Vector3.UP)
	_sculpt(top)
	var heights: PackedFloat32Array = top.displacement.distances.duplicate()
	var faces: Array = brush.get_faces()
	var straight := HFConvexClip.split(faces, Plane(Vector3.RIGHT, 0.0))
	var diagonal := HFConvexClip.split(faces, Plane(Vector3(1, 0, 1).normalized(), 0.0))
	assert_false(diagonal["front"].is_empty(), "the diagonal cut makes two pieces")

	assert_eq(
		HFConvexClip.sculpts_a_cut_would_drop(
			[straight["front"], straight["back"]], straight["origins"]
		),
		0,
		"two quads keep the sculpt"
	)
	assert_eq(
		HFConvexClip.sculpts_a_cut_would_drop(
			[diagonal["front"], diagonal["back"]], diagonal["origins"]
		),
		1,
		"two triangles cannot"
	)
	for piece in diagonal["front"] + diagonal["back"]:
		assert_null(piece.displacement, "nothing was resampled onto a piece")
	assert_eq(top.displacement.distances, heights, "and the sculpt itself is untouched")


# -- The confirmations -------------------------------------------------------


## A box turned a quarter of a right angle about X has diamond sides, and Clip's
## horizontal cut through the middle splits each one into two triangles.
func test_clip_says_when_a_sculpt_will_be_dropped():
	var brush := _box("b1", Vector3.ZERO, Vector3(32, 32, 32), Basis(Vector3.RIGHT, PI / 4.0))
	_sculpt(_face_along(brush, Vector3.RIGHT))
	plugin.selection = [brush]

	HFPluginEditActions.clip_selected(plugin, root)

	assert_string_contains(_dialog_text(), "1 sculpt cannot follow this cut and will be dropped")


func test_clip_says_nothing_extra_when_every_sculpt_is_kept():
	var brush := _box("b1", Vector3.ZERO, Vector3(32, 32, 32))
	_sculpt(_face_along(brush, Vector3.RIGHT))
	_sculpt(_face_along(brush, Vector3.UP))
	plugin.selection = [brush]

	HFPluginEditActions.clip_selected(plugin, root)

	assert_false(_dialog_text().contains("sculpt"), "a straight cut keeps both")


## A carver turned an eighth of a turn about Y takes a corner off the top, and the
## piece of the top it leaves has five corners.
func test_carve_says_when_a_sculpt_will_be_dropped():
	var target := _box("t1", Vector3.ZERO, Vector3(64, 16, 64))
	_sculpt(_face_along(target, Vector3.UP))
	var carver := _box("c1", Vector3(32, 0, 32), Vector3(24, 32, 24), Basis(Vector3.UP, PI / 4.0))
	plugin.selection = [carver]

	HFPluginEditActions.carve_selected(plugin, root)

	assert_string_contains(_dialog_text(), "cannot follow this cut and will be dropped")


func test_carve_says_nothing_extra_when_every_sculpt_is_kept():
	var target := _box("t1", Vector3.ZERO, Vector3(64, 16, 64))
	_sculpt(_face_along(target, Vector3.UP))
	var carver := _box("c1", Vector3(32, 0, 32), Vector3(24, 32, 24))
	plugin.selection = [carver]

	HFPluginEditActions.carve_selected(plugin, root)

	assert_false(_dialog_text().contains("sculpt"), "every piece of the top is a quad")


func test_hollow_says_nothing_extra_when_every_sculpt_is_kept():
	var brush := _box("b1", Vector3.ZERO, Vector3(64, 64, 64))
	_sculpt(_face_along(brush, Vector3.UP))
	plugin.selection = [brush]

	HFPluginEditActions.hollow_selected(plugin, root)

	assert_false(
		_dialog_text().contains("sculpt"), "a box's walls keep their faces whole or square"
	)
