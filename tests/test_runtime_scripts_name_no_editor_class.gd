extends GutTest

## No script a level can load names an editor class (#1175).
##
## An export has no editor classes, and GDScript resolves a name as it parses, so a
## script that names `EditorInterface` does not load in a game wherever the name
## sits: behind `Engine.is_editor_hint()`, or in a function nothing calls. The
## editor and these tests run on an editor binary, where the name resolves, so
## nothing else here would see it. `Engine.get_singleton(&"EditorInterface")` is
## the way to reach one.
##
## The scripts are the ones reachable from what a shipped scene carries: by
## `preload()`, by `load()` of a literal path, and by global class name. Following
## every `load()` takes in the systems LevelRoot builds only in the editor as well,
## so they stay loadable if one of them moves into the game.

const ADDON := "res://addons/hammerforge"
const ROOTS := [
	"res://addons/hammerforge/level_root.gd",
	"res://addons/hammerforge/brush_instance.gd",
	"res://addons/hammerforge/draft_entity.gd",
	"res://addons/hammerforge/hf_io_runtime.gd",
	"res://addons/hammerforge/hf_door_runtime.gd",
	"res://addons/hammerforge/playtest_fps.gd",
]

var _strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
var _identifiers := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")
var _loads := RegEx.create_from_string('(?:preload|load)\\(\\s*"([^"]+\\.gd)"')
var _class_name := RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
var _editor_class := RegEx.create_from_string("^Editor[A-Z]")


func test_no_script_a_level_can_load_names_an_editor_class():
	var reached := _reached_from(ROOTS)
	assert_true(reached.has(ADDON + "/systems/hf_io_presets.gd"), "the walk follows load() as well")
	var named: Array = []
	for path in reached:
		var editor_names := _editor_names(_code(reached[path]))
		if not editor_names.is_empty():
			named.append("%s: %s" % [path, ", ".join(editor_names)])
	assert_eq(named, [], "an export cannot parse these")


func test_a_name_in_code_counts_and_one_in_a_string_or_a_comment_does_not():
	assert_eq(_editor_names(_code("var e = EditorInterface.get_selection()")), ["EditorInterface"])
	assert_eq(
		_editor_names(_code('var e = Engine.get_singleton(&"EditorInterface")  # EditorInterface')),
		[]
	)


## Every script under the addon, by path, as written.
func _sources() -> Dictionary:
	var out: Dictionary = {}
	var dirs: Array = [ADDON]
	while not dirs.is_empty():
		var dir_path: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			dirs.append(dir_path.path_join(sub))
		for file in DirAccess.get_files_at(dir_path):
			if file.get_extension() == "gd":
				var path := dir_path.path_join(file)
				out[path] = FileAccess.get_file_as_string(path)
	return out


func _reached_from(roots: Array) -> Dictionary:
	var sources := _sources()
	var classes: Dictionary = {}
	for path in sources:
		var found := _class_name.search(sources[path])
		if found:
			classes[found.get_string(1)] = path
	var reached: Dictionary = {}
	var queue: Array = roots.duplicate()
	while not queue.is_empty():
		var path: String = queue.pop_back()
		if reached.has(path) or not sources.has(path):
			continue
		reached[path] = sources[path]
		for found in _loads.search_all(sources[path]):
			var target := found.get_string(1)
			if not target.begins_with("res://"):
				target = path.get_base_dir().path_join(target).simplify_path()
			queue.append(target)
		for name in _names(_code(sources[path])):
			if classes.has(name):
				queue.append(classes[name])
	return reached


## The source with its strings and comments taken out.
func _code(source: String) -> String:
	var lines: PackedStringArray = []
	for line in source.split("\n"):
		var bare := _strings.sub(line, '""', true)
		var hash_at := bare.find("#")
		lines.append(bare if hash_at < 0 else bare.substr(0, hash_at))
	return "\n".join(lines)


func _names(code: String) -> Dictionary:
	var out: Dictionary = {}
	for found in _identifiers.search_all(code):
		out[found.get_string()] = true
	return out


func _editor_names(code: String) -> Array:
	var out: Array = []
	for name in _names(code):
		if _editor_class.search(name):
			out.append(name)
	out.sort()
	return out
