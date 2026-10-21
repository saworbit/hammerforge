extends GutTest

## Each tool's last settings are kept between sessions (#1406).
##
## Grid Snap was kept and everything else started at its default every session:
## the Build tab's Shape and Sides, Solid or Cutout, the snap toggles, Hollow's
## wall and the Bevel boxes, the Structure section, which also rebuilt its fields
## at their defaults on every change of type, and the Polygon, Path and Decal
## tools. `tests/test_user_prefs.gd` pins the tools' round trip and clamping;
## this pins the dock's, the Structure section's, Reset Tool Settings, and the
## plugin keeping its tools in its preferences.
##
## Nothing here reads or writes the preferences file: every set of preferences
## has persistence off, and a restart is the data read back through its text.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")
const HFToolRegistryType = preload("res://addons/hammerforge/hf_tool_registry.gd")
const HFDockToolMemoryType = preload("res://addons/hammerforge/dock_tool_memory.gd")
const PathToolType = preload("res://addons/hammerforge/hf_path_tool.gd")
const PolygonToolType = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")

const BrushShape = LevelRootScript.BrushShape
const SnapMode = HFSnapSystem.SnapMode


func _quiet_prefs() -> HFUserPrefsType:
	var quiet := HFUserPrefsType.new()
	quiet.persistence_enabled = false
	quiet.data = HFUserPrefsType._defaults()
	quiet.data["show_welcome"] = false
	return quiet


## The preferences as the next session reads them, through the file's text.
func _restarted(from: HFUserPrefsType) -> HFUserPrefsType:
	var reread := HFUserPrefsType.new()
	reread.persistence_enabled = false
	reread.data = HFUserPrefsType._validated(JSON.parse_string(JSON.stringify(from.data, "\t")))
	return reread


func _dock_with(prefs: HFUserPrefsType) -> Node:
	var dock = DockScene.instantiate()
	add_child_autofree(dock)
	dock.set_user_prefs(prefs)
	return dock


## The Tool Settings panel's controls of one class, as built last. The panel
## frees the rows it replaces at the end of the frame, so the tree still holds
## them for now.
func _panel_controls(dock, class_name_wanted: String) -> Array:
	var out: Array = []
	for row in dock._tool_settings_controls:
		for child in row.get_children():
			if child.is_class(class_name_wanted):
				out.append(child)
	return out


func _pick_shape(dock, shape: int) -> void:
	for index in dock.shape_select.item_count:
		if dock.shape_select.get_item_id(index) == shape:
			dock.shape_select.select(index)
			dock._on_shape_selected(index)
			return
	fail_test("no shape %d in the list" % shape)


func _pick_structure(dock, type: String) -> void:
	for index in dock.structure_type_option.item_count:
		if str(dock.structure_type_option.get_item_metadata(index)) == type:
			dock.structure_type_option.select(index)
			dock._on_structure_type_changed(index)
			return
	fail_test("no structure type %s" % type)


## Change every Build tab setting that is kept away from its default, the way a
## mapper does it, through the controls.
func _set_up_the_build_tab(dock) -> void:
	_pick_shape(dock, BrushShape.PYRAMID)
	dock.sides_spin.value = 6
	_pick_shape(dock, BrushShape.CYLINDER)
	dock.sides_spin.value = 24
	dock.mode_subtract.button_pressed = true
	dock.snap_grid_btn.button_pressed = false
	dock.snap_vertex_btn.button_pressed = true
	dock.snap_perp_btn.button_pressed = true
	dock.hollow_thickness.value = 0.2
	dock._bevel_segments_spin.value = 4
	dock._bevel_radius_spin.value = 0.5
	dock._bevel_inset_dist_spin.value = 0.75
	dock._bevel_inset_height_spin.value = -0.25


# ===========================================================================
# The Build tab
# ===========================================================================


