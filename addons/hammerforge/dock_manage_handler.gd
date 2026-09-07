@tool
class_name HFDockManageHandler
extends RefCounted
## Test-tab bake, play, spawn, and validation handlers extracted from dock.gd.

const DraftEntity = preload("draft_entity.gd")
const HFUndoHelper = preload("undo_helper.gd")


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
	var shown := 0
	for issue in issues:
		if shown >= 3:
			break
		var msg: String = issue.get("message", "")
		var sev: int = issue.get("severity", 0)
		dock.show_toast(msg, min(sev, 2))
		shown += 1
	if issues.size() > 3:
		dock.show_toast("...and %d more issues (check Output)" % (issues.size() - 3), 1)
	for issue in issues:
		push_warning("HF Bake Issue: %s" % issue.get("message", ""))


static func update_bake_estimate(dock: Object) -> void:
	if dock == null or not dock.level_root or not dock.bake_estimate_label:
		return
	var est: Dictionary = dock.level_root.estimate_bake_time()
	var ms: int = est.get("estimated_ms", 0)
	var count: int = est.get("brush_count", 0)
	var tip: String = est.get("tip", "")
	var time_str := ""
	if ms < 1000:
		time_str = "%d ms" % ms
	elif ms < 60000:
		time_str = "%.1f s" % (float(ms) / 1000.0)
	else:
		time_str = "%.1f min" % (float(ms) / 60000.0)
	var label_text := "Est: %s (%d brushes)" % [time_str, count]
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
	if success:
		dock._set_status("Bake complete", false, 3.0)
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

	notify_running_instances(dock)
	if dock.editor_interface:
		dock.editor_interface.play_current_scene()


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

	notify_running_instances(dock)
	if dock.editor_interface:
		dock.editor_interface.play_current_scene()

	restore_spawn(spawn, old_pos, old_angle)


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

	var prev_cordon_enabled: bool = dock.level_root.cordon_enabled
	var prev_cordon_aabb: AABB = dock.level_root.cordon_aabb

	dock.level_root.set_cordon_from_selection(dock._selection_nodes)
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
		restore_cordon_state(dock, prev_cordon_enabled, prev_cordon_aabb)
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
			restore_cordon_state(dock, prev_cordon_enabled, prev_cordon_aabb)
			return
		if severity >= 1:
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 6.0)
			dock.show_toast("Spawn warning: %s" % "\n".join(issues), 1)

	notify_running_instances(dock)
	if dock.editor_interface:
		dock.editor_interface.play_current_scene()

	restore_cordon_state(dock, prev_cordon_enabled, prev_cordon_aabb)


static func restore_cordon_state(dock: Object, enabled: bool, bounds: AABB) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.cordon_enabled = enabled
	dock.level_root.cordon_aabb = bounds
	dock.level_root.tag_full_reconcile()
	dock.level_root.update_cordon_visual()


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

	if spawn and dock.level_root.spawn_system:
		var mask = dock.get_collision_layer_mask()
		var validation: Dictionary = dock.level_root.spawn_system.validate_spawn(spawn, mask)
		var severity: int = validation.get("severity", 0)
		if severity >= 2:
			var issues: PackedStringArray = validation.get("issues", PackedStringArray())
			dock.level_root.spawn_system.show_validation_debug(spawn, validation, 10.0)
			dock.show_toast("Spawn blocked: %s" % "\n".join(issues), 2)
			return

	dock.show_toast("Baking for playtest...", 0)
	var mask = dock.get_collision_layer_mask()
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


static func show_spawn_fix_dialog(
	dock: Object, spawn: Node3D, validation: Dictionary, _mask: int
) -> void:
	if dock == null:
		return
	var issues: PackedStringArray = validation.get("issues", PackedStringArray())
	var dialog := ConfirmationDialog.new()
	dialog.title = "Quick Play — Spawn Warning"
	dialog.dialog_text = (
		"Player spawn may be invalid:\n\n"
		+ "\n".join(issues)
		+ "\n\nFix automatically and play, or cancel?"
	)
	dialog.ok_button_text = "Fix & Play"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(
		func():
			if not is_instance_valid(dock):
				dialog.queue_free()
				return
			if is_instance_valid(spawn) and dock.level_root and dock.level_root.spawn_system:
				var old_pos := spawn.global_position
				dock.level_root.spawn_system.auto_fix_spawn(spawn, validation)
				dock.level_root.spawn_system.cleanup_debug()
				record_spawn_move_undo(dock, spawn, old_pos, spawn.global_position)
				dock.show_toast("Spawn fixed — launching playtest", 0)
			notify_running_instances(dock)
			if dock.editor_interface:
				dock.editor_interface.play_current_scene()
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
	if dock.undo_redo and dock.level_root.state_system:
		pre_state = dock.level_root.state_system.capture_state(true)
	var spawn = dock.level_root.spawn_system.create_default_spawn()
	if spawn and not pre_state.is_empty():
		record_spawn_create_undo(dock, pre_state)
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
		result = dock.level_root.validate_level(false)
		issues = result.get("issues", [])
		var before_count = issues.size()
		HFUndoHelper.commit(
			dock.undo_redo,
			dock.level_root,
			"Validate + Fix",
			"validate_level",
			[true],
			false,
			Callable(dock, "record_history")
		)
		var after = dock.level_root.validate_level(false)
		var after_count = int(after.get("issues", []).size())
		fixed = max(0, before_count - after_count)
	else:
		result = dock.level_root.validate_level(false)
		issues = result.get("issues", [])
	if issues.is_empty():
		dock._set_status("Validate: no issues found", false, 3.0)
		return
	var message = "Validate: %d issue(s)" % issues.size()
	if auto_fix:
		message += ", fixed %d" % fixed
	dock._set_status_warning(message, 6.0)
	for issue in issues:
		dock._log("[Validate] %s" % str(issue), true)
