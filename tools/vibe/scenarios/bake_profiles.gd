@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Bake profiles, driven through the real dock.
##
## A profile is a named set of bake options (#964 on). Editing and Shipping are
## built in and set two options each; a saved one holds every option
## `HFBakeSystem.profile_setting_names()` lists. Nothing is stored in the level:
## which profile a level is on is read off its options each time.
##
## So the questions are about exactness and coverage. Does switching away and
## back put every value back to the bit? Which bake settings does a profile
## leave out, against every bake property the level exports? Does the level
## still read as its profile after a `.hflevel` and a state round trip? What
## does a hand-edited profiles file -- an unknown key, a wrong type, a value out
## of range -- do to the list and to the level? And Export Game Scene, which
## bakes on a profile of its own and then puts the level's options back: what
## does the bake actually run with, and does everything come back, including
## after an export that fails?

const DockScene = preload("res://addons/hammerforge/dock.tscn")

const PREFIX := "user://bake-profiles"
const PRESETS := "user://bake-profiles_presets"
const GAME_SCENE_SOURCE := "res://.godot/bake-profiles_probe.tscn"
const GAME_SCENE_OUT := "res://.godot/bake-profiles_probe_game.tscn"


## The real dock, with its toasts and its undo steps kept where they can be read.
class ProfileDock:
	extends "res://addons/hammerforge/dock.gd"

	var toasts: Array = []
	var steps: Array = []

	func show_toast(message: String, level: int = 0) -> void:
		toasts.append([level, message])

	func _commit_bake_profile(action_name: String, before: Dictionary) -> void:
		if level_root and level_root.capture_bake_options() != before:
			steps.append([action_name, before, level_root.capture_bake_options()])


var _written: Array[String] = []
var _dirs: Array[String] = []


func id() -> String:
	return "bake-profiles"


func summary() -> String:
	return "bake profiles: switching, saving, held options, and what an export takes from them"


func run() -> void:
	await _what_a_profile_carries()
	await _switching_and_back()
	await _names()
	await _through_the_hflevel_and_state()
	await _a_hand_edited_project_file()
	await _what_an_export_takes()
	await _a_failed_export()
	_cleanup()


func _cleanup() -> void:
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for dir in _dirs:
		if DirAccess.dir_exists_absolute(dir):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _dock(root: Node3D, presets: String) -> Node:
	var dock = DockScene.instantiate()
	dock.set_script(ProfileDock)
	dock.presets_dir = presets
	_tree.get_root().add_child(dock)
	await frame()
	var prefs := HFUserPrefs.new()
	prefs.persistence_enabled = false
	dock.set_user_prefs(prefs)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	HFDockManageHandler.sync_bake_profile_ui(dock)
	return dock


func _shown(dock: Node) -> String:
	var opt: OptionButton = dock.bake_profile_opt
	return opt.get_item_text(opt.selected) if opt.selected >= 0 else ""


func _listed(opt: OptionButton) -> Array:
	var out: Array = []
	for i in range(opt.item_count):
		out.append(opt.get_item_text(i))
	return out


func _pick(dock: Node, profile: String) -> bool:
	var opt: OptionButton = dock.bake_profile_opt
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == profile:
			dock._select_option_notifying(opt, i)
			return true
	return false


func _save_as(dock: Node, profile: String) -> void:
	dock.bake_profile_name.text = profile
	dock.bake_profile_name.text_changed.emit(profile)
	dock.bake_profile_save_btn.pressed.emit()


func _delete(dock: Node, profile: String) -> void:
	dock.bake_profile_name.text = profile
	dock.bake_profile_name.text_changed.emit(profile)
	dock.bake_profile_delete_btn.pressed.emit()
	dock.bake_profile_delete_btn.pressed.emit()


