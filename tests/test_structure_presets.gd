extends GutTest

## Structure presets: a type's settings kept under a name in the project, and put
## back in the fields with one pick (#1415).
##
## The file is read through the builder's schema, so these pin what that buys: a
## round trip gives back what was saved, a key the builder does not have is
## dropped, and a value out of range is refused by name with every field left as
## it was. The dock half drives a real dock and LevelRoot, and checks that a pick
## fills the fields and redraws the ghost without building or moving anything.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFStructurePresetsScript = preload("res://addons/hammerforge/hf_structure_presets.gd")

## Where these tests keep the project's presets, never the project's own folder.
const PROJECT_DIR := "user://hf_test_structure_presets"

var dock: HammerForgeDock
var root: LevelRoot


func before_each() -> void:
	_clear_project_dir()
	dock = DockScene.instantiate()
	dock.presets_dir = PROJECT_DIR
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	dock._structure_section.set_expanded(true)
	_choose("arch")


func after_each() -> void:
	_clear_project_dir()
	dock = null
	root = null


func _clear_project_dir() -> void:
	if not DirAccess.dir_exists_absolute(PROJECT_DIR):
		return
	for file_name in DirAccess.get_files_at(PROJECT_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROJECT_DIR.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROJECT_DIR))


func _project_file() -> String:
	return PROJECT_DIR.path_join(HFStructurePresetsScript.PROJECT_FILE)


## Put `presets` in the project's file, as a pull from a teammate would.
func _pull(presets: Dictionary) -> void:
	assert_true(HFStructurePresetsScript.write(presets, _project_file()), "fixture: the file")
	HFDockBrushHandler.sync_structure_presets(dock)


func _on_disk() -> Dictionary:
	return HFStructurePresetsScript.read_raw(_project_file())


func _choose(type: String) -> void:
	for index in dock.structure_type_option.item_count:
		if str(dock.structure_type_option.get_item_metadata(index)) == type:
			dock.structure_type_option.selected = index
			break
	HFDockBrushHandler.on_structure_type_changed(dock)


## Turn a control the way the user does, signal and all.
func _turn(key: String, value: float) -> void:
	var control = dock.structure_fields.get(key, null)
	assert_not_null(control, "the section has a %s control" % key)
	control.value = value


func _field(key: String) -> float:
	return float(dock.structure_fields[key].value)


func _listed() -> PackedStringArray:
	var opt: OptionButton = dock.structure_preset_option
	var out := PackedStringArray()
	for index in opt.item_count:
		out.append(opt.get_item_text(index))
	return out


func _shown() -> String:
	var opt: OptionButton = dock.structure_preset_option
	return opt.get_item_text(opt.selected) if opt.selected >= 0 else ""


func _pick(preset_name: String) -> void:
	var opt: OptionButton = dock.structure_preset_option
	for index in opt.item_count:
		if opt.get_item_text(index) == preset_name:
			dock._select_option_notifying(opt, index)
			return
	fail_test("%s is not in the list" % preset_name)


func _status() -> String:
	return dock.status_label.text if dock.status_label else ""


## The first number field of the chosen type, and a value for it in range that is
## not its default. Read from the schema, so no type is named here.
func _a_number_to_change(type: String) -> Array:
	for entry in HFGeneratorSystem.settings_schema(type):
		var spec: Dictionary = entry
		if spec["type"] not in [HFGeneratorSchema.TYPE_FLOAT, HFGeneratorSchema.TYPE_INT]:
			continue
		var step := float(spec.get("step", 1.0))
		var value := float(spec["default"]) + step
		if value > float(spec["max"]):
			value = float(spec["default"]) - step
		return [str(spec["key"]), value]
	return []


# ===========================================================================
# The file, through the schema
# ===========================================================================


func test_a_preset_round_trips_through_the_file():
	var saved: Dictionary = HFGeneratorSystem.default_settings("stairs")
	saved["steps"] = 12
	saved["rise"] = 0.2
	assert_true(HFStructurePresetsScript.write({"stairs": {"Main hall": saved}}, _project_file()))

	var read := HFStructurePresetsScript.settings_of(_on_disk(), "stairs", "Main hall")

	assert_true(read["ok"], str(read.get("message", "")))
	assert_true(HFGeneratorSystem.same_settings("stairs", read["settings"], saved))
	assert_eq(typeof(read["settings"]["steps"]), TYPE_INT, "a whole number comes back whole")


func test_unknown_keys_are_dropped_on_load():
	_pull({"arch": {"Old": {"radius": 2.0, "colour": "red", "keystone": true}}})

	var read := HFStructurePresetsScript.settings_of(_on_disk(), "arch", "Old")

	assert_true(read["ok"], str(read.get("message", "")))
	var settings: Dictionary = read["settings"]
	assert_false(settings.has("colour"), "a key the arch does not have is dropped")
	assert_false(settings.has("keystone"))
	assert_eq(
		Array(settings.keys()),
		Array(HFGeneratorSchema.keys(HFGeneratorSystem.settings_schema("arch"))),
		"and the arch's own keys are all there"
	)
	assert_almost_eq(float(settings["radius"]), 2.0, 0.001)


