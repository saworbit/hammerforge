extends "res://tests/mcp/mcp_dispatcher_case.gd"
## Every brush action on every brush, and every face action on every face, of the
## levels in `tests/levels/`, against a baseline (#1648).
##
## The sweeps try every command in a handful of prepared states, and the face
## tools are mostly tried on boxes. Real levels hold rotated, clipped and sheared
## brushes, cylinders, structure pieces and brush entities, which is where the
## bugs have lived. Here each action runs on each item of a real level through
## the bridge, or for the four it does not run, through the LevelRoot calls their
## commands make, with the undo step their commands make.
##
## A try **passes** when it changes the level, raises no script error, leaves
## every brush it touched closed, and one undo gives back the level. It is
## **refused** when the action says why and changes nothing. Anything else
## **fails**. `tests/goldens/action_matrix.txt` holds one line per item, the
## actions that pass bare, refused ones as `~action` and failing ones as
## `!action`. It is a ratchet: a try that did better than its line passes and
## says so, one that did worse fails, naming the item.
##
## Items are named by what they are, not by id, which is per session: a brush by
## its shape, rounded middle and size, a face by its brush and the side it faces.
##
## `HF_MATRIX_BLESS=1` writes the baseline from the whole matrix, in the nightly
## test, which runs every try. The test in `tests/` runs one try in `SAMPLE`.

const SolidChecks = preload("res://tests/solid_checks.gd")
const VarietyLevel = preload("res://tests/support/matrix_variety_level.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")

const LEVELS := "res://tests/levels"
const GOLDEN := "res://tests/goldens/action_matrix.txt"
const BLESS_ENV := "HF_MATRIX_BLESS"
## A comma list of levels to run alone, such as `variety`; the rest are left out,
## and a blessing keeps their lines as they are.
const ONLY_ENV := "HF_MATRIX_ONLY"
## The pull request runs one try in this many, picked by a hash of the level, the
## item and the action, so the same ones run every time.
const SAMPLE := 40

const BRUSH_ACTIONS := [
	"hollow", "clip", "carve", "merge", "flip", "move_to_floor", "reset_rotation", "mirror_copy"
]
const FACE_ACTIONS := ["extrude", "clip_to_face", "material", "wrap_texture", "justify"]

const PASS := "pass"
const REFUSED := "refused"

## How far apart two brushes may be and still be neighbours, for Merge and Clip
## to Face.
const NEIGHBOUR_REACH := 0.5


## The folders under tests/levels with a level in them, in order, and the level
## the matrix builds for itself with what they lack (`matrix_variety_level.gd`).
static func folders() -> Array:
	var out: Array = []
	for name in DirAccess.get_directories_at(LEVELS):
		if FileAccess.file_exists(LEVELS.path_join(name).path_join("expected.json")):
			out.append(name)
	out.sort()
	out.append(VarietyLevel.NAME)
	var only := OS.get_environment(ONLY_ENV).strip_edges()
	if only != "":
		var wanted := only.split(",", false)
		out = out.filter(func(name): return wanted.has(name))
	return out


## The level file a folder holds, or the one its expected.json names.
static func level_file(folder: String) -> String:
	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(LEVELS.path_join(folder).path_join("expected.json"))
	)
	var expected: Dictionary = parsed if parsed is Dictionary else {}
	return str(expected.get("level", LEVELS.path_join(folder).path_join("level.hflevel")))


## The baseline, `"folder/item": {action: outcome}`, outcome PASS, REFUSED or
## "fail".
static func read_golden() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(GOLDEN):
		return out
	for line in FileAccess.get_file_as_string(GOLDEN).split("\n", false):
		var at := line.rfind(": ")
		if line.begins_with("#") or at < 0:
			continue
		var outcomes := {}
		for word in line.substr(at + 2).split(" ", false):
			if word.begins_with("!"):
				outcomes[word.substr(1)] = "fail"
			elif word.begins_with("~"):
				outcomes[word.substr(1)] = REFUSED
			else:
				outcomes[word] = PASS
		out[line.substr(0, at)] = outcomes
	return out


