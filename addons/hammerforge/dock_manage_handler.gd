@tool
class_name HFDockManageHandler
extends RefCounted
## Test-tab bake, play, spawn, and validation handlers extracted from dock.gd.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFPlaytestRequest = preload("hf_playtest_request.gd")
const HFBakeProfilesType = preload("hf_bake_profiles.gd")
const HFAcceptedFindings = preload("hf_accepted_findings.gd")
const HFValidationChecks = preload("hf_validation_checks.gd")
const HFTranslationType = preload("hf_translation.gd")

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
	apply_pending_cuts_as_a_step(dock)
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
	if not is_instance_valid(dock):
		return
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
	if not is_instance_valid(dock):
		return
	set_bake_buttons_disabled(dock, false)
	if succeeded:
		dock.record_history("Bake Selected")


static func on_bake_changed(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Bake changed requested")
	if not dock.level_root or not can_start_bake(dock, "Bake Changed"):
		return
	apply_pending_cuts_as_a_step(dock)
	dock._warn_missing_dependencies()
	var mask = dock.get_collision_layer_mask()
	set_bake_buttons_disabled(dock, true)
	var succeeded: bool = await dock.level_root.bake_dirty(mask, get_bake_preview_mode(dock))
	if not is_instance_valid(dock):
		return
	set_bake_buttons_disabled(dock, false)
	if succeeded:
		dock.record_history("Bake Changed")


static func on_bake_check_issues(dock: Object) -> void:
	if dock == null or not dock.level_root or not dock.level_root.validation_system:
		return
	var issues: Array = dock.level_root.validation_system.check_bake_issues()
	if dock.level_root.spawn_system:
		issues.append_array(dock.level_root.spawn_system.layout_issues())
	var sorted := HFAcceptedFindings.sort(dock.level_root, issues)
	show_findings(dock, sorted["open"], sorted["accepted"], "bake")
	issues = sorted["open"]
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
	var summary := HFTranslationType.t("Bake check: {errors} errors, {warnings} warnings").format(
		{"errors": errors, "warnings": warnings}
	)
	dock._set_status(summary, errors > 0, 5.0)
	var listed := HFTranslationType.t("{summary}, listed under Check Bake Issues")
	dock.show_toast(listed.format({"summary": summary}), mini(1 + int(errors > 0), 2))
	for issue in issues:
		push_warning("HF Bake Issue: %s" % issue.get("message", ""))


## Fill the list under Check Bake Issues, one row per issue (#992). Validate fills
## it too, with its own findings (#1004). A row that names an object can select it. A row whose fix is one mechanical edit has a
## Fix button that makes it as one undo step and checks again; the rest stay rows,
## because a fix that is a judgement call is the mapper's.
static func show_bake_issue_list(dock: Object, issues: Array) -> void:
	var sorted := HFAcceptedFindings.sort(dock.level_root, issues)
	show_findings(dock, sorted["open"], sorted["accepted"], "bake")


## Keep what the list shows, `open` findings and the `accepted` ones set aside,
## and which button found them, then draw it. An edit to what a Validate list
## names is checked again from this once it settles (#1731).
static func show_findings(dock: Object, open: Array, accepted: Array, source: String) -> void:
	dock._shown_findings = {"open": open, "accepted": accepted, "source": source}
	dock._findings_changed_ids = {}
	dock._findings_entities_changed = false
	render_findings(dock)


## Draw the list from what it keeps: a row per open finding, the accepted ones
## when Show accepted is on, and a Select All row per kind.
static func render_findings(dock: Object) -> void:
	var list: VBoxContainer = dock.bake_issue_list
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var shown: Dictionary = dock._shown_findings
	var issues: Array = _still_there(shown.get("open", []))
	var accepted: Array = _still_there(shown.get("accepted", []))
	var with_accepted: bool = (
		dock.show_accepted_findings != null and dock.show_accepted_findings.button_pressed
	)
	for issue in issues:
		list.add_child(_bake_issue_row(dock, issue))
	if with_accepted:
		for issue in accepted:
			list.add_child(_accepted_row(dock, issue))
	for kind in KIND_ROWS:
		var nodes := _nodes_of_kind(issues, kind)
		if not nodes.is_empty():
			list.add_child(_kind_row(dock, kind, nodes))
	list.visible = list.get_child_count() > 0
	if dock.show_accepted_findings != null:
		dock.show_accepted_findings.text = HFTranslationType.t("Show accepted ({count})").format(
			{"count": accepted.size()}
		)


## The findings whose objects are still in the level. A row naming a brush that
## was deleted has nothing left to select.
static func _still_there(findings: Array) -> Array:
	var out: Array = []
	for finding in findings:
		var node: Variant = finding.get("node")
		if node != null and not is_instance_valid(node):
			continue
		var other: Variant = finding.get("other_node")
		if other != null and not is_instance_valid(other):
			continue
		out.append(finding)
	return out


## A row for an accepted finding: what it says, why it is fine and when that was
## said, and Un-accept.
static func _accepted_row(dock: Object, issue: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var record: Dictionary = issue.get("accepted", {})
	var text := Label.new()
	var note := str(record.get("note", ""))
	var accepted := {"issue": str(issue.get("message", "")), "note": note}
	accepted["date"] = str(record.get("date", ""))
	text.text = (
		HFTranslationType.t("Accepted  {issue}: {note} ({date})").format(accepted)
		if note != ""
		else HFTranslationType.t("Accepted  {issue} ({date})").format(accepted)
	)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.modulate = Color(1, 1, 1, 0.6)
	row.add_child(text)
	var back := Button.new()
	back.text = "Un-accept"
	back.tooltip_text = "List this finding again on every pass"
	back.pressed.connect(dock._on_finding_unaccept.bind(str(issue.get("key", ""))))
	row.add_child(back)
	return row


## Accept `finding` with `note`, as one undo step, and draw the list again.
static func accept_finding(dock: Object, finding: Dictionary, note: String) -> void:
	if dock == null or not dock.level_root:
		return
	var before: Dictionary = dock.level_root.capture_state()
	var key := HFAcceptedFindings.accept(dock.level_root, finding, note)
	if key == "":
		return
	HFUndoHelper.commit_completed(
		dock.undo_redo, dock.level_root, "Accept Finding", before, Callable(dock, "record_history")
	)
	_resort_shown(dock)


## Take an acceptance back, as one undo step, and draw the list again.
static func unaccept_finding(dock: Object, key: String) -> void:
	if dock == null or not dock.level_root:
		return
	var before: Dictionary = dock.level_root.capture_state()
	if not HFAcceptedFindings.unaccept(dock.level_root, key):
		return
	HFUndoHelper.commit_completed(
		dock.undo_redo,
		dock.level_root,
		"Un-accept Finding",
		before,
		Callable(dock, "record_history")
	)
	_resort_shown(dock)


static func _resort_shown(dock: Object) -> void:
	var shown: Dictionary = dock._shown_findings
	var everything: Array = []
	for finding in shown.get("open", []) + shown.get("accepted", []):
		var plain: Dictionary = finding.duplicate()
		for key in ["key", "accepted", "changed_since_accepted", "accepted_note"]:
			plain.erase(key)
		everything.append(plain)
	var sorted := HFAcceptedFindings.sort(dock.level_root, everything)
	dock._shown_findings["open"] = sorted["open"]
	dock._shown_findings["accepted"] = sorted["accepted"]
	render_findings(dock)


## Ask why a finding is fine, then accept it.
static func open_accept_dialog(dock: Object, finding: Dictionary) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Accept Finding"
	dialog.ok_button_text = "Accept"
	var box := VBoxContainer.new()
	var says := Label.new()
	says.text = str(finding.get("message", ""))
	says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	says.custom_minimum_size = Vector2(320, 0)
	box.add_child(says)
	var note := LineEdit.new()
	note.name = "Note"
	note.placeholder_text = "Why this is fine, such as decorative, not walked"
	box.add_child(note)
	dialog.add_child(box)
	dialog.confirmed.connect(
		func():
			accept_finding(dock, finding, note.text)
			dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dock.add_child(dialog)
	dialog.popup_centered()
	note.grab_focus()
	return dialog


## An edit to the level while a Validate list shows: note what changed and wait
## for a second without edits before checking it again (#1731).
static func note_findings_change(dock: Object, brush_id: String, entities: bool) -> void:
	if dock == null or str(dock._shown_findings.get("source", "")) != "validate":
		return
	if brush_id != "":
		dock._findings_changed_ids[brush_id] = true
	if entities:
		dock._findings_entities_changed = true
	if dock._findings_settle == null or not is_instance_valid(dock._findings_settle):
		dock._findings_settle = Timer.new()
		dock._findings_settle.name = "FindingsSettle"
		dock._findings_settle.one_shot = true
		dock._findings_settle.wait_time = FINDINGS_SETTLE_SECONDS
		dock._findings_settle.timeout.connect(dock._on_findings_settled)
		dock.add_child(dock._findings_settle)
	if dock._findings_settle.is_inside_tree():
		dock._findings_settle.start()


## How long the level has to stay still before the list checks what changed.
const FINDINGS_SETTLE_SECONDS := 1.0


## Check again only what changed since the list was drawn, and redraw it: rows
## about a changed brush go, and what the recheck finds about them comes in.
static func settle_findings(dock: Object) -> void:
	if dock == null or not dock.level_root or not dock.level_root.validation_system:
		return
	var ids: Array = dock._findings_changed_ids.keys()
	var entities: bool = dock._findings_entities_changed
	dock._findings_changed_ids = {}
	dock._findings_entities_changed = false
	if ids.is_empty() and not entities:
		return
	var result: Dictionary = dock.level_root.validation_system.recheck(ids, entities)
	var shown: Dictionary = dock._shown_findings
	for part in ["open", "accepted"]:
		var kept: Array = []
		for finding in shown.get(part, []):
			if (
				_names_a_changed(finding, ids)
				or (entities and finding.get("check", "") == "entities")
			):
				continue
			kept.append(finding)
		kept.append_array(result.get(part, []))
		shown[part] = kept
	render_findings(dock)


static func _names_a_changed(finding: Dictionary, ids: Array) -> bool:
	for slot in ["node", "other_node"]:
		var node: Variant = finding.get(slot)
		if node is DraftBrush and is_instance_valid(node) and ids.has(str(node.brush_id)):
			return true
	return false


## Run a kind of check or leave it out, for the whole project.
static func set_check_runs(dock: Object, kind: String, on: bool) -> void:
	var err := HFValidationChecks.set_runs(kind, on)
	if dock and err == OK:
		var check := HFTranslationType.t(str(HFValidationChecks.KINDS[kind]))
		var said := (
			HFTranslationType.t("Validate runs: {check}")
			if on
			else HFTranslationType.t("Validate leaves out: {check}")
		)
		dock._set_status(said.format({"check": check}), false, 3.0)


## The kinds of finding a row below the list selects together (#1708). Each
## finding's `node` is the brush that adds nothing: the cut, the brush inside, the
## later of a near pair. `_kind_words()` says what the row calls them.
const KIND_ROWS := ["cut_cuts_nothing", "solid_inside_solid", "near_duplicate"]


## What the row for `count` findings of `kind` says, with a `{count}` to fill, and
## its Select All's tooltip. Whole sentences, so a language can inflect each.
static func _kind_words(kind: String, count: int) -> PackedStringArray:
	match kind:
		"cut_cuts_nothing":
			return [
				HFTranslationType.tn(
					"{count} cut that cuts nothing", "{count} cuts that cut nothing", count
				),
				HFTranslationType.t("Select every one of the cuts that cut nothing"),
			]
		"solid_inside_solid":
			return [
				HFTranslationType.tn(
					"{count} brush inside another", "{count} brushes inside another", count
				),
				HFTranslationType.t("Select every one of the brushes inside another"),
			]
	return [
		HFTranslationType.tn(
			"{count} later brush of a near pair", "{count} later brushes of near pairs", count
		),
		HFTranslationType.t("Select every one of the later brushes of near pairs"),
	]


static func _nodes_of_kind(issues: Array, kind: String) -> Array:
	var nodes: Array = []
	for issue in issues:
		var node: Variant = issue.get("node")
		if str(issue.get("kind", "")) == kind and node is Node and is_instance_valid(node):
			if not nodes.has(node):
				nodes.append(node)
	return nodes


## Select All for one kind, so the mapper can look and press Delete. A near pair
## also gets Keep First, which deletes the later brush of each pair as one undo
## step, and only when pressed.
static func _kind_row(dock: Object, kind: String, nodes: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var text := Label.new()
	var words := _kind_words(kind, nodes.size())
	text.text = words[0].format({"count": nodes.size()})
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var select := Button.new()
	select.text = "Select All"
	select.tooltip_text = words[1]
	select.pressed.connect(dock._on_bake_issue_select_all.bind(nodes))
	row.add_child(select)
	if kind == "near_duplicate":
		var keep := Button.new()
		keep.text = "Keep First"
		keep.tooltip_text = "Delete the later brush of each pair, as one undo step"
		keep.pressed.connect(dock._on_keep_first.bind(nodes))
		row.add_child(keep)
	return row


## Delete `later`, the later brush of each near pair, as one undo step, then
## validate again so the list shows what is left (#1708).
static func keep_first(dock: Object, later: Array) -> void:
	if dock == null or not dock.level_root:
		return
	var ids: Array = []
	for node in later:
		if node is DraftBrush and is_instance_valid(node):
			ids.append(dock.level_root.brush_system.ensure_brush_id(node))
	if ids.is_empty():
		return
	HFUndoHelper.commit(
		dock.undo_redo,
		dock.level_root,
		"Keep First",
		"delete_brushes_by_id",
		[ids],
		false,
		Callable(dock, "record_history")
	)
	var said := HFTranslationType.tn(
		"Kept the first of each pair: deleted {count} brush",
		"Kept the first of each pair: deleted {count} brushes",
		ids.size()
	)
	dock.show_toast(said.format({"count": ids.size()}), 0)
	run_validation(dock, false)


static func _bake_issue_row(dock: Object, issue: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var severity: int = clampi(int(issue.get("severity", 0)), 0, 2)
	var text := Label.new()
	var rows := [
		HFTranslationType.t("Info  {message}"),
		HFTranslationType.t("Warning  {message}"),
		HFTranslationType.t("Error  {message}"),
	]
	text.text = str(rows[severity]).format({"message": str(issue.get("message", ""))})
	if issue.get("changed_since_accepted", false):
		text.text += "  " + HFTranslationType.t("(changed since accepted)")
		var note := str(issue.get("accepted_note", ""))
		if note != "":
			text.tooltip_text = HFTranslationType.t("Accepted as: {note}").format({"note": note})
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var node: Variant = issue.get("node")
	if node is Node and is_instance_valid(node):
		var select := Button.new()
		select.text = "Select"
		select.tooltip_text = HFTranslationType.t("Select {name}").format(
			{"name": (node as Node).name}
		)
		# A finding about a pair, such as a micro-gap, selects both (#1037).
		var other: Variant = issue.get("other_node")
		if other is Node and is_instance_valid(other):
			select.tooltip_text = HFTranslationType.t("Select {name} and {other}").format(
				{"name": (node as Node).name, "other": (other as Node).name}
			)
			select.pressed.connect(dock._on_bake_issue_select.bind(node, other))
		else:
			select.pressed.connect(dock._on_bake_issue_select.bind(node))
		row.add_child(select)
	var fix := str(issue.get("fix", ""))
	if fix in BAKE_ISSUE_FIXES:
		var fix_button := Button.new()
		fix_button.text = "Fix"
		fix_button.tooltip_text = BAKE_ISSUE_FIXES[fix]
		fix_button.pressed.connect(dock._on_bake_issue_fix.bind(fix, node))
		row.add_child(fix_button)
	# Fine as it is for this level: set it aside, with a note (#1731).
	var accept := Button.new()
	accept.text = "Accept"
	accept.tooltip_text = "This is meant: stop listing it until what it names changes"
	accept.pressed.connect(dock._on_finding_accept.bind(issue))
	row.add_child(accept)
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
	var before_state: Dictionary = dock.level_root.state_system.capture_state(true)
	spawn.global_position = place
	dock._commit_spawn_move(before_state)
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


## The bake buttons and progress bar as the dock's level has them: disabled only
## while that level is baking. Run when the dock moves to another level, since a
## bake whose scene was closed under it never said it finished, and left the
## buttons disabled for every level after (#1290).
static func sync_bake_state_to_root(dock: Object) -> void:
	var root = dock.level_root
	var baking: bool = (
		root != null and root.has_method("is_bake_in_flight") and root.is_bake_in_flight()
	)
	if not baking and dock.progress_bar:
		dock.progress_bar.hide()
	set_bake_buttons_disabled(dock, baking)


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
		var wait := HFTranslationType.t(
			"{command} will be available when the current bake finishes"
		)
		dock.show_toast(wait.format({"command": action_label}), 1)
		return false
	return true


## A bake applies the pending cuts, moving them in among the brushes, and
## nothing recorded that: after Bake or Quick Play, Ctrl+Z could not bring a cut
## back to pending, and Quick Play's redo brought back the spawn it made and not
## the cuts the bake applied (#1353). Every bake the dock starts with cuts
## applied records the apply first, as a step of its own when there was anything
## to apply (#1303); the bake then finds none to apply. Undo puts the cuts back
## to pending, and the bake made after them goes with any other step undone past
## a bake, since the level it restores had none yet.
static func apply_pending_cuts_as_a_step(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	HFUndoHelper.apply_pending_cuts_step(
		dock.undo_redo, dock.level_root, Callable(dock, "record_history")
	)


## Whether the dock and the level a bake was started for are both still there once
## it is done, and the dock still on that level. A bake runs over frames, and the
## plugin can be disabled or the scene switched away from meanwhile. The action
## that awaited it then stops quietly: what it would test, ask about or launch has
## gone, and so may the dock it would say so in.
## Untyped, as a typed parameter refuses the freed object this exists to catch.
static func _came_back_to(dock, root) -> bool:
	return is_instance_valid(dock) and is_instance_valid(root) and dock.level_root == root


## The spawn a playtest starts from: the level's own, or a default one made for
## it as one undo step. Null, said as an error, when there is none and none could
## be made. The caller then stops before its bake: a run with no spawn starts
## wherever the level falls back to, which nobody judged. Play from Camera
## stopped there and the others baked and launched (#1460).
static func ensure_playtest_spawn(dock: Object) -> Node3D:
	var spawns = dock.level_root.spawn_system
	var spawn: Node3D = spawns.get_active_spawn() if spawns else null
	if spawn:
		return spawn
	if spawns:
		var before: Dictionary = {}
		if dock.undo_redo and dock.level_root.state_system:
			before = dock.level_root.state_system.capture_state(true)
		spawn = spawns.create_default_spawn()
		if spawn and not before.is_empty():
			record_spawn_create_undo(dock, before)
	if not spawn:
		dock.show_toast("No player_start found, and none could be made. Add one and try again", 2)
		return null
	dock.show_toast("No player_start found — auto-creating default spawn", 1)
	return spawn


## Judge the spawn a playtest starts from on the level its bake just made, by the
## rules every playtest keeps: an error stops the launch and asks what to do, a
## warning says so and plays on. Returns whether to launch. `start` is what the
## run launches with, as `launch_playtest()` takes it, and `launch` what the
## dialog's OK runs with it in place of `launch_playtest()`.
##
## A spawn gone by now, taken by an agent's edit or an undo, stops the run as
## well, for the same reason as a spawn that could not be made. `spawn` is untyped
## because a typed parameter refuses the freed object this checks for.
static func judge_spawn(
	dock: Object, spawn, mask: int, start: Dictionary = {}, launch: Callable = Callable()
) -> bool:
	var spawns = dock.level_root.spawn_system
	if not spawns or not is_instance_valid(spawn) or not spawn.is_inside_tree():
		dock.show_toast("Spawn was removed during bake", 2)
		return false
	var validation: Dictionary = spawns.validate_spawn(spawn, mask)
	var severity: int = validation.get("severity", 0)
	var issues: PackedStringArray = validation.get("issues", PackedStringArray())
	if severity >= 2:
		spawns.show_validation_debug(spawn, validation, 10.0)
		_say_spawn_issues(dock, issues)
		show_spawn_fix_dialog(dock, spawn, validation, mask, start, launch)
		return false
	if severity >= 1:
		spawns.show_validation_debug(spawn, validation, 6.0)
		var warned := HFTranslationType.t("Spawn warning: {issues}")
		dock.show_toast(warned.format({"issues": "\n".join(issues)}), 1)
	return true


static func on_quick_play(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Playtest requested")
	dock._warn_missing_dependencies()
	if not dock.level_root or not can_start_bake(dock, "Test Level"):
		return
	apply_pending_cuts_as_a_step(dock)
	var spawn := ensure_playtest_spawn(dock)
	if not spawn:
		return

	var mask = dock.get_collision_layer_mask()
	var root: Node = dock.level_root
	var baked: bool = await root.bake(true, false, mask)
	if not _came_back_to(dock, root):
		return
	if not baked:
		dock.show_toast("Test cancelled because the level could not be baked", 2)
		return
	if judge_spawn(dock, spawn, mask):
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
	apply_pending_cuts_as_a_step(dock)
	var spawn := ensure_playtest_spawn(dock)
	if not spawn:
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

	var start := {"spawn_position": camera.global_position, "spawn_yaw_degrees": camera_yaw_deg}
	var mask = dock.get_collision_layer_mask()
	var root: Node = dock.level_root
	var baked: bool = await root.bake(true, false, mask)
	if not _came_back_to(dock, root):
		restore_spawn(spawn, old_pos, old_angle)
		return
	if not baked:
		restore_spawn(spawn, old_pos, old_angle)
		dock.show_toast("Test cancelled because the level could not be baked", 2)
		return
	var judged_fit := judge_spawn(dock, spawn, mask, start)

	# Put back before the launch rather than after it. Godot saves the edited scene
	# on the way into a run, so a spawn still at the camera was written into the
	# mapper's scene file (#822). The run reads the camera pose from the request.
	restore_spawn(spawn, old_pos, old_angle)
	if judged_fit:
		launch_playtest(dock, start)


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
	apply_pending_cuts_as_a_step(dock)

	var prev_cordons: Dictionary = dock.level_root.capture_cordons()

	# The selected area alone: the level's other cordons would add their rooms,
	# and the first one may be switched off.
	var no_extra: Array[AABB] = []
	var all_on: Array[bool] = []
	dock.level_root.cordon_extra_aabbs = no_extra
	dock.level_root.cordon_active = all_on
	dock.level_root.set_cordon_from_selection(dock._selection_nodes)
	var play_area: AABB = dock.level_root.cordon_aabb
	var spawn := ensure_playtest_spawn(dock)
	if not spawn:
		restore_cordon_state(dock, prev_cordons)
		return
	dock.show_toast("Cordon set to selection — baking area", 0)

	var mask = dock.get_collision_layer_mask()
	var root: Node = dock.level_root
	var baked: bool = await root.bake(true, false, mask)
	if not _came_back_to(dock, root):
		if is_instance_valid(root):
			root.restore_cordons(prev_cordons)
		return
	if not baked:
		restore_cordon_state(dock, prev_cordons)
		dock.show_toast("Test cancelled because the selected area could not be baked", 2)
		return
	var judged_fit := judge_spawn(dock, spawn, mask, {"cordon": play_area})

	# Before the launch, for the same reason as the camera spawn above.
	restore_cordon_state(dock, prev_cordons)
	if judged_fit:
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
	sync_export_profile_ui(dock)
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


## What the Export with list calls the level's own options.
const LEVEL_OWN_OPTIONS := "Level's own options"


## List the profiles Export Game Scene can bake with, keeping the one picked, or
## Shipping when that is gone or nothing was picked yet. The first entry keeps the
## level's own options.
static func sync_export_profile_ui(dock: Object) -> void:
	var opt: OptionButton = dock.export_profile_opt
	if opt == null:
		return
	var keep := export_profile_name(dock) if opt.item_count > 0 else HFBakeProfilesType.SHIPPING
	var names := HFBakeProfilesType.names(saved_bake_profiles(dock))
	if keep != "" and not names.has(keep):
		keep = HFBakeProfilesType.SHIPPING
	opt.clear()
	opt.add_item(LEVEL_OWN_OPTIONS)
	opt.set_item_metadata(0, "")
	for profile_name in names:
		opt.add_item(profile_name)
		opt.set_item_metadata(opt.item_count - 1, profile_name)
		if profile_name == keep:
			opt.select(opt.item_count - 1)


## The profile picked to export with, or "" for the level's own options, which is
## also the answer with no list.
static func export_profile_name(dock: Object) -> String:
	var opt: OptionButton = dock.export_profile_opt
	if opt == null or opt.selected < 0:
		return ""
	return str(opt.get_item_metadata(opt.selected))


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
	if dock.bake_options_held():
		say_bake_options_held(dock)
		sync_bake_profile_ui(dock)
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
		var already := HFTranslationType.t("The bake options are already on {profile}")
		dock._set_status(already.format({"profile": profile_name}), false, 3.0)
		return
	var before: Dictionary = dock.level_root.capture_bake_options()
	dock.level_root.apply_bake_options(values)
	dock._commit_bake_profile("Bake Profile: %s" % profile_name, before)
	var said := HFTranslationType.tn(
		"Bake profile {profile}: {count} option changed",
		"Bake profile {profile}: {count} options changed",
		changed
	)
	dock.show_toast(said.format({"profile": profile_name, "count": changed}), 0)


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
	var said := (
		HFTranslationType.t("Bake profile {profile} updated")
		if replacing
		else HFTranslationType.t("Bake profile {profile} saved")
	)
	dock.show_toast(said.format({"profile": profile_name}), 0)


static func _save_project_bake_profile(dock: Object, profile_name: String) -> void:
	var path := project_bake_profiles_path(dock)
	if HFBakeProfilesType.project_file_unreadable(path):
		var unread := HFTranslationType.t("{file} could not be read. Fix it before saving to it")
		dock._set_status(unread.format({"file": path}), true)
		return
	var profiles := HFBakeProfilesType.read_project_raw(path)
	var replacing := profiles.has(profile_name)
	profiles[profile_name] = dock.level_root.capture_bake_options()
	if not HFBakeProfilesType.write_project(profiles, path):
		_say_unwritten(dock, path)
		return
	if dock._user_prefs and dock._user_prefs.get_bake_profiles().has(profile_name):
		dock._user_prefs.remove_bake_profile(profile_name)
	_saved_profiles_key = 0
	dock.bake_profile_name.text = profile_name
	sync_bake_profile_ui(dock)
	var said := (
		HFTranslationType.t(
			"Bake profile {profile} updated in the project. Commit {file} to share it"
		)
		if replacing
		else HFTranslationType.t(
			"Bake profile {profile} saved in the project. Commit {file} to share it"
		)
	)
	dock.show_toast(said.format({"profile": profile_name, "file": path.get_file()}), 0)


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
		var again := (
			(
				HFTranslationType
				. t(
					"Press Delete again to delete bake profile {profile} from the project. It cannot be undone"
				)
			)
			if shared
			else HFTranslationType.t(
				"Press Delete again to delete bake profile {profile}. It cannot be undone"
			)
		)
		dock._set_status(again.format({"profile": profile_name}), true)
		return
	dock._bake_profile_delete_ack = ""
	if shared:
		var path := project_bake_profiles_path(dock)
		if HFBakeProfilesType.project_file_unreadable(path):
			var unread := HFTranslationType.t(
				"{file} could not be read. Fix it before deleting from it"
			)
			dock._set_status(unread.format({"file": path}), true)
			return
		var profiles := HFBakeProfilesType.read_project_raw(path)
		profiles.erase(profile_name)
		if not HFBakeProfilesType.write_project(profiles, path):
			_say_unwritten(dock, path)
			return
		_saved_profiles_key = 0
	else:
		dock._user_prefs.remove_bake_profile(profile_name)
	dock.bake_profile_name.text = ""
	sync_bake_profile_ui(dock)
	var said := HFTranslationType.t("Bake profile {profile} deleted")
	dock.show_toast(said.format({"profile": profile_name}), 0)


static func _say_unwritten(dock: Object, path: String) -> void:
	dock._set_status(HFTranslationType.t("Could not write {file}").format({"file": path}), true)


static func on_export_playtest(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Export Playtest Build requested")
	if not dock.level_root:
		dock.show_toast("No LevelRoot active", 2)
		return
	if not can_start_bake(dock, "Export Playtest"):
		return
	apply_pending_cuts_as_a_step(dock)
	var spawn := ensure_playtest_spawn(dock)
	if not spawn:
		return

	dock.show_toast("Baking for playtest...", 0)
	var mask = dock.get_collision_layer_mask()
	var root: Node = dock.level_root
	var baked: bool = await root.bake(true, false, mask)
	if not _came_back_to(dock, root):
		return
	if not baked:
		dock.show_toast("Export cancelled because the level could not be baked", 2)
		return
	# Judged on the level the bake made, as the other playtests judge it. It was
	# judged before the bake, on what the last bake left: a floor deleted since
	# still held the spawn up, and the export launched a player over nothing (#1460).
	var export_and_play := func(_run: Dictionary) -> void: export_and_play_playtest(dock)
	if judge_spawn(dock, spawn, mask, {}, export_and_play):
		export_and_play_playtest(dock)


## Write the baked level as the playtest scene and play that: Export Playtest
## Build's last step, once the spawn is judged or from the spawn dialog's OK.
static func export_and_play_playtest(dock: Object) -> void:
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
## Export Playtest Build bakes, checks the spawn, exports and launches. This bakes
## and exports and stops: there is nobody to drop at a spawn, because the game
## brings its own player. What it writes has the same geometry and the same real
## entity nodes - a light_point as an OmniLight3D, a logic_timer as a Timer - and
## none of the debug rig (#697, #698).
##
## It bakes on the profile picked under Export with, then puts the level's own
## options back, whatever happened and with no undo step, as Play Selected Area
## puts the cordons back. Picking Shipping, exporting and picking Editing again
## was two undo steps and two full bakes, and forgetting the second left the
## level on the slower bake (#1003).
static func on_export_game_scene(dock: Object) -> void:
	if dock == null:
		return
	dock._log("Export Game Scene requested")
	if not dock.level_root:
		dock.show_toast("No LevelRoot active", 2)
		return
	if not can_start_bake(dock, "Export Game Scene"):
		return

	var root: Node = dock.level_root
	var saved := saved_bake_profiles(dock)
	var profile := export_profile_name(dock)
	var values := HFBakeProfilesType.values_of(profile, saved)
	var own: Dictionary = root.capture_bake_options()
	var switched := HFBakeProfilesType.count_changes(root, values) > 0
	if switched:
		root.apply_bake_options(values)
	if profile == "":
		profile = HFBakeProfilesType.current(root, saved)
	var export_path := _game_scene_path(dock)
	var baked_with: Dictionary = root.capture_bake_options()
	dock._export_baking_level = root if switched else null
	var failure: String = await _bake_game_scene(dock, export_path)
	var dock_left := not is_instance_valid(dock)
	if not dock_left:
		dock._export_baking_level = null
	if switched and is_instance_valid(root):
		var kept := options_set_during_export(root, baked_with)
		var put_back := own.duplicate()
		for key in kept:
			put_back.erase(key)
		root.apply_bake_options(put_back)
		if not kept.is_empty() and not dock_left:
			var left := "The export left %s as set while it baked" % ", ".join(kept)
			dock.show_toast(left, 1)
	if dock_left:
		return
	if failure != "":
		dock.show_toast(failure, 2)
		return
	# Say which bake options went into the game, and warn on the Editing ones:
	# unmerged meshes and no LODs are right while a level changes, not in a game.
	if profile == HFBakeProfilesType.EDITING:
		var warning := HFTranslationType.t(
			(
				"Game scene written to {file} with the Editing bake options. "
				+ "Pick Shipping under Export with and export again for a game."
			)
		)
		dock.show_toast(warning.format({"file": export_path}), 1)
		return
	if profile == "":
		profile = HFBakeProfilesType.CUSTOM
	var written := HFTranslationType.t(
		"Game scene written to {file} with the {profile} bake options"
	)
	dock.show_toast(written.format({"file": export_path, "profile": profile}), 0)


## The bake options that changed while Export Game Scene baked: set from the
## Inspector or a script, since the dock holds its own controls then (#1011). The
## export keeps them rather than put them back, which lost the change and left an
## Inspector edit's undo step behind (#1020). One set to the value the export
## baked with cannot be told apart, and goes back with the rest.
static func options_set_during_export(root: Node, baked_with: Dictionary) -> Array:
	var now: Dictionary = root.capture_bake_options()
	var changed: Array = []
	for key in baked_with:
		if now.get(key) != baked_with[key]:
			changed.append(key)
	return changed


## Say why a bake option will not change while Export Game Scene bakes on its own
## profile (#1011).
static func say_bake_options_held(dock: Object) -> void:
	dock.show_toast("Change the bake options when the export finishes", 1)


## Bake the whole level and write it as the game scene at `export_path`, with any
## cordon left on set aside for the bake. Returns what went wrong, or "" once the
## scene is written.
static func _bake_game_scene(dock: Object, export_path: String) -> String:
	apply_pending_cuts_as_a_step(dock)
	dock.show_toast("Baking for export...", 0)
	var root: Node = dock.level_root
	var baked: bool = await root.bake_whole_level(true, false, dock.get_collision_layer_mask())
	if not _came_back_to(dock, root):
		return "Export cancelled because the level was closed while it baked"
	if not baked:
		return "Export cancelled because the level could not be baked"
	if not dock.level_root.export_game_scene(export_path):
		return "Export failed — could not pack scene"
	return ""


## Beside the level's own scene, named after it, so a project ends up with
## `arena.tscn` and `arena_game.tscn` rather than a file in user:// nobody finds.
static func _game_scene_path(dock: Object) -> String:
	var source := ""
	if dock.level_root.has_method("scene_source_path"):
		source = str(dock.level_root.scene_source_path())
	if source == "" or not source.begins_with("res://"):
		return "res://hammerforge_game_scene.tscn"
	return "%s/%s_game.tscn" % [source.get_base_dir(), source.get_file().get_basename()]


## Ask what to do about a spawn Test Level would not start from. Fix & Play moves
## it to the validation's suggestion as one undo step and plays; with no
## suggestion the button says Play Anyway and moves nothing (#1002).
##
## `overrides` is what the caller would have launched with, and both buttons
## launch with it. When it carries a start pose, as Play from Camera's does, Fix
## & Play moves that pose and leaves the level's spawn alone (#1010). `launch`,
## when given, is called with it in place of `launch_playtest()`: Export
## Playtest Build's export and play.
static func show_spawn_fix_dialog(
	dock: Object,
	spawn: Node3D,
	validation: Dictionary,
	_mask: int,
	overrides: Dictionary = {},
	launch: Callable = Callable()
) -> void:
	if dock == null:
		return
	var issues: PackedStringArray = validation.get("issues", PackedStringArray())
	var run := overrides.duplicate()
	var start: Vector3 = run.get("spawn_position", spawn.global_position)
	# With nowhere to move the spawn, the button said Fix & Play and the toast said
	# fixed, and the player started where they were, inside the brush (#1002).
	var suggested: Vector3 = validation.get("suggested_position", start)
	var fixes := suggested != start
	# Held weakly, as anything can free them while the dialog is up: an agent's
	# edit, a reload. A freed capture made OK an engine error.
	var spawn_ref: WeakRef = weakref(spawn)
	var level_ref: WeakRef = weakref(dock.level_root)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Quick Play — Spawn Warning"
	var ask := HFTranslationType.t("Fix automatically and play, or cancel?")
	if not fixes:
		ask = HFTranslationType.t(
			"There is nowhere near to move it. Play anyway, or cancel and move it by hand?"
		)
	dialog.dialog_text = (
		HFTranslationType
		. t("Player spawn may be invalid:\n\n{issues}\n\n{ask}")
		. format({"issues": "\n".join(issues), "ask": ask})
	)
	dialog.ok_button_text = "Fix & Play" if fixes else "Play Anyway"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(
		func():
			var level: Node = level_ref.get_ref()
			if not _came_back_to(dock, level):
				dialog.queue_free()
				return
			var live_spawn: Node3D = spawn_ref.get_ref()
			if live_spawn and level.spawn_system:
				level.spawn_system.cleanup_debug()
				if fixes and run.has("spawn_position"):
					run["spawn_position"] = suggested
					dock.show_toast("Starting at the nearest clear spot to the camera", 0)
				elif fixes:
					var old_pos := live_spawn.global_position
					var before_state: Dictionary = level.state_system.capture_state(true)
					level.spawn_system.auto_fix_spawn(live_spawn, validation)
					if live_spawn.global_position != old_pos:
						record_spawn_move_undo(dock, before_state)
					dock.show_toast("Spawn fixed — launching playtest", 0)
			if launch.is_valid():
				launch.call(run)
			else:
				launch_playtest(dock, run)
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
	_record_spawn_step(dock, "Auto-create player_start", before_state)


## A move is a snapshot both ways, as a create is. It held the spawn node and set
## its position, but `restore_state()` frees every entity and builds it again, so
## once a snapshot step was undone or redone past it the step aimed at a freed
## node and did nothing (#1108).
static func record_spawn_move_undo(dock: Object, before_state: Dictionary) -> void:
	_record_spawn_step(dock, "Fix player_start position", before_state)


static func _record_spawn_step(dock: Object, action_name: String, before_state: Dictionary) -> void:
	if (
		dock == null
		or not dock.undo_redo
		or not dock.level_root
		or not dock.level_root.state_system
	):
		return
	var after_state: Dictionary = dock.level_root.state_system.capture_state(true)
	dock.undo_redo.create_action(action_name)
	dock.undo_redo.add_do_method(dock.level_root.state_system, "restore_state", after_state)
	dock.undo_redo.add_undo_method(dock.level_root.state_system, "restore_state", before_state)
	dock.undo_redo.commit_action(false)


## `spawn` is untyped because it can be freed by the time it goes back, and a
## typed parameter refuses a freed object before the check below can.
static func restore_spawn(spawn, pos: Vector3, angle_deg: float) -> void:
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
		return
	var spawn = dock.level_root.spawn_system.get_active_spawn()
	if not spawn:
		dock.show_toast("No player_start entity found", 1)
		return
	var mask = dock.get_collision_layer_mask()
	dock.show_toast("Baking before validation…", 0)
	apply_pending_cuts_as_a_step(dock)
	var root: Node = dock.level_root
	var baked: bool = await root.bake(true, false, mask)
	if not _came_back_to(dock, root):
		return
	if not baked:
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
		_say_spawn_issues(dock, issues)


static func _say_spawn_issues(dock: Object, issues: PackedStringArray) -> void:
	var said := HFTranslationType.t("Spawn issues: {issues}")
	dock.show_toast(said.format({"issues": "\n".join(issues)}), 2)


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
		apply_pending_cuts_as_a_step(dock)
		var root: Node = dock.level_root
		var baked: bool = await root.bake(true, false, mask)
		if not is_instance_valid(dock):
			return
		if not baked or dock.level_root != root:
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


## Validate the level, and with `auto_fix` repair it first as one undo step. The
## findings left go to the status line, the log, and the Check Bake Issues rows
## with Select on the object each names (#1004).
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
	# The same rows Check Bake Issues fills, with Select on the object each names.
	# The findings were a count in the status line and text in the log, so a
	# mapper found the brushes they named by hand in the Scene dock (#1004).
	show_findings(dock, result.get("findings", []), result.get("accepted", []), "validate")
	if issues.is_empty():
		if auto_fix and fixed > 0:
			var clean := HFTranslationType.t("Validate: fixed {fixed}, no issues left")
			dock._set_status(clean.format({"fixed": fixed}), false, 3.0)
		else:
			dock._set_status("Validate: no issues found", false, 3.0)
		return
	var message := HFTranslationType.tn(
		"Validate: {count} issue", "Validate: {count} issues", issues.size()
	)
	if auto_fix:
		message = HFTranslationType.t("Validate: fixed {fixed}, {count} remaining")
	message = message.format({"fixed": fixed, "count": issues.size()})
	dock._set_status_warning(message, 6.0)
	for issue in issues:
		dock._log("[Validate] %s" % str(issue), true)