## Every option a profile carries set away from its default, each to a value the
## dock's own control can hold.
func _custom(root: Node3D) -> void:
	(
		root
		. apply_bake_options(
			{
				"bake_use_face_materials": true,
				"bake_collision_mode": 2,
				"bake_collision_layer_index": 3,
				"bake_convex_clean": false,
				"bake_convex_simplify": 0.35,
				"bake_lightmap_uv2": true,
				"bake_lightmap_texel_size": 0.05,
				"bake_unwrap_uv0": true,
				"bake_generate_lods": true,
				"bake_chunk_size": 12.5,
				"bake_merge_meshes": false,
				"bake_use_atlas": true,
				"bake_generate_occluders": true,
				"bake_occluder_min_area": 6.0,
				"bake_navmesh": true,
				"bake_navmesh_cell_size": 0.2,
				"bake_navmesh_cell_height": 0.1,
				"bake_navmesh_agent_height": 1.6,
				"bake_navmesh_agent_radius": 0.3,
				"bake_navmesh_agent_max_climb": 0.3,
				"bake_navmesh_agent_max_slope": 40.0,
				"bake_auto_connectors": true,
				"bake_connector_mode": 2,
				"bake_connector_stair_height": 0.2,
				"bake_connector_width": 3,
				"bake_connector_stair_threshold": 1.5,
				"bake_wire_io": false,
			}
		)
	)


## Which keys of `a` and `b` differ, with both values.
func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for key in a:
		if not b.has(key) or typeof(a[key]) != typeof(b[key]) or a[key] != b[key]:
			out[key] = [a[key], b.get(key, "<missing>")]
	for key in b:
		if not a.has(key):
			out[key] = ["<missing>", b[key]]
	return out


# ---------------------------------------------------------------------------


## The profile's list against every bake property the level exports.
func _what_a_profile_carries() -> void:
	var root: Node3D = await fresh_root("ProfileCarries")
	var carried: Array = HFBakeSystem.profile_setting_names()
	var exported: Array = []
	for prop in root.get_property_list():
		var name := str(prop.get("name", ""))
		var usage := int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if name.begins_with("bake_") or name.begins_with("export_") or name.begins_with("cordon_"):
			exported.append(name)
	var left_out: Array = []
	for name in exported:
		if name not in carried:
			left_out.append(name)
	note("a profile carries %d settings" % carried.size(), carried)
	note(
		"bake, export and cordon properties the level stores but a profile does not carry", left_out
	)
	note(
		"why each is out",
		(
			"bake_visible_only and the cordon_* settings are scope (HFBakeSystem.SCOPE_SETTING_NAMES, the guide says so);"
			+ " bake_material_override is a Material, which a JSON profile cannot hold, and is in the bake signature by path;"
			+ " bake_use_thread_pool changes how fast, not what; export_level_environment shapes the export, not the bake"
		)
	)
	var unexplained: Array = []
	for name in left_out:
		if name in HFBakeSystem.SCOPE_SETTING_NAMES:
			continue
		if (
			name
			in [
				"bake_material_override",
				"bake_use_thread_pool",
				"export_level_environment",
				"cordon_names"
			]
		):
			continue
		unexplained.append(name)
	if not unexplained.is_empty():
		flag(
			"bake settings a profile leaves out with no reason in the code or the guide",
			"%s are stored on the level and not in profile_setting_names()" % [unexplained]
		)
	# Every profile setting has to survive a .hflevel, or a level saved on a
	# profile reopens on Custom.
	var settings: Dictionary = root.state_system.capture_hflevel_settings()
	var unsaved: Array = []
	for name in carried:
		if not settings.has(name):
			unsaved.append(name)
	note("profile settings the .hflevel does not write", unsaved)
	if not unsaved.is_empty():
		flag("a profile setting is not saved in the .hflevel", "%s" % [unsaved])
	await drop_root(root)


