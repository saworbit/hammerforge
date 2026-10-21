extends GutTest

## New brushes are made with the level's Active Material (#1405).
##
## The Build tab's Active Material reached a dropped preset and a Paint-mode click
## and nothing else. A drawn box, a Polygon brush, a Path and every piece of a new
## structure came out translucent, so each had to be painted afterwards. The pick
## lived on the dock, so it was gone after a restart, and once picked nothing could
## clear it. It is the level's now, saved with the scene, and every tool that makes
## a brush from nothing asks it.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const BrushPresetScript = preload("res://addons/hammerforge/brush_preset.gd")
const HFPolygonToolScript = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const HFPathToolScript = preload("res://addons/hammerforge/hf_path_tool.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

const BRICK_PATH := "user://hf_active_material_brick.tres"
const STONE_PATH := "user://hf_active_material_stone.tres"
const PRESET_PATH := "user://hf_active_material_preset.tres"
const SCENE_PATH := "user://hf_active_material_scene.tscn"
## Box faces are stored +X, -X, +Y, -Y, +Z, -Z.
const TOP := 2
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()
var brick: Material = null
var stone: Material = null


func before_all():
	await rig.bring_up(self, true)
	brick = _saved_material(BRICK_PATH, Color(0.6, 0.25, 0.1))
	stone = _saved_material(STONE_PATH, Color(0.5, 0.5, 0.5))


func after_all():
	brick = null
	stone = null
	await rig.take_down()
	for path in [BRICK_PATH, STONE_PATH, PRESET_PATH, SCENE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## A material on disk, as the Active Material button picks one.
func _saved_material(path: String, color: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	assert_eq(ResourceSaver.save(mat, path), OK)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Material


func _brushes(level) -> Array:
	return level._iter_managed_brush_nodes()


func _made_since(level, before: Array) -> Array:
	var out: Array = []
	for brush in _brushes(level):
		if not before.has(brush):
			out.append(brush)
	return out


## Draw a box through the plugin as a mapper does: press, drag the base, let go,
## raise it, click, on open ground around `at`. The brush the draw made, or null.
func _draw(level, subtract := false, at := Vector3.ZERO) -> Node:
	var dock = rig.plugin.dock
	dock.tool_draw.button_pressed = true
	dock.mode_add.button_pressed = not subtract
	dock.mode_subtract.button_pressed = subtract
	var before := _brushes(level)
	var a := rig.camera.unproject_position(at + Vector3(-2, 0, -2))
	var b := rig.camera.unproject_position(at + Vector3(2, 0, 2))
	var up := b - Vector2(0, 40)
	rig.forward(PluginRig.motion(a))
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, a)), STOP, "the draw starts")
	rig.forward(PluginRig.motion(b, MOUSE_BUTTON_MASK_LEFT))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, b))
	rig.forward(PluginRig.motion(up))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, up))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, up))
	dock.mode_subtract.button_pressed = false
	dock.mode_add.button_pressed = true
	var made := _made_since(level, before)
	assert_eq(made.size(), 1, "the draw made one brush")
	return made[0] if made.size() == 1 else null


func _undo_then_redo(level, ids: Array) -> void:
	assert_true(rig.undo().press_undo(), "the step undoes")
	for brush_id in ids:
		assert_null(level.find_brush_by_id(str(brush_id)), "undo takes %s away" % brush_id)
	assert_true(rig.undo().press_redo(), "and redoes")


func _ids(brushes: Array) -> Array:
	var out: Array = []
	for brush in brushes:
		out.append(str(brush.brush_id))
	return out


# ===========================================================================
# Draw
# ===========================================================================


func test_the_draw_commit_info_names_the_active_material():
	var level = await rig.make_level()
	level.active_material = brick
	assert_true(level.begin_drag(rig.camera, Vector2(400, 300), 0, Vector3(2, 2, 2), 0))
	level.input_state.advance_to_height(Vector2(400, 300))
	var result: Dictionary = level.end_drag_info(rig.camera, Vector2(400, 260), Vector3(2, 2, 2))
	assert_true(result.get("placed", false))
	assert_eq(result["info"].get("material"), brick, "the info the undo step keeps holds it")
	await rig.leave_level(level)


