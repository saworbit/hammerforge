@tool
class_name HFConsoleControls
extends VBoxContainer
## The Console's Controls tab: every HammerForge switch on one screen, grouped
## by what it affects and captioned with what it actually does.
##
## The dock owns these settings already, scattered across a collapsed Settings
## section and an Advanced Bake section. This does not become a second owner of
## them. Where the dock has a control for a setting, the console writes *through
## that control*, so the dock's existing handler runs and both surfaces agree.
## Only settings the dock never exposed are written to LevelRoot directly.

signal setting_changed(label: String, value: Variant)

## Toggles, grouped the way a level designer thinks about them rather than the
## way LevelRoot stores them.
##
##   key    LevelRoot property, authoritative when present
##   dock   the dock's own control for this setting; writing through it keeps
##          the dock's handler in charge of side effects
##   pref   HFUserPrefs key, for settings that outlive a level
const GROUPS := [
	{
		"title": "Viewport",
		"blurb": "What you see while building. None of these change the level.",
		"rows":
		[
			{
				"key": "grid_visible",
				"dock": "show_grid",
				"label": "Show grid",
				"help": "A ground plane at the snap size, to judge scale while drawing."
			},
			{
				"key": "grid_follow_brush",
				"dock": "follow_grid",
				"label": "Grid follows brush",
				"help":
				"Moves the grid plane to the brush you are working on, instead of leaving it at the origin."
			},
			{
				"pref": "show_hud",
				"dock": "show_hud",
				"label": "Shortcut HUD",
				"help": "The key reminders overlaid on the 3D viewport."
			},
			{
				"pref": "power_user_overlays",
				"dock": "power_user_overlays",
				"label": "Power-user overlays",
				"help":
				"Radial menu, coach marks and operation replay. Off by default to keep the core loop quiet."
			},
			{
				"dock": "_show_io_lines",
				"label": "I/O connection lines",
				"help": "Draws the wiring between entities that trigger each other."
			},
			{
				"key": "show_subtract_preview",
				"dock": "_show_subtract_preview",
				"label": "Subtract preview",
				"help": "Shows what a subtract brush will remove before you commit the cut."
			},
			{
				"dock": "_show_spawn_debug",
				"label": "Spawn debug",
				"help": "Draws the player capsule and clearance check at each spawn point."
			},
			{
				"key": "texture_lock",
				"dock": "texture_lock_check",
				"label": "Texture lock",
				"help":
				"Keeps face textures pinned to world space when a brush moves, so alignment survives a nudge."
			},
			{
				"key": "cordon_enabled",
				"dock": "cordon_enabled_check",
				"label": "Cordon",
				"help":
				"Restricts editing and baking to a box, for working on one room of a large level."
			},
		]
	},
	{
		"title": "Bake",
		"blurb": "How drafts become the meshes and collision that ship.",
		"rows":
		[
			{
				"key": "bake_merge_meshes",
				"dock": "bake_merge_meshes",
				"label": "Merge meshes",
				"help":
				"Combines brushes sharing a material into one mesh. Fewer draw calls, coarser culling."
			},
			{
				"key": "bake_generate_lods",
				"dock": "bake_generate_lods",
				"label": "Generate LODs",
				"help":
				"Builds simplified versions for distance. Costs bake time, saves frame time."
			},
			{
				"key": "bake_unwrap_uv0",
				"dock": "bake_unwrap_uv0",
				"label": "Unwrap UV0",
				"help":
				"Re-unwraps the base UV channel. Needed when a material expects a continuous unwrap rather than per-face projection."
			},
			{
				"key": "bake_lightmap_uv2",
				"dock": "bake_lightmap_uv2",
				"label": "Lightmap UV2",
				"help":
				"Generates the second UV set LightmapGI needs. Slow on large levels; only required if you bake light."
			},
			{
				"key": "bake_use_face_materials",
				"dock": "bake_use_face_materials",
				"label": "Face materials",
				"help":
				"Bakes each face with its assigned palette material instead of one override. Needs a loaded palette."
			},
			{
				"key": "bake_navmesh",
				"dock": "bake_navmesh",
				"label": "Bake navmesh",
				"help": "Builds a navigation mesh from the baked floors, for AI pathfinding."
			},
			{
				"key": "bake_visible_only",
				"dock": "bake_visible_only_check",
				"label": "Visible only",
				"help": "Skips hidden visgroups and invisible brushes. Fast iteration on one area."
			},
			{
				"key": "bake_use_multimesh",
				"dock": "bake_use_multimesh_check",
				"label": "MultiMesh repeats",
				"help": "Collapses identical repeated meshes into one instanced draw."
			},
			{
				"key": "bake_use_atlas",
				"dock": "bake_use_atlas_check",
				"label": "Material atlas",
				"help":
				"Packs palette textures into one atlas to cut draw calls. Requires face materials."
			},
			{
				"key": "bake_auto_connectors",
				"dock": "bake_auto_connectors_check",
				"label": "Auto connectors",
				"help": "Generates ramps or stairs between paint layers at different heights."
			},
			{
				"key": "bake_wire_io",
				"label": "Wire I/O at bake",
				"help":
				"Connects entity outputs to their targets in the baked scene. Off leaves the wiring to your own code."
			},
			{
				"key": "bake_generate_occluders",
				"label": "Generate occluders",
				"help":
				"Emits occlusion geometry from large flat surfaces, so the renderer can cull what is behind walls."
			},
			{
				"key": "bake_use_thread_pool",
				"label": "Bake on worker threads",
				"help":
				"Spreads the bake across cores. Turn off only to rule threading out while chasing a bake bug."
			},
			{
				"key": "commit_freeze",
				"dock": "commit_freeze",
				"label": "Freeze on commit",
				"help":
				"Keeps the CSG source hidden after a commit, leaving only the baked result visible."
			},
		]
	},
	{
		"title": "Safety net",
		"blurb": "What survives a crash, and what tells you why one happened.",
		"rows":
		[
			{
				"key": "hflevel_autosave_enabled",
				"dock": "autosave_enabled",
				"label": "Autosave",
				"help": "Writes a .hflevel snapshot on a timer, separate from Godot's scene saving."
			},
			{
				"key": "hflevel_compress",
				"label": "Compress saves",
				"help": "Smaller .hflevel files. Turn off to read or diff a save as plain text."
			},
			{
				"key": "auto_spawn_player",
				"label": "Auto-spawn player",
				"help":
				"Places a player at the origin during Test Level when the level has no spawn point."
			},
			{
				"key": "debug_logging",
				"dock": "debug_logs",
				"label": "Debug logging",
				"help":
				"Adds per-operation detail to the Log tab. Noisy by design — turn it on when reproducing a fault."
			},
		]
	},
]

