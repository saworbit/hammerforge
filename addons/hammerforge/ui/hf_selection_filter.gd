@tool
extends PopupPanel
## Selection filter popover — provides bulk selection tools:
## Select by normal (walls/floors/ceilings), by material, by visgroup,
## "Select Similar" based on the current face, brush or entity, with what it
## matches on ticked here, and Quick Select, which selects by a typed rule
## (#1698).

signal filter_applied(nodes: Array, faces: Dictionary)
## Emitted instead of `filter_applied` when a filter has nothing to select,
## carrying the reason. A filter that matched nothing used to close in silence
## and leave the previous selection standing, which is indistinguishable from a
## dead button.
signal filter_reported(message: String)

## Where a wall stops being a wall and starts being a ramp.
##
## The three normal buttons partition the sphere between them: anything within
## this much of vertical is a wall, everything else is a floor or a ceiling by
## its sign. They used to sample three patches with a gap between them, and a
## face 17 to 45 degrees off level - a ramp, a chamfer, a bevelled edge - was
## reachable from no button at all.
const WALL_NORMAL_Y := 0.3
const WALL_TILT_DEGREES := 17

const HFSelectionGrowType = preload("res://addons/hammerforge/hf_selection_grow.gd")
const HFSimilarType = preload("res://addons/hammerforge/hf_similar.gd")
const HFQuickSelectType = preload("res://addons/hammerforge/hf_quick_select.gd")

const SIMILAR_HEADS := {"brush": "Brushes:", "face": "Faces:", "entity": "Entities:"}

var _root: Node = null  # LevelRoot reference
var _hf_selection: Array = []  # Current plugin selection
var _vbox: VBoxContainer
## Grow and Shrink's options. Ctrl+] and Ctrl+[ read them here too.
var _grow_same_plane: CheckBox
var _grow_max_angle: SpinBox
## Where Select Similar's keys are kept, so Shift+S matches on them too.
var _prefs: Object = null
## `{kind: {key: CheckBox}}` for what Select Similar matches on.
var _similar_checks: Dictionary = {}
var _similar_property: LineEdit
var _syncing := false
var _quick_kind: OptionButton
var _quick_rule: LineEdit
var _quick_properties: MenuButton
var _quick_within: CheckBox


func _ready() -> void:
	size = Vector2(240, 0)
	_build_ui()


