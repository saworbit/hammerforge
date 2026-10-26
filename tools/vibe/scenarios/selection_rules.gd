@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Selection commands (#1790, #1836) against hidden, locked and grouped brushes,
## and typed rules (#1836) with odd input.
##
## A level with a brush in a hidden visgroup, one in a locked visgroup, one hidden
## with Hide Selection, a cut hidden by the Cuts view filter, and a group with one
## member inside a throwaway box and one outside. Each command is run through the
## plugin, and the selection read back off the editor. The guide says filters
## "only ever reach brushes you can see", Invert leaves what a visgroup hides out,
## and Hide Selection is there "so nothing is lost to a hide you forgot".

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFSelectionCommands = preload("res://addons/hammerforge/plugin_selection_commands.gd")
const HFQuickSelect = preload("res://addons/hammerforge/hf_quick_select.gd")

var rig = null
var _host: Node = null


func id() -> String:
	return "selection-rules"


func summary() -> String:
	return "selection commands against hidden, locked and grouped brushes, and typed rules"


func expected_issues() -> Array[int]:
	return [1974]


func run() -> void:
	_host = Node.new()
	_host.name = "VibeRigHost"
	_tree.root.add_child(_host)
	rig = PluginRig.new()
	await rig.bring_up(_host, true)
	if rig.plugin == null:
		flag("the plugin stand-in did not come up", rig.error())
	else:
		await _commands_against_hidden_locked_grouped()
	await rig.take_down()
	_host.queue_free()
	await frame()


func _ids(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		if is_instance_valid(n):
			out.append(str(n.get_meta("brush_id", n.name)))
	out.sort()
	return out


func _selected() -> Array:
	return _ids(rig.plugin.stand_in_editor.selection.get_selected_nodes())


func _level_with_everything() -> Node:
	var level = await rig.make_level()
	level.grid_snap = 1.0
	var vg = level.visgroup_system
	var s := Vector3(2, 2, 2)
	rig.box(level, "a", Vector3(0, 1, 0), s)
	rig.box(level, "b", Vector3(5, 1, 0), s)
	rig.box(level, "c", Vector3(10, 1, 0), s)
	var h = rig.box(level, "hidden_vg", Vector3(15, 1, 0), s)
	var l = rig.box(level, "locked_vg", Vector3(20, 1, 0), s)
	var v = rig.box(level, "hidden_sel", Vector3(25, 1, 0), s)
	level.create_brush_from_info(
		{"size": s, "center": Vector3(30, 1, 0), "brush_id": "cut_filtered", "operation": 2}
	)
	var g1 = rig.box(level, "g_in", Vector3(0, 1, 10), s)
	var g2 = rig.box(level, "g_out", Vector3(40, 1, 10), s)
	level.create_visgroup("Off")
	level.add_selection_to_visgroup("Off", [h])
	level.set_visgroup_visible("Off", false)
	level.create_visgroup("Safe")
	level.add_selection_to_visgroup("Safe", [l])
	vg.set_visgroup_locked("Safe", true)
	vg.hide_from_view([v])
	level.set_view_filter("cut", true)
	vg.group_units("Spread", [g1, g2])
	await rig.frame()
	var shown: Array = []
	for b in level.draft_brushes_node.get_children():
		if b.visible:
			shown.append(b)
	note("visible brushes", _ids(shown))
	return level


func _commands_against_hidden_locked_grouped() -> void:
	var level = await _level_with_everything()
	# Select All.
	rig.select([])
	await rig.frame()
	rig.plugin._on_hotkey_palette_action("select_all")
	await rig.frame()
	note("Select All", _selected())
	# Invert from a.
	rig.select([level.find_brush_by_id("a")])
	await rig.frame()
	rig.plugin._on_hotkey_palette_action("invert_selection")
	await rig.frame()
	note("Invert from a", _selected())
	# Select Similar from a (size).
	rig.select([level.find_brush_by_id("a")])
	await rig.frame()
	rig.plugin._on_hotkey_palette_action("select_similar")
	await rig.frame()
	note("Select Similar from a", _selected())
	# Select Inside a volume around a and g_in.
	var vol = rig.box(level, "vol", Vector3(0, 1, 5), Vector3(4, 4, 14))
	rig.select([vol])
	await rig.frame()
	rig.plugin._on_hotkey_palette_action("select_inside")
	await rig.frame()
	note("Select Inside a box around a and g_in", _selected())
	# What Select All then Delete leaves.
	var before: int = level.draft_brushes_node.get_child_count()
	rig.select([])
	await rig.frame()
	rig.plugin._on_hotkey_palette_action("select_all")
	await rig.frame()
	var all_selected := _selected()
	rig.plugin._on_hotkey_palette_action("delete")
	await rig.frame()
	var asked: Array = []
	for dialog in rig.open_dialogs():
		asked.append(dialog.dialog_text)
	note("Delete asks", asked)
	await rig.accept_dialogs()
	var left: Array = _ids(level.draft_brushes_node.get_children())
	note("Select All then Delete: brushes %d -> %d" % [before, left.size()], left)
	var lost: Array = []
	for hidden in ["hidden_vg", "hidden_sel", "cut_filtered"]:
		if not left.has(hidden):
			lost.append(hidden)
	if not lost.is_empty():
		known(
			1974,
			"Select All selects hidden brushes, so Select All then Delete deletes them",
			(
				(
					"with 5 brushes in view and selectable, Select All selected %s and Delete asked %s, leaving only %s. "
					+ "%s are hidden by a visgroup, by Hide Selection and by the Cuts view filter. select_all() takes root._iter_pick_nodes() whole, where invert_selection() beside it asks is_visible_in_tree()"
				)
				% [all_selected, asked, left, lost]
			)
		)
	rig.undo().press_undo()
	await rig.frame()
	note("after Ctrl+Z", level.draft_brushes_node.get_child_count())
	var back = level.find_brush_by_id("hidden_sel")
	note("the Hide Selection'd brush after that undo: visible", back.visible if back else null)
	# Keep one kind, from a brush and an entity.
	var lamp = level._create_entity_from_map(
		{"classname": "light_point", "origin": Vector3(0, 3, 0)}
	)
	rig.select([level.find_brush_by_id("a"), lamp])
	await rig.frame()
	HFSelectionCommands.narrow_selection(rig.plugin, level, "solid")
	await rig.frame()
	note("keep one kind (solid) from a and a light", _selected())
	await _rules(level)
	await rig.leave_level(level)


func _rules(level: Node) -> void:
	var lights: Array = []
	for pair in [
		[1.0, Vector3(0, 3, 0)],
		[3.0, Vector3(5, 3, 0)],
		["10", Vector3(10, 3, 0)],
		[2, Vector3(0, 3, 5)]
	]:
		var e = level._create_entity_from_map({"classname": "light_point", "origin": pair[1]})
		e.entity_data["energy"] = pair[0]
		lights.append(e)
	# 1.0, 3.0, "10" and 2: a String compares as text, as the guide says, so
	# "energy > 2" passes the "10" by.
	var cases: Array = [
		["brush", ""],
		["brush", " , and , "],
		["brush", "operation is cut"],
		["brush", "OPERATION IS CUT"],
		["brush", "operation isnt cut"],
		["brush", "operation is not cut"],
		["brush", "operation >= cut"],
		["brush", "operation is"],
		["brush", "size > 2"],
		["brush", "shape is BOX"],
		["brush", "name matches G_*"],
		["brush", "visgroup is off"],
		["brush", "visgroup is Off"],
		["brush", "group is Spread"],
		["brush", "material is 0"],
		["brush", "material is 999"],
		["brush", "operation is cut and"],
		["brush", 'name is "a and b"'],
		["entity", "class is LIGHT_POINT"],
		["entity", "energy > 2"],
		["entity", "energy >= 2 and energy <= 3"],
		["entity", "energy is 2"],
		["entity", "energy matches 3"],
		["entity", "energy matches 1"],
		["entity", "energy is not 3"],
		["entity", "energy > abc"],
		["entity", "has_outputs is maybe"],
		["entity", "range is 10"],
	]
	for case in cases:
		var parsed: Dictionary = HFQuickSelect.parse(case[0], case[1])
		if not parsed["ok"]:
			note("rule %s '%s'" % case, "refused: %s" % parsed["error"])
			continue
		var picked: Dictionary = HFQuickSelect.pick(level, case[0], parsed["conditions"])
		if not picked["ok"]:
			note("rule %s '%s'" % case, "pick refused: %s" % picked["error"])
			continue
		var names: Array = []
		for n in picked["nodes"]:
			names.append(str(n.get_meta("brush_id", n.name)))
		names.sort()
		note("rule %s '%s'" % case, names)
