extends GutTest

## Run Trim Along Faces and Re-pick Trim Run, through the real plugin (#1414).
##
## The key, the palette, the Space menu and the Structure section all reach the
## same two commands. Each builds or re-picks in one undo step, and a refusal (no
## face picked, a sloped face, nothing selected to re-pick) builds nothing,
## leaves no step and says why.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFTrimRunBuilderScript = preload("res://addons/hammerforge/hf_trim_run_builder.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")

const CEILING := 9.0

var rig: PluginRig


func before_all():
	rig = PluginRig.new()
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()
	rig = null


# ===========================================================================
# Fixtures
# ===========================================================================


## A 10 m box hollowed into a room with 1 m walls.
func _room(level: Node) -> void:
	var solid = (
		level
		. create_brush_from_info(
			{
				"shape": level.BrushShape.BOX,
				"size": Vector3(10, 10, 10),
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)),
			}
		)
	)
	assert_true(level.hollow_brush_by_id(solid.brush_id, 1.0).ok)


## The upright faces facing into the room, as Face Select keeps them. `skip`
## leaves out that many walls.
func _inner_walls(level: Node, skip := 0) -> Dictionary:
	var picked := {}
	var left := skip
	for brush in level.draft_brushes_node.get_children():
		if brush.has_meta(HFGeneratorSystemScript.GENERATOR_META):
			continue
		for i in brush.get_faces().size():
			var ring := PackedVector3Array()
			for corner in brush.get_faces()[i].local_verts:
				ring.append(brush.global_transform * corner)
			var middle := (ring[0] + ring[2]) * 0.5
			var normal: Vector3 = brush.get_faces()[i].normal_through(brush.global_transform.basis)
			if absf(normal.y) > 0.01 or normal.dot(Vector3(-middle.x, 0, -middle.z)) <= 0.0:
				continue
			if absf(middle.x) > 4.01 or absf(middle.z) > 4.01:
				continue
			if left > 0:
				left -= 1
				continue
			picked[HFBrushSystem.face_key(brush)] = [i]
	return picked


func _trim_runs(level: Node) -> Array:
	var out: Array = []
	for record in level.generator_system.generators.values():
		if record.type == HFGeneratorSystemScript.TYPE_TRIM_RUN:
			out.append(record)
	return out


func _pieces(level: Node, generator_id: String) -> Array:
	var out: Array = []
	for brush in level.draft_brushes_node.get_children():
		if str(brush.get_meta(HFGeneratorSystemScript.GENERATOR_META, "")) == generator_id:
			out.append(brush)
	return out


func _said(text: String) -> bool:
	for toast in rig.toasts():
		if str(toast).contains(text):
			return true
	return false


func _select_type(type: String) -> void:
	var dock = rig.plugin.dock
	for index in dock.structure_type_option.item_count:
		if str(dock.structure_type_option.get_item_metadata(index)) == type:
			dock.structure_type_option.select(index)
			dock._on_structure_type_changed(index)
			return


# ===========================================================================
# Run Trim Along Faces
# ===========================================================================


func test_the_shortcut_builds_a_trim_run_along_the_picked_faces_in_one_step():
	var level = await rig.make_level()
	_room(level)
	level.face_selection = _inner_walls(level)
	var undo = rig.undo()
	undo.clear()
	var key := PluginRig.key_for("run_trim_along_faces")
	assert_eq(rig.forward(key), EditorPlugin.AFTER_GUI_INPUT_STOP, "the key is consumed")
	var runs := _trim_runs(level)
	assert_eq(runs.size(), 1, "a trim run was built")
	assert_eq(_pieces(level, runs[0].generator_id).size(), 4, "a piece per wall")
	assert_eq(undo.step_count(), 1, "in one undo step")
	undo.press_undo()
	assert_eq(_trim_runs(level).size(), 0, "Ctrl+Z takes it away")
	assert_eq(_pieces(level, runs[0].generator_id).size(), 0, "and its pieces")
	undo.press_redo()
	assert_eq(_trim_runs(level).size(), 1, "and Ctrl+Shift+Z puts it back")
	await rig.leave_level(level)


func test_it_builds_with_the_structure_sections_trim_run_settings():
	var level = await rig.make_level()
	_room(level)
	_select_type(HFGeneratorSystemScript.TYPE_TRIM_RUN)
	var dock = rig.plugin.dock
	(dock.structure_fields["edge"] as OptionButton).select(HFTrimRunBuilderScript.EDGE_TOP)
	level.face_selection = _inner_walls(level)
	# The section's own button, as the palette's Create Structure is.
	dock._on_create_structure()
	var runs := _trim_runs(level)
	assert_eq(runs.size(), 1, "Create Trim Run built one")
	assert_eq(int(runs[0].settings["edge"]), HFTrimRunBuilderScript.EDGE_TOP, "a cornice")
	var high := -INF
	for piece in _pieces(level, runs[0].generator_id):
		for face in piece.get_faces():
			for corner in face.local_verts:
				high = maxf(high, (piece.global_transform * corner).y)
	assert_almost_eq(high, CEILING, 0.001, "under the ceiling")
	assert_true(dock.structure_repick_btn.visible, "Re-pick sits beside the button")
	_select_type("arch")
	assert_false(dock.structure_repick_btn.visible, "and only for a type built along faces")
	await rig.leave_level(level)


