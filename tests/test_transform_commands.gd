extends GutTest

## The command surfaces free transform is reachable from, and the contracts that
## keep them wired: keymap bindings, shared dispatch, the viewport input ladder,
## the context menu, the floating toolbar, and the dock.
##
## Undo dispatches by method name on LevelRoot, so a typo in one of those strings
## would leave the command working and its undo entry silently absent. These
## tests exist mostly to make that impossible.

const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HFTransformSystemScript = preload("res://addons/hammerforge/systems/hf_transform_system.gd")

const TRANSFORM_ACTIONS := ["rotate_ccw", "rotate_cw", "flip_selection", "reset_rotation"]

# ===========================================================================
# Keymap
# ===========================================================================


func test_every_transform_action_has_a_default_binding():
	var keymap := HFKeymap.new()
	keymap._bindings = HFKeymap._default_bindings()
	for action in TRANSFORM_ACTIONS:
		assert_true(keymap.get_all_bindings().has(action), "%s must ship with a binding" % action)
		assert_ne(keymap.get_display_string(action), "?", "%s must render a shortcut" % action)


func test_transform_actions_land_in_their_own_palette_category():
	for action in TRANSFORM_ACTIONS:
		assert_eq(HFKeymap.get_category(action), "Transform", action)


func test_the_palette_renders_the_transform_category():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/hf_hotkey_palette.gd")
	assert_true(
		source.contains('"Transform"'),
		"a category the keymap emits but the palette never orders would never be drawn"
	)


func test_transform_actions_have_readable_labels():
	for action in TRANSFORM_ACTIONS:
		var label := HFKeymap.get_action_label(action)
		assert_ne(label, action, "%s must have a written label, not its raw name" % action)
		assert_false(label.contains("_"), "%s label should read as prose" % action)


func test_no_transform_binding_collides_with_another_action():
	var keymap := HFKeymap.new()
	keymap._bindings = HFKeymap._default_bindings()
	var bindings: Dictionary = keymap.get_all_bindings()
	for action in TRANSFORM_ACTIONS:
		var binding: Dictionary = bindings[action]
		for other in bindings:
			if other == action:
				continue
			# paint_ramp deliberately shares R: the router only dispatches it in
			# paint mode, and gates the whole transform group on paint mode being
			# off. Every other collision would be two live commands on one key.
			if other == "paint_ramp":
				continue
			assert_false(
				_same_chord(binding, bindings[other]),
				"%s and %s are bound to the same chord" % [action, other]
			)


func _same_chord(a: Dictionary, b: Dictionary) -> bool:
	for key in ["keycode", "ctrl", "shift", "alt", "meta"]:
		var default_value: Variant = 0 if key == "keycode" else false
		if a.get(key, default_value) != b.get(key, default_value):
			return false
	return true


# ===========================================================================
# Shared dispatch
# ===========================================================================


func test_transform_actions_require_an_existing_level():
	for action in TRANSFORM_ACTIONS:
		assert_true(
			HFPluginCommands.requires_existing_root(action),
			"%s changes scene content, so it must not create a level as a side effect" % action
		)


func test_shared_dispatch_routes_every_transform_action():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_commands.gd")
	for pair in [
		['"rotate_ccw":', "plugin._rotate_selected(root, 1)"],
		['"rotate_cw":', "plugin._rotate_selected(root, -1)"],
		['"flip_selection":', "plugin._flip_selected(root)"],
		['"reset_rotation":', "plugin._reset_rotation_selected(root)"],
	]:
		assert_true(source.contains(pair[0]), "%s must be dispatched" % pair[0])
		assert_true(source.contains(pair[1]), "%s must be called" % pair[1])


func test_plugin_transform_callbacks_are_thin_delegates():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for method_name in ["rotate_selected", "flip_selected", "reset_rotation_selected"]:
		assert_true(
			source.contains("HFPluginEditActions.%s" % method_name),
			"plugin.gd must delegate %s to the edit-action module" % method_name
		)


# ===========================================================================
# Undo boundary
# ===========================================================================


