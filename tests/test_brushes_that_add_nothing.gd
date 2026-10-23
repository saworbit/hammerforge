extends GutTest

## Validate finds brushes that add nothing to the bake (#1708): a cut that cuts no
## solid brush, a solid brush wholly inside another, and two brushes the same to
## within a millimetre. The Test tab selects every brush of a kind, Keep First
## deletes the later brush of each near pair as one undo step, and a bake names
## the cuts that sent it down the CSG path for nothing.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")

var root: LevelRoot
var dock: Node
var undo


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	undo = UndoStandIn.new()
	dock.undo_redo = undo


func after_each() -> void:
	HFLog.end_test_capture()
	undo.free_histories()
	root = null
	dock = null


func _box(id: String, size: Vector3, center: Vector3, subtract := false) -> DraftBrush:
	var info := {
		"brush_id": id,
		"size": size,
		"center": center,
		"operation": CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION,
	}
	var brush: DraftBrush = root.create_brush_from_info(info)
	assert_not_null(brush, "fixture: %s" % id)
	return brush


func _findings(kind: String) -> Array:
	var out: Array = []
	for finding in root.validate_level(false).get("findings", []):
		if str(finding.get("kind", "")) == kind:
			out.append(finding)
	return out


func _named(findings: Array) -> Array:
	return findings.map(func(f): return str((f["node"] as Node).get("brush_id")))


func test_a_cut_in_empty_space_is_found_and_one_cutting_a_wall_is_not():
	_box("wall", Vector3(8, 4, 1), Vector3(0, 2, 0))
	_box("door", Vector3(2, 3, 2), Vector3(0, 1.5, 0), true)
	_box("stray", Vector3(1, 1, 1), Vector3(0, 2, 10), true)
	var found := _findings("cut_cuts_nothing")
	assert_eq(_named(found), ["stray"])
	assert_string_contains(found[0]["message"], "Cut brush cuts no solid brush")


func test_a_turned_cut_whose_box_crosses_a_wall_it_misses_is_found():
	_box("pillar", Vector3(1, 4, 1), Vector3(0, 2, 0))
	var cut := _box("near", Vector3(4, 1, 0.2), Vector3(1.6, 2, 1.6), true)
	cut.rotation = Vector3(0, deg_to_rad(45), 0)
	assert_eq(_named(_findings("cut_cuts_nothing")), ["near"])


func test_a_box_inside_another_is_found_and_one_poking_out_a_centimetre_is_not():
	_box("hall", Vector3(10, 4, 10), Vector3(0, 2, 0))
	_box("crate", Vector3(1, 1, 1), Vector3(2, 1, 2))
	_box("beam", Vector3(1, 1, 1), Vector3(-2, 3.51, -2))
	var found := _findings("solid_inside_solid")
	assert_eq(_named(found), ["crate"])
	assert_eq(str((found[0]["other_node"] as Node).get("brush_id")), "hall")


func test_boxes_half_a_millimetre_apart_are_near_duplicates_and_five_centimetres_apart_are_not():
	_box("a", Vector3(2, 2, 2), Vector3(0, 1, 0))
	_box("a_copy", Vector3(2, 2, 2), Vector3(0.0005, 1, 0))
	_box("b", Vector3(2, 2, 2), Vector3(10, 1, 0))
	_box("b_moved", Vector3(2, 2, 2), Vector3(10.05, 1, 0))
	var found := _findings("near_duplicate")
	assert_eq(_named(found), ["a_copy"], "the later of the near pair")
	assert_eq(str((found[0]["other_node"] as Node).get("brush_id")), "a")
	assert_eq(_findings("solid_inside_solid"), [], "a near pair is not also inside")


func test_an_exact_copy_is_said_once():
	_box("a", Vector3(2, 2, 2), Vector3(0, 1, 0))
	_box("a_copy", Vector3(2, 2, 2), Vector3(0, 1, 0))
	var messages: Array = root.validate_level(false)["issues"]
	assert_eq(messages.filter(func(m): return str(m).contains("same space")).size(), 1)
	assert_eq(_findings("near_duplicate"), [], "the exact check said it")


func _kind_row(label: String) -> HBoxContainer:
	for row in dock.bake_issue_list.get_children():
		if row.is_queued_for_deletion():
			continue
		var text := (row.get_child(0) as Label).text
		if text.ends_with(label):
			return row
	return null


func _button(row: HBoxContainer, text: String) -> Button:
	for child in row.get_children():
		if child is Button and (child as Button).text == text:
			return child
	return null


func test_select_all_on_a_kind_selects_exactly_the_brushes_it_names():
	_box("wall", Vector3(8, 4, 1), Vector3(0, 2, 0))
	var one := _box("stray_1", Vector3(1, 1, 1), Vector3(0, 2, 10), true)
	var two := _box("stray_2", Vector3(1, 1, 1), Vector3(5, 2, 10), true)
	HFDockManageHandler.on_validate_level(dock)
	var row := _kind_row("cuts that cut nothing")
	assert_not_null(row, "a row for the kind")
	if row == null:
		return
	assert_eq((row.get_child(0) as Label).text, "2 cuts that cut nothing")
	var select := _button(row, "Select All")
	var bound: Array = select.pressed.get_connections()[0]["callable"].get_bound_arguments()
	assert_eq(bound, [[one, two]])
	assert_null(_button(row, "Keep First"), "only near pairs are offered Keep First")


func test_keep_first_deletes_the_later_brush_of_each_pair_in_one_undo_step_when_asked():
	_box("a", Vector3(2, 2, 2), Vector3(0, 1, 0))
	_box("a_copy", Vector3(2, 2, 2), Vector3(0.0005, 1, 0))
	_box("b", Vector3(2, 2, 2), Vector3(10, 1, 0))
	_box("b_copy", Vector3(2, 2, 2), Vector3(10, 1, 0.0006))
	HFDockManageHandler.on_validate_level(dock)
	assert_eq(undo.scene_history.get_history_count(), 0, "validate deletes nothing")
	assert_not_null(root.find_brush_by_id("a_copy"), "both are there until asked")
	var row := _kind_row("later brushes of near pairs")
	assert_not_null(row)
	if row == null:
		return
	_button(row, "Keep First").pressed.emit()
	assert_null(root.find_brush_by_id("a_copy"))
	assert_null(root.find_brush_by_id("b_copy"))
	assert_not_null(root.find_brush_by_id("a"))
	assert_not_null(root.find_brush_by_id("b"))
	assert_eq(undo.scene_history.get_history_count(), 1, "one undo step")
	assert_eq(undo.scene_history.get_current_action_name(), "Keep First")
	undo.scene_history.undo()
	assert_not_null(root.find_brush_by_id("a_copy"), "and undo brings them back")
	assert_not_null(root.find_brush_by_id("b_copy"))


func test_a_bake_names_the_cuts_that_cut_nothing():
	root.bake_use_face_materials = true
	_box("floor", Vector3(8, 1, 8), Vector3(0, -0.5, 0))
	_box("stray", Vector3(1, 1, 1), Vector3(0, 6, 0), true)
	HFLog.begin_test_capture(["Bake took the CSG path"])
	await root.bake()
	var said := HFLog.get_captured_warnings().filter(
		func(w): return str(w).contains("Bake took the CSG path")
	)
	assert_eq(said.size(), 1)
	if not said.is_empty():
		assert_string_contains(said[0], "1 cut that cut no solid brush: ")
		assert_string_contains(said[0], str(root.find_brush_by_id("stray").name))
