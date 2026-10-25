@tool
extends RefCounted
## Sweep Faces (#1714): the faces picked in Face Select carried along a straight
## run, an arc or an S bend, as a run of convex brushes, grouped, in one undo step.
##
## A pipe with a flange, an arched corridor's profile or a bevelled beam starts as
## faces the mapper built, and bending them meant rebuilding the shape piece by
## piece. The dialog takes where the run goes as typed values and outlines the
## pieces as they change; a piece that would fold back on itself is drawn red and
## OK makes nothing. The geometry is `hf_face_sweep.gd`.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("undo_helper.gd")
const FaceData = preload("face_data.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
const HFOpResult = preload("hf_op_result.gd")
const HFSweepBuilder = preload("hf_sweep_builder.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFFaceSweep = preload("hf_face_sweep.gd")
const HFSweepPreview = preload("systems/hf_sweep_preview.gd")

## Which way the run turns or steps aside, in the start frame: the face's own up,
## down, left and right as the frame sets them.
const TOWARD := {
	"Up": Vector2(0, 1),
	"Down": Vector2(0, -1),
	"Left": Vector2(-1, 0),
	"Right": Vector2(1, 0),
}

## What the dialog starts with.
const DEFAULTS := {
	"path": HFFaceSweep.Path.ARC,
	"length": 4.0,
	"angle": 90.0,
	"radius": 4.0,
	"offset": 2.0,
	"toward": "Right",
	"segments": 8,
	"iterations": 1,
	"end_width": 1.0,
	"end_height": 1.0,
}


## The picked faces as a cross section, read as a Sweep structure reads its run
## (#1885): `{ok, run, placement}`, the run in the space of the sweep's start
## frame, or `{ok: false, reason}` when nothing is picked or the faces are not in
## one plane.
static func section(root: Node) -> Dictionary:
	if root == null:
		return {"ok": false, "reason": "Pick the faces to sweep in Face Select first"}
	var picked: Dictionary = root.get("face_selection")
	if picked == null or picked.is_empty():
		return {"ok": false, "reason": "Pick the faces to sweep in Face Select first"}
	var read: Dictionary = root.run_from_faces(HFGeneratorSystem.TYPE_SWEEP, picked)
	if read.has("refused"):
		var reason := str(read["refused"]).trim_prefix("Sweep: ")
		return {"ok": false, "reason": reason.left(1).to_upper() + reason.substr(1)}
	if HFSweepBuilder.rings_of(read["run"]).is_empty():
		return {"ok": false, "reason": "Pick the faces to sweep in Face Select first"}
	return {"ok": true, "run": read["run"], "placement": read["placement"]}


## The dialog's values as a Sweep's settings: Toward by its place in the list, as
## a structure keeps a choice.
static func settings_of(values: Dictionary) -> Dictionary:
	var settings := values.duplicate()
	var toward := HFSweepBuilder.TOWARD_NAMES.find(str(values.get("toward", "Right")))
	settings["toward"] = toward if toward >= 0 else int(values.get("toward", 3))
	return settings


## What sweeping `cut` with `values` makes: `{pieces, folded, frames}`, placed in
## the level, for the dialog's outline.
static func plan(cut: Dictionary, values: Dictionary) -> Dictionary:
	var made := HFSweepBuilder.plan(settings_of(values), cut["run"])
	var placement: Transform3D = cut["placement"]
	for piece in made["pieces"]:
		for face in piece["faces"]:
			var placed := PackedVector3Array()
			for corner in (face as FaceData).local_verts:
				placed.append(placement * corner)
			face.local_verts = placed
			face.normal = (placement.basis * (face as FaceData).normal).normalized()
	var frames: Array = []
	for frame in made["frames"]:
		frames.append(placement * (frame as Transform3D))
	made["frames"] = frames
	return made


## Sweep the picked faces with `values` as one undo step, kept as a Sweep
## structure so its values can be changed after (#1885). False, with the reason
## said and nothing made, when a piece folds or nothing is picked.
static func run(plugin: Object, root: Node, values: Dictionary) -> bool:
	var cut := section(root)
	if not bool(cut["ok"]):
		_say(plugin, str(cut["reason"]), 1)
		return false
	var settings := settings_of(values)
	var check := HFGeneratorSystem.can_build(HFGeneratorSystem.TYPE_SWEEP, settings, cut["run"])
	if not check.ok:
		_say(plugin, "%s. %s" % [check.message, check.fix_hint], 1)
		return false
	var before: Dictionary = root.capture_state()
	var known: Array = root.generator_system.generators.keys()
	var made: HFOpResult = root.create_generator(
		HFGeneratorSystem.TYPE_SWEEP,
		settings,
		cut["placement"],
		root.get("active_material"),
		cut["run"]
	)
	if not made.ok:
		_say(plugin, made.user_text(), 1)
		return false
	var record = null
	for generator_id in root.generator_system.generators:
		if not known.has(generator_id):
			record = root.generator_system.generators[generator_id]
	var count: int = record.brush_ids.size() if record else 0
	var group := _group_name(root, count)
	if record and root.get("visgroup_system"):
		root.visgroup_system.create_group(group)
		for brush_id in record.brush_ids:
			var piece = root.find_brush_by_id(str(brush_id))
			if piece:
				piece.set_meta("group_id", group)
	HFUndoHelper.commit_completed(
		plugin.call("_get_undo_redo"),
		root,
		"Sweep Faces (%d pieces)" % count,
		before,
		Callable(plugin, "_record_history")
	)
	_say(plugin, "Swept into %d pieces, grouped as %s" % [count, group], 0)
	return true


static func _group_name(root: Node, count: int) -> String:
	var base := "Sweep of %d pieces" % count
	var system = root.get("visgroup_system")
	if system == null or not system.groups.has(base):
		return base
	var n := 2
	while system.groups.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


# ---------------------------------------------------------------------------
# The dialog
# ---------------------------------------------------------------------------


## Open the Sweep dialog for the picked faces, with the pieces outlined as the
## values change.
static func open(plugin: Object, root: Node) -> bool:
	var cut := section(root)
	if not bool(cut["ok"]):
		_say(plugin, str(cut["reason"]), 1)
		return false
	var values: Dictionary = DEFAULTS.duplicate()
	var preview := HFSweepPreview.new(root)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Sweep Faces"
	dialog.min_size = Vector2i(360, 240)
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var rows := {}
	var refresh := func():
		var made := plan(cut, values)
		preview.show_pieces(made["pieces"])
		var folded := int(made["folded"])
		var total := (made["pieces"] as Array).size()
		dialog.get_ok_button().disabled = folded > 0
		status.text = (
			"%d pieces" % total
			if folded == 0
			else (
				"%d of %d pieces fold back on themselves: widen the radius or cut more segments"
				% [folded, total]
			)
		)
		var path := int(values["path"])
		rows["length"].visible = path != HFFaceSweep.Path.ARC
		rows["angle"].visible = path == HFFaceSweep.Path.ARC
		rows["radius"].visible = path == HFFaceSweep.Path.ARC
		rows["offset"].visible = path == HFFaceSweep.Path.S_BEND
		rows["toward"].visible = path != HFFaceSweep.Path.STRAIGHT
	var path_pick := OptionButton.new()
	for path_name in HFFaceSweep.PATH_NAMES:
		path_pick.add_item(path_name)
	path_pick.selected = int(values["path"])
	path_pick.accessibility_name = "Path"
	path_pick.item_selected.connect(
		func(index: int):
			values["path"] = index
			refresh.call()
	)
	_row(grid, rows, "path", "Path:", path_pick)
	for spec in [
		["length", "Length (m):", 0.1, 1000.0, 0.1],
		["angle", "Angle (degrees):", -360.0, 360.0, 1.0],
		["radius", "Radius (m):", 0.1, 1000.0, 0.1],
		["offset", "Offset (m):", -1000.0, 1000.0, 0.1],
		["segments", "Segments:", 1.0, float(HFFaceSweep.MAX_SEGMENTS), 1.0],
		["iterations", "Iterations:", 1.0, float(HFFaceSweep.MAX_ITERATIONS), 1.0],
		# How wide and tall the far end is, as a part of the start (#1899).
		["end_width", "End width scale:", 0.05, 20.0, 0.05],
		["end_height", "End height scale:", 0.05, 20.0, 0.05],
	]:
		var spin := SpinBox.new()
		spin.min_value = spec[2]
		spin.max_value = spec[3]
		spin.step = spec[4]
		spin.value = float(values[spec[0]])
		spin.accessibility_name = str(spec[1]).trim_suffix(":")
		var key: String = spec[0]
		spin.value_changed.connect(
			func(value: float):
				if key in ["segments", "iterations"]:
					values[key] = int(value)
				else:
					values[key] = value
				refresh.call()
		)
		_row(grid, rows, key, spec[1], spin)
	var toward_pick := OptionButton.new()
	for way in TOWARD:
		toward_pick.add_item(way)
	toward_pick.selected = TOWARD.keys().find(values["toward"])
	toward_pick.accessibility_name = "Toward"
	toward_pick.item_selected.connect(
		func(index: int):
			values["toward"] = TOWARD.keys()[index]
			refresh.call()
	)
	_row(grid, rows, "toward", "Toward:", toward_pick)
	dialog.confirmed.connect(
		func():
			preview.destroy()
			if is_instance_valid(root):
				run(plugin, root, values)
			dialog.queue_free()
	)
	dialog.canceled.connect(
		func():
			preview.destroy()
			dialog.queue_free()
	)
	plugin.call("_add_confirmable_dialog", dialog)
	refresh.call()
	if dialog.is_inside_tree():
		dialog.popup_centered()
	return true


static func _row(
	grid: GridContainer, rows: Dictionary, key: String, text: String, control: Control
) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	rows[key] = SweepRow.new(label, control)


## A label and its control, shown and hidden together.
class SweepRow:
	extends RefCounted
	var label: Label
	var control: Control

	var visible: bool:
		set(value):
			label.visible = value
			control.visible = value

	func _init(row_label: Label, row_control: Control) -> void:
		label = row_label
		control = row_control


static func _say(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and dock.has_method("show_toast"):
		dock.show_toast(message, level)