func _build_ui() -> void:
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 2)
	add_child(_vbox)

	var title_label = Label.new()
	title_label.text = "Selection Filters"
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title_label)
	_vbox.add_child(HSeparator.new())

	# --- By Normal ---
	var normal_label = Label.new()
	normal_label.text = "By Normal"
	normal_label.add_theme_font_size_override("font_size", 11)
	normal_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(normal_label)

	var normal_row1 = HBoxContainer.new()
	normal_row1.add_theme_constant_override("separation", 4)
	_vbox.add_child(normal_row1)
	_add_filter_btn(
		normal_row1,
		"Walls",
		"Select faces within %d degrees of vertical" % WALL_TILT_DEGREES,
		"_filter_walls"
	)
	_add_filter_btn(
		normal_row1, "Floors", "Select upward-facing faces, ramps included", "_filter_floors"
	)
	_add_filter_btn(
		normal_row1,
		"Ceilings",
		"Select downward-facing faces, overhangs included",
		"_filter_ceilings"
	)

	_vbox.add_child(HSeparator.new())

	# --- By Material ---
	var mat_label = Label.new()
	mat_label.text = "By Material"
	mat_label.add_theme_font_size_override("font_size", 11)
	mat_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(mat_label)

	var mat_row = HBoxContainer.new()
	mat_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(mat_row)
	_add_filter_btn(
		mat_row,
		"Same Material",
		"Select all faces with the same material as current",
		"_filter_same_material"
	)

	_vbox.add_child(HSeparator.new())

	# --- Select Similar ---
	var sim_label = Label.new()
	sim_label.text = "Select Similar"
	sim_label.add_theme_font_size_override("font_size", 11)
	sim_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(sim_label)

	var sim_row = HFlowContainer.new()
	sim_row.add_theme_constant_override("h_separation", 4)
	_vbox.add_child(sim_row)
	_add_filter_btn(
		sim_row,
		"Similar Faces",
		"Select faces like the selected faces, on what is ticked for faces",
		"_filter_similar_faces"
	)
	_add_filter_btn(
		sim_row,
		"Similar Brushes",
		"Select brushes like the selected brushes, on what is ticked for brushes",
		"_filter_similar_brushes"
	)
	_add_filter_btn(
		sim_row,
		"Similar Entities",
		"Select entities like the selected entities, on what is ticked for entities",
		"_filter_similar_entities"
	)
	_build_similar_keys()

	_vbox.add_child(HSeparator.new())
	_build_quick_select()

	_vbox.add_child(HSeparator.new())

	# --- Grow / Shrink ---
	var grow_label = Label.new()
	grow_label.text = "Grow / Shrink"
	grow_label.add_theme_font_size_override("font_size", 11)
	grow_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(grow_label)

	var grow_row = HBoxContainer.new()
	grow_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(grow_row)
	_add_filter_btn(
		grow_row,
		"Grow",
		"Add the faces sharing an edge with the selected faces, or the brushes touching the selected brushes",
		"_filter_grow"
	)
	_add_filter_btn(
		grow_row,
		"Shrink",
		"Drop the selected faces or brushes on the edge of the selection",
		"_filter_shrink"
	)

	var grow_options_row = HBoxContainer.new()
	grow_options_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(grow_options_row)
	_grow_same_plane = CheckBox.new()
	_grow_same_plane.text = "Same plane only"
	_grow_same_plane.tooltip_text = "Faces: reach only faces in the plane of the one they border"
	_grow_same_plane.add_theme_font_size_override("font_size", 11)
	grow_options_row.add_child(_grow_same_plane)
	var angle_label = Label.new()
	angle_label.text = "Max angle"
	angle_label.add_theme_font_size_override("font_size", 11)
	grow_options_row.add_child(angle_label)
	_grow_max_angle = SpinBox.new()
	_grow_max_angle.min_value = 0.0
	_grow_max_angle.max_value = HFSelectionGrowType.DEFAULT_MAX_ANGLE
	_grow_max_angle.step = 1.0
	_grow_max_angle.value = HFSelectionGrowType.DEFAULT_MAX_ANGLE
	_grow_max_angle.suffix = "°"
	_grow_max_angle.tooltip_text = "Faces: the most two neighbours' normals may differ by, in degrees"
	grow_options_row.add_child(_grow_max_angle)

	_vbox.add_child(HSeparator.new())

	# --- By Visgroup ---
	var vg_label = Label.new()
	vg_label.text = "By Visgroup"
	vg_label.add_theme_font_size_override("font_size", 11)
	vg_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(vg_label)

	var vg_row = HBoxContainer.new()
	vg_row.name = "VisgroupRow"
	vg_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(vg_row)
	# Visgroup buttons are rebuilt dynamically in show_for()

	# --- Detail filter ---
	_vbox.add_child(HSeparator.new())
	var detail_row = HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(detail_row)
	_add_filter_btn(
		detail_row, "Detail Brushes", "Select only func_detail / detail brushes", "_filter_detail"
	)
	_add_filter_btn(
		detail_row,
		"Structural",
		"Select only structural (non-detail) brushes",
		"_filter_structural"
	)


