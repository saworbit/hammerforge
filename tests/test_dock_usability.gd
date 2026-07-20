extends GutTest
## Locks the dock's novice-facing defaults to the deliberately small workflow.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var dock: HammerForgeDock


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)


func after_each() -> void:
	dock = null


func test_primary_navigation_uses_plain_workflow_names() -> void:
	var titles: Array[String] = []
	for index in dock.main_tabs.get_tab_count():
		titles.append(dock.main_tabs.get_tab_title(index))
	assert_eq(titles, ["Build", "Paint", "Objects", "Test"])
	assert_eq(dock.quick_play_btn.text, "Test Level  (Bake + Play)")
	assert_eq(dock._mode_label.text, "Draw - drag in the 3D viewport")


func test_solid_and_cutout_live_in_build_context() -> void:
	assert_eq(dock.mode_add.get_parent().name, "OperationRow")
	assert_eq(dock.mode_subtract.get_parent().name, "OperationRow")
	assert_eq(dock.mode_add.text, "Solid")
	assert_eq(dock.mode_subtract.text, "Cutout")
	assert_false(dock._advanced_build_section.is_expanded())
	assert_true(_is_descendant_of(dock._snap_mode_row, dock._advanced_build_section))
	assert_true(_is_descendant_of(dock._axis_lock_row, dock._advanced_build_section))
	assert_true(_is_descendant_of(dock._disp_section, dock._advanced_build_section))
	assert_true(_is_descendant_of(dock._bevel_section, dock._advanced_build_section))
	assert_true(_is_descendant_of(dock.texture_lock_check, dock._advanced_build_section))


func test_specialist_edit_tools_only_appear_for_brush_selection() -> void:
	assert_false(dock.tool_extrude_up.visible)
	assert_false(dock.tool_extrude_down.visible)
	assert_false(dock.tool_vertex.visible)
	var brush := DraftBrush.new()
	autofree(brush)
	dock.set_selection_nodes([brush])
	assert_true(dock.tool_extrude_up.visible)
	assert_true(dock.tool_extrude_down.visible)
	assert_true(dock.tool_vertex.visible)
	dock.set_selection_nodes([])
	assert_false(dock.tool_extrude_up.visible)
	assert_false(dock.tool_vertex.visible)


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false