func test_level_root_exposes_the_methods_undo_dispatches_by_name():
	# HFUndoHelper resolves these with has_method() and silently does nothing when
	# the lookup fails, so a rename here would cost the whole undo entry.
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	for method_name in [
		"rotate_managed_nodes",
		"flip_managed_nodes",
		"reset_managed_rotation",
		"create_radial_array",
		"create_grid_array",
		"resolve_transform_pivot",
		"transform_axis_index",
		"can_flip_brushes",
	]:
		assert_true(root.has_method(method_name), "LevelRoot must expose %s" % method_name)


func test_transform_undo_methods_stay_within_the_helper_argument_limit():
	# HFUndoHelper falls back to a direct, non-undoable call past five arguments.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/level_root.gd")
	for method_name in ["rotate_managed_nodes", "flip_managed_nodes", "reset_managed_rotation"]:
		var start := source.find("func %s(" % method_name)
		assert_gt(start, -1, "%s must exist" % method_name)
		var finish := source.find(") -> void:", start)
		var signature := source.substr(start, finish - start)
		assert_lt(
			signature.count(",") + 1,
			6,
			"%s would drop off the undoable path with six arguments" % method_name
		)


func test_edit_actions_commit_through_the_undo_helper():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_edit_actions.gd")
	for pair in [
		["rotate_selected", '"rotate_managed_nodes"'],
		["flip_selected", '"flip_managed_nodes"'],
		["reset_rotation_selected", '"reset_managed_rotation"'],
	]:
		var start := source.find("static func %s" % pair[0])
		assert_gt(start, -1, "%s must exist" % pair[0])
		var body := source.substr(start, 1200)
		assert_true(body.contains("HFUndoHelper.commit"), "%s must be undoable" % pair[0])
		assert_true(body.contains(pair[1]), "%s must name its LevelRoot method" % pair[0])


func test_flip_asks_permission_before_committing():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_edit_actions.gd")
	var start := source.find("static func flip_selected")
	var body := source.substr(start, 1200)
	assert_lt(
		body.find("can_flip_brushes"),
		body.find("HFUndoHelper.commit"),
		"the displacement check must run before the undo entry is created"
	)
	assert_true(body.contains("user_message.emit"), "a refusal must reach the user")


# ===========================================================================
# Viewport input ladder
# ===========================================================================


func test_the_transform_group_is_gated_on_paint_mode():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_input_router.gd")
	var paint_block := source.find('keymap.matches("paint_ramp", event)')
	var transform_block := source.find('keymap.matches("rotate_ccw", event)')
	assert_gt(paint_block, -1, "paint_ramp dispatch must still exist")
	assert_gt(transform_block, -1, "rotate_ccw dispatch must exist")
	assert_lt(
		paint_block, transform_block, "R must reach the ramp tool first while paint mode is active"
	)
	assert_true(
		source.contains("if not paint_mode:"),
		"the transform group must be skipped entirely in paint mode"
	)


func test_every_transform_shortcut_asks_the_selection_guard_first():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_input_router.gd")
	for pair in [
		['keymap.matches("rotate_ccw", event)', "plugin._rotate_selected(root, 1)"],
		['keymap.matches("rotate_cw", event)', "plugin._rotate_selected(root, -1)"],
		['keymap.matches("flip_selection", event)', "plugin._flip_selected(root)"],
		['keymap.matches("reset_rotation", event)', "plugin._reset_rotation_selected(root)"],
	]:
		var start := source.find(pair[0])
		assert_gt(start, -1, "%s must be handled" % pair[0])
		var block := source.substr(start, 400)
		var guard := block.find("_guard_hammerforge_shortcut")
		var command := block.find(pair[1])
		assert_gt(guard, -1, "%s must consult the selection guard" % pair[0])
		assert_lt(guard, command, "the guard must be asked before the command runs")


# ===========================================================================
# Menus and toolbars
# ===========================================================================


func test_the_viewport_context_menu_offers_every_transform_action():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/hf_viewport_context_menu.gd"
	)
	for action in TRANSFORM_ACTIONS:
		assert_true(source.contains('action = "%s"' % action), "%s must be reachable" % action)
	for label in ["Rotate CCW", "Rotate CW", "Flip", "Reset Rotation"]:
		assert_true(source.contains('add_item("%s"' % label), "%s must be listed" % label)