## A row of ticks for each kind: what Select Similar, from here or Shift+S,
## must find the same (#1698).
func _build_similar_keys() -> void:
	for kind in ["brush", "face", "entity"]:
		var row := HFlowContainer.new()
		row.name = "Similar%sKeys" % str(kind).capitalize()
		row.add_theme_constant_override("h_separation", 4)
		_vbox.add_child(row)
		var head := Label.new()
		head.text = SIMILAR_HEADS[kind]
		head.add_theme_font_size_override("font_size", 11)
		head.add_theme_color_override("font_color", HFThemeUtils.muted_text())
		row.add_child(head)
		var checks: Dictionary = {}
		for key in HFSimilarType.known_keys(kind):
			var check := CheckBox.new()
			check.text = HFSimilarType.LABELS[key]
			check.add_theme_font_size_override("font_size", 11)
			check.button_pressed = HFSimilarType.DEFAULTS[kind].has(key)
			check.tooltip_text = (
				"Similar %s must have the same %s"
				% [SIMILAR_HEADS[kind].trim_suffix(":").to_lower(), str(check.text).to_lower()]
			)
			check.toggled.connect(_on_similar_key_toggled.bind(kind))
			row.add_child(check)
			checks[key] = check
		_similar_checks[kind] = checks
		if kind == "entity":
			_similar_property = LineEdit.new()
			_similar_property.placeholder_text = "Property, such as energy"
			_similar_property.tooltip_text = "The property Property compares"
			_similar_property.add_theme_font_size_override("font_size", 11)
			_similar_property.custom_minimum_size.x = 120
			_similar_property.text_changed.connect(_on_similar_property_changed)
			row.add_child(_similar_property)


## Pick by a rule typed as a property, a test and a value (#1698).
func _build_quick_select() -> void:
	var label := Label.new()
	label.text = "Quick Select"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(label)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	_vbox.add_child(head)
	_quick_kind = OptionButton.new()
	_quick_kind.add_item("Brushes")
	_quick_kind.add_item("Entities")
	_quick_kind.add_theme_font_size_override("font_size", 11)
	_quick_kind.item_selected.connect(_on_quick_kind_selected)
	head.add_child(_quick_kind)
	_quick_properties = MenuButton.new()
	_quick_properties.text = "Properties"
	_quick_properties.flat = false
	_quick_properties.add_theme_font_size_override("font_size", 11)
	_quick_properties.tooltip_text = "Add a property to the rule"
	_quick_properties.get_popup().index_pressed.connect(_on_quick_property_picked)
	head.add_child(_quick_properties)
	_quick_within = CheckBox.new()
	_quick_within.text = "In selection"
	_quick_within.tooltip_text = "Look only among what is selected now"
	_quick_within.add_theme_font_size_override("font_size", 11)
	head.add_child(_quick_within)
	_quick_rule = LineEdit.new()
	_quick_rule.name = "QuickRule"
	_quick_rule.add_theme_font_size_override("font_size", 11)
	_quick_rule.tooltip_text = (
		"A property, a test and a value: is, is not, >, <, or matches with * for any run."
		+ "\nJoin more with and. An entity takes its own properties by name too."
	)
	_quick_rule.text_submitted.connect(_on_quick_rule_submitted)
	_vbox.add_child(_quick_rule)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	_vbox.add_child(buttons)
	var select := _add_filter_btn(buttons, "Select", "Select what the rule picks", "_quick_replace")
	select.name = "QuickSelect"
	_add_filter_btn(buttons, "Add", "Add what the rule picks to the selection", "_quick_add")
	_add_filter_btn(
		buttons, "Take Away", "Take what the rule picks out of the selection", "_quick_take_away"
	)
	_on_quick_kind_selected(0)