## Numeric settings that belong beside the switches they qualify.
const NUMBERS := [
	{
		"key": "hflevel_autosave_minutes",
		"dock": "autosave_minutes",
		"group": "Safety net",
		"label": "Autosave every (min)",
		"help": "How long an editor crash can cost you.",
		"min": 1.0,
		"max": 60.0,
		"step": 1.0,
	},
	{
		"key": "hflevel_autosave_keep",
		"dock": "autosave_keep",
		"group": "Safety net",
		"label": "Backups kept",
		"help": "How far back you can roll an autosave.",
		"min": 1.0,
		"max": 50.0,
		"step": 1.0,
	},
	{
		"key": "bake_chunk_size",
		"dock": "bake_chunk_size_spin",
		"group": "Bake",
		"label": "Chunk size",
		"help": "Spatial grouping for baked meshes. 0 bakes the level as one piece.",
		"min": 0.0,
		"max": 256.0,
		"step": 1.0,
	},
]

var _dock = null
var _prefs = null
var _base_control: Control = null

var _search: LineEdit = null
var _descriptions: CheckButton = null
var _columns: HFlowContainer = null
var _status: Label = null
var _rows: Array = []  # {spec, control, container, haystack, kind}
var _group_boxes: Array = []  # {title, node, rows}
var _syncing := false


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)

	var hint := Label.new()
	hint.text = "Every HammerForge switch, grouped by what it affects."
	hint.add_theme_font_size_override("font_size", 11)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hint)
	_status = hint

	# 27 switches is more than a bottom panel can show at once. Descriptions off
	# turns three visible rows into eight; the text stays available as tooltips,
	# so nothing is lost, only folded away.
	_descriptions = CheckButton.new()
	_descriptions.text = "Descriptions"
	_descriptions.button_pressed = true
	_descriptions.focus_mode = Control.FOCUS_NONE
	_descriptions.tooltip_text = (
		"Show what each switch does under its name. Turn off to fit more on"
		+ "\nscreen — the same text stays on the tooltips."
	)
	_descriptions.toggled.connect(_on_descriptions_toggled)
	header.add_child(_descriptions)

	_search = LineEdit.new()
	_search.placeholder_text = "Find a setting..."
	_search.clear_button_enabled = true
	_search.custom_minimum_size.x = 180
	_search.size_flags_horizontal = Control.SIZE_SHRINK_END
	_search.tooltip_text = 'Filters by name and by description, so "navmesh" and "pathfinding" both find the same switch.'
	_search.text_changed.connect(_on_search_changed)
	header.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	# A bottom panel is wide and short, so the groups flow into columns and use
	# the width instead of forcing a long scroll down a single narrow list.
	_columns = HFlowContainer.new()
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("h_separation", 12)
	_columns.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_columns)

	for group in GROUPS:
		_build_group(group)


