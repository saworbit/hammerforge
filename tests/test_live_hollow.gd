extends GutTest

## A hollowed brush you can shell again at a different thickness.
##
## Hollow was the last operation with no way back to its own numbers short of
## Ctrl+Z: it replaced a solid with walls and forgot the solid. A structure could
## be reselected and re-tuned, an array reselected and rebuilt, and a room whose
## walls came out too thin could only be undone.
##
## The record keeps the one thing that could not be recovered from the walls
## themselves — the solid they were shelled out of.

const DockScene = preload("res://addons/hammerforge/dock.tscn")

var dock: HammerForgeDock
var root: LevelRoot


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root


func after_each() -> void:
	dock = null
	root = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _a_brush(size: Vector3 = Vector3(64, 64, 64), at: Vector3 = Vector3.ZERO) -> Node3D:
	var brush_id: String = root.brush_system._next_brush_id()
	var made = (
		root
		. brush_system
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": brush_id,
				"transform": Transform3D(Basis.IDENTITY, at),
			}
		)
	)
	assert_not_null(made, "the fixture needs a brush to hollow")
	return made


func _id_of(brush: Node3D) -> String:
	return str(root.get_brush_info_from_node(brush).get("brush_id", ""))


func _hollow(brush: Node3D, thickness: float = 4.0) -> Dictionary:
	var result: HFOpResult = root.brush_system.hollow_brush_by_id(_id_of(brush), thickness)
	assert_true(result.ok, "the fixture needs a hollow: %s" % result.message)
	var record = root.hollow_for_selection(Array(_wall_ids()))
	assert_not_null(record, "hollowing records the solid it shelled")
	return record


func _wall_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for child in root.draft_brushes_node.get_children():
		var brush_id := _id_of(child)
		if brush_id != "":
			out.append(brush_id)
	return out


func _select(nodes: Array) -> void:
	dock.set_selection_nodes(nodes)


func _a_wall(record: Dictionary) -> Node3D:
	var wall = root.brush_system.find_brush_by_id(str(record["wall_ids"][0]))
	assert_not_null(wall, "a recorded wall is a brush that exists")
	return wall


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


func _button_text() -> String:
	return dock.hollow_btn.text if dock.hollow_btn else ""


func _detach_shown() -> bool:
	return dock.hollow_detach_btn.visible if dock.hollow_detach_btn else false


# ===========================================================================
# The record
# ===========================================================================


func test_hollowing_remembers_the_solid_it_shelled():
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	assert_almost_eq(float(record["thickness"]), 4.0, 0.001)
	assert_eq(record["source"]["size"], Vector3(64, 64, 64))
	assert_eq(record["wall_ids"].size(), _brush_count(), "every wall is in the record")


func test_every_wall_finds_the_hollow_it_belongs_to():
	var brush := _a_brush()
	var record := _hollow(brush)
	for wall_id in record["wall_ids"]:
		var found = root.hollow_for_selection([str(wall_id)])
		assert_not_null(found, "wall '%s' has to reach its hollow" % wall_id)
		assert_eq(str(found["hollow_id"]), str(record["hollow_id"]))


func test_a_brush_that_was_never_hollowed_finds_nothing():
	var loose := _a_brush()
	assert_null(root.hollow_for_selection([_id_of(loose)]))


func test_an_unknown_hollow_resolves_to_nothing():
	assert_null(root.hollow_for_id("hol_that_never_existed"))


func test_a_failed_hollow_records_nothing():
	# A thickness that leaves no interior is refused, and there is no hollow to
	# offer Re-hollow on afterwards.
	var brush := _a_brush(Vector3(16, 16, 16))
	var result: HFOpResult = root.brush_system.hollow_brush_by_id(_id_of(brush), 40.0)
	assert_false(result.ok)
	assert_null(root.hollow_for_selection([_id_of(brush)]))


# ===========================================================================
# Re-hollowing
# ===========================================================================


func test_re_hollowing_shells_the_same_solid_again():
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	var result: HFOpResult = root.update_hollow(str(record["hollow_id"]), 12.0)
	assert_true(result.ok, result.message)
	var after = root.hollow_for_id(str(record["hollow_id"]))
	assert_not_null(after, "the hollow keeps its identity across the rebuild")
	assert_almost_eq(float(after["thickness"]), 12.0, 0.001)


func test_re_hollowing_leaves_no_solid_behind():
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	var walls_before := _brush_count()
	root.update_hollow(str(record["hollow_id"]), 8.0)
	assert_eq(_brush_count(), walls_before, "walls replaced walls, and the solid is gone")


