@tool
class_name HFSelectionInfo
extends VBoxContainer
## The Selection Info section of the Build tab (#1404): where the selection is and
## how big, from the same summary the size labels in the viewport are drawn from
## (`HFSelectionReadout`).
##
## One brush shows its centre and size, one face its centre, normal and area, one
## edge its length and midpoint, and several of anything their count and the
## centre and size of their bounds. One vertex shows X, Y and Z as fields: Enter,
## or leaving a field, asks for the vertex there through `vertex_typed`, and the
## plugin moves it the way a drag does, so a place that would break the brush is
## refused and the field goes back to where the vertex is.
##
## World or Local picks the space. Local is the brush's own space for a vertex,
## edge or face, and the parent's space for a brush, as the Inspector shows it.

## The one selected vertex is wanted at [param place], in its brush's own space
## when [param local].
signal vertex_typed(place: Vector3, local: bool)

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFNumberFormat = preload("../hf_number_format.gd")
@warning_ignore_restore("shadowed_global_identifier")

const AXES := ["X", "Y", "Z"]

var _summary: Dictionary = {}
var _local := false
var _world_button: Button = null
var _local_button: Button = null
var _title: Label = null
var _rows: GridContainer = null
var _vertex_row: HBoxContainer = null
var _fields: Array[LineEdit] = []
## What each field was last given, so a field left unedited asks for nothing.
var _shown: Array[String] = ["", "", ""]
var _note: Label = null


func _init() -> void:
	add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	header.add_child(_title)
	var space := ButtonGroup.new()
	_world_button = _space_button("World", "Numbers in world space", space)
	_world_button.button_pressed = true
	header.add_child(_world_button)
	_local_button = _space_button(
		"Local",
		"A vertex, edge or face in its brush's own space; a brush in its parent's, as the Inspector shows it",
		space
	)
	header.add_child(_local_button)

	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 8)
	add_child(_rows)

	_vertex_row = HBoxContainer.new()
	add_child(_vertex_row)
	for axis in AXES.size():
		var label := Label.new()
		label.text = AXES[axis]
		_vertex_row.add_child(label)
		var field := LineEdit.new()
		field.name = "Vertex%s" % AXES[axis]
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.custom_minimum_size.x = 0
		field.select_all_on_focus = true
		field.tooltip_text = "Type a place and press Enter, or leave the field, to move the vertex there"
		field.text_submitted.connect(_on_field_submitted.bind(axis))
		field.focus_exited.connect(_on_field_left.bind(axis))
		_vertex_row.add_child(field)
		_fields.append(field)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", 11)
	_note.modulate = Color(1, 1, 1, 0.6)
	add_child(_note)
	_render(true)


## Show [param summary], as `HFSelectionReadout.get_summary()` gives it. A field
## being typed in is left alone.
func set_summary(summary: Dictionary) -> void:
	_summary = summary.duplicate(true)
	_render(false)


func is_local() -> bool:
	return _local


func set_local(enabled: bool) -> void:
	_local = enabled
	_world_button.set_pressed_no_signal(not enabled)
	_local_button.set_pressed_no_signal(enabled)
	_render(true)


## The rows shown, `[name, value]` each, top to bottom.
func get_rows() -> Array:
	var out: Array = []
	var cells := _rows.get_children()
	for i in range(0, cells.size() - 1, 2):
		out.append([(cells[i] as Label).text, (cells[i + 1] as Label).text])
	return out


func get_title() -> String:
	return _title.text


func get_note() -> String:
	return _note.text


## The X, Y and Z fields of a vertex, shown only for one vertex.
func get_vertex_fields() -> Array[LineEdit]:
	return _fields