func _add_filter_btn(parent: Control, text: String, tooltip: String, method: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.add_theme_font_size_override("font_size", 11)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(Callable(self, method))
	parent.add_child(btn)
	return btn


## Call before popup() to inject current state.
func show_for(root: Node, hf_selection: Array) -> void:
	_root = root
	_hf_selection = hf_selection
	_rebuild_visgroup_buttons()
	_sync_similar_keys()


## Where Select Similar's ticks are kept.
func set_user_prefs(prefs: Object) -> void:
	_prefs = prefs
	_sync_similar_keys()


## Put focus in the Quick Select rule, as the Quick Select command opens it.
func focus_quick_rule() -> void:
	if _quick_rule != null:
		_quick_rule.grab_focus()
		_quick_rule.select_all()


func _sync_similar_keys() -> void:
	if _similar_checks.is_empty():
		return
	_syncing = true
	for kind in _similar_checks:
		var keys := HFSimilarType.keys_for(_prefs, kind)
		for key in _similar_checks[kind]:
			(_similar_checks[kind][key] as CheckBox).button_pressed = keys.has(key)
	if _similar_property != null:
		_similar_property.text = HFSimilarType.property_for(_prefs)
	_syncing = false


func _on_similar_key_toggled(_pressed: bool, kind: String) -> void:
	if _syncing or _prefs == null:
		return
	var keys: Array = []
	for key in HFSimilarType.known_keys(kind):
		if (_similar_checks[kind][key] as CheckBox).button_pressed:
			keys.append(key)
	_prefs.set_pref(HFSimilarType.PREFS[kind], keys)
	_prefs.save()


func _on_similar_property_changed(text: String) -> void:
	if _syncing or _prefs == null:
		return
	_prefs.set_pref(HFSimilarType.PROPERTY_PREF, text.strip_edges())
	_prefs.save()


func _rebuild_visgroup_buttons() -> void:
	var row = _vbox.get_node_or_null("VisgroupRow")
	if not row:
		return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	if not _root or not _root.visgroup_system:
		var none_lbl = Label.new()
		none_lbl.text = "(no visgroups)"
		none_lbl.add_theme_font_size_override("font_size", 11)
		var muted_color = HFThemeUtils.muted_text()
		muted_color.a = 0.45
		none_lbl.add_theme_color_override("font_color", muted_color)
		row.add_child(none_lbl)
		return
	var names: PackedStringArray = _root.get_visgroup_names()
	if names.is_empty():
		var none_lbl = Label.new()
		none_lbl.text = "(no visgroups)"
		none_lbl.add_theme_font_size_override("font_size", 11)
		var muted_color = HFThemeUtils.muted_text()
		muted_color.a = 0.45
		none_lbl.add_theme_color_override("font_color", muted_color)
		row.add_child(none_lbl)
		return
	for vg_name in names:
		var btn = Button.new()
		btn.text = vg_name
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = "Select all brushes in visgroup '%s'" % vg_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_filter_visgroup.bind(vg_name))
		row.add_child(btn)


# ---------------------------------------------------------------------------
# Filter implementations
# ---------------------------------------------------------------------------


## Every brush a bulk filter is allowed to touch.
##
## A hidden brush is left out. Hiding geometry to work on what is behind it is
## the normal use of a visgroup, which is exactly when a bulk filter is most
## likely to be reached for, and a material assignment or a nudge made straight
## after the filter would land on geometry the mapper cannot see.
func _get_all_brushes() -> Array:
	if not _root:
		return []
	var out: Array = []
	for node in _root._iter_pick_nodes():
		if not _root.is_brush_node(node):
			continue
		if node is Node3D and not (node as Node3D).is_visible_in_tree():
			continue
		out.append(node)
	return out


## Close the popover and say why nothing was selected.
func _report(message: String) -> void:
	filter_reported.emit(message)
	visible = false


func _filter_walls() -> void:
	_select_faces_by_normal(
		func(n: Vector3) -> bool: return absf(n.y) <= WALL_NORMAL_Y, "vertical faces"
	)


func _filter_floors() -> void:
	_select_faces_by_normal(func(n: Vector3) -> bool: return n.y > WALL_NORMAL_Y, "upward faces")


func _filter_ceilings() -> void:
	_select_faces_by_normal(func(n: Vector3) -> bool: return n.y < -WALL_NORMAL_Y, "downward faces")


func _select_faces_by_normal(predicate: Callable, what: String) -> void:
	if not _root:
		return
	var face_sel: Dictionary = {}
	var brushes := _get_all_brushes()
	for brush in brushes:
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = HFBrushSystem.face_key(brush)
		var basis: Basis = brush.global_transform.basis if brush is Node3D else Basis.IDENTITY
		var indices: Array = []
		for i in range(faces.size()):
			var face = faces[i]
			if face:
				var world_normal: Vector3 = face.normal_through(basis)
				if predicate.call(world_normal):
					indices.append(i)
		if not indices.is_empty():
			face_sel[key] = indices
	if face_sel.is_empty():
		_report("No %s on any visible brush" % what)
		return
	filter_applied.emit([], face_sel)
	visible = false