func test_the_build_tab_comes_back_as_it_was_left():
	var prefs := _quiet_prefs()
	_set_up_the_build_tab(_dock_with(prefs))

	var dock = _dock_with(_restarted(prefs))
	assert_eq(dock.active_shape, BrushShape.CYLINDER, "the shape")
	assert_eq(dock.sides_spin.value, 24.0, "the Sides it had")
	assert_eq(dock._kept_sides["pyramid"], 6, "and the pyramid keeps its own")
	assert_true(dock.mode_subtract.button_pressed, "Cutout")
	assert_false(dock.mode_add.button_pressed)
	assert_false(dock.snap_grid_btn.button_pressed, "the snap toggles")
	assert_true(dock.snap_vertex_btn.button_pressed)
	assert_false(dock.snap_center_btn.button_pressed)
	assert_false(dock.snap_edge_btn.button_pressed)
	assert_true(dock.snap_perp_btn.button_pressed)
	assert_almost_eq(dock.hollow_thickness.value, 0.2, 0.0001, "Hollow's wall")
	assert_eq(dock._bevel_segments_spin.value, 4.0, "and the Bevel boxes")
	assert_almost_eq(dock._bevel_radius_spin.value, 0.5, 0.0001)
	assert_almost_eq(dock._bevel_inset_dist_spin.value, 0.75, 0.0001)
	assert_almost_eq(dock._bevel_inset_height_spin.value, -0.25, 0.0001)

	_pick_shape(dock, BrushShape.PYRAMID)
	assert_eq(dock.sides_spin.value, 6.0, "a pyramid comes back with its own Sides")


func test_putting_the_build_tab_back_writes_nothing():
	var prefs := _quiet_prefs()
	_set_up_the_build_tab(_dock_with(prefs))
	var next := _restarted(prefs)
	var before: Dictionary = next.get_build_settings()
	_dock_with(next)
	assert_eq(next.get_build_settings(), before, "nothing read back is heard as a change")


func test_the_snap_toggles_reach_the_level_the_dock_adopts():
	var prefs := _quiet_prefs()
	_set_up_the_build_tab(_dock_with(prefs))
	var dock = _dock_with(_restarted(prefs))
	var root = LevelRootScript.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autofree(root)
	assert_true(root.snap_system.is_mode_on(SnapMode.GRID), "a level starts on the grid alone")
	dock.level_root = root
	dock._process(0.0)
	assert_false(root.snap_system.is_mode_on(SnapMode.GRID), "and takes the dock's toggles")
	assert_true(root.snap_system.is_mode_on(SnapMode.VERTEX))
	assert_true(root.snap_system.is_mode_on(SnapMode.PERPENDICULAR))
	assert_false(root.snap_system.is_mode_on(SnapMode.CENTER))
	dock.level_root = null
	dock.connected_root = null


func test_a_build_setting_out_of_range_loads_clamped_with_a_warning():
	var prefs := _quiet_prefs()
	prefs.data[HFUserPrefsType.BUILD_SETTINGS] = {
		"hollow_thickness": 900.0,
		"sides_round": 2.0,
		"bevel_segments": 0.0,
		"shape": "BLOB",
		"cutout": "yes",
	}
	var dock = _dock_with(_restarted(prefs))
	assert_eq(dock.hollow_thickness.value, dock.hollow_thickness.max_value, "held to its largest")
	assert_push_warning("%s: 'build_settings/hollow_thickness' is 900" % HFUserPrefsType.prefs_path)
	assert_eq(dock._kept_sides["round"], DraftBrush.MIN_ROUND_SIDES, "a round shape's fewest")
	assert_push_warning("'build_settings/sides_round' is 2")
	assert_eq(dock._bevel_segments_spin.value, 1.0, "a bevel of one segment at least")
	assert_push_warning("'build_settings/bevel_segments' is 0")
	assert_eq(dock.active_shape, BrushShape.BOX, "a shape that does not exist is not drawn")
	assert_push_warning("'build_settings/shape' is BLOB")
	assert_true(dock.mode_add.button_pressed, "and a word where a switch goes is not one")
	assert_push_warning("'build_settings/cutout' is a String")


func test_custom_is_not_a_shape_that_comes_back():
	var prefs := _quiet_prefs()
	prefs.data[HFUserPrefsType.BUILD_SETTINGS] = {"shape": "CUSTOM"}
	var dock = _dock_with(prefs)
	assert_eq(dock.active_shape, BrushShape.BOX, "a polygon's or a path's shape is not drawn")
	assert_push_warning("is not a brush shape")