func test_a_key_an_older_file_lacks_takes_its_default():
	_pull({"arch": {"Old": {"radius": 2.0}}})

	var read := HFStructurePresetsScript.settings_of(_on_disk(), "arch", "Old")

	assert_true(read["ok"])
	var defaults: Dictionary = HFGeneratorSystem.default_settings("arch")
	assert_eq(read["settings"]["segments"], defaults["segments"])


func test_a_value_out_of_range_is_refused_naming_the_field():
	_pull({"arch": {"Huge": {"radius": 999999.0}}})

	var read := HFStructurePresetsScript.settings_of(_on_disk(), "arch", "Huge")

	assert_false(read["ok"])
	assert_true(str(read["message"]).contains("'Radius'"), str(read["message"]))
	assert_true(str(read["message"]).contains("Huge"), "and the preset")


func test_a_value_of_the_wrong_kind_is_refused_naming_the_field():
	_pull({"arch": {"Typed": {"segments": "eight"}}})

	var read := HFStructurePresetsScript.settings_of(_on_disk(), "arch", "Typed")

	assert_false(read["ok"])
	assert_true(str(read["message"]).contains("'Segments'"), str(read["message"]))


func test_a_type_this_version_does_not_know_is_kept_when_saving():
	_pull({"crane": {"Dockside": {"boom": 12.0}}})

	HFDockBrushHandler.save_structure_preset(dock, "Doorway")

	assert_true(_on_disk().has("crane"), "a newer version's presets are left for it")
	assert_true(HFStructurePresetsScript.of_type(_on_disk(), "arch").has("Doorway"))


func test_a_file_that_does_not_read_is_never_written_over():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROJECT_DIR))
	var file := FileAccess.open(_project_file(), FileAccess.WRITE)
	file.store_string("<<<<<<< HEAD\n{}\n")
	file.close()
	HFLog.begin_test_capture(["is not a presets file"])

	HFDockBrushHandler.save_structure_preset(dock, "Doorway")
	HFLog.end_test_capture()

	assert_true(_status().contains("could not be read"), _status())
	assert_eq(FileAccess.get_file_as_string(_project_file()), "<<<<<<< HEAD\n{}\n")


# ===========================================================================
# The row in the Structure section
# ===========================================================================


func test_the_row_offers_defaults_and_no_delete_until_a_preset_is_saved():
	assert_eq(Array(_listed()), ["Defaults"])
	assert_eq(_shown(), "Defaults", "a fresh section holds the defaults")
	assert_true(dock.structure_preset_delete_btn.disabled, "Defaults is not the mapper's to delete")


func test_save_pick_and_delete_work_for_every_type():
	for type in HFGeneratorSystem.known_types():
		_choose(type)
		var change := _a_number_to_change(type)
		assert_false(change.is_empty(), "%s has a number to change" % type)
		var key := str(change[0])
		var wanted := float(change[1])
		_turn(key, wanted)
		assert_eq(_shown(), "Custom", "%s: a changed field is no preset" % type)

		HFDockBrushHandler.save_structure_preset(dock, "House")
		assert_true(
			HFStructurePresetsScript.of_type(_on_disk(), type).has("House"), "%s saved" % type
		)
		assert_eq(_shown(), "House", "%s: the row names what was saved" % type)

		# Choosing the type again keeps what was last set for it (#1406), so the
		# fields go back to the builder's own through Defaults.
		_pick("Defaults")
		assert_almost_eq(_field(key), float(HFGeneratorSystem.default_settings(type)[key]), 0.001)
		_pick("House")
		assert_almost_eq(_field(key), wanted, 0.001, "%s: the pick fills the field" % type)

		dock.structure_preset_delete_btn.pressed.emit()
		assert_true(
			HFStructurePresetsScript.of_type(_on_disk(), type).has("House"),
			"%s: one press only asks" % type
		)
		dock.structure_preset_delete_btn.pressed.emit()
		assert_false(
			HFStructurePresetsScript.of_type(_on_disk(), type).has("House"),
			"%s: the second press deletes" % type
		)
		assert_false(_listed().has("House"), "%s: and the row drops it" % type)
	assert_eq(root.generator_count(), 0, "nothing was ever built")


func test_presets_are_kept_by_type():
	_turn("radius", 5.0)
	HFDockBrushHandler.save_structure_preset(dock, "Wide")

	_choose("dome")

	assert_false(_listed().has("Wide"), "an arch's preset is not offered for a dome")