## Write the baseline from `results`, keeping the lines of every level they do
## not cover.
static func write_golden(results: Dictionary) -> void:
	var covered := {}
	for key in results:
		covered[str(key).get_slice("/", 0)] = true
	var kept := read_golden()
	for key in kept:
		if not covered.has(str(key).get_slice("/", 0)) and not results.has(key):
			results[key] = kept[key]
	var lines := PackedStringArray(
		[
			"# What each action does to each brush and face of the levels in tests/levels (#1648).",
			"# Bare passes, ~ is refused with a reason, ! fails. Written by HF_MATRIX_BLESS=1;",
			"# see tests/support/action_matrix_case.gd.",
		]
	)
	var keys := results.keys()
	keys.sort()
	for key in keys:
		var words := PackedStringArray()
		var outcomes: Dictionary = results[key]
		for action in BRUSH_ACTIONS + FACE_ACTIONS:
			if not outcomes.has(action):
				continue
			var outcome := str(outcomes[action])
			if outcome == PASS:
				words.append(action)
			elif outcome == REFUSED:
				words.append("~" + action)
			else:
				words.append("!" + action)
		lines.append("%s: %s" % [key, " ".join(words)])
	var file := FileAccess.open(GOLDEN, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()


static func blessing() -> bool:
	return OS.get_environment(BLESS_ENV) == "1"


## Whether the pull request's sample runs this try.
static func sampled(key: String, action: String) -> bool:
	return hash("%s|%s" % [key, action]) % SAMPLE == 0


# ---------------------------------------------------------------------------
# A level and its items
# ---------------------------------------------------------------------------


func load_level(folder: String) -> LevelRoot:
	var level := make_level()
	if folder == VarietyLevel.NAME:
		await VarietyLevel.fill(level, get_tree())
	else:
		assert_true(level.load_hflevel(level_file(folder)), "%s loads" % folder)
	await get_tree().process_frame
	undo.scene_history.clear_history()
	dispatcher.current_target()
	return level


## Every brush and face of `level`, each `{key, brush_id, face}` with `face` -1
## for the brush itself. A name two items share gets a number after it.
static func items(level: LevelRoot) -> Array:
	var out: Array = []
	var seen := {}
	var brushes: Array = level._iter_managed_brush_nodes()
	for brush in brushes:
		var brush_id := str(brush.brush_id)
		if brush_id == "":
			continue
		var brush_key := _unique(seen, "brush:" + brush_name(level, brush))
		out.append({"key": brush_key, "brush_id": brush_id, "face": -1})
		var faces: Array = brush.faces
		for i in faces.size():
			if faces[i] == null:
				continue
			var face_key := _unique(seen, "%s/face:%s" % [brush_key, side_of(brush, faces[i])])
			out.append({"key": face_key, "brush_id": brush_id, "face": i})
	return out


static func _unique(seen: Dictionary, name: String) -> String:
	var n := int(seen.get(name, 0)) + 1
	seen[name] = n
	return name if n == 1 else "%s#%d" % [name, n]


## A brush by what it is: "box 2,1.5,-4 4x3x1", its rounded middle and size.
static func brush_name(level: LevelRoot, brush: Node) -> String:
	var bounds: AABB = level.brush_system.world_bounds_of(brush)
	var middle := bounds.get_center().snapped(Vector3.ONE * 0.1)
	var size := bounds.size.snapped(Vector3.ONE * 0.1)
	var shape := "custom"
	for shape_name in LevelRoot.BrushShape:
		if int(LevelRoot.BrushShape[shape_name]) == int(brush.get("shape")):
			shape = str(shape_name).to_lower()
	return (
		"%s %s,%s,%s %sx%sx%s"
		% [
			shape,
			_num(middle.x),
			_num(middle.y),
			_num(middle.z),
			_num(size.x),
			_num(size.y),
			_num(size.z)
		]
	)


static func _num(value: float) -> String:
	var text := String.num(snappedf(value, 0.1), 1)
	return "0" if text == "-0" else text


## The world side a face mostly faces: "+x", "-y".
static func side_of(brush: Node, face: Object) -> String:
	var normal: Vector3 = ((brush as Node3D).global_basis * face.normal).normalized()
	var axis := normal.abs().max_axis_index()
	return "%s%s" % ["+" if normal[axis] >= 0.0 else "-", "xyz"[axis]]


# ---------------------------------------------------------------------------
# One try
# ---------------------------------------------------------------------------


## Run `action` on `item` and judge it: PASS, REFUSED, or "fail: why". The level
## is as it was afterwards, or `reload` is set in the answer when it is not.
func run_try(level: LevelRoot, item: Dictionary, action: String) -> Dictionary:
	var errors_before := get_errors().size()
	var before := _records(level)
	var before_text := var_to_str(level.capture_state(false))
	# The version, not the count of steps: the count keeps a step an undo took back.
	var version_before: int = undo.scene_history.get_version()
	var applied: Dictionary = await _apply(level, item, action)
	var problems: Array = []
	for e in get_errors().slice(errors_before):
		e.handled = true
		problems.append("%s:%d %s" % [str(e.file).get_file(), e.line, str(e.code)])
	var changed := var_to_str(level.capture_state(false)) != before_text
	if not bool(applied.get("ok", false)):
		if changed:
			problems.append("refused, and the level changed")
		if problems.is_empty():
			return {"outcome": REFUSED}
		return {"outcome": "fail: " + "; ".join(problems), "reload": changed}
	if not changed:
		if problems.is_empty():
			return {"outcome": REFUSED}
		return {"outcome": "fail: " + "; ".join(problems)}
	problems.append_array(_solid_problems(level, before))
	if undo.scene_history.get_version() == version_before:
		problems.append("it made no undo step")
	var undone: bool = await _undo(applied)
	if not undone or var_to_str(level.capture_state(false)) != before_text:
		problems.append("undo did not give back the level")
		return {"outcome": "fail: " + "; ".join(problems), "reload": true}
	if problems.is_empty():
		return {"outcome": PASS}
	return {"outcome": "fail: " + "; ".join(problems)}


## brush_id -> record, for what a try changed.
static func _records(level: LevelRoot) -> Dictionary:
	var out := {}
	for brush in level._iter_managed_brush_nodes():
		if str(brush.brush_id) != "":
			out[str(brush.brush_id)] = level.get_brush_info_from_node(brush)
	return out


## What is wrong with the brushes a try made or changed: an open edge, a face
## turned inward, a piece that is not convex.
static func _solid_problems(level: LevelRoot, before: Dictionary) -> Array:
	var out: Array = []
	for brush in level._iter_managed_brush_nodes():
		var brush_id := str(brush.brush_id)
		if before.has(brush_id) and before[brush_id] == level.get_brush_info_from_node(brush):
			continue
		var problem := SolidChecks.describe_problem(brush.faces)
		if problem != "":
			out.append("%s %s" % [brush_name(level, brush), problem])
	return out


func _undo(applied: Dictionary) -> bool:
	if bool(applied.get("bridge", false)):
		var r := await call_tool("hf_undo")
		await get_tree().process_frame
		return bool(r.get("ok", false))
	var ok: bool = undo.scene_history.undo()
	await get_tree().process_frame
	return ok


## `{ok, bridge}`: whether it ran, and whether the bridge made its step.
func _apply(level: LevelRoot, item: Dictionary, action: String) -> Dictionary:
	var brush_id: String = item["brush_id"]
	var face: int = item["face"]
	match action:
		"hollow", "clip", "carve", "move_to_floor", "reset_rotation":
			return await _bridge("hf_run_command", {"command": action, "brush_ids": [brush_id]})
		"merge":
			var near := _neighbours(level, brush_id)
			if near.is_empty():
				return {"ok": false}
			return await _bridge(
				"hf_run_command", {"command": "merge", "brush_ids": [brush_id, near[0]]}
			)
		"flip":
			return _local(
				level,
				"Flip HammerForge Objects",
				"flip_managed_nodes",
				[[brush_id], [], 0, level.resolve_transform_pivot([brush_id], [])]
			)
		"mirror_copy":
			var before := HFUndoHelper.capture_scope_or_state(level, [])
			var pivot: Vector3 = level.resolve_mirror_copy_pivot([brush_id], [])
			var made: Dictionary = level.mirror_copy_managed_nodes([brush_id], [], 1, pivot)
			if (made.get("brush_ids", []) as Array).is_empty():
				return {"ok": false}
			HFUndoHelper.commit_completed(undo, level, "Mirror Copy", before["state"])
			return {"ok": true}
		"extrude":
			return await _bridge(
				"hf_extrude_face",
				{"brush_id": brush_id, "face": face, "distance": 1.0, "snap": false}
			)
		"clip_to_face":
			var near := _neighbours(level, brush_id)
			if near.is_empty():
				return {"ok": false}
			return await _bridge(
				"hf_run_command",
				{
					"command": "clip_to_face",
					"brush_ids": near,
					"params": {"plane_brush_id": brush_id, "plane_face": face},
				}
			)
		"material":
			return await _bridge(
				"hf_assign_material",
				{
					"brush_id": brush_id,
					"faces": [face],
					"material": _other_slot(level, brush_id, face)
				}
			)
		"wrap_texture":
			var target := _face_beside(level, brush_id, face)
			if target < 0:
				return {"ok": false}
			var before := HFUndoHelper.capture_scope_or_state(level, [brush_id])
			var result: Dictionary = level.wrap_face_texture(brush_id, face, brush_id, target)
			if not bool(result.get("ok", false)):
				return {"ok": false}
			HFUndoHelper.commit_completed_if_changed(
				undo, level, "Wrap Texture", before["state"], Callable(), before["scope_ids"]
			)
			return {"ok": true}
		"justify":
			var before := HFUndoHelper.capture_scope_or_state(level, [brush_id])
			level.face_selection = {brush_id: [face]}
			level.justify_selected_faces("fit", false)
			level.face_selection = {}
			HFUndoHelper.commit_completed_if_changed(
				undo, level, "Justify", before["state"], Callable(), before["scope_ids"]
			)
			return {"ok": true}
	return {"ok": false}


func _bridge(method: String, params: Dictionary) -> Dictionary:
	var r := await call_tool(method, params)
	await get_tree().process_frame
	return {"ok": bool(r.get("ok", false)), "bridge": true}


func _local(level: LevelRoot, name: String, method: String, args: Array) -> Dictionary:
	HFUndoHelper.commit(undo, level, name, method, args, false, Callable(), "", true)
	return {"ok": true}


## The other brushes whose bounds come within NEIGHBOUR_REACH of this one's,
## nearest first.
static func _neighbours(level: LevelRoot, brush_id: String) -> Array:
	var brush = level.find_brush_by_id(brush_id)
	if brush == null:
		return []
	var mine: AABB = level.brush_system.world_bounds_of(brush).grow(NEIGHBOUR_REACH)
	var near: Array = []
	for other in level._iter_managed_brush_nodes():
		if other == brush or str(other.brush_id) == "":
			continue
		var theirs: AABB = level.brush_system.world_bounds_of(other)
		if mine.intersects(theirs):
			near.append([mine.get_center().distance_to(theirs.get_center()), str(other.brush_id)])
	near.sort_custom(func(a, b): return a[0] < b[0])
	return near.map(func(pair): return pair[1])


## Another palette slot than the face's, as "palette:N".
static func _other_slot(level: LevelRoot, brush_id: String, face: int) -> String:
	var brush = level.find_brush_by_id(brush_id)
	var slots: int = (
		level.material_manager.get_material_names().size() if level.material_manager else 0
	)
	if brush == null or slots < 2:
		return "palette:0"
	return "palette:%d" % ((int(brush.faces[face].material_idx) + 1) % slots)


## A face of the same brush that shares an edge with `face`, or -1.
static func _face_beside(level: LevelRoot, brush_id: String, face: int) -> int:
	var brush = level.find_brush_by_id(brush_id)
	if brush == null:
		return -1
	var corners := {}
	for point in brush.faces[face].local_verts:
		corners[SolidChecks.key(point)] = true
	for i in brush.faces.size():
		if i == face or brush.faces[i] == null:
			continue
		var shared := 0
		for point in brush.faces[i].local_verts:
			if corners.has(SolidChecks.key(point)):
				shared += 1
		if shared >= 2:
			return i
	return -1


# ---------------------------------------------------------------------------
# The matrix
# ---------------------------------------------------------------------------

const _RANK := {PASS: 2, REFUSED: 1, "fail": 0}


## Every try of `folder`'s level, or the sampled ones, against the baseline.
## Returns `{results, worse, better, failed}`: each try's outcome by item and
## action, the tries that did worse or better than their line, and every failing
## try with why, each said in a sentence.
func run_matrix(folder: String, sample_only: bool) -> Dictionary:
	var level := await load_level(folder)
	var golden := read_golden()
	var results := {}
	var worse: Array = []
	var better: Array = []
	var failed: Array = []
	for item in items(level):
		var key := "%s/%s" % [folder, item["key"]]
		var actions: Array = BRUSH_ACTIONS if int(item["face"]) < 0 else FACE_ACTIONS
		for action in actions:
			if sample_only and not sampled(key, action):
				continue
			var answer: Dictionary = await run_try(level, item, action)
			var said := str(answer["outcome"])
			var outcome := said if said == PASS or said == REFUSED else "fail"
			results.get_or_add(key, {})[action] = outcome
			if outcome == "fail":
				failed.append("%s %s: %s" % [key, action, said])
			var was := str((golden.get(key, {}) as Dictionary).get(action, ""))
			if was == "":
				worse.append("%s %s: not in the baseline (%s)" % [key, action, said])
			elif _RANK[outcome] < _RANK[was]:
				worse.append("%s %s: %s, was %s" % [key, action, said, was])
			elif _RANK[outcome] > _RANK[was]:
				better.append("%s %s: %s, was %s" % [key, action, outcome, was])
			if bool(answer.get("reload", false)):
				await _drop(level)
				level = await load_level(folder)
	await _drop(level)
	return {"results": results, "worse": worse, "better": better, "failed": failed}


## Say what got better, with the command that takes it into the baseline.
func say_better(better: Array) -> void:
	if better.is_empty():
		return
	(
		gut
		. p(
			(
				"%d tries do better than the baseline, for example %s. Take them in with %s=1 on tests/nightly."
				% [better.size(), better[0], BLESS_ENV]
			)
		)
	)


func _drop(level: LevelRoot) -> void:
	if level == null or not is_instance_valid(level):
		return
	var scene := level.get_parent()
	if scene and scene.get_parent():
		scene.get_parent().remove_child(scene)
	if scene:
		scene.queue_free()
	await get_tree().process_frame
