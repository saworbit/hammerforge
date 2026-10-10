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
	var toasts: Array = []

	func show_toast(message: String, level: int = 0) -> void:
		toasts.append({"message": message, "level": level})

	func _commit_bake_profile(action_name: String, before: Dictionary) -> void:
		HFDockManageHandler.record_bake_profile(fake_undo, level_root, action_name, before)


## Where these tests keep the project's shared profiles, in place of the
## project's own hammerforge_presets folder.
const PROJECT_DIR := "user://hf_test_bake_profile_project"

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
	_clear_project_file()
	dock.presets_dir = PROJECT_DIR
	add_child_autoqfree(dock)
	dock.set_user_prefs(prefs)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()


func after_each():
	_clear_project_file()
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


func _project_file() -> String:
	return PROJECT_DIR.path_join(HFBakeProfiles.PROJECT_FILE)


func _clear_project_file() -> void:
	if FileAccess.file_exists(_project_file()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_project_file()))


## Put `profiles` in the project's file, as a pull from a teammate would.
func _pull(profiles: Dictionary) -> void:
	assert_true(HFBakeProfiles.write_project(profiles, _project_file()), "fixture: the file")
	HFDockManageHandler.sync_bake_profile_ui(dock)


func _listed() -> PackedStringArray:
	var opt: OptionButton = dock.bake_profile_opt
	var out := PackedStringArray()
	for index in opt.item_count:
		out.append(opt.get_item_text(index))
	return out


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

	# Values between spin steps are displayed rounded but must remain exact on
	# the level when the dock binds again.
	root.bake_navmesh_cell_height = 0.125
	root.bake_navmesh_agent_radius = 0.33
	dock._connect_root_signals()
	assert_eq(root.bake_navmesh_cell_height, 0.125)
	assert_eq(root.bake_navmesh_agent_radius, 0.33)


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


# ---------------------------------------------------------------------------
# Export Game Scene says which options it baked with (#981)
# ---------------------------------------------------------------------------

## Where the export lands: beside a scene under .godot, which git ignores.
const EXPORT_PROBE := "res://.godot/hf_export_profile_probe.tscn"


func _export_game_scene() -> Dictionary:
	root.create_brush_from_info({"size": Vector3(4, 1, 4)})
	root.scene_file_path = EXPORT_PROBE
	await HFDockManageHandler.on_export_game_scene(dock)
	var written := EXPORT_PROBE.get_basename() + "_game.tscn"
	assert_true(FileAccess.file_exists(written), "fixture: the scene was written")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
	return dock.toasts[-1] if not dock.toasts.is_empty() else {}


func _export_with(profile: String) -> void:
	var opt: OptionButton = dock.export_profile_opt
	for index in opt.item_count:
		if opt.get_item_text(index) == profile:
			opt.select(index)
			return
	fail_test("no %s under Export with" % profile)


func test_exporting_on_the_editing_options_warns():
	# A level being worked on sits on Editing, and the export shipped it that way
	# without a word.
	assert_eq(_shown(), HFBakeProfiles.EDITING, "fixture: a new level is on Editing")
	_export_with(HFDockManageHandler.LEVEL_OWN_OPTIONS)
	var toast: Dictionary = await _export_game_scene()
	assert_eq(toast.get("level"), 1, "a warning: %s" % toast)
	assert_string_contains(str(toast.get("message")), "Editing")
	assert_string_contains(str(toast.get("message")), "Shipping")


func test_exporting_names_the_profile_it_baked_with():
	root.apply_bake_options(HFBakeProfiles.built_in(HFBakeProfiles.SHIPPING))
	var toast: Dictionary = await _export_game_scene()
	assert_eq(toast.get("level"), 0, "nothing to warn about: %s" % toast)
	assert_string_contains(str(toast.get("message")), "Shipping bake options")


func test_exporting_on_hand_set_options_calls_them_custom():
	root.bake_merge_meshes = true
	_export_with(HFDockManageHandler.LEVEL_OWN_OPTIONS)
	var toast: Dictionary = await _export_game_scene()
	assert_eq(toast.get("level"), 0, "%s" % toast)
	assert_string_contains(str(toast.get("message")), "Custom bake options")