func test_a_drawn_box_is_made_with_the_active_material_and_keeps_it_through_undo():
	var level = await rig.make_level()
	level.active_material = brick
	var brush = _draw(level)
	assert_eq(brush.material_override, brick, "the drawn box carries the Active Material")
	var brush_id := str(brush.brush_id)

	_undo_then_redo(level, [brush_id])

	var back = level.find_brush_by_id(brush_id)
	assert_not_null(back, "redo puts the box back")
	assert_eq(back.material_override, brick, "with the material it was drawn with")
	await rig.leave_level(level)


func test_with_no_active_material_a_drawn_box_looks_as_it_always_did():
	var level = await rig.make_level()
	var brush = _draw(level)
	assert_null(brush.material_override, "the translucent default")
	await rig.leave_level(level)


func test_a_drawn_cutout_keeps_the_cut_look():
	var level = await rig.make_level()
	level.active_material = brick
	var info: Dictionary = level.drag_system._build_brush_info(
		Vector3.ZERO,
		Vector3(2, 0, 2),
		2.0,
		0,
		Vector3(2, 2, 2),
		CSGShape3D.OPERATION_SUBTRACTION,
		false,
		false
	)
	assert_false(info.has("material"), "a cut's info carries no material")
	var cut = _draw(level, true)
	assert_eq(cut.operation, CSGShape3D.OPERATION_SUBTRACTION)
	assert_null(cut.material_override, "and the cut keeps its own look")
	await rig.leave_level(level)


# ===========================================================================
# Polygon and Path
# ===========================================================================


func test_a_polygon_brush_is_made_with_the_active_material_and_keeps_it_through_undo():
	var level = await rig.make_level()
	level.active_material = brick
	var tool = HFPolygonToolScript.new()
	tool.root = level
	tool.undo_redo = rig.undo()
	tool._polygon_points = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	)
	tool._ground_y = 0.0
	tool._height = 2.0
	var before := _brushes(level)
	tool._finalize_brush()
	var made := _made_since(level, before)
	assert_eq(made.size(), 1, "the polygon made one brush")
	assert_eq(made[0].material_override, brick, "with the Active Material")

	_undo_then_redo(level, _ids(made))

	var back = level.find_brush_by_id(str(made[0].brush_id))
	assert_not_null(back)
	assert_eq(back.material_override, brick, "redo keeps it")
	await rig.leave_level(level)


func test_every_piece_of_a_path_is_made_with_the_active_material_and_keeps_it_through_undo():
	var level = await rig.make_level()
	level.active_material = brick
	var tool = HFPathToolScript.new()
	tool.root = level
	tool.undo_redo = rig.undo()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 8)])
	var before := _brushes(level)
	tool._build_path()
	var made := _made_since(level, before)
	assert_gt(made.size(), 2, "two segments and the joint between them")
	for brush in made:
		assert_eq(brush.material_override, brick, "%s carries it" % brush.name)

	_undo_then_redo(level, _ids(made))

	for brush_id in _ids(made):
		var back = level.find_brush_by_id(brush_id)
		assert_not_null(back)
		assert_eq(back.material_override, brick, "redo keeps it on %s" % brush_id)
	await rig.leave_level(level)


# ===========================================================================
# Structures
# ===========================================================================


func _choose_stairs(dock) -> void:
	for index in dock.structure_type_option.item_count:
		if str(dock.structure_type_option.get_item_metadata(index)) == "stairs":
			dock.structure_type_option.selected = index
			break
	HFDockBrushHandler.rebuild_structure_fields(dock)


func _pieces(level) -> Array:
	var out: Array = []
	for generator_id in level.generator_system.generators:
		for brush_id in level.generator_system.generators[generator_id].brush_ids:
			var brush = level.find_brush_by_id(str(brush_id))
			if brush:
				out.append(brush)
	return out


func _create_stairs(level, steps := 0) -> Array:
	var dock = rig.plugin.dock
	dock.set_selection_nodes([])
	_choose_stairs(dock)
	if steps > 0:
		dock.structure_fields["steps"].set_value_no_signal(steps)
	dock._on_create_structure()
	assert_eq(level.generator_count(), 1, "the stairs were built")
	return _pieces(level)


func test_every_piece_of_new_stairs_is_made_with_the_active_material():
	var level = await rig.make_level()
	level.active_material = brick
	var pieces := _create_stairs(level)
	assert_gt(pieces.size(), 1, "a flight of several steps")
	for piece in pieces:
		assert_eq(piece.material_override, brick, "%s carries it" % piece.name)

	_undo_then_redo(level, _ids(pieces))

	var back := _pieces(level)
	assert_eq(back.size(), pieces.size(), "redo puts every step back")
	for piece in back:
		assert_eq(piece.material_override, brick, "and keeps it on %s" % piece.name)
	await rig.leave_level(level)