func test_the_walls_of_a_re_hollowed_brush_still_say_what_they_belong_to():
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	root.update_hollow(str(record["hollow_id"]), 8.0)
	var after = root.hollow_for_id(str(record["hollow_id"]))
	var found = root.hollow_for_selection([str(after["wall_ids"][0])])
	assert_not_null(found, "a second Re-hollow has to be reachable from the new walls")
	assert_eq(str(found["hollow_id"]), str(record["hollow_id"]))


func test_a_thickness_the_brush_cannot_take_leaves_the_walls_alone():
	# The new walls are planned on a rebuilt solid before the old walls are
	# touched, so a refusal costs nothing.
	var brush := _a_brush(Vector3(64, 64, 64))
	var record := _hollow(brush, 4.0)
	var before := _brush_count()
	var result: HFOpResult = root.update_hollow(str(record["hollow_id"]), 40.0)
	assert_false(result.ok, "half the brush is not a wall thickness")
	assert_eq(_brush_count(), before, "and the level is exactly as it was")
	assert_not_null(root.hollow_for_id(str(record["hollow_id"])))


func test_re_hollowing_an_unknown_hollow_answers_no():
	var result: HFOpResult = root.update_hollow("hol_nothing", 8.0)
	assert_false(result.ok)


func test_re_hollowing_twice_keeps_one_hollow():
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	root.update_hollow(str(record["hollow_id"]), 8.0)
	root.update_hollow(str(record["hollow_id"]), 12.0)
	var after = root.hollow_for_id(str(record["hollow_id"]))
	assert_not_null(after)
	assert_almost_eq(float(after["thickness"]), 12.0, 0.001)


func test_a_room_dragged_across_the_level_re_hollows_where_it_now_stands():
	# Rebuilding it back where it was made is the surprise the structure records'
	# relocation vote exists to prevent.
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	for wall_id in record["wall_ids"]:
		root.brush_system.find_brush_by_id(str(wall_id)).global_position += Vector3(512, 0, 0)
	root.update_hollow(str(record["hollow_id"]), 8.0)
	var after = root.hollow_for_id(str(record["hollow_id"]))
	for wall_id in after["wall_ids"]:
		var wall = root.brush_system.find_brush_by_id(str(wall_id))
		assert_almost_eq(
			wall.global_position.x, 512.0, 40.0, "the room stayed where it was dragged to"
		)


func test_a_turned_room_re_hollows_at_the_angle_it_now_has():
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	# Turning the room, not turning each wall where it stands: every wall orbits
	# the room's centre as well as facing a new way.
	var turn := Basis(Vector3.UP, deg_to_rad(45.0))
	for wall_id in record["wall_ids"]:
		var wall = root.brush_system.find_brush_by_id(str(wall_id))
		wall.global_transform = Transform3D(turn) * wall.global_transform
	root.update_hollow(str(record["hollow_id"]), 8.0)
	var after = root.hollow_for_id(str(record["hollow_id"]))
	var rebuilt = root.brush_system.find_brush_by_id(str(after["wall_ids"][0]))
	assert_true(
		HFTransformSystem.same_transform(
			Transform3D(rebuilt.global_transform.basis, Vector3.ZERO),
			Transform3D(turn, Vector3.ZERO),
			0.01
		),
		"the walls keep the angle the room was turned to"
	)


func test_walls_moved_one_at_a_time_are_not_a_relocation():
	# They disagree about where the room is, which is editing rather than moving,
	# and the placement stays where it was.
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	root.brush_system.find_brush_by_id(str(record["wall_ids"][0])).global_position += Vector3(
		512, 0, 0
	)
	root.update_hollow(str(record["hollow_id"]), 8.0)
	var after = root.hollow_for_id(str(record["hollow_id"]))
	for wall_id in after["wall_ids"]:
		var wall = root.brush_system.find_brush_by_id(str(wall_id))
		assert_almost_eq(wall.global_position.x, 0.0, 40.0, "the room rebuilt where it was")


# ===========================================================================
# Detach
# ===========================================================================


func test_detach_keeps_every_wall():
	var brush := _a_brush()
	var record := _hollow(brush)
	var before := _brush_count()
	assert_true(root.detach_hollow(str(record["hollow_id"])))
	assert_eq(_brush_count(), before, "detach is the option that deletes nothing")


func test_detach_forgets_the_hollow():
	var brush := _a_brush()
	var record := _hollow(brush)
	var wall_id := str(record["wall_ids"][0])
	root.detach_hollow(str(record["hollow_id"]))
	assert_null(root.hollow_for_id(str(record["hollow_id"])))
	assert_null(
		root.hollow_for_selection([wall_id]), "a detached wall is ordinary geometry and says so"
	)


