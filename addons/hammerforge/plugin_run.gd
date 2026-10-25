@tool
extends RefCounted
## Repeat Run (#1735): play the commands run since the selection last changed by
## hand again, on what is selected now, as one undo step.
##
## Repeat Last Command plays one command again, and much level work is a short
## run of them repeated: duplicate, move up, turn, for each step of a stair. The
## run is kept on the plugin as `run_steps`, each `{id, settings, version}`: a
## command and its settings as the Agent Bridge's `hf_run_command` takes them
## (#1645), and the scene history's version after its step. A drag of the gizmo
## is kept as how far it went, a Nudge offset and a Rotate angle, never as where
## it ended, so the next press goes as far again from where it starts.
##
## A selection changed by hand starts a new run at the next command. Until then
## Repeat Run plays the last one, which is how it goes from one room to the next.
## A change the run cannot play, such as a Flip, ends the run, and the next one
## starts after it.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("hf_command_registry.gd")
const HFUndoHelper = preload("undo_helper.gd")
const HFPluginEditActions = preload("plugin_edit_actions.gd")
const HFPluginAdjustLast = preload("plugin_adjust_last.gd")
const HFNumberFormat = preload("hf_number_format.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFUndoNavType = preload("ui/hf_undo_nav.gd")

## The commands that play the run and empty it, which are never in it.
const REPEAT := "repeat_run"
const CLEAR := "clear_run"
## The commands the run plays itself. Any other it holds, the Agent Bridge runs.
## The arrays have no bridge form, so the run makes them as their button does.
const PLAYS_ITSELF := [
	"duplicate", "nudge", "rotate_ccw", "rotate_cw", "duplicate_array", "radial_array", "grid_array"
]
## The commands with settings the run holds. Their call sites say what they ran
## with once the step has landed (`note()`), which is when the run takes them:
## Hollow asks first, and a Hollow turned down is not in the run.
const PLAYS_WITH_SETTINGS := [
	"nudge",
	"rotate_ccw",
	"rotate_cw",
	"hollow",
	"clip",
	"duplicate_array",
	"radial_array",
	"grid_array",
	"clip_to_face",
	"replace_material",
]
const AXES := ["x", "y", "z"]
## How near a turn of the gizmo has to be to a world axis to be kept as a turn
## about it, as the cosine of the angle between them.
const AXIS_TOLERANCE := 0.9999

# ---------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------


## Whether the run can hold `id`: one it plays itself, or one the bridge runs on
## the selection with no settings or with settings its call site says.
static func playable(id: String) -> bool:
	if id in PLAYS_ITSELF or id in PLAYS_WITH_SETTINGS:
		return true
	if not HFCommandRegistry.params(id).is_empty():
		return false
	var spec := HFCommandRegistry.bridge(id)
	if spec.is_empty():
		return false
	return int((spec.get("targets", {}) as Dictionary).get("min", 0)) >= 1


## A command ran from a key, the palette or a menu. One with settings is taken
## when its call site says them; any other the run can hold goes on the end of
## it, and one that changes the level and that the run cannot hold ends it.
static func on_command(plugin: Object, action: String) -> void:
	if _quiet(plugin) or action == REPEAT or action == CLEAR:
		return
	if not HFCommandRegistry.params(action).is_empty():
		if not (action in PLAYS_WITH_SETTINGS) and _changes_level(action) and _landed(plugin):
			clear(plugin)
		return
	# A command its own checks turned down made no step, and is not in the run.
	if not _landed(plugin):
		return
	if playable(action):
		_record(plugin, action, {})
	elif _changes_level(action):
		clear(plugin)


## Whether a step has landed since the run's last one. The first step of a run
## has nothing to be measured from, and is taken as it comes.
static func _landed(plugin: Object) -> bool:
	var steps := steps_of(plugin)
	if steps.is_empty() or plugin.get("run_restart") == true:
		return true
	return _version(plugin) != int(steps.back()["version"])


## A command with settings has made its step: `HFPluginAdjustLast.note()` hears
## the same.
static func note(plugin: Object, id: String, settings: Dictionary) -> void:
	if _quiet(plugin):
		return
	if playable(id):
		_record(plugin, id, settings)
	else:
		clear(plugin)


## Adjust Last made the last step again with other settings. The run's step for
## it takes them, so the run plays what is in the level.
static func adjusted(plugin: Object, id: String, settings: Dictionary, version: int) -> void:
	var steps := steps_of(plugin)
	if steps.is_empty() or str(steps.back()["id"]) != id:
		return
	steps.back()["settings"] = settings.duplicate(true)
	steps.back()["version"] = version


## The gizmo moved or turned `moved`, each `{node, from}` (see
## `HFSelectionGesture.moved()`). Kept as how far it went: a turn about a world
## axis and then a move, either left out when it is nothing. A drag that scaled
## them, turned them about any other axis or moved them apart ends the run.
static func note_moved(plugin: Object, moved: Array) -> void:
	if _quiet(plugin):
		return
	var root := _root(plugin)
	if root == null:
		return
	var pairs: Array = []
	for entry in moved:
		var node = entry.get("node")
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if root.is_brush_node(node) or root.is_entity_node(node):
			pairs.append([(node as Node3D).global_transform, entry["from"]])
	if pairs.is_empty():
		return
	var said := move_steps(pairs)
	if said.is_empty() and not _same_place(pairs):
		clear(plugin)
		return
	for step in said:
		_record(plugin, str(step[0]), step[1])


## What a drag did to `pairs`, each `[after, before]` global transforms, as the
## run's steps: `[[id, settings], ...]`. Empty when it did nothing, or when it did
## something a turn about a world axis and a move cannot say.
static func move_steps(pairs: Array) -> Array:
	var after_0: Transform3D = pairs[0][0]
	var before_0: Transform3D = pairs[0][1]
	var turn: Basis = after_0.basis.orthonormalized() * before_0.basis.orthonormalized().inverse()
	var centre_before := Vector3.ZERO
	var centre_after := Vector3.ZERO
	for pair in pairs:
		var after: Transform3D = pair[0]
		var before: Transform3D = pair[1]
		if not after.basis.get_scale().is_equal_approx(before.basis.get_scale()):
			return []
		var its_turn: Basis = (
			after.basis.orthonormalized() * before.basis.orthonormalized().inverse()
		)
		if not its_turn.is_equal_approx(turn):
			return []
		centre_before += before.origin
		centre_after += after.origin
	centre_before /= pairs.size()
	centre_after /= pairs.size()
	# Turned about the middle of their origins, as the gizmo turns them and as a
	# Rotate turns them, and then moved: the middle moves only by the move.
	var offset := centre_after - centre_before
	for pair in pairs:
		var after: Transform3D = pair[0]
		var before: Transform3D = pair[1]
		var expected := centre_before + turn * (before.origin - centre_before) + offset
		if not after.origin.is_equal_approx(expected):
			return []
	var out: Array = []
	var quat := turn.get_rotation_quaternion()
	var angle := rad_to_deg(quat.get_angle())
	# The quaternion may say a small turn the long way round.
	if angle > 180.0:
		angle -= 360.0
	if not is_zero_approx(snappedf(angle, 0.001)):
		var axis := quat.get_axis()
		var found := -1
		for i in 3:
			if absf(axis[i]) >= AXIS_TOLERANCE:
				found = i
		if found < 0:
			return []
		var degrees := snappedf(angle * signf(axis[found]), 0.001)
		out.append(
			[
				"rotate_ccw" if degrees > 0.0 else "rotate_cw",
				{"angle": degrees, "axis": AXES[found]}
			]
		)
	if not offset.is_zero_approx():
		out.append(["nudge", {"offset": offset.snapped(Vector3.ONE * 0.0001)}])
	return out


static func _same_place(pairs: Array) -> bool:
	for pair in pairs:
		if not (pair[0] as Transform3D).is_equal_approx(pair[1]):
			return false
	return true


## The selection changed. One the run did not make starts a new run at the next
## command, and leaves this one to play on it. Asked once the frame's work is
## done: a command says the selection changed while it is still changing it,
## before the run has taken the step that changed it.
static func on_selection_changed(plugin: Object) -> void:
	if _quiet(plugin) or steps_of(plugin).is_empty():
		return
	_check_selection.call_deferred(plugin)


## Untyped, since the plugin may be gone by the time a deferred call arrives.
static func _check_selection(plugin) -> void:
	if not is_instance_valid(plugin) or _quiet(plugin) or steps_of(plugin).is_empty():
		return
	if _selection_ids(plugin) != plugin.get("run_selection"):
		plugin.set("run_restart", true)


## A step was undone: the run's steps it took back leave the run with it.
static func on_version_changed(plugin: Object) -> void:
	if _quiet(plugin) or plugin.get("_adjusting_last") == true:
		return
	var steps := steps_of(plugin)
	var version := _version(plugin)
	if steps.is_empty() or version < 0:
		return
	while not steps.is_empty() and int(steps.back()["version"]) > version:
		steps.pop_back()


## Empty the run. The next command starts a new one.
static func clear(plugin: Object) -> void:
	steps_of(plugin).clear()
	plugin.set("run_restart", false)


static func _record(plugin: Object, id: String, settings: Dictionary) -> void:
	var root := _root(plugin)
	if root == null:
		return
	var steps := steps_of(plugin)
	if plugin.get("run_restart") == true or plugin.get("run_root") != root.get_instance_id():
		steps.clear()
	plugin.set("run_restart", false)
	plugin.set("run_root", root.get_instance_id())
	var kept := settings.duplicate(true)
	var version := _version(plugin)
	var last: Dictionary = {}
	if not steps.is_empty():
		last = steps.back()
	if not last.is_empty() and _adds_to(last, id, kept):
		for key in HFPluginAdjustLast.ADDS_UP[id]:
			last["settings"][key] += kept[key]
		last["version"] = version
	else:
		steps.append({"id": id, "settings": kept, "version": version})
	plugin.set("run_selection", _selection_ids(plugin))


## Whether a step of `id` with `settings` goes into `last` rather than after it:
## the same move or turn again, as held arrow keys and repeated R presses make.
static func _adds_to(last: Dictionary, id: String, settings: Dictionary) -> bool:
	if str(last["id"]) != id or not HFPluginAdjustLast.ADDS_UP.has(id):
		return false
	var held: Dictionary = last["settings"]
	for key in HFPluginAdjustLast.ADDS_UP[id]:
		if not (held.has(key) and settings.has(key)):
			return false
	return str(held.get("axis", "")) == str(settings.get("axis", ""))


static func _changes_level(action: String) -> bool:
	return (
		HFCommandRegistry.repeatable(action) and HFCommandRegistry.category(action) != "Selection"
	)


# ---------------------------------------------------------------------------
# Playing
# ---------------------------------------------------------------------------


## Play the run on the selection, as one undo step named Repeat Run. Each step
## acts on what the step before it left selected: after Duplicate the copy, after
## a Hollow its walls. A step that is refused stops the run, takes back what the
## steps before it made, and is named with why. True when the run played.
static func play(plugin: Object, root: Node) -> bool:
	var steps: Array = steps_of(plugin).duplicate(true)
	if steps.is_empty():
		_say(plugin, "Nothing to repeat: run commands on a selection first", 0)
		return false
	if root == null:
		return false
	var start := _managed(plugin, root)
	if start.is_empty():
		_say(plugin, "Select what to repeat the run on", 1)
		return false
	var start_refs := _refs(root, start)
	var restart: bool = plugin.get("run_restart") == true
	var before: Dictionary = HFUndoHelper.capture_scope_or_state(root, [])["state"]
	plugin.set("playing_run", true)
	var targets := start
	for i in steps.size():
		var outcome := _play_step(plugin, root, steps[i], targets)
		if not bool(outcome["ok"]):
			# The steps before it changed the level, if this one did not.
			if i > 0 or bool(outcome.get("touched", true)):
				root.restore_state(before)
			plugin.set("playing_run", false)
			# The same selection, rebuilt by the restore, so the run is as it was.
			_select(plugin, _found(root, start_refs))
			plugin.set("run_selection", _selection_ids(plugin))
			plugin.set("run_restart", restart)
			_say(
				plugin,
				(
					"Repeat Run stopped at step %d of %d, %s: %s. Nothing was changed"
					% [i + 1, steps.size(), step_text(steps[i]), str(outcome["message"])]
				),
				1
			)
			return false
		targets = outcome["targets"]
	plugin.set("playing_run", false)
	HFUndoHelper.commit_completed_if_changed(
		plugin.call("_get_undo_redo"),
		root,
		"Repeat Run",
		before,
		Callable(plugin, "_record_history")
	)
	# Its own selection, so the run goes on from it rather than starting again.
	_select(plugin, targets)
	plugin.set("run_selection", _selection_ids(plugin))
	plugin.set("run_restart", false)
	_say(plugin, "Repeat Run: %s" % run_text(plugin), 0)
	return true


## One step on `targets`: `{ok, targets}` with what it leaves selected, or `{ok:
## false, message, touched}` with `touched` false when it changed nothing.
static func _play_step(plugin: Object, root: Node, step: Dictionary, targets: Array) -> Dictionary:
	var id := str(step["id"])
	var settings: Dictionary = step["settings"]
	var refs := _refs(root, targets)
	var ids: Array = refs["brush_ids"]
	var paths: Array = refs["entity_paths"]
	match id:
		"duplicate":
			var made := HFPluginEditActions.make_duplicates(
				plugin, root, targets, HFPluginEditActions.duplicate_shift(root)
			)
			if made.is_empty():
				return {"ok": false, "message": "there is nothing to copy", "touched": false}
			return {"ok": true, "targets": made}
		"nudge":
			if ids.is_empty() and paths.is_empty():
				return {"ok": false, "message": "there is nothing to move", "touched": false}
			root.nudge_managed_nodes(ids, paths, settings.get("offset", Vector3.ZERO))
			return {"ok": true, "targets": targets}
		"rotate_ccw", "rotate_cw":
			if ids.is_empty() and paths.is_empty():
				return {"ok": false, "message": "there is nothing to turn", "touched": false}
			var pivot: Vector3 = root.resolve_transform_pivot(ids, paths)
			var axis := maxi(0, AXES.find(str(settings.get("axis", "y"))))
			root.rotate_managed_nodes(ids, paths, axis, float(settings.get("angle", 0.0)), pivot)
			return {"ok": true, "targets": targets}
		"duplicate_array", "radial_array", "grid_array":
			return _play_array(root, id, settings, ids, targets)
	return _play_on_bridge(plugin, root, id, settings, refs)


## An array round the brushes `ids`, with the settings it was made with, as its
## button makes it (#1896): a radial array turns about the pivot the brushes give
## now, as the button takes it from the selection. What stays selected is what it
## was made from, as after the button.
static func _play_array(
	root: Node, id: String, settings: Dictionary, ids: Array, targets: Array
) -> Dictionary:
	if ids.is_empty():
		return {"ok": false, "message": "there is no brush to make it from", "touched": false}
	var brush_ids := PackedStringArray(ids)
	var made: Variant = null
	match id:
		"duplicate_array":
			made = root.create_duplicate_array(
				brush_ids, int(settings.get("count", 3)), settings.get("offset", Vector3.ZERO)
			)
		"radial_array":
			made = root.create_radial_array(
				brush_ids,
				int(settings.get("count", 7)),
				maxi(0, AXES.find(str(settings.get("axis", "y")))),
				float(settings.get("step", 45.0)),
				root.resolve_transform_pivot(ids, []),
				float(settings.get("rise", 0.0))
			)
		"grid_array":
			made = root.create_grid_array(
				brush_ids,
				Vector3i(
					int(settings.get("count_x", 2)),
					int(settings.get("count_y", 1)),
					int(settings.get("count_z", 2))
				),
				settings.get("spacing", Vector3.ZERO)
			)
	if made == null:
		return {"ok": false, "message": "the array made nothing", "touched": false}
	return {"ok": true, "targets": targets}


## A step the Agent Bridge runs, with its checks and its refusals: on each brush
## in turn for a command that takes one, and on them all for any other.
static func _play_on_bridge(
	plugin: Object, root: Node, id: String, settings: Dictionary, refs: Dictionary
) -> Dictionary:
	var dispatcher = plugin.get("mcp_dispatcher")
	var commands = dispatcher.get("commands") if dispatcher != null else null
	if commands == null:
		return {"ok": false, "message": "its commands are not ready yet", "touched": false}
	var spec := HFCommandRegistry.bridge(id)
	var allowed: Dictionary = spec.get("targets", {})
	var ids: Array = refs["brush_ids"]
	var groups: Array = [ids]
	if int(allowed.get("max", -1)) == 1 and ids.size() > 1:
		groups = ids.map(func(brush_id): return [brush_id])
	var left: Array = []
	var touched := false
	for group in groups:
		var request := {"command": id, "brush_ids": group}
		if not settings.is_empty():
			request["params"] = settings
		if bool(allowed.get("entities", false)) and not (refs["entity_paths"] as Array).is_empty():
			request["entities"] = refs["entity_paths"]
		var checked: Dictionary = commands.check(root, request)
		if not bool(checked.get("ok", false)):
			return {"ok": false, "message": _refusal(checked), "touched": touched}
		touched = true
		var outcome: Dictionary = (checked["apply"] as Callable).call()
		if not bool(outcome.get("ok", false)):
			return {"ok": false, "message": _refusal(outcome), "touched": true}
		var result: Dictionary = outcome.get("result", {})
		for brush in (result.get("made", []) as Array) + (result.get("changed", []) as Array):
			left.append(str(brush.get("brush_id", "")))
	var after := _found(root, {"brush_ids": left, "entity_paths": []})
	if after.is_empty():
		after = _found(root, refs)
	return {"ok": true, "targets": after}


static func _refusal(answer: Dictionary) -> String:
	var error: Dictionary = answer.get("error", {})
	return str(error.get("message", "it was refused")).trim_suffix(".")


# ---------------------------------------------------------------------------
# Saying what the run holds
# ---------------------------------------------------------------------------


## The run as one line, as the palette shows it: "Duplicate, Move +Y 3 m, Rotate
## CCW 15° Y". Empty when there is no run.
static func run_text(plugin: Object) -> String:
	var parts := PackedStringArray()
	for step in steps_of(plugin):
		parts.append(step_text(step))
	return ", ".join(parts)


static func step_text(step: Dictionary) -> String:
	var id := str(step["id"])
	var settings: Dictionary = step["settings"]
	match id:
		"replace_material":
			return (
				"Replace %s with %s" % [str(settings.get("from", "")), str(settings.get("to", ""))]
			)
		"nudge":
			return "Move %s" % _offset_text(settings.get("offset", Vector3.ZERO))
		"rotate_ccw", "rotate_cw":
			return (
				"%s %s° %s"
				% [
					HFCommandRegistry.label(id),
					HFNumberFormat.number(absf(float(settings.get("angle", 0.0))), 0.001),
					str(settings.get("axis", "y")).to_upper()
				]
			)
		"hollow":
			return (
				"Hollow (%s m)"
				% HFNumberFormat.number(float(settings.get("thickness", 0.0)), 0.001)
			)
		"duplicate_array", "radial_array":
			return "%s x%d" % [HFCommandRegistry.label(id), int(settings.get("count", 0))]
		"grid_array":
			return (
				"%s %dx%dx%d"
				% [
					HFCommandRegistry.label(id),
					int(settings.get("count_x", 1)),
					int(settings.get("count_y", 1)),
					int(settings.get("count_z", 1))
				]
			)
		"clip":
			if settings.has("position"):
				return (
					"Clip at %s %s"
					% [
						str(settings.get("axis", "y")).to_upper(),
						HFNumberFormat.number(float(settings["position"]), 0.001)
					]
				)
	return HFCommandRegistry.label(id)


static func _offset_text(offset: Vector3) -> String:
	var parts := PackedStringArray()
	for i in 3:
		if not is_zero_approx(offset[i]):
			parts.append(
				(
					"%s%s %s m"
					% [
						"+" if offset[i] > 0.0 else "-",
						"XYZ"[i],
						HFNumberFormat.number(absf(offset[i]), 0.0001)
					]
				)
			)
	return " ".join(parts) if not parts.is_empty() else "0 m"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## The run's steps, the plugin's own array, so a change here is the plugin's.
static func steps_of(plugin: Object) -> Array:
	var steps = plugin.get("run_steps") if plugin else null
	return steps if steps is Array else []


## While the run plays, nothing it does is a new step, a selection by hand or an
## undo.
static func _quiet(plugin: Object) -> bool:
	# A stand-in with no run, as some tests hand over, has nothing to keep.
	return plugin == null or not ("run_steps" in plugin) or plugin.get("playing_run") == true


static func _root(plugin: Object) -> Node:
	var root = plugin.get("active_root")
	if root == null and plugin.has_method("_get_level_root"):
		root = plugin.call("_get_level_root")
	return root if root is Node and is_instance_valid(root) else null


static func _version(plugin: Object) -> int:
	var manager = plugin.get("undo_redo_manager")
	var root := _root(plugin)
	if manager == null or root == null:
		return -1
	var history: UndoRedo = HFUndoNavType.get_scene_undo_redo(manager, root)
	return history.get_version() if history else -1


## The selected brushes and entities still in the level, as instance ids in order:
## a brush a step took away, as Hollow does, is no longer selected.
static func _selection_ids(plugin: Object) -> Array:
	var ids: Array = []
	for node in plugin.call("_current_selection_nodes"):
		if is_instance_valid(node) and node is Node and (node as Node).is_inside_tree():
			if not (node as Node).is_queued_for_deletion():
				ids.append((node as Node).get_instance_id())
	ids.sort()
	return ids


## The selected brushes and entities the run can act on.
static func _managed(plugin: Object, root: Node) -> Array:
	var out: Array = []
	for node in plugin.call("_current_selection_nodes"):
		if not is_instance_valid(node) or not (node is Node):
			continue
		if root.is_brush_node(node):
			out.append(node)
		elif root.is_entity_node(node):
			var entity: Node = plugin.call("_managed_entity_owner", root, node)
			if entity and not out.has(entity):
				out.append(entity)
	return out


static func _refs(root: Node, nodes: Array) -> Dictionary:
	var brush_ids: Array = []
	var entity_paths: Array = []
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if root.is_brush_node(node):
			var brush_id := str(root.brush_system.ensure_brush_id(node))
			if brush_id != "":
				brush_ids.append(brush_id)
		elif root.is_entity_node(node):
			entity_paths.append(root.get_path_to(node))
	return {"brush_ids": brush_ids, "entity_paths": entity_paths}


static func _found(root: Node, refs: Dictionary) -> Array:
	var out: Array = []
	for brush_id in refs["brush_ids"]:
		var brush = root.find_brush_by_id(str(brush_id))
		if brush and not brush.is_queued_for_deletion() and not out.has(brush):
			out.append(brush)
	for path in refs["entity_paths"]:
		var entity := root.get_node_or_null(path)
		if entity and not entity.is_queued_for_deletion():
			out.append(entity)
	return out


static func _select(plugin: Object, nodes: Array) -> void:
	var editor = plugin.call("get_editor_interface")
	var selection = editor.get_selection() if editor else null
	plugin.set("hf_selection", nodes.duplicate())
	if selection:
		plugin.call("_apply_hf_selection", selection)


static func _say(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and dock.has_method("show_toast"):
		dock.show_toast(message, level)