func _build_group(group: Dictionary) -> void:
	var box := PanelContainer.new()
	box.custom_minimum_size.x = 300
	_columns.add_child(box)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	box.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	var title := Label.new()
	title.text = str(group["title"])
	title.add_theme_font_size_override("font_size", 13)
	column.add_child(title)

	var blurb := Label.new()
	blurb.text = str(group["blurb"])
	blurb.add_theme_font_size_override("font_size", 10)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(blurb)

	var separator := HSeparator.new()
	column.add_child(separator)

	var group_rows: Array = []
	for spec in group["rows"]:
		group_rows.append(_build_toggle(column, spec))
	for spec in NUMBERS:
		if str(spec["group"]) == str(group["title"]):
			group_rows.append(_build_number(column, spec))

	_group_boxes.append({"node": box, "rows": group_rows, "blurb": blurb, "title": title})


func _build_toggle(parent: VBoxContainer, spec: Dictionary) -> Dictionary:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 0)
	parent.add_child(holder)

	var toggle := CheckButton.new()
	toggle.text = str(spec["label"])
	toggle.tooltip_text = str(spec["help"])
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(_on_toggled.bind(spec))
	holder.add_child(toggle)

	var caption := Label.new()
	caption.text = str(spec["help"])
	caption.add_theme_font_size_override("font_size", 10)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(caption)

	var entry := {
		"spec": spec,
		"control": toggle,
		"container": holder,
		"caption": caption,
		"kind": "toggle",
		"haystack": ("%s %s" % [spec["label"], spec["help"]]).to_lower(),
	}
	_rows.append(entry)
	return entry


func _build_number(parent: VBoxContainer, spec: Dictionary) -> Dictionary:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 0)
	parent.add_child(holder)

	var row := HBoxContainer.new()
	holder.add_child(row)

	var label := Label.new()
	label.text = str(spec["label"])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = float(spec["min"])
	spin.max_value = float(spec["max"])
	spin.step = float(spec["step"])
	spin.tooltip_text = str(spec["help"])
	spin.value_changed.connect(_on_number_changed.bind(spec))
	row.add_child(spin)

	var caption := Label.new()
	caption.text = str(spec["help"])
	caption.add_theme_font_size_override("font_size", 10)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(caption)

	var entry := {
		"spec": spec,
		"control": spin,
		"container": holder,
		"caption": caption,
		"kind": "number",
		"haystack": ("%s %s" % [spec["label"], spec["help"]]).to_lower(),
	}
	_rows.append(entry)
	return entry


func set_dock(dock) -> void:
	_dock = dock
	refresh()


func set_prefs(prefs) -> void:
	_prefs = prefs
	refresh()


func set_theme_source(base_control: Control) -> void:
	_base_control = base_control
	_apply_caption_colors()


