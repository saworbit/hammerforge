extends GutTest

## A test that needs a level uses the real LevelRoot (#922).
##
## The suite used to build some sixty hand-written stand-ins for LevelRoot, and
## they had drifted from the class they stood in for: grid_snap 0.0 or 8.0 where
## a level starts at 0.5, texture_lock off where it is on, an entity check reading
## a meta nothing sets, a fake brush manager copied line for line, and one file
## testing its own copy of the dirty tags. Each agreed with its own tests and not
## with the level, and production code was bent to suit them.
##
## Two rules keep that from coming back:
##
## - No test declares the level's brush containers as members, in its own script,
##   an inner class, or a script it builds from source. Those belong to a
##   LevelRoot, so a script that has them is a stand-in. Use the real class, or a
##   class that extends it and overrides only what the test has to intercept.
## - A script a test builds from source, a spy or a fake, starts every value it
##   shares with LevelRoot where LevelRoot starts it. A test that needs another
##   value sets it, where the reader can see it.
##
## A deliberate exception says why on a line containing `hf-allow-level-stand-in:`
## inside the script, or in the three lines above the declaration.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")

const CONTAINERS := ["draft_brushes_node", "pending_node", "committed_node", "entities_node"]
const ALLOW := "hf-allow-level-stand-in:"
const SELF := "test_level_root_shims.gd"


func _test_sources() -> Dictionary:
	var out := {}
	for file_name in DirAccess.get_files_at("res://tests"):
		if file_name.begins_with("test_") and file_name.ends_with(".gd") and file_name != SELF:
			out[file_name] = FileAccess.get_file_as_string("res://tests/" + file_name)
	return out


## Each `"""..."""` block in a test file: [first line number, raw text].
func _string_blocks(text: String) -> Array:
	var out: Array = []
	var at := 0
	while true:
		var open := text.find('"""', at)
		if open < 0:
			break
		var close := text.find('"""', open + 3)
		if close < 0:
			break
		out.append([text.substr(0, open).count("\n") + 1, text.substr(open + 3, close - open - 3)])
		at = close + 3
	return out


## The text of a script built from source, as the engine will read it.
func _unescape(raw: String) -> String:
	return raw.replace('\\"', '"').replace("\\\\", "\\")


func _declares_container(line: String) -> bool:
	var stripped := line.strip_edges()
	for name in CONTAINERS:
		if stripped.begins_with("var %s" % name):
			var rest := stripped.substr(("var %s" % name).length())
			if rest == "" or rest[0] in [":", " ", "="]:
				return true
	return false


## Container members declared in `text`, as "line N" strings. Function locals do
## not count, and the bodies of scripts built from source are read on their own.
func _container_members(text: String) -> Array:
	var lines := text.split("\n")
	# Blank the string blocks out, keeping the line count, so a script built
	# from source cannot be mistaken for this file's own members.
	var in_string := false
	for i in lines.size():
		var quotes := lines[i].count('"""')
		var was_in_string := in_string
		if quotes % 2 == 1:
			in_string = not in_string
		if was_in_string or quotes > 0:
			lines[i] = ""
	var found: Array = []
	var func_indent := -1
	for i in lines.size():
		var line: String = lines[i]
		var stripped := line.strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			continue
		var indent := line.length() - line.lstrip("\t").length()
		if func_indent >= 0 and indent <= func_indent:
			func_indent = -1
		if stripped.begins_with("func ") or stripped.begins_with("static func "):
			func_indent = indent
			continue
		if func_indent >= 0:
			continue
		if _declares_container(line) and not _allowed_above(text.split("\n"), i):
			found.append("line %d" % (i + 1))
	return found


func _allowed_above(lines: PackedStringArray, index: int) -> bool:
	for j in range(maxi(0, index - 3), index + 1):
		if lines[j].contains(ALLOW):
			return true
	return false