func _space_button(text: String, tooltip: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(_on_space_toggled.bind(text == "Local"))
	return button


func _render(force: bool) -> void:
	var kind := str(_summary.get("kind", ""))
	var count := int(_summary.get("count", 0))
	var step := float(_summary.get("step", 0.0))
	_title.text = _title_for(kind, count)
	var space: Dictionary = _summary.get("world", {})
	var note := ""
	if _local:
		var local: Dictionary = _summary.get("local", {})
		if local.is_empty() and kind != "":
			note = "In world space: these are not all in one space."
		else:
			space = local
	_note.text = note
	_note.visible = not note.is_empty()
	_vertex_row.visible = kind == "vertex"
	var rows: Array = []
	match kind:
		"brush":
			rows.append(["Centre", HFNumberFormat.point(space.get("centre", Vector3.ZERO), step)])
			rows.append(["Size", HFNumberFormat.dimensions(space.get("size", Vector3.ZERO), step)])
		"face":
			rows.append(["Centre", HFNumberFormat.point(space.get("centre", Vector3.ZERO), step)])
			rows.append(["Normal", HFNumberFormat.direction(space.get("normal", Vector3.ZERO))])
			rows.append(["Area", HFNumberFormat.area(float(space.get("area", 0.0)), step)])
		"edge":
			rows.append(["Length", HFNumberFormat.number(float(space.get("length", 0.0)), step)])
			rows.append(
				["Midpoint", HFNumberFormat.point(space.get("midpoint", Vector3.ZERO), step)]
			)
		"vertex":
			var place: Vector3 = space.get("position", Vector3.ZERO)
			for axis in AXES.size():
				var field := _fields[axis]
				if not force and field.has_focus():
					continue
				_shown[axis] = HFNumberFormat.number(place[axis], step)
				field.text = _shown[axis]
		"brushes", "faces", "vertices", "edges":
			rows.append(["Count", str(count)])
			rows.append(["Centre", HFNumberFormat.point(space.get("centre", Vector3.ZERO), step)])
			rows.append(["Size", HFNumberFormat.dimensions(space.get("size", Vector3.ZERO), step)])
	_show_rows(rows)


## Put [param rows] in the grid, reusing its labels: a gizmo drag changes the
## numbers every frame.
func _show_rows(rows: Array) -> void:
	while _rows.get_child_count() > rows.size() * 2:
		var spare := _rows.get_child(_rows.get_child_count() - 1)
		_rows.remove_child(spare)
		spare.free()
	while _rows.get_child_count() < rows.size() * 2:
		var label := Label.new()
		if _rows.get_child_count() % 2 == 0:
			label.modulate = Color(1, 1, 1, 0.7)
		else:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(label)
	for i in rows.size():
		var value: String = rows[i][1]
		(_rows.get_child(i * 2) as Label).text = rows[i][0]
		# A size of nothing prints as nothing, which would read as a missing row.
		(_rows.get_child(i * 2 + 1) as Label).text = value if not value.is_empty() else "0 x 0 x 0"


static func _title_for(kind: String, count: int) -> String:
	match kind:
		"brush":
			return "1 brush"
		"face":
			return "1 face"
		"vertex":
			return "1 vertex"
		"edge":
			return "1 edge"
		"brushes":
			return "%d brushes" % count
		"faces":
			return "%d faces" % count
		"vertices":
			return "%d vertices" % count
		"edges":
			return "%d edges" % count
	return ""


func _on_space_toggled(pressed: bool, local: bool) -> void:
	if pressed and local != _local:
		_local = local
		_render(true)


func _on_field_submitted(_text: String, axis: int) -> void:
	_commit(axis)


func _on_field_left(axis: int) -> void:
	_commit(axis)


## Ask for the vertex where the fields now put it. A field that is not a number
## goes back, and says so. Whatever happens to the request, the fields are then
## filled from the summary the plugin leaves, so a refused place goes back too.
func _commit(axis: int) -> void:
	if str(_summary.get("kind", "")) != "vertex":
		return
	var field := _fields[axis]
	var typed := field.text.strip_edges()
	if typed == _shown[axis]:
		return
	if not typed.is_valid_float() or not is_finite(typed.to_float()):
		field.text = _shown[axis]
		_note.text = "%s must be a number." % AXES[axis]
		_note.visible = true
		return
	var space_key := "world"
	if _local and not (_summary.get("local", {}) as Dictionary).is_empty():
		space_key = "local"
	var space: Dictionary = _summary.get(space_key, {})
	var place: Vector3 = space.get("position", Vector3.ZERO)
	place[axis] = typed.to_float()
	_shown[axis] = typed
	vertex_typed.emit(place, space_key == "local")
	_render(true)