func _switching_and_back() -> void:
	var root: Node3D = await fresh_root("ProfileSwitch")
	var dock = await _dock(root, PRESETS + "_switch")
	note("a new level reads as", _shown(dock))
	_custom(root)
	HFDockManageHandler.sync_bake_profile_ui(dock)
	note("after setting every option by hand the list shows", _shown(dock))
	var full: Dictionary = root.capture_bake_options()
	_save_as(dock, "Full")
	var stored: Dictionary = dock._user_prefs.get_bake_profiles().get("Full", {})
	note("Save under Full keeps %d options" % stored.size(), "the list shows %s" % _shown(dock))
	var stored_diff := _diff(full, stored)
	if not stored_diff.is_empty():
		flag("Save does not keep the options the level is on", "differences %s" % stored_diff)

	var trail: Array = []
	for profile in ["Shipping", "Editing", "Full", "Editing", "Shipping", "Full"]:
		var before: Dictionary = root.capture_bake_options()
		var picked := _pick(dock, profile)
		var now: Dictionary = root.capture_bake_options()
		trail.append([profile, picked, _diff(before, now).size(), _shown(dock)])
	note("picked in turn: [profile, found, options changed, list shows]", trail)
	var back := _diff(full, root.capture_bake_options())
	note(
		"back on Full after Shipping, Editing, Full, Editing, Shipping",
		"differences from the saved values: %s" % back
	)
	if not back.is_empty():
		flag(
			"switching away from a saved profile and back does not restore it exactly", "%s" % back
		)

	# Undo: each step holds the options before and after; apply the befores in
	# reverse, as Ctrl+Z would.
	var steps: Array = dock.steps.duplicate()
	note("undo steps recorded", steps.map(func(s): return s[0]))
	for i in range(steps.size() - 1, -1, -1):
		root.apply_bake_options(steps[i][1])
	var undone := _diff(full, root.capture_bake_options())
	var first_before: Dictionary = steps[0][1] if not steps.is_empty() else {}
	var to_start := _diff(first_before, root.capture_bake_options())
	note("after undoing every pick", "differences from where the picks started: %s" % to_start)
	if not to_start.is_empty():
		flag(
			"undoing every profile pick does not return to the options before the first",
			"%s" % to_start
		)
	if undone.size() != 0:
		note("(the level is back on Full, which is where the picks started)", undone.size() == 0)
	dock.queue_free()
	await frame()
	await drop_root(root)


func _names() -> void:
	var root: Node3D = await fresh_root("ProfileNames")
	var dock = await _dock(root, PRESETS + "_names")
	_custom(root)
	_save_as(dock, "Full")
	# Rename: there is no Rename, so it is Save under the new name, Delete the old.
	_save_as(dock, "Everything")
	_delete(dock, "Full")
	note(
		"rename as Save + Delete",
		(
			"saved %s; the list %s; shows %s"
			% [
				dock._user_prefs.get_bake_profiles().keys(),
				_listed(dock.bake_profile_opt),
				_shown(dock)
			]
		)
	)

	# Same values, a second name: which one does the list say the level is on?
	_save_as(dock, "Copy")
	_pick(dock, "Copy")
	note(
		"two profiles with the same values, Copy picked",
		"the list shows %s, the name box %s" % [_shown(dock), dock.bake_profile_name.text]
	)

	# Names that differ only in case, a built-in in another case, and odd ones.
	var tries := [
		"everything",
		"SHIPPING",
		"  custom  ",
		"Level's own options",
		'Lights: "on" / ü 🙂, {x}',
		"two\nlines",
		"x".repeat(60),
		"   ",
	]
	var results: Array = []
	for typed in tries:
		var had: Array = dock._user_prefs.get_bake_profiles().keys()
		_save_as(dock, typed)
		var now: Array = dock._user_prefs.get_bake_profiles().keys()
		var added: Array = now.filter(func(k): return k not in had)
		results.append([typed, added, dock.bake_profile_save_btn.disabled])
	note("typed name -> profile added, Save disabled", results)
	note("the Profile list now", _listed(dock.bake_profile_opt))
	note("the Export with list now", _listed(dock.export_profile_opt))
	var own_twice := _listed(dock.export_profile_opt).count(HFDockManageHandler.LEVEL_OWN_OPTIONS)
	if own_twice > 1:
		note(
			"Export with lists 'Level's own options' %d times" % own_twice,
			"once for the level's options and once for a saved profile of that name; is_reserved_name() reserves Editing, Shipping and Custom but not the export list's own entry"
		)
	# The odd name through the project file and back.
	var odd := 'Lights: "on" / ü 🙂, {x}'
	var path := PRESETS + "_names/" + HFBakeProfiles.PROJECT_FILE
	_written.append(path)
	_dirs.append(PRESETS + "_names")
	HFBakeProfiles.write_project({odd: root.capture_bake_options()}, path)
	var back: Dictionary = HFBakeProfiles.read_project(root, path)
	note(
		"an odd name through the project file",
		"read back as %s, %d options" % [back.keys(), back.get(odd, {}).size()]
	)
	if not back.has(odd) or not _diff(back[odd], root.capture_bake_options()).is_empty():
		flag(
			"a profile with punctuation and non-ASCII in its name does not survive the project file",
			"%s" % [back.keys()]
		)
	dock.queue_free()
	await frame()
	await drop_root(root)