func _filter_same_material() -> void:
	if not _root:
		return
	# Get material indices from currently selected faces
	var mat_indices: Array = _get_selected_material_indices()
	if mat_indices.is_empty():
		_report("Select a face first, then Same Material")
		return
	var face_sel: Dictionary = {}
	var brushes := _get_all_brushes()
	for brush in brushes:
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = HFBrushSystem.face_key(brush)
		var indices: Array = []
		for i in range(faces.size()):
			var face = faces[i]
			if face and mat_indices.has(face.material_idx):
				indices.append(i)
		if not indices.is_empty():
			face_sel[key] = indices
	if face_sel.is_empty():
		_report("No visible face uses that material")
		return
	filter_applied.emit([], face_sel)
	visible = false


func _filter_similar_faces() -> void:
	if not _root:
		return
	if _get_selected_face_refs().is_empty():
		_report("Select a face first, then Similar Faces")
		return
	var keys := HFSimilarType.keys_for(_prefs, "face")
	if keys.is_empty():
		_report("Tick what similar faces match on")
		return
	var face_sel: Dictionary = HFPluginSelectionCommands.similar_face_selection(_root, keys)
	if face_sel.is_empty():
		_report("No visible face matches the selected one on %s" % HFSimilarType.describe(keys))
		return
	filter_applied.emit([], face_sel)
	visible = false


func _filter_similar_brushes() -> void:
	if not _root:
		return
	var has_brush := false
	for node in _hf_selection:
		if is_instance_valid(node) and node is DraftBrush:
			has_brush = true
			break
	if not has_brush:
		_report("Select a brush first, then Similar Brushes")
		return
	var keys := HFSimilarType.keys_for(_prefs, "brush")
	if keys.is_empty():
		_report("Tick what similar brushes match on")
		return
	var picked: Array = HFPluginSelectionCommands.similar_brushes(_root, _hf_selection, keys)
	if picked.is_empty():
		_report("No visible brush matches on %s" % HFSimilarType.describe(keys))
		return
	filter_applied.emit(picked, {})
	visible = false


func _filter_similar_entities() -> void:
	if not _root:
		return
	var has_entity := false
	for node in _hf_selection:
		if is_instance_valid(node) and node is DraftEntity:
			has_entity = true
			break
	if not has_entity:
		_report("Select an entity first, then Similar Entities")
		return
	var keys := HFSimilarType.keys_for(_prefs, "entity")
	if keys.is_empty():
		_report("Tick what similar entities match on")
		return
	var picked := HFSimilarType.entities(
		_root, _hf_selection, keys, HFSimilarType.property_for(_prefs)
	)
	if picked.is_empty():
		_report("No visible entity matches on %s" % HFSimilarType.describe(keys))
		return
	filter_applied.emit(picked, {})
	visible = false


# ---------------------------------------------------------------------------
# Quick Select
# ---------------------------------------------------------------------------


func _quick_kind_name() -> String:
	return "entity" if _quick_kind != null and _quick_kind.selected == 1 else "brush"


func _on_quick_kind_selected(_index: int) -> void:
	var kind := _quick_kind_name()
	_quick_rule.placeholder_text = HFQuickSelectType.EXAMPLES[kind]
	var menu := _quick_properties.get_popup()
	menu.clear()
	for property in HFQuickSelectType.properties(kind):
		menu.add_item(property)


func _on_quick_property_picked(index: int) -> void:
	var property := _quick_properties.get_popup().get_item_text(index)
	var text := _quick_rule.text.strip_edges()
	_quick_rule.text = (text + " and " if text != "" else "") + property + " is "
	_quick_rule.grab_focus()
	_quick_rule.caret_column = _quick_rule.text.length()


func _on_quick_rule_submitted(_text: String) -> void:
	_quick_replace()


func _quick_replace() -> void:
	quick_select(HFQuickSelectType.Mode.REPLACE)


func _quick_add() -> void:
	quick_select(HFQuickSelectType.Mode.ADD)


func _quick_take_away() -> void:
	quick_select(HFQuickSelectType.Mode.TAKE_AWAY)


