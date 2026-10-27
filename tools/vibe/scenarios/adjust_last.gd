@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Adjust Last, Repeat Run and Replace Material, on the real plugin.
##
## Adjust Last undoes the last command's step and makes it again with a changed
## setting, so the questions are about what it does with a value the command
## refuses or never expected: does the level keep what it had, does the history
## keep one step for it, and does the panel say why. Repeat Run plays the commands
## made since the selection last changed by hand, so: after an undo does it play
## only what is still in the level, and does a refused step leave the level as it
## was. Replace Material counts, shows and undoes the faces it changes (#1949), so
## what it reports is held against what changed, and one undo against the level
## before it. Keys can pass settings to a command (#1877), so a keymap entry's
## `args` are held against what the command then ran with.
##
## These live on the EditorPlugin, which cannot be built headless. The GUT
## suite's `plugin_rig.gd` compiles the real `plugin.gd` over a Node, so this does
## too, with the clipboard, prefabs, preferences and texture folder pointed at a
## folder of this run's own, as the suite's pre-run hook points them.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginAdjustLast = preload("res://addons/hammerforge/plugin_adjust_last.gd")
const HFPluginRun = preload("res://addons/hammerforge/plugin_run.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")
const HFTextureFolderType = preload("res://addons/hammerforge/hf_texture_folder.gd")
const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")
const McpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const McpHost = preload("res://tests/mcp/mcp_test_host.gd")

var rig = null
var _host: Node = null
var _saved := {}
var _folder := ""


func id() -> String:
	return "adjust-last"


func summary() -> String:
	return "Adjust Last at the edges, Repeat Run after an undo, Replace Material's count and undo, key args"


func expected_issues() -> Array[int]:
	return [1995, 1996, 1997]


func run() -> void:
	_redirect_files()
	_host = Node.new()
	_host.name = "AdjustLastHost"
	_tree.root.add_child(_host)
	rig = PluginRig.new()
	await rig.bring_up(_host, true)
	if rig.plugin == null:
		flag("the plugin stand-in could not be built", rig.error())
	else:
		await _adjust_hollow_out_of_range()
		await _adjust_array_out_of_range()
		await _repeat_run_after_undo()
		await _repeat_run_refused()
		await _replace_material()
		await _key_args()
		await rig.take_down()
	await _repeat_on_a_turned_grid()
	if is_instance_valid(_host):
		_tree.root.remove_child(_host)
		_host.free()
	await frame()
	_restore_files()


func _redirect_files() -> void:
	_folder = "user://vibe_adjust_last_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	_saved = {
		"prefab_dir": HFPrefabSystemType.prefab_dir,
		"clipboard": HFPrefabSystemType.clipboard_path,
		"stand_in": HFPrefabSystemType.system_clipboard_stand_in,
		"prefs": HFUserPrefsType.prefs_path,
		"textures": HFTextureFolderType.write_dir,
	}
	HFPrefabSystemType.prefab_dir = _folder.path_join("prefabs")
	HFPrefabSystemType.clipboard_path = _folder.path_join("clipboard.hfprefab")
	HFPrefabSystemType.system_clipboard_stand_in = ""
	HFUserPrefsType.prefs_path = _folder.path_join("hammerforge_prefs.json")
	HFTextureFolderType.write_dir = _folder.path_join("texture_folder")


func _restore_files() -> void:
	HFPrefabSystemType.prefab_dir = _saved["prefab_dir"]
	HFPrefabSystemType.clipboard_path = _saved["clipboard"]
	HFPrefabSystemType.system_clipboard_stand_in = _saved["stand_in"]
	HFUserPrefsType.prefs_path = _saved["prefs"]
	HFTextureFolderType.write_dir = _saved["textures"]
	_remove(_folder)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove(path.path_join(d))
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _level() -> Node:
	var level = await rig.make_level()
	level.grid_snap = 1.0
	level.rotate_snap_degrees = 15.0
	rig.undo().clear()
	HFPluginRun.clear(rig.plugin)
	rig.clear_toasts()
	return level