# ===========================================================================
# The Structure section
# ===========================================================================


func test_switching_structure_type_and_back_keeps_the_first_types_fields():
	var dock = _dock_with(_quiet_prefs())
	_pick_structure(dock, "arch")
	dock.structure_fields["radius"].value = 5.5
	dock.structure_fields["segments"].value = 12
	_pick_structure(dock, "stairs")
	assert_eq(dock.structure_fields["rise"].value, 0.2, "stairs start at their own defaults")
	dock.structure_fields["rise"].value = 0.15
	_pick_structure(dock, "arch")
	assert_eq(dock.structure_fields["radius"].value, 5.5, "the arch comes back as it was tuned")
	assert_eq(dock.structure_fields["segments"].value, 12.0)
	_pick_structure(dock, "stairs")
	assert_almost_eq(dock.structure_fields["rise"].value, 0.15, 0.0001, "and so do the stairs")


func test_switching_type_and_back_keeps_the_fields_without_any_preferences():
	var dock = DockScene.instantiate()
	add_child_autofree(dock)
	_pick_structure(dock, "arch")
	dock.structure_fields["radius"].value = 5.5
	_pick_structure(dock, "dome")
	_pick_structure(dock, "arch")
	assert_eq(dock.structure_fields["radius"].value, 5.5, "the session keeps them on its own")


func test_the_structure_section_comes_back_as_it_was_left():
	var prefs := _quiet_prefs()
	var first = _dock_with(prefs)
	_pick_structure(first, "arch")
	first.structure_fields["radius"].value = 5.5
	_pick_structure(first, "stairs")
	first.structure_fields["rise"].value = 0.15

	var dock = _dock_with(_restarted(prefs))
	assert_eq(HFDockBrushHandler.structure_type(dock), "stairs", "the type last chosen")
	assert_almost_eq(dock.structure_fields["rise"].value, 0.15, 0.0001, "with its fields")
	assert_eq(dock.structure_create_btn.text, "Create Stairs", "and the button says so")
	_pick_structure(dock, "arch")
	assert_eq(dock.structure_fields["radius"].value, 5.5, "and the other type keeps its own")


func test_a_structure_field_out_of_range_loads_clamped_with_a_warning():
	var prefs := _quiet_prefs()
	prefs.data[HFUserPrefsType.STRUCTURE_SETTINGS] = {
		"type": "arch",
		"fields": {"arch": {"radius": 99999.0, "segments": 0.0, "nonsense": 1.0}, "blob": {}},
	}
	var dock = _dock_with(_restarted(prefs))
	assert_eq(dock.structure_fields["radius"].value, 4096.0, "held to the schema's largest")
	assert_push_warning("'structure_settings/fields/arch/radius' is 99999")
	assert_eq(dock.structure_fields["segments"].value, 1.0, "and its smallest")
	assert_push_warning("'structure_settings/fields/arch/segments' is 0")
	assert_false(dock._structure_kept["arch"].has("nonsense"), "a key the type lacks is dropped")
	assert_false(dock._structure_kept.has("blob"), "and a type that does not exist")
	assert_push_warning("is not a structure type")


# ===========================================================================
# The tools' own settings
# ===========================================================================


func test_a_choice_in_a_tools_list_reaches_the_tool_as_its_index():
	var dock = _dock_with(_quiet_prefs())
	var path = PathToolType.new()
	dock.show_tool_settings(path)
	var lists := _panel_controls(dock, "OptionButton")
	assert_eq(lists.size(), 2, "Side and Auto-Generate")
	var side: OptionButton = lists[0]
	side.select(PathToolType.PathSide.LEFT)
	side.item_selected.emit(PathToolType.PathSide.LEFT)
	assert_eq(
		path.get_setting("path_side"),
		PathToolType.PathSide.LEFT,
		"an index, which the tool reads into an int, not the label"
	)
	dock.show_tool_settings(path)
	lists = _panel_controls(dock, "OptionButton")
	assert_eq((lists[0] as OptionButton).selected, 1, "and the list shows it when rebuilt")
	dock.show_tool_settings(null)


