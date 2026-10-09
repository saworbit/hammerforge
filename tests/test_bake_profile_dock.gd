extends GutTest

## The bake profile row in Test > Advanced Bake.
##
## Picking a profile sets the bake options as one undo step and the checkboxes
## follow. The list always says which profile the level is on, or Custom once an
## option has been changed by hand. Save keeps the options under a name and
## Delete takes two presses, because a saved profile is not on the undo stack.
##
## Each test drives the real dock and its real handlers. Only where the undo step
## lands is swapped, as in `test_cordon_undo.gd`: an `EditorUndoRedoManager`
## cannot be built outside the editor.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const CollationTests = preload("res://tests/test_undo_collation.gd")


## The dock, with its profile steps going to the stand-in.
class DockWithUndo:
	extends "res://addons/hammerforge/dock.gd"

	var fake_undo = null

	func _commit_bake_profile(action_name: String, before: Dictionary) -> void:
		HFDockManageHandler.record_bake_profile(fake_undo, level_root, action_name, before)


var root: LevelRoot
var dock: Node
var prefs: HFUserPrefs
var undo


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	undo = CollationTests.FakeUndoRedo.new()
	prefs = HFUserPrefs.new()
	prefs.persistence_enabled = false
	dock = DockScene.instantiate()
	dock.set_script(DockWithUndo)
	dock.fake_undo = undo
	add_child_autoqfree(dock)
	dock.set_user_prefs(prefs)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()


func after_each():
	dock = null
	root = null
	prefs = null
	undo = null


func _shown() -> String:
	var opt: OptionButton = dock.bake_profile_opt
	return opt.get_item_text(opt.selected) if opt.selected >= 0 else ""


func _pick(profile: String) -> void:
	var opt: OptionButton = dock.bake_profile_opt
	for index in opt.item_count:
		if opt.get_item_text(index) == profile:
			dock._select_option_notifying(opt, index)
			return
	fail_test("%s is not in the list" % profile)


func _save_as(profile: String) -> void:
	dock.bake_profile_name.text = profile
	dock.bake_profile_name.text_changed.emit(profile)
	dock.bake_profile_save_btn.pressed.emit()


func test_a_new_level_shows_editing():
	assert_eq(_shown(), "Editing")


func test_picking_shipping_sets_the_options_and_the_checkboxes_follow():
	_pick("Shipping")
	assert_true(root.bake_merge_meshes, "the level has the profile's options")
	assert_true(root.bake_generate_lods)
	assert_true(dock.bake_merge_meshes.button_pressed, "and the dock shows them")
	assert_true(dock.bake_generate_lods.button_pressed)
	assert_eq(_shown(), "Shipping")


func test_a_switch_is_one_undo_step():
	var before: Dictionary = root.capture_bake_options()
	_pick("Shipping")
	assert_eq(undo.entries.size(), 1, "one step for every option it set")
	if undo.entries.size() != 1:
		return
	assert_eq(undo.entries[0]["name"], "Bake Profile: Shipping")
	var after: Dictionary = root.capture_bake_options()

	root._full_reconcile_needed = false
	undo.undo()
	assert_eq(root.capture_bake_options(), before, "undo puts every option back")
	assert_true(root._full_reconcile_needed, "and the next bake rebuilds")
	assert_false(dock.bake_merge_meshes.button_pressed, "the checkboxes follow the undo")
	assert_eq(_shown(), "Editing", "and so does the list")

	undo.redo()
	assert_eq(root.capture_bake_options(), after)
	assert_eq(_shown(), "Shipping")


func test_picking_the_profile_the_level_is_on_adds_no_step():
	root._full_reconcile_needed = false
	_pick("Editing")
	assert_eq(undo.entries.size(), 0, "nothing changed, so there is nothing to undo")
	assert_false(root._full_reconcile_needed, "and the last bake is still the level's")


func test_an_option_changed_by_hand_shows_custom():
	_pick("Shipping")
	dock.bake_generate_lods.button_pressed = false
	assert_false(root.bake_generate_lods, "fixture: the checkbox reached the level")
	assert_eq(_shown(), "Custom", "the level is on neither profile now")