func test_with_no_faces_picked_it_says_so_and_builds_nothing():
	var level = await rig.make_level()
	_room(level)
	var undo = rig.undo()
	undo.clear()
	rig.plugin._dispatch_viewport_action("run_trim_along_faces", [])
	await rig.frame()
	assert_eq(_trim_runs(level).size(), 0)
	assert_eq(undo.step_count(), 0, "no step")
	assert_true(_said("pick the wall faces first"), "and says what to do")
	await rig.leave_level(level)


func test_a_sloped_face_is_refused_and_leaves_no_step():
	var level = await rig.make_level()
	_room(level)
	var ramp = (
		level
		. create_brush_from_info(
			{
				"shape": level.BrushShape.BOX,
				"size": Vector3(2, 0.5, 3),
				"transform": Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 2, 0)),
			}
		)
	)
	var picked := _inner_walls(level)
	for i in ramp.get_faces().size():
		if ramp.get_faces()[i].normal_through(ramp.global_transform.basis).y > 0.5:
			picked[HFBrushSystem.face_key(ramp)] = [i]
	level.face_selection = picked
	var undo = rig.undo()
	undo.clear()
	rig.forward(PluginRig.key_for("run_trim_along_faces"))
	await rig.frame()
	assert_eq(_trim_runs(level).size(), 0, "nothing built")
	assert_eq(undo.step_count(), 0, "no step")
	assert_true(_said("is not upright"), "and the face is named")
	await rig.leave_level(level)


# ===========================================================================
# Re-pick
# ===========================================================================


func test_repick_takes_the_run_selected_on_the_way_into_face_select():
	var level = await rig.make_level()
	_room(level)
	level.face_selection = _inner_walls(level, 1)
	rig.plugin._dispatch_viewport_action("run_trim_along_faces", [])
	var runs := _trim_runs(level)
	assert_eq(runs.size(), 1)
	var generator_id: String = runs[0].generator_id
	assert_eq(_pieces(level, generator_id).size(), 3, "three walls")

	# Select a piece, open Face Select, which hides it, and pick all four walls.
	level.clear_face_selection()
	rig.select([_pieces(level, generator_id)[0]])
	await rig.frame()
	rig.plugin.dock.face_select_mode.button_pressed = true
	await rig.frame()
	level.face_selection = _inner_walls(level)
	var state := HFPluginOverlays.build_viewport_state(rig.plugin, level, 0)
	assert_true(state.get("repick_trim_run", false), "the Space menu offers Re-pick")
	var menu = rig.plugin._viewport_context_menu
	menu.show_at(Vector2.ZERO, state)
	var labels: Array = []
	for i in menu.item_count:
		labels.append(menu.get_item_text(i))
	menu.hide()
	assert_has(labels, "Run Trim Along Faces")
	assert_has(labels, "Re-pick Trim Run")

	var undo = rig.undo()
	undo.clear()
	rig.plugin._dispatch_viewport_action("repick_trim_run", [])
	assert_eq(_trim_runs(level).size(), 1, "still one trim run")
	assert_eq(_pieces(level, generator_id).size(), 4, "along all four walls now")
	assert_eq(undo.step_count(), 1, "in one step")

	# The same faces again would put back what is there.
	undo.clear()
	rig.plugin._dispatch_viewport_action("repick_trim_run", [])
	assert_eq(undo.step_count(), 0, "so it records nothing")
	assert_true(_said("Nothing to re-pick"))
	rig.plugin.dock.face_select_mode.button_pressed = false
	await rig.leave_level(level)


func test_repick_with_nothing_selected_says_what_it_needs():
	var level = await rig.make_level()
	_room(level)
	level.face_selection = _inner_walls(level)
	var undo = rig.undo()
	undo.clear()
	rig.plugin._dispatch_viewport_action("repick_trim_run", [])
	assert_eq(undo.step_count(), 0)
	assert_true(_said("select a piece of the trim run"))
	await rig.leave_level(level)


func test_an_update_from_the_section_keeps_the_run():
	var level = await rig.make_level()
	_room(level)
	level.face_selection = _inner_walls(level)
	rig.plugin._dispatch_viewport_action("run_trim_along_faces", [])
	var record = _trim_runs(level)[0]
	var run: Dictionary = record.run.duplicate(true)
	level.clear_face_selection()
	rig.select([_pieces(level, record.generator_id)[0]])
	await rig.frame()
	var dock = rig.plugin.dock
	assert_eq(dock.structure_create_btn.text, "Update Trim Run", "the section edits it")
	(dock.structure_fields["profile"] as OptionButton).select(1)
	dock._on_create_structure()
	var rebuilt = level.generator_for_id(record.generator_id)
	assert_eq(int(rebuilt.settings["profile"]), 1, "with the new profile")
	assert_true(HFTrimRunBuilderScript.same_run(rebuilt.run, run), "along the same run")
	await rig.leave_level(level)
