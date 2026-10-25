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
@warning_ignore_restore("shadowed_global_identifier")
const HFFaceSweep = preload("hf_face_sweep.gd")
const LevelRootType = preload("level_root.gd")
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
}


## The picked faces as a cross section: `{ok, rings, normal, sources}`, each
## ring a face's corners in world space and its source FaceData beside it, or
## `{ok: false, reason}` when nothing is picked or the faces are not in one plane.
static func section(root: Node) -> Dictionary:
	var rings: Array = []
	var sources: Array = []
	var normal := Vector3.ZERO
	var plane := Plane()
	var picked: Dictionary = root.get("face_selection") if root else {}
	for brush_key in picked:
		var brush = root.find_brush_by_id(str(brush_key))
		if brush == null:
			continue
		var xform: Transform3D = (brush as Node3D).global_transform
		for index in picked[brush_key]:
			if int(index) < 0 or int(index) >= brush.faces.size():
				continue
			var face: FaceData = brush.faces[int(index)]
			var ring := PackedVector3Array()
			for corner in face.local_verts:
				ring.append(xform * corner)
			if ring.size() < 3:
				continue
			var facing := (xform.basis.inverse().transposed() * face.normal).normalized()
			if rings.is_empty():
				normal = facing
				plane = Plane(facing, ring[0])
			elif facing.dot(normal) < 0.999 or absf(plane.distance_to(ring[0])) > 0.001:
				return {"ok": false, "reason": "Pick faces that lie in one plane, facing one way"}
			rings.append(ring)
			sources.append(face)
	if rings.is_empty():
		return {"ok": false, "reason": "Pick the faces to sweep in Face Select first"}
	return {"ok": true, "rings": rings, "normal": normal, "sources": sources}


## What sweeping `cut` with `values` makes: `{pieces, folded, frames}`.
static func plan(cut: Dictionary, values: Dictionary) -> Dictionary:
	var start := HFFaceSweep.start_frame(cut["rings"], cut["normal"])
	var end := HFFaceSweep.end_frame(
		start,
		int(values["path"]),
		float(values["length"]),
		float(values["angle"]),
		float(values["radius"]),
		float(values["offset"]),
		TOWARD.get(str(values["toward"]), Vector2(1, 0))
	)
	var frame_list := HFFaceSweep.frames(int(values["path"]), start, end, int(values["segments"]))
	frame_list = HFFaceSweep.repeated(frame_list, int(values["iterations"]))
	var made := HFFaceSweep.pieces(cut["rings"], frame_list)
	made["frames"] = frame_list
	return made


## Sweep the picked faces with `values` as one undo step. False, with the reason
## said and nothing made, when a piece folds or nothing is picked.
static func run(plugin: Object, root: Node, values: Dictionary) -> bool:
	var cut := section(root)
	if not bool(cut["ok"]):
		_say(plugin, str(cut["reason"]), 1)
		return false
	var made := plan(cut, values)
	var pieces: Array = made["pieces"]
	if int(made["folded"]) > 0:
		_say(
			plugin,
			(
				"Sweep: %d of %d pieces fold back on themselves. Widen the radius or cut more segments"
				% [int(made["folded"]), pieces.size()]
			),
			1
		)
		return false
	if pieces.is_empty():
		return false
	var before: Dictionary = root.capture_state()
	var group := _group_name(root, pieces.size())
	for piece in pieces:
		var faces: Array = piece["faces"]
		HFFaceSweep.take_look(faces, cut["sources"][int(piece["section"])])
		var info := _info(faces, group)
		root.brush_system.give_active_material(info)
		_keep_looks(info, faces)
		root.brush_system.create_brush_from_info(info)
	if root.get("visgroup_system"):
		root.visgroup_system.create_group(group)
	HFUndoHelper.commit_completed(
		plugin.call("_get_undo_redo"),
		root,
		"Sweep Faces (%d pieces)" % pieces.size(),
		before,
		Callable(plugin, "_record_history")
	)
	_say(plugin, "Swept into %d pieces, grouped as %s" % [pieces.size(), group], 0)
	return true


## What `create_brush_from_info()` takes for one piece: its faces local to their
## middle, in a group with the rest.
static func _info(faces: Array, group: String) -> Dictionary:
	var middle := Vector3.ZERO
	var count := 0
	for face: FaceData in faces:
		for corner in face.local_verts:
			middle += corner
			count += 1
	if count > 0:
		middle /= count
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var face_dicts: Array = []
	for face: FaceData in faces:
		var local := PackedVector3Array()
		for corner in face.local_verts:
			local.append(corner - middle)
			low = low.min(corner - middle)
			high = high.max(corner - middle)
		face.local_verts = local
		face_dicts.append(face.to_dict())
	return {
		"shape": LevelRootType.BrushShape.CUSTOM,
		"size": high - low,
		"operation": CSGShape3D.OPERATION_UNION,
		"center": middle,
		"faces": face_dicts,
		"group_id": group,
	}


## The source faces' looks over whatever the active material would give.
static func _keep_looks(info: Dictionary, faces: Array) -> void:
	var face_dicts: Array = info["faces"]
	for i in mini(face_dicts.size(), faces.size()):
		face_dicts[i] = (faces[i] as FaceData).to_dict()


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
