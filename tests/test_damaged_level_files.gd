extends GutTest

## A level file reaches the loader from disk, git merges, sync tools and hand
## edits. A half resolved merge in an uncompressed `.hflevel` and a cloud sync
## that cut a file short are both realistic. These feed the loader damaged copies
## of real levels on purpose, from a fixed seed (#1641).
##
## Every case goes through `read_hflevel()` and, when that takes it, through the
## whole load on a level that holds one brush. The rule for each:
##
## - no script error;
## - a refusal that names the file, after which the open level is exactly as it
##   was; or a level whose numbers are all finite and whose brushes are closed
##   convex solids.
##
## The cases come from every level in `tests/levels/`, the reference map, and a
## small level built here with one of each kind of thing a level saves.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")

const SEED := 1641
const DIR := "user://hf_damaged_levels"
const REFERENCE := "res://addons/hammerforge/data/reference_map.hflevel"
const LEVELS_DIR := "res://tests/levels"
## Stands for a number JSON cannot write, put in the text after it is written.
const INF_MARK := "__hf_test_inf__"
const BAD_VALUES := [null, -1, INF_MARK, "", [], {}, "LONG", "WRONG"]

## Cases waiting on a fix, by label: issue.
const KNOWN := {}
## Engine messages a damaged file earns that no script can head off, by where the
## engine prints them: a compressed stream that does not inflate, a number too
## large to be one, which Godot's JSON reader prints as it reads 1e999, and on
## Windows a resource path whose case a flipped bit changed.
const ENGINE_SAYS := ["compression.cpp", "Exponent too high", "Case mismatch"]

var _rng := RandomNumberGenerator.new()


func after_all() -> void:
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


## Every source level as its decoded JSON: the small one built here, the
## reference map and each file in tests/levels.
func _sources() -> Array:
	var out: Array = [{"label": "small", "json": _small_level_json()}]
	var paths: Array = [REFERENCE]
	if DirAccess.dir_exists_absolute(LEVELS_DIR):
		for name in DirAccess.get_files_at(LEVELS_DIR):
			if name.ends_with(".hflevel"):
				paths.append(LEVELS_DIR.path_join(name))
	for path in paths:
		var parsed := HFLevelIO.load_from_path(path)
		assert_false(parsed.is_empty(), "fixture: %s loads" % path)
		out.append({"label": str(path).get_file().get_basename(), "json": parsed})
	return out


## A level with a box, a wedge, a cylinder, a pending cut, a door, a light, a
## visgroup, a group and a cordon, as its file holds it.
func _small_level_json() -> Dictionary:
	var level := _new_level()
	level.add_prototype_materials()
	var box := level.create_brush_from_info(
		{"brush_id": "box", "size": Vector3(4, 2, 4), "center": Vector3(0, 1, 0)}
	)
	box.faces[2].material_idx = 3
	level.create_brush_from_info(
		{
			"brush_id": "ramp",
			"shape": level.BrushShape.WEDGE,
			"size": Vector3(2, 2, 4),
			"center": Vector3(5, 1, 0)
		}
	)
	level.create_brush_from_info(
		{
			"brush_id": "pillar",
			"shape": level.BrushShape.CYLINDER,
			"sides": 12,
			"size": Vector3(1, 3, 1),
			"center": Vector3(-4, 1.5, 0)
		}
	)
	level.create_brush_from_info(
		{
			"brush_id": "hole",
			"size": Vector3(1, 1, 1),
			"center": Vector3(0, 1, 0),
			"operation": CSGShape3D.OPERATION_SUBTRACTION,
			"pending": true
		}
	)
	level.create_brush_from_info(
		{"brush_id": "gate", "size": Vector3(0.2, 2, 1), "center": Vector3(2, 1, 3)}
	)
	level.tie_brushes_to_entity(["gate"], "func_door", "gate_1")
	var lamp := DraftEntityScript.new()
	lamp.entity_type = "light_point"
	lamp.name = "lamp"
	lamp.position = Vector3(0, 3, 0)
	level.add_entity(lamp)
	level.add_selection_to_visgroup("upstairs", [box])
	level.set_cordon_from_selection([box])
	var json: Dictionary = level.state_system.capture_hflevel_state()
	_free_level(level)
	return json


func _new_level() -> LevelRoot:
	var level := LevelRootType.new()
	level.auto_spawn_player = false
	level.commit_freeze = false
	level.hflevel_autosave_enabled = false
	add_child(level)
	return level


func _free_level(level: Node) -> void:
	if is_instance_valid(level):
		remove_child(level)
		level.free()