func test_context_menu_transform_ids_are_unique():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/hf_viewport_context_menu.gd"
	)
	var seen := {}
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const _ID_"):
			continue
		var value := trimmed.get_slice(":=", 1).strip_edges()
		assert_false(seen.has(value), "menu id %s is used twice" % value)
		seen[value] = true


func test_the_context_toolbar_offers_every_transform_action():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/hf_context_toolbar.gd")
	for action in TRANSFORM_ACTIONS:
		assert_true(source.contains('"%s"' % action), "%s must have a toolbar button" % action)
	assert_true(source.contains('_add_group_label(section, "Transform")'))


# ===========================================================================
# Dock
# ===========================================================================


func test_the_dock_reaches_the_same_level_root_methods():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	for method_name in [
		'"rotate_managed_nodes"',
		'"flip_managed_nodes"',
		'"reset_managed_rotation"',
		'"create_radial_array"',
		'"create_grid_array"',
	]:
		assert_true(source.contains(method_name), "the dock must reach %s" % method_name)


func test_the_dock_transform_controls_are_connected():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/selection_tools_builder.gd"
	)
	for connection in [
		"dock._on_rotate_selection.bind(1)",
		"dock._on_rotate_selection.bind(-1)",
		"dock._on_flip_selection",
		"dock._on_reset_rotation",
		"dock._on_duplicate_array_mode_changed",
		"dock._on_rotate_snap_changed",
		"dock._on_transform_pivot_changed",
	]:
		assert_true(source.contains(connection), "%s must be wired" % connection)


func test_the_dock_reflects_saved_transform_settings():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	for property in ["rotate_snap_degrees", "transform_pivot_mode"]:
		assert_true(
			source.contains('_root_has_property("%s")' % property),
			"%s must be read back onto the dock when a level connects" % property
		)


# ===========================================================================
# Settings persistence
# ===========================================================================


func test_transform_settings_travel_with_the_level_not_the_undo_snapshot():
	# `rotate_snap_degrees` and `transform_pivot_mode` are editor settings, so they
	# belong in the settings bundle that goes into the .hflevel file — the same
	# place `texture_lock` lives — and not in the per-action undo snapshot.
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.rotate_snap_degrees = 45.0
	root.transform_pivot_mode = 2
	var bundle: Dictionary = root.capture_full_state()
	var settings: Dictionary = bundle.get("settings", {})
	assert_true(settings.has("rotate_snap_degrees"), "the rotate step must be saved with the level")
	assert_true(settings.has("transform_pivot_mode"), "the pivot mode must be saved with the level")
	assert_true(settings.has("texture_lock"), "the reference setting must still be there")
	root.rotate_snap_degrees = 15.0
	root.transform_pivot_mode = 0
	root.restore_full_state(bundle)
	assert_almost_eq(root.rotate_snap_degrees, 45.0, 0.001)
	assert_eq(root.transform_pivot_mode, 2)


func test_the_transform_subsystem_is_built_with_the_other_editor_systems():
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	assert_not_null(root.transform_system, "LevelRoot must construct the transform system")


func test_pivot_modes_are_named_the_same_way_everywhere():
	# The dock stores the OptionButton index straight into transform_pivot_mode,
	# so the option order and the enum have to agree.
	assert_eq(HFTransformSystemScript.PivotMode.SELECTION_CENTER, 0)
	assert_eq(HFTransformSystemScript.PivotMode.WORLD_ORIGIN, 1)
	assert_eq(HFTransformSystemScript.PivotMode.ACTIVE, 2)
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/selection_tools_builder.gd"
	)
	var start := source.find("transform_pivot_opt = HFUIFactoryType.make_option")
	assert_gt(start, -1, "the pivot picker must exist")
	var block := source.substr(start, 200)
	assert_lt(block.find('"Selection"'), block.find('"World Origin"'))
	assert_lt(block.find('"World Origin"'), block.find('"Active"'))
