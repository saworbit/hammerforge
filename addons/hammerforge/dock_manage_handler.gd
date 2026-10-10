@tool
class_name HFDockManageHandler
extends RefCounted
## Test-tab bake, play, spawn, and validation handlers extracted from dock.gd.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftEntity = preload("draft_entity.gd")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFPlaytestRequest = preload("hf_playtest_request.gd")
const HFBakeProfilesType = preload("hf_bake_profiles.gd")

## The saved profiles as last read and the stored values they were read from, so
## a bad entry in the preferences is named once rather than at every click.
static var _saved_profiles_key := 0
static var _saved_profiles := {}


static func on_bake(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Bake requested")
	dock._warn_missing_dependencies()
	if not dock.level_root or not can_start_bake(dock, "Bake"):
		return
	# Prefer incremental bake when only specific brushes are dirty
	if (
		dock.level_root
		and not dock.level_root._dirty_brush_ids.is_empty()
		and not dock.level_root._full_reconcile_needed
	):
		dock._log("Dirty brushes detected — using incremental bake")
		dock._on_bake_changed()
		return
	set_bake_buttons_disabled(dock, true)
	var succeeded: bool = await dock.level_root.bake(
		true, false, dock.get_collision_layer_mask(), get_bake_preview_mode(dock)
	)
	set_bake_buttons_disabled(dock, false)
	if succeeded:
		dock.record_history("Bake")


static func on_bake_dry_run(dock: Object) -> void:
	if dock == null or not dock.level_root:
		if dock:
			dock._set_status("No LevelRoot for bake dry run", true)
		return
	var info: Dictionary = dock.level_root.bake_dry_run()
	if info.is_empty():
		dock._set_status("Bake dry run failed", true)
		return
	var draft = int(info.get("draft", 0))
	var pending = int(info.get("pending", 0))
	var committed = int(info.get("committed", 0))
	var gen_floors = int(info.get("generated_floors", 0))
	var gen_walls = int(info.get("generated_walls", 0))
	var hm = int(info.get("heightmap_floors", 0))
	var chunks = int(info.get("chunk_count", 0))
	var summary = (
		"Dry run: draft %d, pending %d, committed %d, floors %d, walls %d, heightmap %d, chunks %d"
		% [draft, pending, committed, gen_floors, gen_walls, hm, chunks]
	)
	dock._set_status(summary, false, 5.0)
	dock._log(summary)


static func get_bake_preview_mode(dock: Object) -> int:
	if dock and dock.bake_preview_mode_opt:
		return dock.bake_preview_mode_opt.get_selected_id()
	return 0  # FULL


static func on_bake_selected(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Bake selected requested")
	if not dock.level_root or not can_start_bake(dock, "Bake Selected"):
		return
	if not dock._guard_selection_action(
		"Bake Selected", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	if dock._selection_nodes.is_empty():
		dock.show_toast("Select brushes to bake", 1)
		return
	var brush_nodes: Array = []
	for node in dock._selection_nodes:
		if dock.level_root.is_brush_node(node):
			brush_nodes.append(node)
	if brush_nodes.is_empty():
		dock.show_toast("No brushes in selection", 1)
		return
	dock._warn_missing_dependencies()
	var mask = dock.get_collision_layer_mask()
	set_bake_buttons_disabled(dock, true)
	var succeeded: bool = await dock.level_root.bake_selected(
		brush_nodes, mask, get_bake_preview_mode(dock)
	)
	set_bake_buttons_disabled(dock, false)
	if succeeded:
		dock.record_history("Bake Selected")


static func on_bake_changed(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Bake changed requested")
	if not dock.level_root or not can_start_bake(dock, "Bake Changed"):
		return
	dock._warn_missing_dependencies()
	var mask = dock.get_collision_layer_mask()
	set_bake_buttons_disabled(dock, true)
	var succeeded: bool = await dock.level_root.bake_dirty(mask, get_bake_preview_mode(dock))
	set_bake_buttons_disabled(dock, false)
	if succeeded:
		dock.record_history("Bake Changed")


static func on_bake_check_issues(dock: Object) -> void:
	if dock == null or not dock.level_root or not dock.level_root.validation_system:
		return
	var issues: Array = dock.level_root.validation_system.check_bake_issues()
	if dock.level_root.spawn_system:
		issues.append_array(dock.level_root.spawn_system.layout_issues())
	show_bake_issue_list(dock, issues)
	if issues.is_empty():
		dock.show_toast("No bake issues found", 0)
		dock._set_status("Bake check: no issues", false, 3.0)
		return
	var errors := 0
	var warnings := 0
	for issue in issues:
		var sev: int = issue.get("severity", 0)
		if sev >= 2:
			errors += 1
		elif sev >= 1:
			warnings += 1
	var summary := "Bake check: %d errors, %d warnings" % [errors, warnings]
	dock._set_status(summary, errors > 0, 5.0)
	dock.show_toast("%s, listed under Check Bake Issues" % summary, mini(1 + int(errors > 0), 2))
	for issue in issues:
		push_warning("HF Bake Issue: %s" % issue.get("message", ""))


## Fill the list under Check Bake Issues, one row per issue (#992). A row that
## names an object can select it. A row whose fix is one mechanical edit has a
## Fix button that makes it as one undo step and checks again; the rest stay rows,
## because a fix that is a judgement call is the mapper's.
static func show_bake_issue_list(dock: Object, issues: Array) -> void:
	var list: VBoxContainer = dock.bake_issue_list
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	list.visible = not issues.is_empty()
	for issue in issues:
		list.add_child(_bake_issue_row(dock, issue))


static func _bake_issue_row(dock: Object, issue: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var severity: int = clampi(int(issue.get("severity", 0)), 0, 2)
	var text := Label.new()
	text.text = "%s  %s" % [["Info", "Warning", "Error"][severity], str(issue.get("message", ""))]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var node: Variant = issue.get("node")
	if node is Node and is_instance_valid(node):
		var select := Button.new()
		select.text = "Select"
		select.tooltip_text = "Select %s" % (node as Node).name
		select.pressed.connect(dock._on_bake_issue_select.bind(node))
		row.add_child(select)
	var fix := str(issue.get("fix", ""))
	if fix in BAKE_ISSUE_FIXES:
		var fix_button := Button.new()
		fix_button.text = "Fix"
		fix_button.tooltip_text = BAKE_ISSUE_FIXES[fix]
		fix_button.pressed.connect(dock._on_bake_issue_fix.bind(fix, node))
		row.add_child(fix_button)
	return row


## The fixes the list can make, each one edit and one undo step, with what it does.
const BAKE_ISSUE_FIXES := {
	"create_spawn": "Make a player spawn in the middle of the level, standing clear",
	"clear_spawn": "Move the spawn sideways to the nearest place it stands clear",
}


## Run a row's Fix, named in `BAKE_ISSUE_FIXES`, then check again so the list
## shows what is left.
static func on_bake_issue_fix(dock: Object, fix: String, node: Variant) -> void:
	if dock == null or not dock.level_root:
		return
	match fix:
		"create_spawn":
			on_spawn_auto_create(dock)
		"clear_spawn":
			if node is Node3D and is_instance_valid(node):
				move_spawn_clear(dock, node as Node3D)
	on_bake_check_issues(dock)


## Move `spawn` to the nearest place on its floor where it stands clear, as one
## undo step. Says so and moves nothing when there is no such place nearby.
static func move_spawn_clear(dock: Object, spawn: Node3D) -> void:
	var place: Variant = dock.level_root.spawn_system.clear_place_for(spawn)
	if place == null:
		dock.show_toast("No clear place near the spawn. Move it by hand", 1)
		return
	var old_pos := spawn.global_position
	spawn.global_position = place
	dock._commit_spawn_move(spawn, old_pos, spawn.global_position)
	dock.show_toast("Spawn moved clear of the brush", 0)


## One way of saying how long something takes, so the estimate before a bake and
## the report after it cannot drift into two different formats.
static func format_duration_ms(ms: int) -> String:
	if ms < 1000:
		return "%d ms" % ms
	if ms < 60000:
		return "%.1f s" % (float(ms) / 1000.0)
	return "%.1f min" % (float(ms) / 60000.0)


static func update_bake_estimate(dock: Object) -> void:
	if dock == null or not dock.level_root or not dock.bake_estimate_label:
		return
	var est: Dictionary = dock.level_root.estimate_bake_time()
	var ms: int = est.get("estimated_ms", 0)
	var count: int = est.get("brush_count", 0)
	var tip: String = est.get("tip", "")
	var label_text := "Est: %s (%d brushes)" % [format_duration_ms(ms), count]
	if tip != "":
		label_text += " — %s" % tip
	dock.bake_estimate_label.text = label_text


static func on_validate_level(dock: Object) -> void:
	run_validation(dock, false)


static func on_validate_fix(dock: Object) -> void:
	run_validation(dock, true)


static func on_bake_started(dock: Object) -> void:
	if dock == null:
		return
	update_bake_estimate(dock)
	dock._bake_started_msec = Time.get_ticks_msec()
	dock._set_status("Baking...", false, 0.0)
	if dock.progress_bar:
		dock.progress_bar.max_value = 100
		dock.progress_bar.value = 0
		dock.progress_bar.show()
	set_bake_buttons_disabled(dock, true)
	dock._hints_dirty = true
	dock.bake_state_changed.emit(true, false)


static func on_bake_progress(dock: Object, value: float, label: String) -> void:
	if dock == null:
		return
	var clamped = clamp(value, 0.0, 1.0)
	var pct = int(round(clamped * 100.0))
	if dock.progress_bar:
		dock.progress_bar.max_value = 100
		dock.progress_bar.value = pct
		if not dock.progress_bar.visible:
			dock.progress_bar.show()
	var message = "Baking"
	if label != "":
		message = "%s: %s" % [message, label]
	message += " (%d%%)" % pct
	dock._set_status(message, false, 0.0)


static func on_bake_finished(dock: Object, success: bool) -> void:
	if dock == null:
		return
	var started: int = int(dock._bake_started_msec)
	dock._bake_started_msec = 0
	if success:
		# A bake this dock did not see the start of is reported without a duration
		# rather than with one measured from zero.
		var message := "Bake complete"
		if started > 0:
			message = "Bake complete in %s" % format_duration_ms(Time.get_ticks_msec() - started)
		dock._set_status_success(message, 3.0)
		dock.show_toast("Bake complete", 0)
	else:
		dock._set_status("Bake failed - check Output for details", true)
		dock.show_toast("Bake failed — check Output for details", 2)
	if dock.progress_bar:
		dock.progress_bar.hide()
	update_bake_estimate(dock)
	set_bake_buttons_disabled(dock, false)
	dock._hints_dirty = true
	dock.bake_state_changed.emit(false, success)


static func set_bake_buttons_disabled(dock: Object, disabled: bool) -> void:
	if dock == null:
		return
	dock._bake_disabled = disabled
	dock.bake_btn.disabled = disabled
	dock.commit_cuts_btn.disabled = disabled
	dock.apply_cuts_btn.disabled = disabled
	if dock.quick_play_btn:
		dock.quick_play_btn.disabled = disabled
	if dock.bake_selected_btn:
		dock.bake_selected_btn.disabled = disabled
	if dock.bake_changed_btn:
		dock.bake_changed_btn.disabled = disabled
	if dock.quick_play_camera_btn:
		dock.quick_play_camera_btn.disabled = disabled
	if dock.quick_play_area_btn:
		dock.quick_play_area_btn.disabled = disabled
	dock._update_disabled_hints()


static func can_start_bake(dock: Object, action_label: String) -> bool:
	if dock == null:
		return false
	if (
		dock.level_root
		and dock.level_root.has_method("is_bake_in_flight")
		and dock.level_root.is_bake_in_flight()
	):
		dock.show_toast("%s will be available when the current bake finishes" % action_label, 1)
		return false
	return true


static func on_quick_play(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Playtest requested")
	dock._warn_missing_dependencies()
	if not dock.level_root or not can_start_bake(dock, "Test Level"):
		return

	var spawn: Node3D = null
	if dock.level_root.spawn_system:
		spawn = dock.level_root.spawn_system.get_active_spawn()
	if not spawn:
		dock.show_toast("No player_start found — auto-creating default spawn", 1)
		if dock.level_root.spawn_system:
			var pre_state: Dictionary = {}
			if dock.undo_redo and dock.level_root.state_system:
				pre_state = dock.level_root.state_system.capture_state(true)
			spawn = dock.level_root.spawn_system.create_default_spawn()
			if dock.undo_redo and spawn and not pre_state.is_empty():
				record_spawn_create_undo(dock, pre_state)

	var mask = dock.get_collision_layer_mask()
	if not await dock.level_root.bake(true, false, mask):
		dock.show_toast("Test cancelled because the level could not be baked", 2)
		return

	if spawn and dock.level_root.spawn_system:
		var validation: Dictionary = dock.level_root.spawn_system.validate_spawn(spawn, mask)
		var severity: int = validation.get("severity", 0)
		var issues: PackedStringArray = validation.get("issues", PackedStringArray())

		if severity >= 2:
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 10.0)
			var issue_text := "\n".join(issues)
			dock.show_toast("Spawn issues: %s" % issue_text, 2)
			show_spawn_fix_dialog(dock, spawn, validation, mask)
			return
		if severity >= 1:
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 6.0)
			dock.show_toast("Spawn warning: %s" % "\n".join(issues), 1)

	launch_playtest(dock)


static func on_quick_play_from_camera(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Play from Camera requested")
	dock._warn_missing_dependencies()
	if not dock.level_root or not can_start_bake(dock, "Test from Camera"):
		return
	var camera: Camera3D = null
	if dock._plugin and dock._plugin.last_3d_camera:
		camera = dock._plugin.last_3d_camera
	if not camera:
		dock.show_toast("No editor camera available", 2)
		return

	var spawn: Node3D = null
	if dock.level_root.spawn_system:
		spawn = dock.level_root.spawn_system.get_active_spawn()
	if not spawn:
		dock.show_toast("No player_start found — auto-creating default spawn", 1)
		if dock.level_root.spawn_system:
			var pre_state: Dictionary = {}
			if dock.undo_redo and dock.level_root.state_system:
				pre_state = dock.level_root.state_system.capture_state(true)
			spawn = dock.level_root.spawn_system.create_default_spawn()
			if dock.undo_redo and spawn and not pre_state.is_empty():
				record_spawn_create_undo(dock, pre_state)
	if not spawn:
		dock.show_toast("Could not create spawn point", 2)
		return

	var old_pos := spawn.global_position
	var old_angle: float = 0.0
	if spawn is DraftEntity:
		old_angle = float((spawn as DraftEntity).entity_data.get("angle", 0.0))

	# The spawn only sits at the camera long enough to bake and launch, and every
	# path below puts it back. Recording the move as an undo action left the undo
	# stack claiming a position the scene no longer had: Undo consumed a step
	# without changing anything, and Redo moved the spawn to the camera for good.
	spawn.global_position = camera.global_position
	var camera_yaw_deg: float = rad_to_deg(camera.global_rotation.y)
	if spawn is DraftEntity:
		(spawn as DraftEntity).entity_data["angle"] = camera_yaw_deg
	dock._log(
		"Spawn temporarily at camera: %s (yaw %.1f)" % [str(camera.global_position), camera_yaw_deg]
	)

	var mask = dock.get_collision_layer_mask()
	if not await dock.level_root.bake(true, false, mask):
		restore_spawn(spawn, old_pos, old_angle)
		dock.show_toast("Test cancelled because the level could not be baked", 2)
		return

	if spawn and dock.level_root.spawn_system:
		var validation: Dictionary = dock.level_root.spawn_system.validate_spawn(spawn, mask)
		var severity: int = validation.get("severity", 0)
		var issues: PackedStringArray = validation.get("issues", PackedStringArray())

		if severity >= 2:
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 10.0)
			dock.show_toast("Spawn issues: %s" % "\n".join(issues), 2)
			show_spawn_fix_dialog(dock, spawn, validation, mask)
			restore_spawn(spawn, old_pos, old_angle)
			return
		if severity >= 1:
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 6.0)
			dock.show_toast("Camera spawn warning: %s" % "\n".join(issues), 1)

	# Put back before the launch rather than after it. Godot saves the edited scene
	# on the way into a run, so a spawn still at the camera was written into the
	# mapper's scene file (#822). The run reads the camera pose from the request.
	restore_spawn(spawn, old_pos, old_angle)
	launch_playtest(
		dock, {"spawn_position": camera.global_position, "spawn_yaw_degrees": camera_yaw_deg}
	)


static func on_quick_play_selected_area(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Play Selected Area requested")
	dock._warn_missing_dependencies()
	if not dock.level_root or not can_start_bake(dock, "Test Selected Area"):
		return
	if not dock._guard_selection_action(
		"Play Selected Area", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	if dock._selection_nodes.is_empty():
		dock.show_toast("Select brushes to define play area", 1)
		return

	var prev_cordons: Dictionary = dock.level_root.capture_cordons()

	# The selected area alone: the level's other cordons would add their rooms,
	# and the first one may be switched off.
	var no_extra: Array[AABB] = []
	var all_on: Array[bool] = []
	dock.level_root.cordon_extra_aabbs = no_extra
	dock.level_root.cordon_active = all_on
	dock.level_root.set_cordon_from_selection(dock._selection_nodes)
	var play_area: AABB = dock.level_root.cordon_aabb
	dock.show_toast("Cordon set to selection — baking area", 0)

	var spawn: Node3D = null
	if dock.level_root.spawn_system:
		spawn = dock.level_root.spawn_system.get_active_spawn()
	if not spawn:
		dock.show_toast("No player_start found — auto-creating default spawn", 1)
		if dock.level_root.spawn_system:
			var pre_state: Dictionary = {}
			if dock.undo_redo and dock.level_root.state_system:
				pre_state = dock.level_root.state_system.capture_state(true)
			spawn = dock.level_root.spawn_system.create_default_spawn()
			if dock.undo_redo and spawn and not pre_state.is_empty():
				record_spawn_create_undo(dock, pre_state)

	var mask = dock.get_collision_layer_mask()
	if not await dock.level_root.bake(true, false, mask):
		restore_cordon_state(dock, prev_cordons)
		dock.show_toast("Test cancelled because the selected area could not be baked", 2)
		return

	if spawn and dock.level_root.spawn_system:
		var validation: Dictionary = dock.level_root.spawn_system.validate_spawn(spawn, mask)
		var severity: int = validation.get("severity", 0)
		var issues: PackedStringArray = validation.get("issues", PackedStringArray())

		if severity >= 2:
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 10.0)
			dock.show_toast("Spawn issues: %s" % "\n".join(issues), 2)
			show_spawn_fix_dialog(dock, spawn, validation, mask)
			restore_cordon_state(dock, prev_cordons)
			return
		if severity >= 1:
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 6.0)
			dock.show_toast("Spawn warning: %s" % "\n".join(issues), 1)

	# Before the launch, for the same reason as the camera spawn above.
	restore_cordon_state(dock, prev_cordons)
	launch_playtest(dock, {"cordon": play_area})


static func restore_cordon_state(dock: Object, cordons: Dictionary) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.restore_cordons(cordons)


## The saved bake profiles, the project's and this machine's, each held to what
## the level can take. A name both keep is the project's.
static func saved_bake_profiles(dock: Object) -> Dictionary:
	return bake_profile_sources(dock)["all"]


## The saved profiles by where they are kept: `project`, `mine` and `all`. Read
## again when the preferences or the project file change.
static func bake_profile_sources(dock: Object) -> Dictionary:
	var none := {"project": {}, "mine": {}, "all": {}}
	if not dock.level_root:
		return none
	var prefs = dock._user_prefs
	var path := project_bake_profiles_path(dock)
	var stored: Dictionary = prefs.get_bake_profiles() if prefs else {}
	var key: int = [stored, path, FileAccess.get_modified_time(path)].hash()
	if key != _saved_profiles_key:
		var project := HFBakeProfilesType.read_project(dock.level_root, path)
		var mine := HFBakeProfilesType.read_saved(dock.level_root, prefs)
		_saved_profiles = {
			"project": project, "mine": mine, "all": HFBakeProfilesType.combined(project, mine)
		}
		_saved_profiles_key = key
	return _saved_profiles


## Where this project keeps its shared bake profiles: beside the brush presets.
static func project_bake_profiles_path(dock: Object) -> String:
	return str(dock.presets_dir).path_join(HFBakeProfilesType.PROJECT_FILE)


## Whether Save and Delete are about the project's profiles rather than this
## machine's.
static func _for_the_project(dock: Object) -> bool:
	var check: CheckBox = dock.bake_profile_project_check
	return check != null and check.button_pressed


## List every profile and select the one the level is on, or Custom once an
## option has been changed by hand. Read from the options each time, so it follows
## a load, an undo or an Inspector edit as soon as the dock resyncs.
static func sync_bake_profile_ui(dock: Object) -> void:
	var opt: OptionButton = dock.bake_profile_opt
	if opt == null:
		return
	opt.clear()
	opt.disabled = not dock.level_root
	if dock.level_root:
		var sources := bake_profile_sources(dock)
		var saved: Dictionary = sources["all"]
		var on := HFBakeProfilesType.current(dock.level_root, saved)
		for profile_name in HFBakeProfilesType.names(saved):
			# The project's are marked; the item's metadata is the name either way.
			var shared: bool = sources["project"].has(profile_name)
			opt.add_item("%s (project)" % profile_name if shared else profile_name)
			opt.set_item_metadata(opt.item_count - 1, profile_name)
			if shared:
				opt.set_item_tooltip(
					opt.item_count - 1, "Kept in the project, so everyone on it has this profile"
				)
			if profile_name == on:
				opt.select(opt.item_count - 1)
		if on == "":
			opt.add_item(HFBakeProfilesType.CUSTOM)
			opt.set_item_metadata(opt.item_count - 1, "")
			opt.set_item_disabled(opt.item_count - 1, true)
			opt.select(opt.item_count - 1)
	sync_bake_profile_buttons(dock)


## Save takes any name but a built-in one. Delete takes a saved profile's name,
## and a changed name starts its two presses over.
static func sync_bake_profile_buttons(dock: Object) -> void:
	if dock.bake_profile_name == null:
		return
	var profile_name := HFBakeProfilesType.clean_name(dock.bake_profile_name.text)
	if profile_name != dock._bake_profile_delete_ack:
		dock._bake_profile_delete_ack = ""
	var save_hint := ""
	if not dock.level_root:
		save_hint = "Needs a LevelRoot to read the options from"
	elif profile_name == "":
		save_hint = "Type a name to save the options under"
	elif HFBakeProfilesType.is_reserved_name(profile_name):
		save_hint = "The list already uses %s. Save under another name" % profile_name
	elif not _for_the_project(dock) and _is_project_profile(dock, profile_name):
		save_hint = "%s is the project's. Tick Project to update it" % profile_name
	dock._set_control_disabled_hint(dock.bake_profile_save_btn, save_hint != "", save_hint)
	var saved := saved_bake_profiles(dock)
	dock._set_control_disabled_hint(
		dock.bake_profile_delete_btn,
		not saved.has(profile_name),
		"Type the name of a profile you saved. Editing and Shipping are built in"
	)


static func _is_project_profile(dock: Object, profile_name: String) -> bool:
	return bake_profile_sources(dock)["project"].has(profile_name)


## Set the options the picked profile names, as one undo step. Picking a saved
## profile also names it in the box, so Save updates it and Delete removes it.
static func on_bake_profile_selected(dock: Object, index: int) -> void:
	var opt: OptionButton = dock.bake_profile_opt
	if not dock.level_root or opt == null or index < 0 or index >= opt.item_count:
		return
	var profile_name := str(opt.get_item_metadata(index))
	var saved := saved_bake_profiles(dock)
	var values := HFBakeProfilesType.values_of(profile_name, saved)
	if values.is_empty():
		return
	if dock.bake_profile_name:
		dock.bake_profile_name.text = profile_name if saved.has(profile_name) else ""
	if dock.bake_profile_project_check and saved.has(profile_name):
		dock.bake_profile_project_check.button_pressed = _is_project_profile(dock, profile_name)
	var changed := HFBakeProfilesType.count_changes(dock.level_root, values)
	if changed == 0:
		sync_bake_profile_ui(dock)
		dock._set_status("The bake options are already on %s" % profile_name, false, 3.0)
		return
	var before: Dictionary = dock.level_root.capture_bake_options()
	dock.level_root.apply_bake_options(values)
	dock._commit_bake_profile("Bake Profile: %s" % profile_name, before)
	dock.show_toast(
		(
			"Bake profile %s: %d option%s changed"
			% [profile_name, changed, "" if changed == 1 else "s"]
		),
		0
	)


## Record a profile switch the dock has just made: the options before it and
## after it. Nothing is recorded when nothing changed.
static func record_bake_profile(
	undo_redo, root: Node, action_name: String, before: Dictionary
) -> bool:
	if undo_redo == null or root == null:
		return false
	var after: Dictionary = root.capture_bake_options()
	if after == before:
		return false
	undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, root, false)
	undo_redo.add_do_method(root, "apply_bake_options", after)
	undo_redo.add_undo_method(root, "apply_bake_options", before)
	undo_redo.commit_action(false)
	return true


## Keep every option a profile carries under the typed name, replacing a saved
## profile of that name. A built-in name is refused. With Project ticked it goes
## into the project's file, and a copy this machine kept under the same name is
## dropped, since the project's would hide it from now on.
static func on_bake_profile_save(dock: Object) -> void:
	if not dock.level_root or dock.bake_profile_name == null:
		return
	var profile_name := HFBakeProfilesType.clean_name(dock.bake_profile_name.text)
	if profile_name == "" or HFBakeProfilesType.is_reserved_name(profile_name):
		sync_bake_profile_buttons(dock)
		return
	if _for_the_project(dock):
		_save_project_bake_profile(dock, profile_name)
		return
	if _is_project_profile(dock, profile_name):
		sync_bake_profile_buttons(dock)
		return
	if dock._user_prefs == null:
		dock._set_status("No preferences to save the profile in", true)
		return
	var replacing: bool = saved_bake_profiles(dock).has(profile_name)
	dock._user_prefs.set_bake_profile(profile_name, dock.level_root.capture_bake_options())
	dock.bake_profile_name.text = profile_name
	sync_bake_profile_ui(dock)
	dock.show_toast("Bake profile %s %s" % [profile_name, "updated" if replacing else "saved"], 0)


static func _save_project_bake_profile(dock: Object, profile_name: String) -> void:
	var path := project_bake_profiles_path(dock)
	var profiles := HFBakeProfilesType.read_project_raw(path)
	var replacing := profiles.has(profile_name)
	profiles[profile_name] = dock.level_root.capture_bake_options()
	if not HFBakeProfilesType.write_project(profiles, path):
		dock._set_status("Could not write %s" % path, true)
		return
	if dock._user_prefs and dock._user_prefs.get_bake_profiles().has(profile_name):
		dock._user_prefs.remove_bake_profile(profile_name)
	_saved_profiles_key = 0
	dock.bake_profile_name.text = profile_name
	sync_bake_profile_ui(dock)
	dock.show_toast(
		(
			"Bake profile %s %s in the project. Commit %s to share it"
			% [profile_name, "updated" if replacing else "saved", path.get_file()]
		),
		0
	)


## Delete the saved profile named in the box. A saved profile is not on the undo
## stack, so the first press says what the second will do.
##
## A project profile is deleted from the project's file. That file is in version
## control, so the deletion is a change to commit like any other.
static func on_bake_profile_delete(dock: Object) -> void:
	if dock.bake_profile_name == null:
		return
	var profile_name := HFBakeProfilesType.clean_name(dock.bake_profile_name.text)
	if not saved_bake_profiles(dock).has(profile_name):
		sync_bake_profile_buttons(dock)
		return
	var shared := _is_project_profile(dock, profile_name)
	if not shared and dock._user_prefs == null:
		return
	if dock._bake_profile_delete_ack != profile_name:
		dock._bake_profile_delete_ack = profile_name
		var where := " from the project" if shared else ""
		dock._set_status(
			(
				"Press Delete again to delete bake profile %s%s. It cannot be undone"
				% [profile_name, where]
			),
			true
		)
		return
	dock._bake_profile_delete_ack = ""
	if shared:
		var path := project_bake_profiles_path(dock)
		var profiles := HFBakeProfilesType.read_project_raw(path)
		profiles.erase(profile_name)
		if not HFBakeProfilesType.write_project(profiles, path):
			dock._set_status("Could not write %s" % path, true)
			return
		_saved_profiles_key = 0
	else:
		dock._user_prefs.remove_bake_profile(profile_name)
	dock.bake_profile_name.text = ""
	sync_bake_profile_ui(dock)
	dock.show_toast("Bake profile %s deleted" % profile_name, 0)


static func on_export_playtest(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Export Playtest Build requested")
	if not dock.level_root or not can_start_bake(dock, "Export Playtest"):
		dock.show_toast("No LevelRoot active", 2)
		return

	var spawn: Node3D = null
	if dock.level_root.spawn_system:
		spawn = dock.level_root.spawn_system.get_active_spawn()
	if not spawn:
		dock.show_toast("No player_start found — creating default spawn", 1)
		if dock.level_root.spawn_system:
			var pre_state: Dictionary = {}
			if dock.undo_redo and dock.level_root.state_system:
				pre_state = dock.level_root.state_system.capture_state(true)
			spawn = dock.level_root.spawn_system.create_default_spawn()
			if dock.undo_redo and spawn and not pre_state.is_empty():
				record_spawn_create_undo(dock, pre_state)

	var mask = dock.get_collision_layer_mask()
	if spawn and dock.level_root.spawn_system:
		var validation: Dictionary = dock.level_root.spawn_system.validate_spawn(spawn, mask)
		var severity: int = validation.get("severity", 0)
		if severity >= 2:
			var issues: PackedStringArray = validation.get("issues", PackedStringArray())
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 10.0)
			dock.show_toast("Spawn blocked: %s" % "\n".join(issues), 2)
			return

	dock.show_toast("Baking for playtest...", 0)
	if not await dock.level_root.bake(true, false, mask):
		dock.show_toast("Export cancelled because the level could not be baked", 2)
		return
	dock.show_toast("Bake complete — exporting scene...", 0)

	var export_path := "user://hammerforge_playtest.tscn"
	var success: bool = dock.level_root.export_playtest_scene(export_path)
	if not success:
		dock.show_toast("Export failed — could not pack scene", 2)
		return

	dock.show_toast("Launching playtest...", 0)
	if dock.editor_interface:
		dock.editor_interface.play_custom_scene(export_path)
	else:
		dock.show_toast("No EditorInterface — cannot launch", 2)


## Write the level as a scene the game loads, beside the level's own scene.
##
## Export Playtest Build validates a spawn, bakes, exports and launches. This does
## the middle two and stops: there is nobody to drop at a spawn, because the game
## brings its own player. What it writes has the same geometry and the same real
## entity nodes - a light_point as an OmniLight3D, a logic_timer as a Timer - and
## none of the debug rig (#697, #698).
static func on_export_game_scene(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Export Game Scene requested")
	if not dock.level_root or not can_start_bake(dock, "Export Game Scene"):
		dock.show_toast("No LevelRoot active", 2)
		return

	dock.show_toast("Baking for export...", 0)
	var mask = dock.get_collision_layer_mask()
	if not await dock.level_root.bake(true, false, mask):
		dock.show_toast("Export cancelled because the level could not be baked", 2)
		return

	var export_path := _game_scene_path(dock)
	if not dock.level_root.export_game_scene(export_path):
		dock.show_toast("Export failed — could not pack scene", 2)
		return
	# Say which bake options went into the game, and warn on the Editing ones:
	# unmerged meshes and no LODs are right while a level changes, not in a game.
	var profile := HFBakeProfilesType.current(dock.level_root, saved_bake_profiles(dock))
	if profile == HFBakeProfilesType.EDITING:
		var warning := (
			"Game scene written to %s with the Editing bake options. "
			+ "Pick Shipping in Test > Advanced Bake and export again for a game."
		)
		dock.show_toast(warning % export_path, 1)
		return
	if profile == "":
		profile = HFBakeProfilesType.CUSTOM
	dock.show_toast("Game scene written to %s with the %s bake options" % [export_path, profile], 0)


## Beside the level's own scene, named after it, so a project ends up with
## `arena.tscn` and `arena_game.tscn` rather than a file in user:// nobody finds.
static func _game_scene_path(dock: Object) -> String:
	var source := ""
	if dock.level_root.has_method("scene_source_path"):
		source = str(dock.level_root.scene_source_path())
	if source == "" or not source.begins_with("res://"):
		return "res://hammerforge_game_scene.tscn"
	return "%s/%s_game.tscn" % [source.get_base_dir(), source.get_file().get_basename()]


static func show_spawn_fix_dialog(
	dock: Object, spawn: Node3D, validation: Dictionary, _mask: int
) -> void:
	if dock == null:
		return
	var issues: PackedStringArray = validation.get("issues", PackedStringArray())
	# With nowhere to move the spawn, the button said Fix & Play and the toast said
	# fixed, and the player started where they were, inside the brush (#1002).
	var suggested: Vector3 = validation.get("suggested_position", spawn.global_position)
	var fixes := suggested != spawn.global_position
	var dialog := ConfirmationDialog.new()
	dialog.title = "Quick Play — Spawn Warning"
	var ask := "Fix automatically and play, or cancel?"
	if not fixes:
		ask = "There is nowhere near to move it. Play anyway, or cancel and move it by hand?"
	dialog.dialog_text = "Player spawn may be invalid:\n\n%s\n\n%s" % ["\n".join(issues), ask]
	dialog.ok_button_text = "Fix & Play" if fixes else "Play Anyway"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(
		func():
			if not is_instance_valid(dock):
				dialog.queue_free()
				return
			if is_instance_valid(spawn) and dock.level_root and dock.level_root.spawn_system:
				dock.level_root.spawn_system.cleanup_debug()
				if fixes:
					var old_pos := spawn.global_position
					dock.level_root.spawn_system.auto_fix_spawn(spawn, validation)
					record_spawn_move_undo(dock, spawn, old_pos, spawn.global_position)
					dock.show_toast("Spawn fixed — launching playtest", 0)
			launch_playtest(dock)
			dialog.queue_free()
	)
	dialog.canceled.connect(
		func():
			if is_instance_valid(dock):
				dock.show_toast("Quick Play cancelled", 0)
			dialog.queue_free()
	)
	dock.add_child(dialog)
	dialog.popup_centered()


static func record_spawn_create_undo(dock: Object, before_state: Dictionary) -> void:
	if (
		dock == null
		or not dock.undo_redo
		or not dock.level_root
		or not dock.level_root.state_system
	):
		return
	var after_state: Dictionary = dock.level_root.state_system.capture_state(true)
	dock.undo_redo.create_action("Auto-create player_start")
	dock.undo_redo.add_do_method(dock.level_root.state_system, "restore_state", after_state)
	dock.undo_redo.add_undo_method(dock.level_root.state_system, "restore_state", before_state)
	dock.undo_redo.commit_action(false)


static func record_spawn_move_undo(
	dock: Object, spawn: Node3D, old_pos: Vector3, new_pos: Vector3
) -> void:
	if dock == null or not dock.undo_redo or not dock.level_root or old_pos == new_pos:
		return
	dock.undo_redo.create_action("Fix player_start position")
	dock.undo_redo.add_do_property(spawn, "global_position", new_pos)
	dock.undo_redo.add_undo_property(spawn, "global_position", old_pos)
	dock.undo_redo.commit_action(false)


static func restore_spawn(spawn: Node3D, pos: Vector3, angle_deg: float) -> void:
	if not is_instance_valid(spawn):
		return
	spawn.global_position = pos
	if spawn is DraftEntity:
		(spawn as DraftEntity).entity_data["angle"] = angle_deg


static func on_spawn_validate(dock: Object) -> void:
	if dock == null or not dock.level_root or not dock.level_root.spawn_system:
		if dock:
			dock.show_toast("No LevelRoot available", 1)
		return
	if not can_start_bake(dock, "Validate Spawn"):
		dock.show_toast("No LevelRoot available", 1)
		return
	var spawn = dock.level_root.spawn_system.get_active_spawn()
	if not spawn:
		dock.show_toast("No player_start entity found", 1)
		return
	var mask = dock.get_collision_layer_mask()
	dock.show_toast("Baking before validation…", 0)
	if not await dock.level_root.bake(true, false, mask):
		dock.show_toast("Spawn validation cancelled because the level could not be baked", 2)
		return
	if not is_instance_valid(spawn) or not spawn.is_inside_tree():
		dock.show_toast("Spawn was removed during bake", 2)
		return
	var validation: Dictionary = dock.level_root.spawn_system.validate_spawn(spawn, mask)
	dock.level_root.spawn_system.show_validation_debug(spawn, validation, 10.0)
	var issues: PackedStringArray = validation.get("issues", PackedStringArray())
	if validation.get("valid", false):
		dock.show_toast("Spawn is valid", 0)
	else:
		dock.show_toast("Spawn issues: %s" % "\n".join(issues), 2)


static func on_spawn_auto_create(dock: Object) -> void:
	if dock == null or not dock.level_root or not dock.level_root.spawn_system:
		if dock:
			dock.show_toast("No LevelRoot available", 1)
		return
	var existing = dock.level_root.spawn_system.get_active_spawn()
	if existing:
		dock.show_toast("player_start already exists — select and move it instead", 1)
		return
	var pre_state: Dictionary = {}
	if dock.level_root.state_system:
		pre_state = dock.level_root.state_system.capture_state(true)
	var spawn = dock.level_root.spawn_system.create_default_spawn()
	if spawn and not pre_state.is_empty():
		dock._commit_spawn_create(pre_state)
	dock.show_toast("Default player_start created", 0)


static func on_show_spawn_debug_toggled(dock: Object, enabled: bool) -> void:
	if dock == null or not dock.level_root or not dock.level_root.spawn_system:
		return
	if enabled:
		if not can_start_bake(dock, "Show Spawn Preview"):
			if dock._show_spawn_debug:
				dock._show_spawn_debug.set_pressed_no_signal(false)
			return
		var spawn = dock.level_root.spawn_system.get_active_spawn()
		if not spawn:
			dock.show_toast("No player_start to preview", 1)
			if dock._show_spawn_debug:
				dock._show_spawn_debug.set_pressed_no_signal(false)
			return
		var mask = dock.get_collision_layer_mask()
		if not await dock.level_root.bake(true, false, mask):
			dock.show_toast("Spawn preview cancelled because the level could not be baked", 2)
			if dock._show_spawn_debug:
				dock._show_spawn_debug.set_pressed_no_signal(false)
			return
		if not is_instance_valid(spawn) or not spawn.is_inside_tree():
			dock.show_toast("Spawn was removed during bake", 2)
			if dock._show_spawn_debug:
				dock._show_spawn_debug.set_pressed_no_signal(false)
			return
		var validation: Dictionary = dock.level_root.spawn_system.validate_spawn(spawn, mask)
		dock.level_root.spawn_system.show_validation_debug(spawn, validation, 0.0)
	else:
		dock.level_root.spawn_system.cleanup_debug()


## Every way the dock starts a playtest goes through here, so that the run it
## starts can tell itself apart from the mapper running their own game (#771).
## `overrides` is what that one run should do differently from the scene, and
## goes into the request rather than onto the level (#822). See
## `HFPlaytestRequest.write()` for the keys.
static func launch_playtest(dock: Object, overrides: Dictionary = {}) -> void:
	if dock == null:
		return
	request_playtest_player(dock, overrides)
	notify_running_instances(dock)
	if dock.editor_interface:
		dock.editor_interface.play_current_scene()


## Leave the request the launched run will collect. Written rather than set on
## the node because `play_current_scene()` plays the scene *file*: a property set
## here would have to be saved into the mapper's own scene to reach the running
## instance, and would then be on for their shipped game too -- which is the
## second character controller #719 removed.
static func request_playtest_player(dock: Object, overrides: Dictionary = {}) -> void:
	if HFPlaytestRequest.write(overrides):
		return
	if dock != null:
		dock._log("Failed to write the playtest request file", true)


static func notify_running_instances(dock: Object) -> void:
	if dock == null:
		return
	var lock_dir = "res://.hammerforge"
	var abs_lock_dir = ProjectSettings.globalize_path(lock_dir)
	if not DirAccess.dir_exists_absolute(abs_lock_dir):
		DirAccess.make_dir_recursive_absolute(abs_lock_dir)
	var file = FileAccess.open("%s/reload.lock" % lock_dir, FileAccess.WRITE)
	if not file:
		dock._log("Failed to write reload lock file", true)
		return
	file.store_string(str(Time.get_ticks_msec()))


static func warn_missing_dependencies(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	var warnings: Array = dock.level_root.check_missing_dependencies()
	if warnings.is_empty():
		return
	dock._set_status_warning("Missing dependencies: %d (see Output)" % warnings.size(), 5.0)
	for warning in warnings:
		dock._log("Dependency: %s" % str(warning), true)


static func run_validation(dock: Object, auto_fix: bool) -> void:
	if dock == null or not dock.level_root:
		if dock:
			dock._set_status("No LevelRoot for validation", true)
		return
	var result: Dictionary = {}
	var issues: Array = []
	var fixed := 0
	if auto_fix:
		# The repair count comes from the validator, which counted it exactly.
		# It used to be re-derived as before minus after, which is not the number
		# of repairs: a pass that fixes one issue and exposes another reported
		# zero fixed. That cost a whole validation pass as well.
		#
		# The second pass is what remains afterwards. `validate()` reports every
		# finding whether or not it repaired it, so its own list is not the
		# residue - and the residue is the one thing a mapper wants after an
		# auto-fix. The log used to print the list from before the fix, so every
		# repaired issue was listed as though it were still there.
		var before: Dictionary = dock.level_root.capture_state()
		fixed = int(dock.level_root.validate_level(true).get("fixed", 0))
		HFUndoHelper.commit_completed(
			dock.undo_redo,
			dock.level_root,
			"Validate + Fix",
			before,
			Callable(dock, "record_history")
		)
		result = dock.level_root.validate_level(false)
		issues = result.get("issues", [])
	else:
		result = dock.level_root.validate_level(false)
		issues = result.get("issues", [])
	if issues.is_empty():
		if auto_fix and fixed > 0:
			dock._set_status("Validate: fixed %d, no issues left" % fixed, false, 3.0)
		else:
			dock._set_status("Validate: no issues found", false, 3.0)
		return
	var message = "Validate: %d issue(s)" % issues.size()
	if auto_fix:
		message = "Validate: fixed %d, %d remaining" % [fixed, issues.size()]
	dock._set_status_warning(message, 6.0)
	for issue in issues:
		dock._log("[Validate] %s" % str(issue), true)