func _through_the_hflevel_and_state() -> void:
	var root: Node3D = await fresh_root("ProfileSave")
	var dock = await _dock(root, PRESETS + "_save")
	box(root, Vector3(4, 1, 4))
	_custom(root)
	_save_as(dock, "Full")
	var saved: Dictionary = HFDockManageHandler.saved_bake_profiles(dock)
	var before: Dictionary = root.capture_bake_options()
	var path := PREFIX + "_level.hflevel"
	_written.append(path)
	root.save_hflevel(path, true)
	await HFVibe.settle_save(_tree, root)

	var loaded: Node3D = await fresh_root("ProfileLoad")
	loaded.load_hflevel(path)
	await frame()
	var after: Dictionary = loaded.capture_bake_options()
	note(
		"a level on Full through .hflevel",
		(
			"reads as %s after the load; differences %s"
			% [HFBakeProfiles.current(loaded, saved), _diff(before, after)]
		)
	)
	if HFBakeProfiles.current(loaded, saved) != "Full":
		flag(
			"a level saved on a profile reopens on another", "differences %s" % _diff(before, after)
		)

	# A state round trip: the options are settings, so a state restore should
	# leave them where they are.
	var state: Dictionary = loaded.state_system.capture_state(true)
	loaded.apply_bake_options(HFBakeProfiles.built_in("Editing"))
	var mid: Dictionary = loaded.capture_bake_options()
	loaded.state_system.restore_state(state)
	await frame()
	note(
		"restore_state() after picking Editing",
		(
			"the options %s"
			% (
				"stay on Editing (a state action does not carry settings)"
				if _diff(mid, loaded.capture_bake_options()).is_empty()
				else "move: %s" % _diff(mid, loaded.capture_bake_options())
			)
		)
	)
	# The settings round trip the undo of a load goes through.
	var settings: Dictionary = loaded.state_system.capture_hflevel_settings()
	loaded.apply_bake_options(HFBakeProfiles.built_in("Shipping"))
	loaded.state_system.apply_hflevel_settings(settings)
	var settings_diff := _diff(mid, loaded.capture_bake_options())
	note("capture/apply_hflevel_settings", "differences %s" % settings_diff)
	if not settings_diff.is_empty():
		flag("a settings round trip does not put the bake options back", "%s" % settings_diff)
	dock.queue_free()
	await frame()
	await drop_root(root)
	await drop_root(loaded)


