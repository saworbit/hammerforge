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
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	var brush := (
		root.create_brush_from_info({"size": Vector3(8, 8, 8), "brush_id": "dock_usability_brush"})
		as DraftBrush
	)
	dock.set_selection_nodes([brush])
	assert_true(dock.tool_extrude_up.visible)
	assert_true(dock.tool_extrude_down.visible)
	assert_true(dock.tool_vertex.visible)
	dock.set_selection_nodes([])
	assert_false(dock.tool_extrude_up.visible)
	assert_false(dock.tool_vertex.visible)
	dock._update_context_hints()
	assert_eq(
		dock._brush_hint.text,
		"Draw another brush, or choose Select to edit one.",
		"An existing brush must not leave the beginner hint stuck on draw-first",
	)


func test_async_bake_and_commit_cuts_never_enter_undo_as_coroutines() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var commit_start := source.find("func _on_commit_cuts")
	var commit_end := source.find("func _on_restore_cuts", commit_start)
	var commit_body := source.substr(commit_start, commit_end - commit_start)
	assert_true(commit_body.contains("await level_root.prepare_commit_cuts()"))
	assert_true(commit_body.contains("level_root.finalize_commit_cuts()"))
	assert_true(commit_body.contains("_commit_precomputed_state_action("))
	assert_false(commit_body.contains("_commit_state_action("))

	var helper_start := source.find("func _commit_precomputed_state_action")
	var helper_end := source.find("func _on_bake", helper_start)
	var helper_body := source.substr(helper_start, helper_end - helper_start)
	assert_true(helper_body.contains("restore_state_with_baked_snapshot"))
	assert_true(helper_body.contains("undo_redo.commit_action(false)"))
	assert_false(helper_body.contains("await "))


func test_manual_save_reports_completion_after_worker_finishes() -> void:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	dock.connected_root = root
	dock._user_prefs = null
	dock._connect_root_signals()
	var path := "user://dock_manual_save_completion_test.hflevel"
	DirAccess.remove_absolute(path)
	dock._on_hflevel_save_selected(path)
	assert_eq(dock.status_label.text, "Saving .hflevel...")
	var guard := 0
	while (
		root.file_system._hflevel_thread
		and root.file_system._hflevel_thread.is_alive()
		and guard < 200
	):
		await get_tree().process_frame
		guard += 1
	root._process_hflevel_saves()
	assert_eq(dock.status_label.text, "Saved .hflevel")
	assert_true(FileAccess.file_exists(path))
	DirAccess.remove_absolute(path)


func test_manual_save_failure_names_destination() -> void:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	var path := "user://blocked/manual.hflevel"
	root.hflevel_save_failed.emit(path, "permission denied")
	assert_true(dock.status_label.text.contains(path))
	assert_true(dock.status_label.text.begins_with("Failed to save"))


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false