## Apply the typed rule in `how`. A rule that cannot be read, or picks nothing
## to select, is said and the selection stays as it is.
func quick_select(how: int) -> void:
	if not _root or _quick_rule == null:
		return
	var kind := _quick_kind_name()
	var read := HFQuickSelectType.parse(kind, _quick_rule.text)
	if not read["ok"]:
		_report(read["error"])
		return
	# The whole level, or what is selected now with In selection ticked.
	var pool: Variant = null
	if _quick_within != null and _quick_within.button_pressed:
		pool = _hf_selection
	var picked := HFQuickSelectType.pick(_root, kind, read["conditions"], pool)
	if not picked["ok"]:
		_report(picked["error"])
		return
	var matched: Array = picked["nodes"]
	if matched.is_empty():
		_report("Nothing visible matches %s" % _quick_rule.text.strip_edges())
		return
	filter_applied.emit(HFQuickSelectType.combine(_hf_selection, matched, how), {})
	visible = false


## What Grow and Shrink read: the row's Same plane only and Max angle.
func grow_options() -> Dictionary:
	return {
		"same_plane": _grow_same_plane != null and _grow_same_plane.button_pressed,
		"max_angle":
		_grow_max_angle.value if _grow_max_angle != null else HFSelectionGrowType.DEFAULT_MAX_ANGLE,
	}


func _filter_grow() -> void:
	_grow_or_shrink(true)


func _filter_shrink() -> void:
	_grow_or_shrink(false)


func _grow_or_shrink(grow: bool) -> void:
	if not _root:
		return
	var options := grow_options()
	var result: Dictionary = HFPluginSelectionCommands.grown_selection(
		_root, _hf_selection, grow, bool(options["same_plane"]), float(options["max_angle"])
	)
	if result.has("message"):
		_report(str(result["message"]))
		return
	if result.has("faces"):
		filter_applied.emit([], result["faces"])
	else:
		filter_applied.emit(result["nodes"], {})
	visible = false


func _filter_visgroup(vg_name: String) -> void:
	if not _root or not _root.visgroup_system:
		return
	var members: Array = _root.visgroup_system.get_members_of(vg_name)
	if members.is_empty():
		_report("Visgroup %s has no members" % vg_name)
		return
	filter_applied.emit(members, {})
	visible = false


func _filter_detail() -> void:
	var picked: Array = []
	var brushes := _get_all_brushes()
	for brush in brushes:
		if brush.has_meta("brush_entity_class"):
			var cls: String = str(brush.get_meta("brush_entity_class", ""))
			if cls == "func_detail" or cls.contains("detail"):
				picked.append(brush)
	if picked.is_empty():
		_report("No detail brushes in this level")
		return
	filter_applied.emit(picked, {})
	visible = false


func _filter_structural() -> void:
	var picked: Array = []
	var brushes := _get_all_brushes()
	for brush in brushes:
		var cls: String = str(brush.get_meta("brush_entity_class", ""))
		if cls == "" or cls == "worldspawn":
			picked.append(brush)
	if picked.is_empty():
		_report("No structural brushes in this level")
		return
	filter_applied.emit(picked, {})
	visible = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _get_selected_material_indices() -> Array:
	if not _root:
		return []
	var indices: Array = []
	for key in _root.face_selection.keys():
		var brush = _root._find_brush_by_key(str(key))
		if not brush:
			continue
		var face_indices: Array = _root.face_selection.get(key, [])
		for fi in face_indices:
			var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
			if int(fi) >= 0 and int(fi) < faces.size():
				var mat_idx: int = faces[int(fi)].material_idx
				if not indices.has(mat_idx):
					indices.append(mat_idx)
	return indices


func _get_selected_face_refs() -> Array:
	if not _root:
		return []
	var refs: Array = []
	for key in _root.face_selection.keys():
		var brush = _root._find_brush_by_key(str(key))
		if not brush:
			continue
		var face_indices: Array = _root.face_selection.get(key, [])
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		for fi in face_indices:
			if int(fi) >= 0 and int(fi) < faces.size():
				refs.append(faces[int(fi)])
	return refs