func test_save_keeps_the_options_under_a_name():
	dock.bake_navmesh.button_pressed = true
	_save_as("Arena")
	var saved: Dictionary = prefs.get_bake_profiles()
	assert_true(saved.has("Arena"), "kept in the preferences")
	if not saved.has("Arena"):
		return
	assert_eq(saved["Arena"], root.capture_bake_options(), "every option a profile carries")
	assert_eq(_shown(), "Arena", "and the level reads as it")


func test_picking_a_saved_profile_sets_it_and_names_it_for_save_and_delete():
	dock.bake_navmesh.button_pressed = true
	_save_as("Arena")
	_pick("Shipping")
	dock.bake_profile_name.text = ""
	_pick("Arena")
	assert_false(root.bake_merge_meshes, "Arena was saved with merging off")
	assert_true(root.bake_navmesh)
	assert_eq(dock.bake_profile_name.text, "Arena", "Save and Delete now mean Arena")


func test_save_refuses_a_built_in_name():
	_save_as("shipping")
	assert_true(prefs.get_bake_profiles().is_empty(), "Shipping means the built in one")
	assert_true(dock.bake_profile_save_btn.disabled, "and Save says so before it is pressed")


func test_delete_takes_two_presses():
	_save_as("Arena")
	assert_false(dock.bake_profile_delete_btn.disabled, "fixture: the name is a saved profile")
	dock.bake_profile_delete_btn.pressed.emit()
	assert_true(prefs.get_bake_profiles().has("Arena"), "the first press only warns")
	dock.bake_profile_delete_btn.pressed.emit()
	assert_false(prefs.get_bake_profiles().has("Arena"), "the second deletes")
	assert_eq(_shown(), "Editing", "and the list no longer offers it")


func test_a_built_in_cannot_be_deleted():
	dock.bake_profile_name.text = "Shipping"
	dock.bake_profile_name.text_changed.emit("Shipping")
	assert_true(dock.bake_profile_delete_btn.disabled)


func test_the_face_materials_checkbox_follows_the_level():
	# It was never read back from the level, so the next reconnect wrote the stale
	# tick over whatever a load or a profile had set.
	root.bake_use_face_materials = false
	root.settings_applied.emit()
	assert_false(dock.bake_use_face_materials.button_pressed)


func test_binding_the_dock_leaves_the_level_options_as_they_were():
	# The dock reads the level into its controls and then writes its controls
	# back. The stair threshold spin could not show 2.0, so every level it bound
	# to came away with 2.01, and read as no profile at all.
	var untouched := LevelRoot.new()
	untouched.auto_spawn_player = false
	untouched.hflevel_autosave_enabled = false
	add_child_autoqfree(untouched)
	var bound: Dictionary = root.capture_bake_options()
	var expected: Dictionary = untouched.capture_bake_options()
	for name in expected:
		# A spin's arithmetic can move a float by its last bit, which is no change.
		if expected[name] is float:
			assert_almost_eq(bound[name], expected[name], 0.000001, "%s as it was" % name)
		else:
			assert_eq(bound[name], expected[name], "%s as it was" % name)


func test_a_resync_writes_nothing_back():
	# Between two of the spin's steps: the spin shows the nearer one.
	root.bake_navmesh_cell_height = 0.125
	root.settings_applied.emit()
	assert_eq(root.bake_navmesh_cell_height, 0.125, "showing a value is not setting it")


func test_a_saved_profile_with_a_value_between_spin_steps_reads_as_itself():
	root.bake_navmesh_cell_height = 0.125
	prefs.set_bake_profile("Fine", root.capture_bake_options())
	root.bake_navmesh_cell_height = 0.3
	root.settings_applied.emit()
	_pick("Fine")
	assert_eq(root.bake_navmesh_cell_height, 0.125)
	assert_eq(_shown(), "Fine", "not Custom the moment it was picked")


func test_agent_climb_slope_and_stair_threshold_reach_the_level():
	# Their spins were built and read back but never wired, so an edit to them
	# did nothing until the dock next bound to a level.
	dock.bake_navmesh_agent_max_climb.value = 0.5
	dock.bake_navmesh_agent_max_slope.value = 30.0
	dock.bake_connector_stair_threshold_spin.value = 1.5
	assert_almost_eq(root.bake_navmesh_agent_max_climb, 0.5, 0.001)
	assert_almost_eq(root.bake_navmesh_agent_max_slope, 30.0, 0.001)
	assert_almost_eq(root.bake_connector_stair_threshold, 1.5, 0.001)
