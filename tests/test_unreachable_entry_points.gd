extends GutTest

## Two things the product advertises and could not be reached: the searchable
## shortcut dialog with no button to open it (#606), and a custom-tool folder that
## does not ship and lives where the documented upgrade deletes it (#612).

const HFToolRegistry = preload("res://addons/hammerforge/hf_tool_registry.gd")

# ===========================================================================
# The shortcut dialog can be opened (#606)
# ===========================================================================


func test_the_dock_builds_the_question_mark_button_the_guide_documents():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	assert_false(source.is_empty(), "dock.gd must be readable")
	assert_true(source.contains("_shortcuts_btn"), "the toolbar needs a control for the dialog")
	assert_true(
		source.contains("_shortcuts_btn.pressed.connect(_on_shortcuts_help)"),
		"and it has to be wired to the handler that opens it"
	)


func test_the_shortcut_dialog_still_exists_to_be_opened():
	var dialog_script = load("res://addons/hammerforge/ui/hf_shortcut_dialog.gd")
	assert_not_null(dialog_script, "HFShortcutDialog is what the button is for")


func test_the_user_guide_still_describes_the_button_that_now_exists():
	var guide := FileAccess.get_file_as_string("res://docs/HammerForge_UserGuide.md")
	assert_false(guide.is_empty(), "the user guide must be readable")
	assert_true(
		guide.contains("searchable shortcut dialog"),
		"the guide documents it, so the control has to stay"
	)


# ===========================================================================
# Custom tools live outside the addon (#612)
# ===========================================================================


func test_the_project_tools_path_is_outside_the_addon():
	assert_false(
		HFToolRegistry.PROJECT_TOOLS_PATH.begins_with("res://addons/"),
		"the upgrade instructions say to replace addons/hammerforge"
	)
	assert_eq(HFToolRegistry.PROJECT_TOOLS_PATH, "res://hammerforge_tools/")


func test_the_folder_ships_and_is_discoverable():
	assert_true(
		DirAccess.dir_exists_absolute(HFToolRegistry.PROJECT_TOOLS_PATH),
		"load_external_tools() returns on its first line when the folder is missing"
	)
	assert_true(
		FileAccess.file_exists(HFToolRegistry.PROJECT_TOOLS_PATH.path_join("README.md")),
		"a feature nobody can find is the thing being fixed"
	)


func test_the_plugin_scans_the_project_path_first():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_false(source.is_empty(), "plugin.gd must be readable")
	assert_true(source.contains("HFToolRegistry.PROJECT_TOOLS_PATH"))
	var project_at := source.find("PROJECT_TOOLS_PATH)")
	var addon_at := source.find('load_external_tools("res://addons/hammerforge/tools/")')
	assert_gt(project_at, -1, "the project path is scanned")
	assert_gt(addon_at, -1, "and the old one is kept so an install today loses nothing")
	assert_lt(project_at, addon_at, "the project path is the one to prefer")


func test_the_example_tool_is_a_real_tool_and_is_not_registered():
	var example_path := "res://hammerforge_tools/examples/example_ruler_tool.gd"
	assert_true(FileAccess.file_exists(example_path), "the folder ships a tool to copy")
	var script = load(example_path)
	assert_not_null(script, "and it has to load")
	if script:
		var instance = script.new()
		assert_true(instance is HFEditorTool, "an example that does not extend the base is no use")
		if instance is HFEditorTool:
			assert_gte(instance.tool_id(), 100, "external tool ids start at 100")
			assert_ne(instance.tool_name(), "Custom Tool", "it names itself")

	var registry := HFToolRegistry.new()
	registry.load_external_tools(HFToolRegistry.PROJECT_TOOLS_PATH)
	for tool_instance in registry.get_all_tools():
		assert_ne(
			tool_instance.tool_id(),
			100,
			"the scan is not recursive, so the example must not reach anyone's toolbar"
		)