# ---------------------------------------------------------------------------
# Export with: the export's own profile, and the level's put back (#1003)
#
# Shipping a level on Editing meant picking Shipping, exporting and picking
# Editing again: two undo steps and two full bakes, and forgetting the second
# left the level on the slower bake.
# ---------------------------------------------------------------------------


func test_export_with_starts_on_shipping_and_lists_every_profile():
	_save_as("Mine")
	var opt: OptionButton = dock.export_profile_opt
	assert_eq(opt.get_item_text(opt.selected), HFBakeProfiles.SHIPPING)
	var listed := PackedStringArray()
	for index in opt.item_count:
		listed.append(opt.get_item_text(index))
	var expected := PackedStringArray([HFDockManageHandler.LEVEL_OWN_OPTIONS, "Editing"])
	expected.append_array(PackedStringArray(["Shipping", "Mine"]))
	assert_eq(listed, expected)


func test_exporting_with_shipping_bakes_on_shipping_and_puts_editing_back():
	assert_eq(_shown(), HFBakeProfiles.EDITING, "fixture: a new level is on Editing")
	var before: Dictionary = root.capture_bake_options()
	var baked_on: Array = []
	root.bake_started.connect(func(): baked_on.append(HFBakeProfiles.current(root, {})))
	var toast: Dictionary = await _export_game_scene()
	assert_eq(baked_on, [HFBakeProfiles.SHIPPING], "the export baked on Shipping")
	assert_eq(root.capture_bake_options(), before, "and the level's options came back")
	assert_eq(_shown(), HFBakeProfiles.EDITING, "the list says so")
	assert_eq(undo.entries, [], "with no undo step")
	assert_eq(toast.get("level"), 0, "%s" % toast)
	assert_string_contains(str(toast.get("message")), "Shipping bake options")


## A level whose bake fails, for the export's failure path.
class FailingBakeLevel:
	extends LevelRoot

	func bake(
		_apply_cuts: bool = true,
		_hide_live: bool = false,
		_collision_layer_mask: int = 0,
		_preview_mode: int = 0,
		_force_csg: bool = false
	) -> bool:
		return false


func test_a_failed_export_puts_the_level_options_back_too():
	var failing := FailingBakeLevel.new()
	failing.auto_spawn_player = false
	failing.hflevel_autosave_enabled = false
	add_child_autoqfree(failing)
	dock.level_root = failing
	var before: Dictionary = failing.capture_bake_options()
	await HFDockManageHandler.on_export_game_scene(dock)
	var last: Dictionary = dock.toasts[-1]
	assert_eq(
		last.get("message"),
		"Export cancelled because the level could not be baked",
		"fixture: the bake failed"
	)
	assert_eq(failing.capture_bake_options(), before, "the level's options came back")
	assert_eq(undo.entries, [], "with no undo step")


## A real bake takes minutes, and the Profile list and the options stayed live.
## A profile picked then was put back by the export, and its undo step put the
## export's options on the level (#1011).
func test_a_profile_cannot_be_picked_while_export_bakes_on_its_own():
	root.apply_bake_options({"bake_navmesh": true})
	_save_as("Mine")
	root.apply_bake_options({"bake_navmesh": false})
	assert_eq(_shown(), HFBakeProfiles.EDITING, "fixture: the level is on Editing")
	var before: Dictionary = root.capture_bake_options()
	var during: Array = []
	root.bake_started.connect(
		func():
			_pick("Mine")
			during.append(
				HFBakeProfiles.current(root, HFDockManageHandler.saved_bake_profiles(dock))
			)
	)
	await _export_game_scene()
	assert_eq(during, [HFBakeProfiles.SHIPPING], "the bake stays on the export's profile")
	assert_eq(root.capture_bake_options(), before, "the level's options came back")
	assert_eq(undo.entries, [], "with no undo step that puts Shipping back on")
	assert_true(_said_options_held(), "and the dock says why: %s" % [dock.toasts])


