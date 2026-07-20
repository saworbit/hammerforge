extends GutTest
## Regression coverage for the simplified Manage-tab workflow.

const ManageTabBuilder = preload("res://addons/hammerforge/ui/manage_tab_builder.gd")

var dock: HammerForgeDock
var root_vbox: VBoxContainer


func before_each() -> void:
	dock = HammerForgeDock.new()
	root_vbox = VBoxContainer.new()
	add_child(root_vbox)
	ManageTabBuilder.new(dock).build(root_vbox)


func after_each() -> void:
	if root_vbox and is_instance_valid(root_vbox):
		root_vbox.free()
	if dock and is_instance_valid(dock):
		dock.free()
	root_vbox = null
	dock = null


func test_default_view_leads_with_one_click_test_level() -> void:
	var test_level := _get_section("TestLevel")
	assert_not_null(test_level)
	assert_true(test_level.is_expanded(), "Test Level should be open by default")

	var content := test_level.get_content()
	var quick_play := content.get_node_or_null("PrimaryQuickPlay") as Button
	var manual_actions := content.get_node_or_null("ManualActions") as HBoxContainer
	assert_eq(content.get_child_count(), 2, "The primary workflow should stay compact")
	assert_eq(content.get_child(0), quick_play)
	assert_not_null(quick_play)
	assert_eq(quick_play.text, "Test Level  (Bake + Play)")
	assert_true(quick_play.pressed.is_connected(dock._on_quick_play))
	assert_not_null(manual_actions)
	assert_eq(manual_actions.get_child(0), dock.validate_btn)
	assert_eq(manual_actions.get_child(1), dock.bake_btn)
	assert_eq(dock.validate_btn.text, "Check Only")
	assert_eq(dock.bake_btn.text, "Bake Only")


func test_advanced_bake_keeps_all_secondary_controls_collapsed() -> void:
	var advanced := _get_section("AdvancedBake")
	assert_not_null(advanced)
	assert_false(advanced.is_expanded(), "Advanced Bake should be collapsed by default")

	var advanced_controls = [
		dock.validate_fix_btn,
		dock.bake_dry_run_btn,
		dock.bake_merge_meshes,
		dock.bake_generate_lods,
		dock.bake_unwrap_uv0,
		dock.bake_lightmap_uv2,
		dock.bake_use_face_materials,
		dock.bake_lightmap_texel,
		dock.bake_navmesh,
		dock.bake_navmesh_cell_size,
		dock.bake_navmesh_cell_height,
		dock.bake_navmesh_agent_height,
		dock.bake_navmesh_agent_radius,
		dock.bake_selected_btn,
		dock.bake_changed_btn,
		dock.bake_check_issues_btn,
		dock.bake_preview_mode_opt,
		dock.bake_chunk_size_spin,
		dock.bake_visible_only_check,
		dock.bake_use_multimesh_check,
		dock.bake_use_atlas_check,
		dock.bake_auto_connectors_check,
		dock.bake_connector_mode_opt,
		dock.bake_connector_stair_height_spin,
		dock.bake_connector_width_spin,
		dock.bake_generate_occluders_check,
		dock.bake_occluder_min_area_spin,
		dock.bake_estimate_label,
		dock.quick_play_camera_btn,
		dock.quick_play_area_btn,
		dock.export_playtest_btn,
	]
	for control in advanced_controls:
		assert_not_null(control)
		assert_true(
			_is_descendant_of(control, advanced),
			"%s should live under Advanced Bake" % control.name,
		)


func test_actions_and_file_are_collapsed_by_default() -> void:
	var actions := _get_section("Actions")
	var file := _get_section("File")
	assert_not_null(actions)
	assert_not_null(file)
	assert_false(actions.is_expanded())
	assert_false(file.is_expanded())


func test_existing_primary_and_advanced_signals_remain_connected() -> void:
	ManageTabBuilder.new(dock).connect_signals()

	assert_true(dock.validate_btn.pressed.is_connected(dock._on_validate_level))
	assert_true(dock.bake_btn.pressed.is_connected(dock._on_bake))
	assert_true(dock.validate_fix_btn.pressed.is_connected(dock._on_validate_fix))
	assert_true(dock.bake_dry_run_btn.pressed.is_connected(dock._on_bake_dry_run))
	assert_true(dock.bake_selected_btn.pressed.is_connected(dock._on_bake_selected))
	assert_true(dock.bake_changed_btn.pressed.is_connected(dock._on_bake_changed))
	assert_true(dock.bake_check_issues_btn.pressed.is_connected(dock._on_bake_check_issues))
	assert_true(dock.quick_play_camera_btn.pressed.is_connected(dock._on_quick_play_from_camera))
	assert_true(dock.quick_play_area_btn.pressed.is_connected(dock._on_quick_play_selected_area))
	assert_true(dock.export_playtest_btn.pressed.is_connected(dock._on_export_playtest))


func test_primary_quick_play_is_disabled_and_explained_without_a_level_root() -> void:
	var quick_play := _get_section("TestLevel").get_content().get_node("PrimaryQuickPlay") as Button
	assert_true(quick_play.disabled)
	assert_string_contains(quick_play.tooltip_text, "Requires a LevelRoot")
	assert_eq(
		quick_play.get_meta("default_tooltip", ""),
		"Bake and run the current level in one step",
	)

	# Clearing a bake lock must not accidentally enable play without a root.
	dock._set_bake_buttons_disabled(false)
	assert_true(quick_play.disabled)
	assert_string_contains(quick_play.tooltip_text, "Requires a LevelRoot")


func test_primary_quick_play_tracks_root_and_bake_busy_states() -> void:
	var quick_play := _get_section("TestLevel").get_content().get_node("PrimaryQuickPlay") as Button
	var level_root := LevelRoot.new()
	autofree(level_root)
	dock.level_root = level_root
	dock._update_disabled_hints()

	assert_false(quick_play.disabled)
	assert_eq(quick_play.tooltip_text, "Bake and run the current level in one step")

	dock._set_bake_buttons_disabled(true)
	assert_true(quick_play.disabled)
	assert_string_contains(quick_play.tooltip_text, "bake")

	dock._set_bake_buttons_disabled(false)
	assert_false(quick_play.disabled)
	assert_eq(quick_play.tooltip_text, "Bake and run the current level in one step")


func _get_section(node_name: String) -> HFCollapsibleSection:
	return root_vbox.get_node_or_null(node_name) as HFCollapsibleSection


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false
