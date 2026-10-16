@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether a door's settings survive every file a level goes through.
##
## `brush-entities` checks a door's class and name through a save and an export.
## A door is more than that: a speed, a wait, a move angle, a lock, and the
## wires it fires, each with a parameter, a delay and a fire-once switch. Those
## are what a mapper spends the time on, and they live in `brush_entity_data`
## and `entity_io_outputs`, which every format has to write and read back by
## itself. This puts one door, one button and one trigger through a state round
## trip, a `.hflevel`, and both `.map` formats, and compares each entity's
## settings and wires by name.

const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")


func id() -> String:
	return "brush-entity-formats"


func summary() -> String:
	return "a door's, a button's and a trigger's settings and wires through state, .hflevel and .map"


func run() -> void:
	var root: Node3D = await fresh_root()
	_build(root)
	await frame()
	var before := _entities(root)
	note("built", before)

	# State round trip.
	var state: Dictionary = root.capture_state()
	var other: Node3D = await fresh_root("StateCopy")
	other.restore_state(state)
	await frame()
	_compare(before, _entities(other), "capture_state/restore_state")
	await drop_root(other)

	# .hflevel.
	var path := "user://brush_entity_formats.hflevel"
	root.save_hflevel(path, true)
	await HFVibe.settle_save(_tree, root)
	var loaded: Node3D = await fresh_root("Loaded")
	loaded.load_hflevel(path)
	await frame()
	_compare(before, _entities(loaded), ".hflevel save/load")
	await drop_root(loaded)

	# .map, both formats.
	for fmt in ["quake", "valve220"]:
		var map_path := "user://brush_entity_formats_%s.map" % fmt
		var rc: int = root.export_map(map_path, fmt)
		var back: Node3D = await fresh_root("Map_%s" % fmt)
		var irc: int = back.import_map(map_path)
		await frame()
		note("%s export rc %d, import rc %d" % [fmt, rc, irc])
		_compare(before, _entities(back), ".map (%s) export/import" % fmt)
		await drop_root(back)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(map_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await drop_root(root)


func _build(root: Node3D) -> void:
	box(root, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0))
	var leaves: Array = []
	for i in 2:
		var b = box(root, Vector3(1, 2, 0.2), Vector3(i * 1.0 - 0.5, 1, 0))
		leaves.append(str(b.get_meta("brush_id", "")))
	root.tie_brushes_to_entity(leaves, "func_door", "gate")
	var door = root.find_brush_by_id(leaves[0])
	root.set_entity_property(door, "speed", 7.5)
	root.set_entity_property(door, "wait", -1.0)
	root.set_entity_property(door, "angle", 45.0)
	root.set_entity_property(door, "locked", true)
	root.add_entity_output(door, "OnOpen", "lamp", "TurnOn", "bright", 0.5, true)

	var btn = box(root, Vector3(0.3, 0.3, 0.1), Vector3(2, 1, 0))
	root.tie_brushes_to_entity([str(btn.get_meta("brush_id", ""))], "func_button", "btn")
	root.add_entity_output(btn, "OnPressed", "gate", "Open", "", 1.25, false)
	for key in _defaults("func_button"):
		var d = _defaults("func_button")[key]
		if d is bool:
			root.set_entity_property(btn, key, not d)
		elif d is float or d is int:
			root.set_entity_property(btn, key, float(d) + 1.5)

	var trig = box(root, Vector3(2, 2, 2), Vector3(-3, 1, 0))
	root.tie_brushes_to_entity([str(trig.get_meta("brush_id", ""))], "trigger_multiple", "zone")
	root.add_entity_output(trig, "OnStartTouch", "gate", "Toggle", "", 0.0, false)
	for key in _defaults("trigger_multiple"):
		var d = _defaults("trigger_multiple")[key]
		if d is bool:
			root.set_entity_property(trig, key, not d)
		elif d is float or d is int:
			root.set_entity_property(trig, key, float(d) + 1.5)
		elif d is String:
			root.set_entity_property(trig, key, "player")


func _defaults(entity_class: String) -> Dictionary:
	var defs: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://addons/hammerforge/entities.json")
	)
	var out := {}
	for p in (defs.get(entity_class, {}) as Dictionary).get("properties", []):
		out[str(p.get("name", ""))] = p.get("default")
	return out


## Every brush entity by identity: class, brush count, settings and wires.
func _entities(root: Node3D) -> Dictionary:
	var out := {}
	for b in root._iter_managed_brush_nodes():
		var cls := HFBrushEntity.entity_class(b)
		if cls == "":
			continue
		var key := HFBrushEntity.identity(b)
		if key == "" or key.begins_with(HFBrushEntity.TIE_PREFIX):
			key = "%s(unnamed)" % cls
		if not out.has(key):
			out[key] = {"class": cls, "brushes": 0, "data": {}, "wires": []}
		var e: Dictionary = out[key]
		e["brushes"] = int(e["brushes"]) + 1
		var data: Dictionary = b.get_meta("brush_entity_data", {})
		for k in data:
			e["data"][k] = _plain(data[k])
		for w in b.get_meta("entity_io_outputs", []):
			var wd: Dictionary = w
			var line := (
				"%s>%s.%s(%s) delay %s once %s"
				% [
					wd.get("output_name", ""),
					wd.get("target_name", ""),
					wd.get("input_name", ""),
					wd.get("parameter", ""),
					_plain(wd.get("delay", 0.0)),
					wd.get("fire_once", false),
				]
			)
			if not (e["wires"] as Array).has(line):
				e["wires"].append(line)
	return out


func _plain(v) -> String:
	if v is float:
		return str(snappedf(v, 0.0001))
	return str(v)


func _compare(before: Dictionary, after: Dictionary, context: String) -> void:
	for key in before:
		if not after.has(key):
			flag("%s loses the entity %s" % [context, key], "after: %s" % after.keys())
			continue
		var a: Dictionary = before[key]
		var b: Dictionary = after[key]
		if int(a["brushes"]) != int(b["brushes"]):
			flag("%s changes %s from %d brushes to %d" % [context, key, a["brushes"], b["brushes"]])
		for k in a["data"]:
			var was: String = a["data"][k]
			var now: String = b["data"].get(k, "(missing)")
			if was != now:
				flag("%s changes %s's %s" % [context, key, k], "%s became %s" % [was, now])
		var wa: Array = a["wires"]
		var wb: Array = b["wires"]
		wa.sort()
		wb.sort()
		if wa != wb:
			flag("%s changes %s's wires" % [context, key], "%s became %s" % [wa, wb])
	note("%s compared" % context, after.keys())