func test_an_option_cannot_be_ticked_while_export_bakes_on_its_own():
	var before: Dictionary = root.capture_bake_options()
	var during: Array = []
	root.bake_started.connect(
		func():
			dock.bake_navmesh.button_pressed = true
			during.append([root.bake_navmesh, dock.bake_navmesh.button_pressed])
	)
	await _export_game_scene()
	assert_eq(during, [[false, false]], "the tick does not reach the bake, and the box says so")
	assert_eq(root.capture_bake_options(), before, "the level's options came back")
	assert_true(_said_options_held(), "and the dock says why: %s" % [dock.toasts])


func test_options_stay_live_while_export_bakes_on_the_levels_own():
	_export_with(HFDockManageHandler.LEVEL_OWN_OPTIONS)
	root.bake_started.connect(func(): dock.bake_navmesh.button_pressed = true)
	await _export_game_scene()
	assert_true(root.bake_navmesh, "nothing is put back, so nothing is held")
	assert_false(_said_options_held())


## An export whose level went away mid bake never comes back to let go.
func test_an_export_that_never_finished_holds_nothing():
	dock._export_baking_level = root
	assert_false(root.is_bake_in_flight(), "fixture: nothing is baking")
	dock.bake_navmesh.button_pressed = true
	assert_true(root.bake_navmesh, "the tick reaches the level")
	assert_false(_said_options_held())


func _said_options_held() -> bool:
	for toast in dock.toasts:
		if str(toast.get("message", "")).contains("when the export finishes"):
			return true
	return false


func test_a_picked_profile_stays_picked_after_a_resync():
	_export_with(HFBakeProfiles.EDITING)
	root.settings_applied.emit()
	assert_eq(HFDockManageHandler.export_profile_name(dock), HFBakeProfiles.EDITING)


# ---------------------------------------------------------------------------
# Profiles the project keeps, for the whole team (#980)
# ---------------------------------------------------------------------------


func test_a_profile_in_the_project_is_listed_and_applies_with_no_other_step():
	# A fresh clone: nothing in this machine's preferences.
	_pull({"Studio": {"bake_merge_meshes": true, "bake_navmesh": true}})
	assert_true("Studio (project)" in _listed(), "listed, marked as the project's: %s" % _listed())
	_pick("Studio (project)")
	assert_true(root.bake_merge_meshes, "it sets its options")
	assert_true(root.bake_navmesh)
	assert_eq(_shown(), "Studio (project)", "and the level reads as it")
	assert_true(dock.bake_profile_project_check.button_pressed, "Save would update the project's")


func test_a_bad_value_in_the_project_file_is_dropped_and_the_rest_kept():
	var path := _project_file()
	assert_true(
		HFBakeProfiles.write_project(
			{"Studio": {"bake_merge_meshes": "yes", "bake_generate_lods": true}}, path
		)
	)
	var read := HFBakeProfiles.read_project(root, path)
	assert_eq(read, {"Studio": {"bake_generate_lods": true}}, "the string is not a bool")


func test_a_file_that_is_not_a_profiles_file_is_none():
	var file := FileAccess.open(_project_file(), FileAccess.WRITE)
	file.store_string("[1, 2, 3]")
	file.close()
	assert_eq(HFBakeProfiles.read_project(root, _project_file()), {})


func test_the_project_keeps_a_name_both_hold():
	prefs.set_bake_profile("Studio", {"bake_merge_meshes": true})
	_pull({"Studio": {"bake_generate_lods": true}})
	var all := HFDockManageHandler.saved_bake_profiles(dock)
	assert_eq(all.get("Studio"), {"bake_generate_lods": true}, "the team's one, not the copy")
	assert_false("Studio" in _listed(), "and the copy is not listed beside it")