func _update_setting(level, key: String, value: float) -> void:
	var dock = rig.plugin.dock
	dock.set_selection_nodes([_pieces(level)[0]])
	assert_ne(str(dock._active_generator_id), "", "selecting a step switches to Update")
	dock.structure_fields[key].set_value_no_signal(value)
	dock._on_update_structure()


func test_an_update_keeps_each_piece_as_it_was_rather_than_taking_the_active_material():
	# Built with brick, then the Active Material moves to stone. An Update rebuilds
	# the steps; each keeps the brick it had.
	var level = await rig.make_level()
	level.active_material = brick
	var count := _create_stairs(level).size()
	level.active_material = stone
	_update_setting(level, "width", 3.0)
	var pieces := _pieces(level)
	assert_eq(pieces.size(), count)
	for piece in pieces:
		assert_eq(piece.material_override, brick, "%s keeps its own material" % piece.name)
	await rig.leave_level(level)


func test_an_update_leaves_steps_built_with_no_material_translucent():
	var level = await rig.make_level()
	_create_stairs(level)
	level.active_material = stone
	_update_setting(level, "width", 3.0)
	for piece in _pieces(level):
		assert_null(piece.material_override, "%s keeps the default it was built with" % piece.name)
	await rig.leave_level(level)


func test_steps_an_update_adds_take_the_material_the_steps_share():
	# Four brick steps taken to six came back as four brick and two translucent
	# (#1526). The new ones take the flight's brick, not the Active Material.
	var level = await rig.make_level()
	level.active_material = brick
	assert_eq(_create_stairs(level, 4).size(), 4, "a flight of four")
	level.active_material = stone
	_update_setting(level, "steps", 6)
	var pieces := _pieces(level)
	assert_eq(pieces.size(), 6, "the Update added two steps")
	for piece in pieces:
		assert_eq(piece.material_override, brick, "%s is brick" % piece.name)
	await rig.leave_level(level)


# ===========================================================================
# A dropped preset, an Extrude
# ===========================================================================


func _drop_preset(level, operation: int) -> Node:
	var preset := BrushPresetScript.new()
	preset.size = Vector3(4, 2, 4)
	preset.operation = operation
	assert_eq(ResourceSaver.save(preset, PRESET_PATH), OK)
	var before := _brushes(level)
	var aim := rig.camera.unproject_position(Vector3.ZERO)
	rig.forward(PluginRig.motion(aim))
	rig.plugin._drop_data(aim, {"type": "hammerforge_brush_preset", "preset_path": PRESET_PATH})
	var made := _made_since(level, before)
	assert_eq(made.size(), 1, "the drop placed one brush")
	return made[0] if made.size() == 1 else null


func test_a_dropped_preset_is_made_with_the_active_material_and_keeps_it_through_undo():
	var level = await rig.make_level()
	level.active_material = brick
	var brush = _drop_preset(level, CSGShape3D.OPERATION_UNION)
	assert_eq(brush.material_override, brick)
	var brush_id := str(brush.brush_id)

	_undo_then_redo(level, [brush_id])

	assert_eq(level.find_brush_by_id(brush_id).material_override, brick, "redo keeps it")
	await rig.leave_level(level)


func test_a_dropped_cutout_preset_keeps_the_cut_look():
	var level = await rig.make_level()
	level.active_material = brick
	var cut = _drop_preset(level, CSGShape3D.OPERATION_SUBTRACTION)
	assert_null(cut.material_override)
	await rig.leave_level(level)


func test_an_extrude_copies_its_source_and_never_the_active_material():
	var level = await rig.make_level()
	level.active_material = brick
	rig.box(level, "plain", Vector3.ZERO)
	var painted = rig.box(level, "painted", Vector3(10, 0, 0))
	painted.material_override = stone

	var plain_info: Dictionary = level.extrude_face_info("plain", TOP, 2.0)
	assert_false(plain_info.has("material"), "a plain source gives its extrusion nothing")
	var before := _brushes(level)
	rig.plugin._commit_brush_placement(level, plain_info)
	var made := _made_since(level, before)
	assert_eq(made.size(), 1)
	assert_null(made[0].material_override, "and the plugin's commit adds nothing either")

	var painted_info: Dictionary = level.extrude_face_info("painted", TOP, 2.0)
	assert_eq(painted_info.get("material"), stone, "a painted source gives its own")
	await rig.leave_level(level)