## Each damaged copy: {label, bytes}.
func _cases() -> Array:
	_rng.seed = SEED
	var cases: Array = []
	for source in _sources():
		var json: Dictionary = source["json"]
		var label: String = source["label"]
		var text := JSON.stringify(json)
		var packed := HFLevelIO.build_payload_from_json(text, true)
		var plain := HFLevelIO.build_payload_from_json(JSON.stringify(json, "\t"), false)
		for i in 8:
			cases.append(
				_case(
					"%s cut short %d" % [label, i],
					packed.slice(0, _rng.randi_range(0, packed.size() - 1))
				)
			)
			cases.append(
				_case(
					"%s plain cut short %d" % [label, i],
					plain.slice(0, _rng.randi_range(0, plain.size() - 1))
				)
			)
			cases.append(_case("%s bit flip %d" % [label, i], _flip_bit(packed)))
			cases.append(_case("%s plain bit flip %d" % [label, i], _flip_bit(plain)))
		cases.append(_case("%s junk after the header" % label, _junk_after_header()))
		cases.append(_case("%s merge conflict" % label, _with_conflict(JSON.stringify(json, "\t"))))
		# The JSON damage costs a full load each, so the large levels take fewer.
		var edits := 25 if label == "small" else 4
		var paths := _paths(json)
		for i in edits:
			var path: Array = paths[_rng.randi_range(0, paths.size() - 1)]
			var bad = BAD_VALUES[i % BAD_VALUES.size()]
			var damaged = json.duplicate(true)
			_set_at(damaged, path, _bad_for(bad, _get_at(json, path)))
			cases.append(_json_case("%s %s = %s" % [label, _path_text(path), str(bad)], damaged))
		for i in edits:
			var keyed := paths.filter(func(p): return not p.is_empty() and p[-1] is String)
			var path: Array = keyed[_rng.randi_range(0, keyed.size() - 1)]
			var damaged = json.duplicate(true)
			_erase_at(damaged, path)
			cases.append(_json_case("%s without %s" % [label, _path_text(path)], damaged))
		var tripled = json.duplicate(true)
		var brushes: Array = tripled.get("state", {}).get("brushes", [])
		tripled["state"]["brushes"] = brushes + brushes + brushes
		cases.append(_json_case("%s every brush three times" % label, tripled))
		var deep = json.duplicate(true)
		var nest: Variant = 1.0
		for i in HFLevelIO.MAX_RECURSION_DEPTH + 16:
			nest = [nest]
		deep["state"]["brushes"][0]["size"] = nest
		cases.append(_json_case("%s nested past the cap" % label, deep))
		var infinite = json.duplicate(true)
		infinite["state"]["brushes"][0]["size"] = {
			"__hf_type": "Vector3", "value": [INF_MARK, 2.0, 2.0]
		}
		cases.append(_json_case("%s infinite brush size" % label, infinite))
	return cases


func _case(label: String, bytes: PackedByteArray) -> Dictionary:
	return {"label": label, "bytes": bytes}


func _json_case(label: String, json: Dictionary) -> Dictionary:
	var text := JSON.stringify(json, "\t").replace('"%s"' % INF_MARK, "1e999")
	return _case(label, HFLevelIO.build_payload_from_json(text, false))


func _flip_bit(bytes: PackedByteArray) -> PackedByteArray:
	var out := bytes.duplicate()
	var at := _rng.randi_range(0, out.size() - 1)
	out[at] = out[at] ^ (1 << _rng.randi_range(0, 7))
	return out


func _junk_after_header() -> PackedByteArray:
	var out := ("%s\n" % HFLevelIO.MAGIC).to_utf8_buffer()
	for i in 256:
		out.append(_rng.randi_range(0, 255))
	return out


## The file as a merge leaves it when both sides changed one line of it.
func _with_conflict(text: String) -> PackedByteArray:
	var lines := text.split("\n")
	var at := lines.size() / 2
	var mine := lines[at]
	lines.insert(at, "<<<<<<< HEAD")
	lines.insert(at + 2, "=======")
	lines.insert(at + 3, mine)
	lines.insert(at + 4, ">>>>>>> theirs")
	return HFLevelIO.build_payload_from_json("\n".join(lines), false)


## Every path into `value`: each dictionary key and array index, as a list.
static func _paths(value: Variant, prefix: Array = []) -> Array:
	var out: Array = []
	if value is Dictionary:
		for key in value:
			var path := prefix + [key]
			out.append(path)
			out.append_array(_paths(value[key], path))
	elif value is Array:
		for i in mini((value as Array).size(), 4):
			var path := prefix + [i]
			out.append(path)
			out.append_array(_paths(value[i], path))
	return out


static func _get_at(value: Variant, path: Array) -> Variant:
	for step in path:
		value = value[step]
	return value


static func _set_at(value: Variant, path: Array, replacement: Variant) -> void:
	var parent: Variant = _get_at(value, path.slice(0, path.size() - 1))
	parent[path[-1]] = replacement


static func _erase_at(value: Variant, path: Array) -> void:
	var parent: Variant = _get_at(value, path.slice(0, path.size() - 1))
	if parent is Dictionary:
		(parent as Dictionary).erase(path[-1])


static func _path_text(path: Array) -> String:
	return ".".join(path.map(func(step): return str(step)))