func _leave(level: Node) -> void:
	HFPluginAdjustLast.close(rig.plugin)
	rig.plugin.last_run = {}
	HFPluginRun.clear(rig.plugin)
	await rig.leave_level(level)


func _brushes(level: Node) -> Array:
	return level._iter_managed_brush_nodes()


func _thinnest(level: Node) -> float:
	var thinnest := INF
	for brush in _brushes(level):
		var b := HFSolidMeasure.bounds(HFSolidMeasure.world_faces(brush))
		thinnest = minf(thinnest, minf(b.size.x, minf(b.size.y, b.size.z)))
	return thinnest


func _last_toast() -> String:
	var t: Array = rig.toasts()
	return str(t.back()) if not t.is_empty() else ""


func _panel_value(key: String) -> Variant:
	var panel = rig.plugin._adjust_last_panel
	if panel == null or not is_instance_valid(panel):
		return null
	return panel.value_of(key)


# ---------------------------------------------------------------------------
# Adjust Last at the edges
# ---------------------------------------------------------------------------


func _adjust_hollow_out_of_range() -> void:
	note("-- Adjust Last: Hollow's thickness at the edges --")
	var level = await _level()
	var b = rig.box(level, "room", Vector3(0, 2, 0), Vector3(4, 4, 4))
	rig.select([b])
	await rig.frame()
	rig.plugin._hollow_selected(level)
	await rig.accept_dialogs()
	var walls: int = _brushes(level).size()
	var steps: int = rig.undo().step_count()
	note("hollow a 4 m box", "%d walls, %d steps, thinnest %.3f" % [walls, steps, _thinnest(level)])
	for value in [3.0, 0.0, -1.0, NAN, 0.5]:
		rig.clear_toasts()
		var ok = await HFPluginAdjustLast.adjust(rig.plugin, "thickness", value)
		await rig.frame()
		var now: int = _brushes(level).size()
		var line := (
			"adjusted %s, %d brushes, %d steps (%s), thinnest %.3f, run thickness %s, panel %s, said '%s'"
			% [
				ok,
				now,
				rig.undo().step_count(),
				rig.undo().scene_history.get_current_action_name(),
				_thinnest(level),
				str(rig.plugin.last_run.get("settings", {}).get("thickness")),
				str(_panel_value("thickness")),
				_last_toast()
			]
		)
		note("Adjust Last thickness %s" % value, line)
		if not is_finite(float(value)) and not is_finite(_thinnest(level)):
			flag("Adjust Last let a thickness of %s reach the walls" % value, line)
		# 3.0 is inside the panel's own range (0.05 to 128); the others are not,
		# so only it is a mapper's reach.
		if is_equal_approx(float(value), 3.0) and now == 1:
			known(
				1995,
				"Adjust Last to a thickness Hollow refuses turns the room back into a solid",
				(
					(
						"3.0 m on a 4 m box, in the panel's range: the hollow is undone, a step named %s "
						+ "that changes nothing takes its place, and the run and the dock keep 3.0. "
						+ "The Hollow press and Repeat Run both refuse it and change nothing: %s"
					)
					% [rig.undo().scene_history.get_current_action_name(), line]
				)
			)
		for problem in HFVibe.check_invariants(level):
			flag("Adjust Last thickness %s broke an invariant" % value, problem)
	rig.undo().press_undo()
	await rig.frame()
	note("one Ctrl+Z after the adjusts", "%d brushes" % _brushes(level).size())
	if _brushes(level).size() != 1:
		flag(
			"one Ctrl+Z after Adjust Last does not give back the solid",
			"%d brushes" % _brushes(level).size()
		)
	await _leave(level)