# ===========================================================================
# The dock: picking, clearing, a scene switch
# ===========================================================================


func test_picking_writes_the_level_and_clearing_brings_back_the_default_for_new_brushes():
	var level = await rig.make_level()
	var dock = rig.plugin.dock
	assert_true(dock.clear_active_material_button.disabled, "nothing to clear yet")

	dock._on_material_file_selected(BRICK_PATH)

	assert_eq(level.active_material, brick, "the level holds the pick")
	assert_eq(
		dock.active_material_button.text,
		"Active Material: %s" % BRICK_PATH.get_file().get_basename()
	)
	assert_false(dock.clear_active_material_button.disabled)
	var first = _draw(level)
	assert_eq(first.material_override, brick)

	dock.clear_active_material_button.pressed.emit()

	assert_null(level.active_material, "Clear empties it")
	assert_eq(dock.active_material_button.text, "Active Material")
	assert_true(dock.clear_active_material_button.disabled)
	var second = _draw(level, false, Vector3(-8, 0, 0))
	assert_null(second.material_override, "a new brush is translucent again")
	assert_eq(first.material_override, brick, "and the one made before keeps its material")
	await rig.leave_level(level)


func _bare_level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func _bind(dock, level) -> void:
	dock._disconnect_root_signals()
	dock.level_root = level
	dock.connected_root = level
	dock._connect_root_signals()


func test_the_button_follows_a_scene_switch_and_an_inspector_edit():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	var first := _bare_level()
	first.active_material = brick
	var second := _bare_level()

	_bind(dock, first)
	assert_eq(
		dock.active_material_button.text,
		"Active Material: %s" % BRICK_PATH.get_file().get_basename()
	)
	_bind(dock, second)
	assert_eq(dock.active_material_button.text, "Active Material", "the other level has none")
	assert_true(dock.clear_active_material_button.disabled)
	_bind(dock, null)
	assert_eq(dock.active_material_button.text, "Active Material", "a scene with no level")
	_bind(dock, first)
	assert_eq(
		dock.active_material_button.text,
		"Active Material: %s" % BRICK_PATH.get_file().get_basename()
	)

	# The Inspector writes the property, and the level says so.
	first.active_material = stone
	assert_eq(
		dock.active_material_button.text,
		"Active Material: %s" % STONE_PATH.get_file().get_basename()
	)
	_bind(dock, null)


func test_with_no_level_the_button_says_there_is_nowhere_to_keep_a_pick():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.active_material_button.pressed.emit()
	assert_false(dock.material_dialog.visible, "no file dialog")
	assert_eq(dock.status_label.text, "No LevelRoot to keep an Active Material")
	# A level closed while the dialog was open says the same.
	dock.status_label.text = ""
	dock._on_material_file_selected(BRICK_PATH)
	assert_eq(dock.status_label.text, "No LevelRoot to keep an Active Material")
	assert_eq(dock.active_material_button.text, "Active Material")


# ===========================================================================
# Saved with the scene, not with the .hflevel
# ===========================================================================


func test_the_active_material_comes_back_when_the_scene_is_reopened():
	var level := _bare_level()
	level.active_material = brick
	var packed := PackedScene.new()
	assert_eq(packed.pack(level), OK)
	assert_eq(ResourceSaver.save(packed, SCENE_PATH), OK)

	var reloaded := (
		ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var reopened = reloaded.instantiate()
	var mat: Material = reopened.active_material
	assert_not_null(mat, "the scene brings it back")
	if mat:
		assert_ne(mat, brick, "read from the file, not handed back from memory")
		assert_eq(mat.resource_path, BRICK_PATH, "the material the level was given")
		assert_eq((mat as StandardMaterial3D).albedo_color, Color(0.6, 0.25, 0.1))
	reopened.free()


func test_the_active_material_stays_out_of_the_hflevel_settings():
	var level := _bare_level()
	level.active_material = brick
	var settings: Dictionary = level.state_system.capture_hflevel_settings()
	assert_false(settings.has("active_material"), "it describes the next brush, not the level")
	assert_false(settings.values().has(brick), "under no other name either")
