extends GutTest

## What a `.hfsettings` file is allowed to do to a level.
##
## Import Settings pushes a parsed dictionary through the dock's controls and on
## to the LevelRoot. Three things can go wrong on that path and all three used
## to: a value that is not a number becomes 0 at the cast, a value outside a
## control's range reaches the level anyway, and a dropdown moves without
## anything writing what it now says.

const DockScene = preload("res://addons/hammerforge/dock.tscn")


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


## The dock wired to a root the way the plugin wires it. `_connect_root_signals()`
## is what fills `root_properties`, and every write to the level is guarded by it,
## so a dock that only has `level_root` set silently writes nothing.
func _dock(root: LevelRoot) -> Node:
	var dock := DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	return dock


# ---------------------------------------------------------------------------
# The two enum settings #373 missed (#480)
# ---------------------------------------------------------------------------


func test_both_bake_mode_settings_clamp_to_the_modes_that_exist() -> void:
	var root := _fresh_root()
	# @export_range is an inspector hint. It does not clamp an assignment from
	# code, from a .hflevel settings block or from a settings import, and both of
	# these are read as a mode at bake time.
	root.bake_collision_mode = 99
	assert_eq(root.bake_collision_mode, 2, "a collision mode above the range is the last mode")
	root.bake_collision_mode = -7
	assert_eq(root.bake_collision_mode, 0, "and below it is the first")
	root.bake_connector_mode = 99
	assert_eq(root.bake_connector_mode, 2, "a connector mode above the range is the last mode")
	root.bake_connector_mode = -7
	assert_eq(root.bake_connector_mode, 0, "and below it is the first")


func test_a_poisoned_hflevel_settings_block_cannot_set_a_mode_that_does_not_exist() -> void:
	var root := _fresh_root()
	root.state_system.apply_hflevel_settings({"bake_collision_mode": 99, "bake_connector_mode": -7})
	assert_between(root.bake_collision_mode, 0, 2, "collision mode is a mode after a file load")
	assert_between(root.bake_connector_mode, 0, 2, "connector mode is a mode after a file load")


# ---------------------------------------------------------------------------
# Chunk size: the spin's own minimum (#481)
# ---------------------------------------------------------------------------


func test_a_chunk_size_of_zero_is_the_off_the_bake_already_understands() -> void:
	var root := _fresh_root()
	# bake() reads `if root.bake_chunk_size > 0.0`, and the dock spin's range
	# starts at 0. Clamping 0 up to 1 gave the mapper the opposite of the control
	# they had just turned all the way down.
	root.bake_chunk_size = 0.0
	assert_eq(root.bake_chunk_size, 0.0, "0 is off, not the smallest chunk")
	root.bake_chunk_size = 0.25
	assert_eq(
		root.bake_chunk_size,
		LevelRoot.MIN_BAKE_CHUNK_SIZE,
		"a size below the minimum is still a size, so it floors"
	)
	root.bake_chunk_size = 64.0
	assert_eq(root.bake_chunk_size, 64.0, "an ordinary size is untouched")


func test_the_chunk_size_spin_and_the_level_agree_at_both_ends_of_its_range() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	if not dock.bake_chunk_size_spin:
		pass_test("no chunk size spin on this build")
		return
	var spin: SpinBox = dock.bake_chunk_size_spin
	for value in [spin.min_value, 32.0, spin.max_value]:
		spin.value = value
		root.bake_chunk_size = spin.value
		assert_eq(
			root.bake_chunk_size,
			spin.value,
			"the spin reading %s must be the chunking the level does" % str(spin.value)
		)


# ---------------------------------------------------------------------------
# Import Settings (#477, #478)
# ---------------------------------------------------------------------------


func test_select_alone_does_not_notify_so_the_import_has_to() -> void:
	# The behaviour the connector-mode bug rests on, pinned here because the
	# OptionButton page does not state it: item_selected is documented as emitted
	# when the item is changed by the user.
	var option := OptionButton.new()
	add_child_autoqfree(option)
	option.add_item("Ramp", 0)
	option.add_item("Stairs", 1)
	option.add_item("Auto", 2)
	var seen: Array = []
	option.item_selected.connect(func(index: int) -> void: seen.append(index))
	option.select(2)
	assert_eq(option.selected, 2, "select moves the dropdown")
	assert_eq(seen, [], "and tells nobody, which is why the import cannot rely on it")


func test_importing_a_connector_mode_writes_it_to_the_level() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	if not dock.bake_connector_mode_opt:
		pass_test("no connector mode dropdown on this build")
		return
	root.bake_connector_mode = 0
	dock._apply_editor_settings({"bake": {"connector_mode": 2}})
	assert_eq(dock.bake_connector_mode_opt.selected, 2, "the dropdown shows the imported mode")
	assert_eq(root.bake_connector_mode, 2, "and the level bakes the mode the dropdown is showing")


func test_an_out_of_range_grid_snap_leaves_the_dock_and_the_level_saying_the_same_thing() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	dock._apply_editor_settings({"grid_snap": 4096.0})
	assert_eq(
		root.grid_snap,
		dock.grid_snap.value,
		"the level must snap to what the dock is showing, not to the number in the file"
	)
	assert_lte(root.grid_snap, dock.grid_snap.max_value, "and not past the control's own range")


func test_a_setting_that_is_not_a_number_keeps_the_one_in_force() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	dock._apply_grid_snap(16.0)
	var before: float = root.grid_snap
	# float("sixteen") is 0.0 in GDScript, so this used to turn snapping off and
	# say nothing about it.
	dock._apply_editor_settings({"grid_snap": "sixteen"})
	assert_eq(root.grid_snap, before, "a word is not a snap, so the snap does not change")
	assert_gt(root.grid_snap, 0.0, "and snapping is certainly not switched off")


func test_a_setting_of_the_wrong_container_type_does_not_abort_the_import() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	# int({}) raises at the cast, which took the rest of the block with it.
	dock._apply_editor_settings(
		{"bake": {"connector_width": {}, "navmesh": true, "occluder_min_area": 12.0}}
	)
	assert_true(
		dock.bake_navmesh.button_pressed if dock.bake_navmesh else true,
		"a bad value earlier in the block must not stop the ones after it landing"
	)
	if dock.bake_occluder_min_area_spin:
		assert_eq(
			dock.bake_occluder_min_area_spin.value,
			12.0,
			"the settings after the bad one are still applied"
		)