## The project's file, edited by hand the way a merge or a teammate does.
func _a_hand_edited_project_file() -> void:
	var root: Node3D = await fresh_root("ProfileFile")
	var presets := PRESETS + "_file"
	var path := presets + "/" + HFBakeProfiles.PROJECT_FILE
	_written.append(path)
	_dirs.append(presets)
	var text := (
		JSON
		. stringify(
			{
				"version": 1,
				"profiles":
				{
					"Hand":
					{
						"bake_navmesh": true,
						"bake_made_up": 1,
						"bake_collision_mode": "two",
						"bake_generate_lods": 1,
					},
					"Out of range":
					{
						"bake_navmesh": true,
						"bake_navmesh_cell_size": 0.0,
						"bake_chunk_size": -5,
						"bake_collision_layer_index": 40,
						"bake_merge_meshes": true,
					},
					"Nothing usable": {"cordon_enabled": true, "bake_visible_only": true},
					"Not a profile": [1, 2, 3],
					"Editing": {"bake_navmesh": true},
				},
			},
			"\t"
		)
	)
	HFVibe.write_text(path, text)
	var dock = await _dock(root, presets)
	var read: Dictionary = HFDockManageHandler.saved_bake_profiles(dock)
	note("what the dock reads from the hand-edited file", read)
	note("the list", _listed(dock.bake_profile_opt))

	var before: Dictionary = root.capture_bake_options()
	_pick(dock, "Hand")
	note(
		"picking Hand",
		(
			"changed %s; the list shows %s; last toast %s"
			% [
				_diff(before, root.capture_bake_options()),
				_shown(dock),
				dock.toasts.back() if not dock.toasts.is_empty() else "none"
			]
		)
	)

	var out_of_range: Dictionary = read.get("Out of range", {})
	before = root.capture_bake_options()
	_pick(dock, "Out of range")
	var first_pick := _diff(before, root.capture_bake_options())
	var shows := _shown(dock)
	var toast_one = dock.toasts.back() if not dock.toasts.is_empty() else "none"
	var steps_before: int = dock.steps.size()
	before = root.capture_bake_options()
	_pick(dock, "Out of range")
	var second_pick := _diff(before, root.capture_bake_options())
	var toast_two = dock.toasts.back() if not dock.toasts.is_empty() else "none"
	note(
		"picking 'Out of range' (cell size 0, chunk -5, layer 40 in the file)",
		(
			"the profile as read holds %s; the level took %s; the list shows %s; toast %s"
			% [out_of_range, first_pick, shows, toast_one]
		)
	)
	note(
		"picking it a second time",
		(
			"changes %s, toast %s, undo steps added %d"
			% [second_pick, toast_two, dock.steps.size() - steps_before]
		)
	)
	if shows != "Out of range" and second_pick.is_empty():
		known(
			1207,
			"a saved profile with a value past a setting's limit never reads as the profile the level is on",
			(
				(
					"the project file holds 'Out of range' with bake_navmesh_cell_size 0.0,"
					+ " bake_chunk_size -5 and bake_collision_layer_index 40. read_project() keeps"
					+ " all three (validated() checks the kind and leaves ranges to the setters),"
					+ " the pick lands the level on %s, and HFBakeProfiles.matches() then compares"
					+ " the level's clamped values against the profile's raw ones. The list shows"
					+ " '%s' straight after the pick; picking it again changes nothing and still"
					+ " toasts %s. Export with 'Out of range' counts it as a switch every time. A"
					+ " teammate's typo in the shared file reads to everyone as a profile that"
					+ " will not stick."
				)
				% [first_pick, shows, toast_two]
			)
		)
	dock.queue_free()
	await frame()
	await drop_root(root)


## Run Export Game Scene and record what the bake ran with.
func _export(root: Node3D, dock: Node, export_with: String) -> Dictionary:
	var opt: OptionButton = dock.export_profile_opt
	for i in range(opt.item_count):
		if opt.get_item_text(i) == export_with:
			opt.select(i)
	var seen := {}
	var during := func():
		seen["options"] = root.capture_bake_options()
		seen["held"] = dock.bake_options_held()
		seen["profile"] = HFBakeProfiles.current(
			root, HFDockManageHandler.saved_bake_profiles(dock)
		)
	root.connect("bake_started", during)
	root.scene_file_path = GAME_SCENE_SOURCE
	_written.append(GAME_SCENE_OUT)
	dock.toasts.clear()
	await HFDockManageHandler.on_export_game_scene(dock)
	await frame()
	root.disconnect("bake_started", during)
	seen["written"] = FileAccess.file_exists(GAME_SCENE_OUT)
	seen["toasts"] = dock.toasts.duplicate()
	seen["held_after"] = dock.bake_options_held()
	if FileAccess.file_exists(GAME_SCENE_OUT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GAME_SCENE_OUT))
	return seen