static func _bad_for(bad: Variant, current: Variant) -> Variant:
	if bad is String and bad == "LONG":
		return "x".repeat(100000)
	if bad is String and bad == "WRONG":
		if current is String:
			return 7
		if current is float or current is int:
			return "seven"
		if current is Array:
			return {}
		return []
	return bad


func test_there_are_at_least_a_hundred_cases():
	assert_gt(_cases().size(), 99)


func test_each_damaged_file_is_refused_or_loads_whole():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for case in _cases():
		await _check(case)


func _check(case: Dictionary) -> void:
	var label: String = case["label"]
	var path := DIR.path_join("damaged.hflevel")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(case["bytes"])
	file.close()
	var level := _new_level()
	level.create_brush_from_info(
		{"brush_id": "open", "size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)}
	)
	var before := var_to_str(level.capture_state(false))
	var errors_before := get_errors().size()
	var read: Dictionary = level.file_system.read_hflevel(path)
	var loaded := false
	if read.get("ok", false):
		loaded = level.load_hflevel(path)
	await get_tree().process_frame
	var errors: Array = get_errors().slice(errors_before)
	var raised: Array = []
	for e in errors:
		e.handled = true
		# A warning is the loader saying what it left out or refused.
		if e.is_push_warning():
			continue
		var said := "%s:%d %s" % [str(e.file).get_file(), e.line, str(e.code)]
		if e.is_engine_error() and ENGINE_SAYS.any(func(text): return said.contains(text)):
			continue
		raised.append(said)
	if KNOWN.has(label):
		pending("%s: %s" % [label, KNOWN[label]])
		_free_level(level)
		return
	assert_eq(raised, [], "%s raised no script error" % label)
	if not read.get("ok", false):
		assert_string_contains(
			str(read.get("error", "")), "damaged.hflevel", "%s: the refusal names the file" % label
		)
		assert_eq(
			var_to_str(level.capture_state(false)),
			before,
			"%s: refused, and the level is as it was" % label
		)
	elif loaded:
		var problem := _whole(level)
		assert_eq(problem, "", "%s: %s" % [label, problem])
	_free_level(level)


## What is wrong with a loaded level, or "" when every number is finite and every
## brush is a closed convex solid.
func _whole(level: LevelRoot) -> String:
	for brush in level._iter_managed_brush_nodes():
		var draft := brush as DraftBrush
		if (
			not draft.global_transform.basis.x.is_finite()
			or not draft.global_transform.origin.is_finite()
		):
			return "%s has a transform that is not finite" % draft.brush_id
		if not draft.size.is_finite():
			return "%s has a size that is not finite" % draft.brush_id
		for face in draft.faces:
			for point in face.local_verts:
				if not point.is_finite():
					return "%s has a corner that is not finite" % draft.brush_id
		var problem := SolidChecks.describe_problem(draft.faces)
		if problem != "":
			return "%s: %s" % [draft.brush_id, problem]
	return ""


func _write(bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := DIR.path_join("one.hflevel")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return path


func test_an_infinite_brush_size_leaves_that_brush_out_and_says_which():
	var json := _small_level_json()
	json["state"]["brushes"][0]["size"] = {"__hf_type": "Vector3", "value": [INF_MARK, 2.0, 2.0]}
	var path := _write(_json_case("inf", json)["bytes"])
	var level := _new_level()
	HFLog.begin_test_capture(["left out"])
	var errors_before := get_errors().size()
	assert_true(level.load_hflevel(path), "the rest of the level loads")
	for e in get_errors().slice(errors_before):
		e.handled = true
	var said := HFLog.get_captured_warnings().filter(func(w): return str(w).contains("left out"))
	HFLog.end_test_capture()
	assert_eq(said.size(), 1, "one brush left out")
	if not said.is_empty():
		assert_string_contains(str(said[0]), "brush box")
		assert_string_contains(str(said[0]), "size is not finite")
	assert_null(level.find_brush_by_id("box"), "that brush is not in the level")
	assert_not_null(level.find_brush_by_id("ramp"), "the others are")
	_free_level(level)


func test_a_merge_conflict_is_refused_as_one_and_the_level_kept():
	var json := _small_level_json()
	var path := _write(_with_conflict(JSON.stringify(json, "\t")))
	var level := _new_level()
	level.create_brush_from_info({"brush_id": "open", "size": Vector3(2, 2, 2)})
	HFLog.begin_test_capture(["unresolved merge"])
	var read: Dictionary = level.file_system.read_hflevel(path)
	HFLog.end_test_capture()
	assert_false(read.get("ok", true))
	assert_string_contains(str(read.get("error", "")), "unresolved merge")
	assert_string_contains(str(read.get("error", "")), "one.hflevel")
	assert_false(level.load_hflevel(path), "and a load refuses it too")
	assert_not_null(level.find_brush_by_id("open"), "the open level is kept")
	_free_level(level)