func _adjust_array_out_of_range() -> void:
	note("-- Adjust Last: an array's count at the edges --")
	var level = await _level()
	var b = rig.box(level, "post", Vector3(0, 1, 0), Vector3(1, 2, 1))
	rig.select([b])
	await rig.frame()
	var dock = rig.plugin.dock
	dock.dup_mode_opt.selected = 0
	dock.dup_count_spin.value = 2
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	note(
		"a duplicate array of 2",
		"%d brushes, run %s" % [_brushes(level).size(), rig.plugin.last_run.get("id")]
	)
	for value in [0, -3, 300, 150, 3]:
		rig.clear_toasts()
		var t0 := Time.get_ticks_msec()
		var ok = await HFPluginAdjustLast.adjust(rig.plugin, "count", value)
		await rig.frame()
		var line := (
			"adjusted %s, %d brushes, %d steps, run count %s, dock count %s, said '%s', %d ms"
			% [
				ok,
				_brushes(level).size(),
				rig.undo().step_count(),
				str(rig.plugin.last_run.get("settings", {}).get("count")),
				str(dock.dup_count_spin.value),
				_last_toast(),
				Time.get_ticks_msec() - t0
			]
		)
		note("Adjust Last count %s" % value, line)
		if value > 256 and _brushes(level).size() > 257:
			flag(
				"Adjust Last makes an array of %d, past the count's own maximum of 256" % value,
				line
			)
		if value == 150 and _brushes(level).size() == 151 and int(dock.dup_count_spin.value) != 150:
			known(
				1996,
				"Adjust Last's array count reaches 256 but the dock's count stops at 100",
				(
					(
						"an array adjusted to 150 copies leaves the dock's count at %d, so the next "
						+ "array and Repeat Last Command make %d, not the 150 in the level (#1896 says they follow)"
					)
					% [int(dock.dup_count_spin.value), int(dock.dup_count_spin.value)]
				)
			)
	await _leave(level)

	# A grid array, whose three counts the panel takes up to 64 each, and whose
	# copies the array caps at 256 brushes.
	var level2 = await _level()
	var p = rig.box(level2, "tile", Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	rig.select([p])
	await rig.frame()
	dock = rig.plugin.dock
	dock.dup_mode_opt.selected = 2
	dock.dup_grid_x.value = 2
	dock.dup_grid_y.value = 1
	dock.dup_grid_z.value = 2
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	var made: int = _brushes(level2).size()
	note("a grid array 2 x 1 x 2", "%d brushes, run %s" % [made, rig.plugin.last_run.get("id")])
	if str(rig.plugin.last_run.get("id")) == "grid_array":
		rig.clear_toasts()
		var ok = await HFPluginAdjustLast.adjust(rig.plugin, "count_x", 20)
		await rig.frame()
		ok = await HFPluginAdjustLast.adjust(rig.plugin, "count_z", 20) and ok
		await rig.frame()
		var line2 := (
			"adjusted %s, %d brushes, %d steps, said '%s', status '%s'"
			% [
				ok,
				_brushes(level2).size(),
				rig.undo().step_count(),
				_last_toast(),
				dock.status_label.text if dock.status_label else ""
			]
		)
		note("Adjust Last count_x 20, then count_z 20 (400 copies, past the cap of 256)", line2)
		if (
			_brushes(level2).size() == 1
			and _last_toast() == ""
			and not (dock.status_label and dock.status_label.text.contains("256"))
		):
			known(
				1995,
				"Adjust Last to an array the cap refuses takes the array away and says nothing",
				(
					(
						"a 2 x 1 x 2 grid array adjusted to 20 x 1 x 20 in the panel's own range: the array is "
						+ "undone, nothing replaces it, and no message says why. The dock's button asks "
						+ "HFDuplicator.can_generate() first and names the number: %s"
					)
					% line2
				)
			)
	await _leave(level2)


# ---------------------------------------------------------------------------
# Repeat Run
# ---------------------------------------------------------------------------


func _run(action: String) -> void:
	rig.plugin._on_hotkey_palette_action(action)


func _repeat_run_after_undo() -> void:
	note("-- Repeat Run after an undo --")
	var level = await _level()
	var first = rig.box(level, "step", Vector3(0, 1, 0), Vector3(2, 1, 2))
	rig.select([first])
	await rig.frame()
	_run("duplicate")
	await rig.frame()
	rig.plugin._nudge_selected(level, Vector3.UP)
	rig.plugin._rotate_selected(level, 1)
	note("the run", HFPluginRun.run_text(rig.plugin))
	# Take the turn back: the run should drop it with the step.
	rig.undo().press_undo()
	await rig.frame()
	note("the run after Ctrl+Z", HFPluginRun.run_text(rig.plugin))
	var before: int = _brushes(level).size()
	var selected: Array = rig.plugin._current_selection_nodes()
	var from: Node3D = selected[0] if not selected.is_empty() else null
	var from_basis: Basis = from.global_basis if from else Basis.IDENTITY
	_run("repeat_run")
	await rig.frame()
	var after: Array = rig.plugin._current_selection_nodes()
	var made: Node3D = after[0] if not after.is_empty() else null
	var turned := false
	if made:
		turned = not made.global_basis.is_equal_approx(from_basis)
	note(
		"Repeat Run after taking the turn back",
		"%d -> %d brushes, the new copy turned: %s" % [before, _brushes(level).size(), turned]
	)
	if turned:
		flag("Repeat Run still plays a turn that was undone", HFPluginRun.run_text(rig.plugin))
	# Undo the Repeat Run and redo the nudge's step back in: what does the run hold?
	rig.undo().press_undo()
	await rig.frame()
	rig.undo().press_undo()
	await rig.frame()
	var after_undo := HFPluginRun.run_text(rig.plugin)
	rig.undo().press_redo()
	await rig.frame()
	note(
		"undo the Repeat Run and the nudge, then redo the nudge",
		(
			"run '%s' after the undos, '%s' after the redo"
			% [after_undo, HFPluginRun.run_text(rig.plugin)]
		)
	)
	await _leave(level)


func _repeat_run_refused() -> void:
	note("-- Repeat Run: a step refused part way --")
	var level = await _level()
	var a = rig.box(level, "big", Vector3(0, 2, 0), Vector3(4, 4, 4))
	var thin = rig.box(level, "thin", Vector3(10, 2, 0), Vector3(0.3, 4, 4))
	rig.select([a])
	await rig.frame()
	_run("duplicate")
	await rig.frame()
	rig.plugin._hollow_selected(level)
	await rig.accept_dialogs()
	note("the run", HFPluginRun.run_text(rig.plugin))
	rig.select([level.find_brush_by_id("thin")])
	await rig.frame()
	var sig := HFVibe.signature(level)
	var steps: int = rig.undo().step_count()
	rig.clear_toasts()
	_run("repeat_run")
	await rig.frame()
	await rig.frame()
	note(
		"Repeat Run on a brush too thin to hollow",
		(
			"level unchanged %s, %d -> %d steps, said '%s'"
			% [HFVibe.signature(level) == sig, steps, rig.undo().step_count(), _last_toast()]
		)
	)
	if HFVibe.signature(level) != sig:
		flag(
			"a refused Repeat Run left the level changed",
			"%s -> %s" % [sig, HFVibe.signature(level)]
		)
	if rig.undo().step_count() != steps:
		flag(
			"a refused Repeat Run registered a step", "%d -> %d" % [steps, rig.undo().step_count()]
		)
	for problem in HFVibe.check_invariants(level):
		flag("a refused Repeat Run broke an invariant", problem)
	await _leave(level)


# ---------------------------------------------------------------------------
# Replace Material
# ---------------------------------------------------------------------------


func _slots_of(level: Node) -> Dictionary:
	var out := {}
	for brush in _brushes(level):
		var slots: Array = []
		for f in brush.faces:
			slots.append([f.material_idx, f.uv_scale, f.uv_offset, snappedf(f.uv_rotation, 0.0001)])
		out[str(brush.brush_id)] = slots
	return out


func _replace_material() -> void:
	note("-- Replace Material: the count, the faces and the undo --")
	var level = await _level()
	level.add_prototype_materials()
	var grey := 1
	var plaster := 2
	var a = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var b = rig.box(level, "b", Vector3(4, 1, 0), Vector3(2, 2, 2))
	var hidden = rig.box(level, "hidden", Vector3(8, 1, 0), Vector3(2, 2, 2))
	var locked = rig.box(level, "locked", Vector3(12, 1, 0), Vector3(2, 2, 2))
	for brush in [a, b, hidden, locked]:
		for i in brush.faces.size():
			brush.faces[i].material_idx = grey
			brush.faces[i].uv_scale = Vector2(0.5, 0.5)
	b.faces[0].material_idx = plaster
	level.create_visgroup("Out")
	level.add_selection_to_visgroup("Out", [hidden])
	level.set_visgroup_visible("Out", false)
	level.create_visgroup("Fixed")
	level.add_selection_to_visgroup("Fixed", [locked])
	level.visgroup_system.set_visgroup_locked("Fixed", true)
	await rig.frame()
	var before := _slots_of(level)
	var expected := 0
	var wearing: Dictionary = level.faces_wearing_material(grey, {})
	for key in wearing:
		expected += (wearing[key] as Array).size()
	rig.clear_toasts()
	rig.plugin.dock._on_replace_material_requested(grey, plaster, {}, true)
	await rig.frame()
	var after := _slots_of(level)
	var changed := 0
	for key in before:
		for i in (before[key] as Array).size():
			if HFVibe.canonical(before[key][i]) != HFVibe.canonical(after[key][i]):
				changed += 1
	note(
		"Replace grey with plaster across the level, resetting UVs",
		(
			"faces_wearing said %d, %d faces changed, said '%s', run %s"
			% [expected, changed, _last_toast(), rig.plugin.last_run.get("id")]
		)
	)
	if _last_toast().find("on %d face" % changed) < 0:
		flag(
			"Replace Material's message does not count the faces it changed",
			"%d changed: '%s'" % [changed, _last_toast()]
		)
	# Adjust Last to 'shown': the hidden brush keeps grey.
	var ok = await HFPluginAdjustLast.adjust(rig.plugin, "scope", "shown")
	await rig.frame()
	var shown := _slots_of(level)
	note(
		"Adjust Last scope to shown",
		(
			"adjusted %s, hidden brush face 0 slot %s, a face 0 slot %s"
			% [ok, shown["hidden"][0][0], shown["a"][0][0]]
		)
	)
	if int(shown["hidden"][0][0]) != grey:
		flag("Adjust Last to 'shown' still changes the hidden brush", str(shown["hidden"][0]))
	ok = await HFPluginAdjustLast.adjust(rig.plugin, "reset_uv", false)
	await rig.frame()
	var kept := _slots_of(level)
	note("Adjust Last reset_uv off", "adjusted %s, a face 0 %s" % [ok, kept["a"][0]])
	rig.undo().press_undo()
	await rig.frame()
	var undone := _slots_of(level)
	var differ: Array = []
	for key in before:
		if HFVibe.canonical(before[key]) != HFVibe.canonical(undone.get(key)):
			differ.append(key)
	note("one Ctrl+Z after Replace and two adjusts", "brushes not as before: %s" % [differ])
	if not differ.is_empty():
		flag("one Ctrl+Z after Replace Material does not put every face back", str(differ))
	await _leave(level)


# ---------------------------------------------------------------------------
# Keys passing settings
# ---------------------------------------------------------------------------


func _key_args() -> void:
	note("-- a key's args reach the command it runs --")
	var level = await _level()
	var b = rig.box(level, "room", Vector3(0, 2, 0), Vector3(4, 4, 4))
	rig.select([b])
	await rig.frame()
	rig.plugin.dock.hollow_thickness.value = 0.25
	var dock_thickness: float = rig.plugin.dock.get_hollow_thickness()
	# What `plugin_input_router.gd` does for a bound key: execute with the
	# keymap entry's `args`. Those run through the bridge, as the command line
	# does, and the editor's bridge host cannot run headless, so the rig's scene
	# and undo get one of their own for this.
	var kept = rig.plugin.mcp_dispatcher
	var host := McpHost.new()
	host.scene = rig.scene_root
	host.undo = rig.undo()
	host.tree = _tree
	rig.plugin.mcp_dispatcher = McpDispatcher.new(host)
	HFPluginCommands.execute(rig.plugin, "hollow", [], {"thickness": 0.5})
	await rig.frame()
	await rig.frame()
	await rig.accept_dialogs()
	rig.plugin.mcp_dispatcher.shutdown()
	rig.plugin.mcp_dispatcher = kept
	var thinnest := _thinnest(level)
	note(
		"Hollow run with args {thickness: 0.5}",
		(
			"dock holds %.3f, the walls are %.3f, run thickness %s"
			% [
				dock_thickness,
				thinnest,
				str(rig.plugin.last_run.get("settings", {}).get("thickness"))
			]
		)
	)
	if absf(thinnest - 0.5) > 0.01:
		known(
			1997,
			"a keymap entry's args do not reach Hollow",
			(
				(
					"Hollow run with {thickness: 0.5} made %.3f m walls, the dock's %.3f; "
					+ "only Extrude reads the settings `execute()` is given"
				)
				% [thinnest, dock_thickness]
			)
		)
	await _leave(level)


# ---------------------------------------------------------------------------
# Repeat on a turned grid (#1950)
# ---------------------------------------------------------------------------


## A Repeat copy of a cut and of a cylinder on a floor grid turned 30 degrees:
## turned with the grid, standing on the point, its corners on the grid's points
## for even sizes, and the same after a save and a load.
func _repeat_on_a_turned_grid() -> void:
	note("-- Repeat on a turned grid --")
	var root: Node3D = await fresh_root()
	root.grid_snap = 1.0
	root.grid_system.set_turn(30.0, Vector3.ZERO)
	var base: Vector3 = root.grid_system.grid_point(Vector3(3.2, 0, 1.7), 1.0)
	var cases := {
		"a 2 x 2 x 2 box":
		{"shape": 0, "size": Vector3(2, 2, 2), "operation": CSGShape3D.OPERATION_UNION},
		"a 2 x 2 x 2 cut":
		{"shape": 0, "size": Vector3(2, 2, 2), "operation": CSGShape3D.OPERATION_SUBTRACTION},
		"a cylinder of 8":
		{"shape": 1, "size": Vector3(2, 3, 2), "operation": CSGShape3D.OPERATION_UNION, "sides": 8},
	}
	var turn := Basis(Vector3.UP, deg_to_rad(30.0))
	for label in cases:
		var info: Dictionary = root.drag_system.repeat_info(cases[label], base)
		var made = root.create_brush_from_info(info)
		await frame()
		if made == null:
			flag("Repeat on a turned grid made no %s" % label, str(info))
			continue
		var turned_ok: bool = made.global_basis.orthonormalized().is_equal_approx(turn)
		var bounds := AABB()
		var first := true
		for f in made.faces:
			for c in f.local_verts:
				var w: Vector3 = made.global_transform * c
				bounds = AABB(w, Vector3.ZERO) if first else bounds.expand(w)
				first = false
		var on_grid := 0
		var corners := 0
		if int(cases[label]["shape"]) == 0:
			for f in made.faces:
				for c in f.local_verts:
					var w: Vector3 = made.global_transform * c
					corners += 1
					if w.distance_to(root.grid_system.grid_point(w, 1.0)) < 0.001:
						on_grid += 1
		note(
			"Repeat %s on a grid turned 30" % label,
			(
				"in %s, turned with the grid %s, bottom at y %.3f, %d of %d corners on grid points"
				% [made.get_parent().name, turned_ok, bounds.position.y, on_grid, corners]
			)
		)
		if not turned_ok:
			flag("a Repeat copy of %s does not turn with the grid" % label, str(made.global_basis))
		if absf(bounds.position.y - base.y) > 0.001:
			flag(
				"a Repeat copy of %s does not stand on the point" % label,
				"bottom at %.3f" % bounds.position.y
			)
		if corners > 0 and on_grid != corners:
			flag(
				"a Repeat copy of %s has corners off the turned grid" % label,
				"%d of %d" % [on_grid, corners]
			)
	# Through a save and a load.
	var path := "user://vibe_adjust_last_turned.hflevel"
	var before := HFVibe.describe_level(root)
	root.save_hflevel(path, true)
	await HFVibe.settle_save(_tree, root)
	var other: Node3D = await fresh_root("Reloaded")
	other.load_hflevel(path)
	await frame()
	diff_levels(
		before, HFVibe.describe_level(other), "turned Repeat copies through a save and a load"
	)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await drop_root(other)
	await drop_root(root)