## Pull every control back into line with the level and the preferences.
## Cheap — property reads only, no tree walks — so the console can call it on
## its poll and the panel never shows a stale switch.
func refresh() -> void:
	_syncing = true
	var root = _level_root()
	var available := 0
	for entry in _rows:
		var spec: Dictionary = entry["spec"]
		var value = _read(spec, root)
		var control = entry["control"]
		# A setting with nowhere to live is disabled rather than shown at a
		# made-up default, so an empty scene reads as "not applicable" instead
		# of "everything is off".
		var usable := value != null
		if usable:
			available += 1
		# Never overwrite a control the reader is in the middle of using. A spin
		# box being typed into would otherwise be reset to the stored value on
		# the next beat, mid-keystroke.
		if _has_focus_within(control):
			continue
		if entry["kind"] == "toggle":
			control.disabled = not usable
			control.set_pressed_no_signal(bool(value) if usable else false)
		else:
			control.editable = usable
			control.set_value_no_signal(float(value) if usable else float(spec["min"]))
	_syncing = false
	_update_status(available)


## A SpinBox puts the focus on its inner LineEdit, not on itself.
static func _has_focus_within(control: Control) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	if control.has_focus():
		return true
	if control is SpinBox:
		var line: LineEdit = (control as SpinBox).get_line_edit()
		return line != null and line.has_focus()
	return false


func _update_status(available: int) -> void:
	if not _status:
		return
	if available == 0:
		_status.text = "No LevelRoot in the scene — these switches turn on once a level is open."
	else:
		_status.text = "Every HammerForge switch, grouped by what it affects."
	_status.add_theme_color_override("font_color", HFThemeUtils.muted_text(_base_control))


func _apply_caption_colors() -> void:
	var muted := HFThemeUtils.muted_text(_base_control)
	for entry in _rows:
		entry["caption"].add_theme_color_override("font_color", muted)
	for group in _group_boxes:
		group["blurb"].add_theme_color_override("font_color", muted)
	_update_status(1 if _level_root() else 0)


func _on_descriptions_toggled(pressed: bool) -> void:
	for entry in _rows:
		entry["caption"].visible = pressed
	for group in _group_boxes:
		group["blurb"].visible = pressed


func _on_search_changed(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	for entry in _rows:
		entry["container"].visible = needle == "" or str(entry["haystack"]).contains(needle)
	for group in _group_boxes:
		var any_visible := false
		for entry in group["rows"]:
			if entry["container"].visible:
				any_visible = true
				break
		group["node"].visible = any_visible


func _on_toggled(pressed: bool, spec: Dictionary) -> void:
	if _syncing:
		return
	_write(spec, pressed)
	setting_changed.emit(str(spec["label"]), pressed)


func _on_number_changed(value: float, spec: Dictionary) -> void:
	if _syncing:
		return
	_write(spec, value)
	setting_changed.emit(str(spec["label"]), value)


# ---------------------------------------------------------------------------
# Reading and writing
# ---------------------------------------------------------------------------


func _level_root():
	if _dock == null or not is_instance_valid(_dock):
		return null
	var root = _dock.get("level_root")
	return root if root != null and is_instance_valid(root) else null


## Null means "this setting has nowhere to live right now" — usually no level
## open — and the control is disabled rather than shown at a made-up default.
func _read(spec: Dictionary, root):
	var key := str(spec.get("key", ""))
	if key != "" and root != null:
		var value = root.get(key)
		if value != null:
			return value
	var pref_key := str(spec.get("pref", ""))
	if pref_key != "" and _prefs != null:
		return _prefs.get_pref(pref_key)
	var control = _dock_control(spec)
	if control != null:
		if control is BaseButton:
			return control.button_pressed
		if control is Range:
			return control.value
	return null


func _write(spec: Dictionary, value) -> void:
	# Writing through the dock's own control runs the dock's handler, which is
	# what applies the side effects (rebuilding the grid, toggling the HUD,
	# saving preferences). Bypassing it would leave the dock showing the old
	# value and the side effect unapplied.
	var control = _dock_control(spec)
	if control != null:
		if control is BaseButton:
			control.button_pressed = bool(value)
			return
		if control is Range:
			control.value = float(value)
			return
	var key := str(spec.get("key", ""))
	var root = _level_root()
	if key != "" and root != null:
		root.set(key, value)
		return
	var pref_key := str(spec.get("pref", ""))
	if pref_key != "" and _prefs != null:
		_prefs.set_pref(pref_key, value)
		_prefs.save()


func _dock_control(spec: Dictionary):
	var name := str(spec.get("dock", ""))
	if name == "" or _dock == null or not is_instance_valid(_dock):
		return null
	var control = _dock.get(name)
	if control == null or not is_instance_valid(control):
		return null
	return control
