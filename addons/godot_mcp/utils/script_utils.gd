@tool
class_name ScriptUtils
extends RefCounted

# Create a new GDScript with basic template content
static func create_new_script(class_name_str: String = "", extends_type: String = "Node") -> GDScript:
	var script = GDScript.new()
	var content = ""
	
	if not class_name_str.is_empty():
		content += "class_name " + class_name_str + "\n"
	
	content += "extends " + extends_type + "\n\n"
	content += "func _ready():\n"
	content += "\tpass\n"
	
	script.source_code = content
	return script

# Create a new script file with basic template content
static func create_script_file(path: String, class_name_str: String = "", extends_type: String = "Node") -> bool:
	# Make sure directory exists
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_error("Failed to create directory: " + dir_path)
			return false
	
	var content = ""
	
	if not class_name_str.is_empty():
		content += "class_name " + class_name_str + "\n"
	
	content += "extends " + extends_type + "\n\n"
	content += "func _ready():\n"
	content += "\tpass\n"
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: " + path)
		return false
	
	file.store_string(content)
	file = null  # Close the file
	
	return true

# Parse a script file and extract its class name and base class
static func get_script_info(path: String) -> Dictionary:
	var result = {
		"class_name": "",
		"extends": "",
		"path": path
	}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file for reading: " + path)
		return result
	
	var content = file.get_as_text()
	file = null  # Close the file
	
	# Find class_name
	var class_name_regex = RegEx.new()
	class_name_regex.compile("class_name\\s+([A-Za-z0-9_]+)")
	var matches = class_name_regex.search(content)
	if matches:
		result["class_name"] = matches.get_string(1)
	
	# Find extends
	var extends_regex = RegEx.new()
	extends_regex.compile("extends\\s+([A-Za-z0-9_]+)")
	matches = extends_regex.search(content)
	if matches:
		result["extends"] = matches.get_string(1)
	
	return result

# Extract all method names from a script
static func get_script_methods(path: String) -> Array:
	var methods = []
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file for reading: " + path)
		return methods
	
	var content = file.get_as_text()
	file = null  # Close the file
	
	var method_regex = RegEx.new()
	method_regex.compile("func\\s+([A-Za-z0-9_]+)\\s*\\(")
	
	var matches = method_regex.search_all(content)
	for match_idx in range(matches.size()):
		methods.append(matches[match_idx].get_string(1))
	
	return methods

# Apply a script to a node
static func apply_script_to_node(node: Node, script_path: String) -> bool:
	if not node:
		push_error("Node is null")
		return false
	
	var script = ResourceLoader.load(script_path)
	if not script:
		push_error("Failed to load script: " + script_path)
		return false
	
	node.set_script(script)
	return true

# Use the editor's already-compiled resource. Reloading a stripped copy prints
# false preload/class_name errors into the Output panel.
static func load_compiled_script(script_path: String) -> Dictionary:
	if not script_path.begins_with("res://") or script_path.get_extension() != "gd":
		return {"ok": false, "error": ERR_INVALID_PARAMETER, "script": null}
	if not ResourceLoader.exists(script_path):
		return {"ok": false, "error": ERR_FILE_NOT_FOUND, "script": null}
	var loaded: Resource = ResourceLoader.load(script_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if loaded is GDScript:
		return {"ok": true, "error": OK, "script": loaded}
	return {"ok": false, "error": ERR_INVALID_DATA, "script": null}

# Rewrite relative preload()/load()/extends "..." against the real script dir so
# anonymous GDScript.reload() does not resolve them as gdscript://.
static func rewrite_relative_resource_paths(source: String, script_path: String) -> String:
	if source.is_empty() or not script_path.begins_with("res://"):
		return source
	var base_dir: String = script_path.get_base_dir()
	var rewritten: String = _rewrite_quoted_calls(source, base_dir, "\\b(preload|load)\\(\\s*([\"'])([^\"']+)\\2\\s*\\)", true)
	rewritten = _rewrite_quoted_calls(rewritten, base_dir, "(extends)\\s+([\"'])([^\"']+)\\2", false)
	return rewritten

static func _rewrite_quoted_calls(source: String, base_dir: String, pattern: String, wrap_parens: bool) -> String:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return source
	var matches: Array[RegExMatch] = regex.search_all(source)
	var result: String = source
	for i in range(matches.size() - 1, -1, -1):
		var match: RegExMatch = matches[i]
		var inner: String = match.get_string(3)
		if inner.begins_with("res://") or inner.begins_with("user://") or inner.begins_with("/"):
			continue
		var abs_path: String = base_dir.path_join(inner).simplify_path()
		if not abs_path.begins_with("res://"):
			abs_path = "res://" + abs_path.lstrip("/")
		var quote: String = match.get_string(2)
		var replacement: String
		if wrap_parens:
			replacement = match.get_string(1) + "(" + quote + abs_path + quote + ")"
		else:
			replacement = match.get_string(1) + " " + quote + abs_path + quote
		result = result.substr(0, match.get_start()) + replacement + result.substr(match.get_end())
	return result

# Compile unsaved source without attaching a fake res:// path. Mute parser
# prints; callers should prefer load_compiled_script() for on-disk files.
static func reload_source_quietly(source: String, script_path: String = "") -> Dictionary:
	var test_script := GDScript.new()
	test_script.source_code = rewrite_relative_resource_paths(source, script_path)
	var previous_print: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	var reload_err: Error = test_script.reload()
	Engine.print_error_messages = previous_print
	return {
		"error": reload_err,
		"script": test_script,
	}