func test_detaching_an_unknown_hollow_answers_no():
	assert_false(root.detach_hollow("hol_nothing"))


# ===========================================================================
# The row becomes an editor
# ===========================================================================


func test_selecting_a_wall_turns_hollow_into_re_hollow():
	var brush := _a_brush()
	var record := _hollow(brush, 6.0)
	_select([_a_wall(record)])
	assert_eq(_button_text(), "Re-hollow")
	assert_true(_detach_shown(), "Detach is the way out, and belongs beside Re-hollow")
	assert_almost_eq(float(dock.hollow_thickness.value), 6.0, 0.001)


func test_selecting_an_unrelated_brush_puts_the_row_back():
	var brush := _a_brush()
	var record := _hollow(brush)
	_select([_a_wall(record)])
	_select([_a_brush(Vector3(32, 32, 32), Vector3(500, 0, 500))])
	assert_eq(_button_text(), "Hollow (Ctrl+H)")
	assert_false(_detach_shown())
	assert_eq(dock._active_hollow_id, "")


func test_the_button_re_hollows_rather_than_hollowing_a_wall():
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	var before := _brush_count()
	_select([_a_wall(record)])
	dock.hollow_thickness.set_value_no_signal(8.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_eq(_brush_count(), before, "the walls were replaced, not shelled again each")
	var after = root.hollow_for_id(str(record["hollow_id"]))
	assert_not_null(after)
	assert_almost_eq(float(after["thickness"]), 8.0, 0.001)
	assert_eq(_button_text(), "Re-hollow", "and the row is still an editor for it")


func test_re_hollow_can_be_pressed_twice_without_reselecting():
	# The first Re-hollow frees the wall that was selected, so the second press is
	# the one that used to find nothing to re-shell.
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	_select([_a_wall(record)])
	dock.hollow_thickness.set_value_no_signal(8.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_eq(_button_text(), "Re-hollow", "the row is still editing the same hollow")
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_almost_eq(float(root.hollow_for_id(str(record["hollow_id"]))["thickness"]), 12.0, 0.001)


func test_detaching_from_the_row_puts_it_back():
	var brush := _a_brush()
	var record := _hollow(brush)
	_select([_a_wall(record)])
	HFDockBrushHandler.on_detach_hollow(dock)
	assert_eq(dock._active_hollow_id, "")
	assert_eq(_button_text(), "Hollow (Ctrl+H)")
	assert_false(_detach_shown())


func test_refreshing_the_row_with_nothing_selected_is_quiet():
	_select([])
	HFDockBrushHandler.refresh_hollow_section(dock)
	assert_eq(_button_text(), "Hollow (Ctrl+H)")
	assert_false(_detach_shown())


# ===========================================================================
# Undo, and what survives a state restore
# ===========================================================================


func test_a_re_hollow_can_be_undone():
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	var before: Dictionary = root.capture_state()
	root.update_hollow(str(record["hollow_id"]), 12.0)
	root.restore_state(before)
	var after = root.hollow_for_id(str(record["hollow_id"]))
	assert_not_null(after, "undo puts the hollow back with its walls")
	assert_almost_eq(float(after["thickness"]), 4.0, 0.001)


func test_a_restored_hollow_is_still_reachable_from_its_walls():
	# A brush info carries no hollow tag, so a restore has to put them back or an
	# undo leaves walls that no longer say what they belong to.
	var brush := _a_brush()
	var record := _hollow(brush)
	var snapshot: Dictionary = root.capture_state()
	root.restore_state(snapshot)
	var restored = root.hollow_for_id(str(record["hollow_id"]))
	assert_not_null(restored)
	var found = root.hollow_for_selection([str(restored["wall_ids"][0])])
	assert_not_null(found, "clicking a wall after an undo still reaches the hollow")


func test_a_restored_hollow_can_still_be_re_shelled():
	# The solid travels in the record, so it survives the round trip through the
	# level file the way the walls do.
	var brush := _a_brush()
	var record := _hollow(brush, 4.0)
	root.restore_state(root.capture_state())
	var result: HFOpResult = root.update_hollow(str(record["hollow_id"]), 10.0)
	assert_true(result.ok, result.message)
	assert_almost_eq(float(root.hollow_for_id(str(record["hollow_id"]))["thickness"]), 10.0, 0.001)


func test_a_detached_hollow_stays_detached_through_a_restore():
	var brush := _a_brush()
	var record := _hollow(brush)
	var wall_id := str(record["wall_ids"][0])
	root.detach_hollow(str(record["hollow_id"]))
	root.restore_state(root.capture_state())
	assert_null(root.hollow_for_id(str(record["hollow_id"])))
	assert_null(root.hollow_for_selection([wall_id]))