## Scripts built from source in `text` that declare a container.
func _stand_in_sources(text: String) -> Array:
	var found: Array = []
	for block in _string_blocks(text):
		var source := _unescape(block[1])
		if not source.strip_edges().begins_with("extends") or source.contains(ALLOW):
			continue
		for line in source.split("\n"):
			if _declares_container(line):
				found.append("script at line %d" % block[0])
				break
	return found


## Values a script built from source starts somewhere LevelRoot does not.
func _drifted_values(text: String, level: Object) -> Array:
	var level_values := {}
	for prop in level.get_property_list():
		level_values[str(prop["name"])] = true
	var found: Array = []
	for block in _string_blocks(text):
		var source := _unescape(block[1])
		if not source.strip_edges().begins_with("extends") or source.contains(ALLOW):
			continue
		# A template filled in with % is not a script until it is formatted.
		if source.contains("%s") or source.contains("%d"):
			continue
		var script := GDScript.new()
		script.source_code = source
		if script.reload() != OK:
			continue
		var instance: Object = script.new()
		for prop in script.get_script_property_list():
			var name := str(prop["name"])
			if not level_values.has(name):
				continue
			var mine: Variant = instance.get(name)
			var theirs: Variant = level.get(name)
			if typeof(mine) == TYPE_OBJECT or typeof(theirs) == TYPE_OBJECT:
				continue
			if typeof(theirs) == TYPE_NIL:
				continue
			if typeof(mine) != typeof(theirs) or mine != theirs:
				found.append(
					(
						"script at line %d: %s starts at %s, LevelRoot at %s"
						% [block[0], name, mine, theirs]
					)
				)
		if instance is Node:
			instance.free()
	return found


func test_no_test_builds_its_own_level():
	var offenders: Array = []
	for file_name in _test_sources():
		var text: String = _test_sources()[file_name]
		for where in _container_members(text) + _stand_in_sources(text):
			offenders.append("%s %s" % [file_name, where])
	assert_eq(
		offenders,
		[],
		"These declare a LevelRoot's brush containers themselves. Use the real class (#922)."
	)


func test_scripts_built_in_tests_start_where_the_level_starts():
	var level: Node = LevelRootScript.new()
	var offenders: Array = []
	var sources := _test_sources()
	for file_name in sources:
		for where in _drifted_values(sources[file_name], level):
			offenders.append("%s %s" % [file_name, where])
	level.free()
	assert_eq(offenders, [], "Set a value a test needs in the test, not as a default (#922).")


# ---------------------------------------------------------------------------
# The guard still catches what it is for
# ---------------------------------------------------------------------------

const _STAND_IN := '''extends GutTest


class FakeRoot:
	extends Node3D
	var draft_brushes_node := Node3D.new()


func test_something():
	var entities_node := Node3D.new()
	entities_node.free()
'''

const _ALLOWED := '''extends GutTest


class FakeRoot:
	extends Node3D
	# hf-allow-level-stand-in: a reason
	var draft_brushes_node := Node3D.new()
'''


func test_the_guard_finds_a_stand_in_and_not_a_local():
	assert_eq(_container_members(_STAND_IN), ["line 6"], "the member, not the local below it")
	assert_eq(_container_members(_ALLOWED), [], "an allowed stand-in says why and passes")


func test_the_guard_reads_scripts_built_from_source():
	var text := 'func _shim():\n\tvar s := GDScript.new()\n\ts.source_code = """\nextends Node3D\nvar pending_node: Node3D\nvar grid_snap := 0.0\n"""\n'
	assert_eq(_stand_in_sources(text), ["script at line 3"])
	assert_eq(_container_members(text), [], "its lines are not the file's own members")
	var level: Node = LevelRootScript.new()
	var drifted := _drifted_values(text, level)
	level.free()
	assert_eq(drifted.size(), 1, "grid_snap starts at 0.0 where a level starts at 0.5")
	if drifted.size() == 1:
		assert_string_contains(drifted[0], "grid_snap")
