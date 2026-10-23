extends GutTest

## Every shrunk chaos case in `tests/regressions/` replays from a fresh level
## with nothing broken (#1644). A case whose bug is still open carries
## `"known": "#N: reason"` and is pending until it passes, when it fails and asks
## for the entry to come off.

const ChaosScenario = preload("res://tools/vibe/scenarios/chaos.gd")
const ChaosShrink = preload("res://tools/vibe/chaos_shrink.gd")
const KnownFailures = preload("res://tests/support/known_failures.gd")


static func cases(folder: String = ChaosShrink.REGRESSIONS_DIR) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file_name in DirAccess.get_files_at(dir):
		if file_name.get_extension() == "json":
			out.append(folder.path_join(file_name))
	out.sort()
	return out


## What replaying one case finds wrong, or [] when nothing broke.
func replay_case(path: String) -> Array:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return ["%s does not read as a case" % path]
	var scenario = ChaosScenario.new(get_tree())
	var found: Dictionary = await scenario.replay(json.data.get("steps", []))
	if found.is_empty():
		return []
	return ["step %d after '%s': %s" % [found["step"], found["op"], found["problem"]]]


func test_every_recorded_case_replays_with_nothing_broken():
	var paths := cases()
	if paths.is_empty():
		pass_test("no cases recorded in tests/regressions yet")
		return
	for path in paths:
		var json := JSON.new()
		json.parse(FileAccess.get_file_as_string(path))
		var data: Dictionary = json.data if json.data is Dictionary else {}
		var known := {}
		if data.get("known") is String:
			known[path] = data["known"]
			KnownFailures.check_shape(self, known)
		KnownFailures.settle(self, known, path, path.get_file(), await replay_case(path))