func test_picking_a_preset_redraws_the_ghost_and_builds_nothing():
	_choose("stairs")
	_turn("steps", 5)
	HFDockBrushHandler.save_structure_preset(dock, "Short")
	_pick("Defaults")
	assert_eq(root.structure_preview_pieces(), 8, "the default flight is drawn first")

	_pick("Short")

	assert_eq(root.structure_preview_pieces(), 5, "the ghost follows the preset")
	assert_eq(root.generator_count(), 0, "and nothing is built")
	assert_eq(root._iter_managed_brush_nodes().size(), 0)


func test_picking_defaults_puts_the_builders_own_values_back():
	_turn("radius", 5.0)

	_pick("Defaults")

	assert_almost_eq(
		_field("radius"), float(HFGeneratorSystem.default_settings("arch")["radius"]), 0.001
	)


func test_with_a_structure_selected_a_pick_only_fills_the_fields():
	_turn("radius", 5.0)
	HFDockBrushHandler.save_structure_preset(dock, "Wide")
	_pick("Defaults")
	dock._on_create_structure()
	assert_eq(root.generator_count(), 1)
	var record = root.generator_system.generators.values()[0]
	var ids_before := Array(record.brush_ids)
	var piece = root.brush_system.find_brush_by_id(str(ids_before[0]))
	var where: Vector3 = piece.global_position
	dock.set_selection_nodes([piece])
	assert_ne(str(dock._active_generator_id), "", "the section edits the structure")

	_pick("Wide")

	assert_almost_eq(_field("radius"), 5.0, 0.001, "the fields take the preset")
	assert_eq(Array(record.brush_ids), ids_before, "no piece was rebuilt")
	var default_radius := float(HFGeneratorSystem.default_settings("arch")["radius"])
	assert_almost_eq(float(record.settings["radius"]), default_radius, 0.001, "nor the record")
	assert_eq(piece.global_position, where, "and nothing moved")
	assert_eq(dock.structure_create_btn.text, "Update Arch", "Update is still its own press")
	assert_true(_status().contains("Update"), _status())


func test_a_preset_out_of_range_is_refused_and_the_fields_keep_their_values():
	_turn("radius", 5.0)
	_pull({"arch": {"Huge": {"radius": 999999.0}}})

	_pick("Huge")

	assert_true(_status().contains("'Radius'"), "the field is named: '%s'" % _status())
	assert_almost_eq(_field("radius"), 5.0, 0.001, "the field kept its value")
	assert_eq(_shown(), "Custom", "and the row says the fields hold no preset")


func test_saving_over_a_name_asks_before_replacing_it():
	_turn("radius", 5.0)
	HFDockBrushHandler.save_structure_preset(dock, "Wide")
	_turn("radius", 6.0)

	HFDockBrushHandler.save_structure_preset(dock, "Wide")

	var stored: Dictionary = HFStructurePresetsScript.of_type(_on_disk(), "arch")["Wide"]
	assert_almost_eq(float(stored["radius"]), 5.0, 0.001, "nothing is replaced before the answer")
	var confirm := (
		dock.find_child("StructurePresetReplaceConfirm", false, false) as ConfirmationDialog
	)
	assert_not_null(confirm, "the dock asks")
	if confirm == null:
		return
	confirm.confirmed.emit()
	stored = HFStructurePresetsScript.of_type(_on_disk(), "arch")["Wide"]
	assert_almost_eq(float(stored["radius"]), 6.0, 0.001, "and replaces it on Replace")
	await get_tree().process_frame


func test_save_asks_for_a_name():
	_turn("radius", 5.0)

	dock.structure_preset_save_btn.pressed.emit()

	var dialog: AcceptDialog = dock._structure_preset_dialog
	assert_not_null(dialog, "Save opens a name prompt")
	if dialog == null:
		return
	var line := dialog.find_children("*", "LineEdit", false, false)[0] as LineEdit
	line.text = "  Chapel door  "
	dialog.confirmed.emit()
	assert_true(HFStructurePresetsScript.of_type(_on_disk(), "arch").has("Chapel door"))
	await get_tree().process_frame


func test_the_list_s_own_names_cannot_be_saved_over():
	for reserved in ["Defaults", "custom", ""]:
		HFDockBrushHandler.save_structure_preset(dock, reserved)
	assert_false(FileAccess.file_exists(_project_file()), "nothing was written")


func test_presets_are_read_from_the_project_folder_by_a_new_dock():
	_turn("radius", 5.0)
	HFDockBrushHandler.save_structure_preset(dock, "Wide")

	# A restart: a new dock, reading the same folder.
	var again: HammerForgeDock = DockScene.instantiate()
	again.presets_dir = PROJECT_DIR
	add_child_autoqfree(again)

	var opt: OptionButton = again.structure_preset_option
	var names: Array = []
	for index in opt.item_count:
		names.append(opt.get_item_text(index))
	assert_true(names.has("Wide"), "got %s" % str(names))