func test_a_hidden_setting_has_no_control():
	var dock = _dock_with(_quiet_prefs())
	dock.show_tool_settings(PolygonToolType.new())
	var boxes := _panel_controls(dock, "SpinBox")
	assert_eq(boxes.size(), 1, "Auto-close Dist only: the extrude height is set by building")
	dock.show_tool_settings(null)


# ===========================================================================
# Reset Tool Settings
# ===========================================================================


func test_reset_tool_settings_restores_every_default():
	var prefs := _quiet_prefs()
	var registry := HFToolRegistryType.new()
	var path = PathToolType.new()
	var polygon = PolygonToolType.new()
	registry.register_tool(path)
	registry.register_tool(polygon)
	registry.keep_settings_in(prefs)
	var dock = _dock_with(prefs)
	var defaults: Dictionary = dock._build_defaults.duplicate(true)
	_set_up_the_build_tab(dock)
	_pick_structure(dock, "stairs")
	dock.structure_fields["rise"].value = 0.15
	path.set_setting("path_width", 3.0)
	polygon._remembered_height = 3.5

	dock.reset_tool_settings_btn.pressed.emit()

	assert_eq(dock.active_shape, BrushShape.BOX, "the shape")
	assert_eq(dock._kept_sides, defaults[HFDockToolMemoryType.SIDES], "both Sides counts")
	assert_true(dock.mode_add.button_pressed, "Solid")
	assert_true(dock.snap_grid_btn.button_pressed, "Grid snap alone")
	assert_false(dock.snap_vertex_btn.button_pressed)
	assert_false(dock.snap_perp_btn.button_pressed)
	for key in HFDockToolMemoryType.SPINS:
		var spin: SpinBox = dock.get(HFDockToolMemoryType.SPINS[key])
		assert_eq(spin.value, defaults[key], "%s" % key)
	assert_eq(path.get_setting("path_width"), 4.0, "the tools too")
	assert_eq(polygon._remembered_height, 0.0)
	assert_eq(prefs.get_build_settings(), {}, "and nothing is left to bring back")
	assert_eq(prefs.get_tool_settings("Path"), {})
	assert_eq(prefs.get_structure_settings(), {})
	assert_eq(HFDockBrushHandler.structure_type(dock), "arch", "the first structure type")
	_pick_structure(dock, "stairs")
	assert_eq(dock.structure_fields["rise"].value, 0.2, "every type at its defaults")
	registry.keep_settings_in(null)


func test_reset_shows_the_open_tool_settings_at_their_defaults():
	var prefs := _quiet_prefs()
	var registry := HFToolRegistryType.new()
	var path = PathToolType.new()
	registry.register_tool(path)
	registry.keep_settings_in(prefs)
	var dock = _dock_with(prefs)
	path.set_setting("path_width", 3.0)
	dock.show_tool_settings(path)
	dock._on_reset_tool_settings()
	var boxes := _panel_controls(dock, "SpinBox")
	assert_eq((boxes[0] as SpinBox).value, 4.0, "Width shows its default, not the 3 it was")
	dock.show_tool_settings(null)
	registry.keep_settings_in(null)


# ===========================================================================
# The plugin
# ===========================================================================


func test_the_plugin_keeps_its_tools_settings_in_its_preferences():
	var rig := PluginRig.new()
	await rig.bring_up(self)
	var path = rig.plugin._tool_registry.get_tool_by_id(103)
	path.set_setting("path_width", 3.0)
	assert_eq(
		rig.plugin._user_prefs.get_tool_settings("Path").get("path_width"),
		3.0,
		"a tool's setting goes into the preferences as it changes"
	)
	var prefs = rig.plugin._user_prefs
	var registry = rig.plugin._tool_registry
	await rig.take_down()
	assert_false(
		prefs.tool_settings_reset.is_connected(registry._on_settings_reset),
		"and the plugin lets go of them when it leaves"
	)