func test_saving_to_the_project_writes_the_file_and_drops_this_machines_copy():
	_save_as("Studio")
	assert_true(prefs.get_bake_profiles().has("Studio"), "fixture: kept on this machine")
	dock.bake_profile_project_check.button_pressed = true
	_save_as("Studio")
	var in_file := HFBakeProfiles.read_project_raw(_project_file())
	assert_true(in_file.has("Studio"), "written into the project's file")
	assert_false(prefs.get_bake_profiles().has("Studio"), "the copy here would be hidden now")
	assert_eq(_shown(), "Studio (project)")


func test_saving_here_will_not_shadow_a_project_profile():
	_pull({"Studio": {"bake_generate_lods": true}})
	dock.bake_profile_project_check.button_pressed = false
	_save_as("Studio")
	assert_true(dock.bake_profile_save_btn.disabled, "Save says to tick Project")
	assert_false(prefs.get_bake_profiles().has("Studio"), "and keeps nothing on this machine")


func test_deleting_a_project_profile_takes_two_presses_and_edits_the_file():
	_pull({"Studio": {"bake_generate_lods": true}, "Arena": {"bake_navmesh": true}})
	dock.bake_profile_name.text = "Studio"
	dock.bake_profile_name.text_changed.emit("Studio")
	dock.bake_profile_delete_btn.pressed.emit()
	assert_true(HFBakeProfiles.read_project_raw(_project_file()).has("Studio"), "first warns")
	dock.bake_profile_delete_btn.pressed.emit()
	var left := HFBakeProfiles.read_project_raw(_project_file())
	assert_false(left.has("Studio"), "the second takes it out of the file")
	assert_true(left.has("Arena"), "and only it")


## A project file a merge left conflict markers in.
const CONFLICTED := (
	"<<<<<<< HEAD\n"
	+ '{"version": 1, "profiles": {"Studio": {"bake_merge_meshes": true}}}\n'
	+ "=======\n"
	+ '{"version": 1, "profiles": {"Arena": {"bake_navmesh": true}}}\n'
	+ ">>>>>>> feature\n"
)


func _leave_a_conflict() -> void:
	var file := FileAccess.open(_project_file(), FileAccess.WRITE)
	file.store_string(CONFLICTED)
	file.close()


func test_save_will_not_write_over_a_project_file_it_cannot_read():
	# Save read the file as no profiles and wrote the one it was saving over
	# every shared one, and the toast said saved (#1006).
	_pull({"Studio": {"bake_generate_lods": true}})
	_leave_a_conflict()
	dock.bake_profile_project_check.button_pressed = true
	_save_as("Quick")
	assert_eq(FileAccess.get_file_as_string(_project_file()), CONFLICTED, "the file is as it was")
	assert_string_contains(dock.status_label.text, "could not be read")


func test_delete_will_not_write_over_a_project_file_it_cannot_read():
	_pull({"Studio": {"bake_generate_lods": true}, "Arena": {"bake_navmesh": true}})
	dock.bake_profile_name.text = "Studio"
	dock.bake_profile_name.text_changed.emit("Studio")
	dock.bake_profile_delete_btn.pressed.emit()
	_leave_a_conflict()
	dock.bake_profile_delete_btn.pressed.emit()
	assert_eq(FileAccess.get_file_as_string(_project_file()), CONFLICTED, "the file is as it was")


func test_a_project_file_that_reads_is_not_unreadable():
	assert_false(HFBakeProfiles.project_file_unreadable(_project_file()), "a missing file is none")
	_pull({"Studio": {"bake_generate_lods": true}})
	assert_false(HFBakeProfiles.project_file_unreadable(_project_file()))
	_leave_a_conflict()
	assert_true(HFBakeProfiles.project_file_unreadable(_project_file()))


func test_writing_keeps_a_profile_this_machine_cannot_read():
	# A teammate on a newer HammerForge saved an option this one does not have.
	_pull({"Future": {"bake_something_new": 3}})
	dock.bake_profile_project_check.button_pressed = true
	_save_as("Studio")
	var in_file := HFBakeProfiles.read_project_raw(_project_file())
	assert_true(in_file.has("Future"), "left in the file for the people who can read it")
	assert_true(in_file.has("Studio"))