func _what_an_export_takes() -> void:
	var root: Node3D = await fresh_root("ProfileExport")
	var dock = await _dock(root, PRESETS + "_export")
	box(root, Vector3(4, 1, 4))
	_custom(root)
	_save_as(dock, "Full")
	# The level is on hand-set options, not on Full.
	root.bake_navmesh = false
	HFDockManageHandler.sync_bake_profile_ui(dock)
	var own: Dictionary = root.capture_bake_options()
	note("the level before the exports", "on %s" % _shown(dock))

	for export_with in [HFDockManageHandler.LEVEL_OWN_OPTIONS, "Shipping", "Editing", "Full"]:
		var seen := await _export(root, dock, export_with)
		var ran_with: Dictionary = seen.get("options", {})
		var expected: Dictionary = own.duplicate()
		if export_with != HFDockManageHandler.LEVEL_OWN_OPTIONS:
			var values := HFBakeProfiles.values_of(
				export_with, HFDockManageHandler.saved_bake_profiles(dock)
			)
			for key in values:
				expected[key] = values[key]
		var off_profile := _diff(expected, ran_with)
		var after := _diff(own, root.capture_bake_options())
		note(
			"Export with %s" % export_with,
			(
				"written %s; the bake ran on %s (held %s), differing from the level's options plus the profile's by %s; afterwards the level differs from its own by %s, held %s; toasts %s"
				% [
					seen.get("written"),
					seen.get("profile"),
					seen.get("held"),
					off_profile,
					after,
					seen.get("held_after"),
					seen.get("toasts"),
				]
			)
		)
		if not off_profile.is_empty():
			flag(
				"Export with %s baked on options it was not given" % export_with, "%s" % off_profile
			)
		if not after.is_empty():
			flag("Export with %s did not put the level's options back" % export_with, "%s" % after)
	dock.queue_free()
	await frame()
	await drop_root(root)


## Two ways for an export to fail: the bake fails, or the scene cannot be written.
func _a_failed_export() -> void:
	var root: Node3D = await fresh_root("ProfileFail")
	var dock = await _dock(root, PRESETS + "_fail")
	box(root, Vector3(4, 1, 4))
	_custom(root)
	root.bake_navmesh = false
	var own: Dictionary = root.capture_bake_options()

	# The bake fails: no baker, which is the bake's own "Bake failed" path.
	var baker = root.baker
	root.baker = null
	var seen := await _export(root, dock, "Shipping")
	root.baker = baker
	var after := _diff(own, root.capture_bake_options())
	note(
		"Export with Shipping when the bake fails",
		(
			"the bake ran on %s, held %s; afterwards differences %s, held %s; toasts %s"
			% [
				seen.get("profile", "(never started)"),
				seen.get("held"),
				after,
				seen.get("held_after"),
				seen.get("toasts")
			]
		)
	)
	if not after.is_empty():
		flag("a failed export bake leaves the export's profile on the level", "%s" % after)

	# The bake works and the scene cannot be written: its folder is not there.
	var opt: OptionButton = dock.export_profile_opt
	for i in range(opt.item_count):
		if opt.get_item_text(i) == "Shipping":
			opt.select(i)
	root.scene_file_path = "res://.godot/bake-profiles-no-such-folder/deeper/probe.tscn"
	dock.toasts.clear()
	await HFDockManageHandler.on_export_game_scene(dock)
	await frame()
	var after_write := _diff(own, root.capture_bake_options())
	note(
		"Export with Shipping when the scene cannot be written",
		(
			"afterwards differences %s, held %s; toasts %s"
			% [after_write, dock.bake_options_held(), dock.toasts]
		)
	)
	if not after_write.is_empty():
		flag(
			"an export that cannot write its scene leaves the export's profile on the level",
			"%s" % after_write
		)
	dock.queue_free()
	await frame()
	await drop_root(root)
