@tool
extends RefCounted
## Other words for commands, so the palette finds a command by the word a mapper
## brings with them: "shell" for Hollow, "slice" for Clip (#1695).
##
## The registry gives a command its own (`aliases` in `HFCommandRegistry`). A
## project adds more in `hammerforge_presets/aliases.txt`, one
## `alias = command_id` a line and `#` for a comment. A word names one command: a
## user alias takes its word from the command that had it, and a later line takes
## it from an earlier one.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("hf_command_registry.gd")
const HFLog = preload("hf_log.gd")
@warning_ignore_restore("shadowed_global_identifier")

const USER_FILE := "res://hammerforge_presets/aliases.txt"


## `text` as an alias or a search is compared: lower case, one space between
## words.
static func normal(text: String) -> String:
	return " ".join(text.strip_edges().to_lower().split(" ", false))


## alias -> command id, as the registry gives them.
static func built_in() -> Dictionary:
	var out: Dictionary = {}
	for id in HFCommandRegistry.ids():
		for alias in HFCommandRegistry.aliases(id):
			out[normal(alias)] = id
	return out


## alias -> command id, read from the text of an aliases file. A line that is not
## `alias = command_id`, or that names no command, is left out, and every line
## left out is said in one warning naming `source`.
static func parse(text: String, source: String) -> Dictionary:
	var out: Dictionary = {}
	var bad := PackedStringArray()
	var number := 0
	for line in text.split("\n"):
		number += 1
		var body := line.split("#", true, 1)[0].strip_edges()
		if body.is_empty():
			continue
		var parts := body.split("=", true, 1)
		var alias := normal(parts[0]) if parts.size() == 2 else ""
		var id := parts[1].strip_edges() if parts.size() == 2 else ""
		if alias.is_empty() or id.is_empty():
			bad.append("line %d is not alias = command_id" % number)
		elif not HFCommandRegistry.dispatches(id):
			bad.append('line %d names no command "%s"' % [number, id])
		else:
			out[alias] = id
	if not bad.is_empty():
		HFLog.warn("Command aliases: %s: %s. Left out." % [source, "; ".join(bad)])
	return out


## alias -> command id from the project's file, or none when it has none.
static func read_user(path: String = USER_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse(FileAccess.get_file_as_string(path), path)


## command id -> its aliases, the registry's and `user`'s, with a user alias
## taken from the command the registry gave it to.
static func by_command(user: Dictionary) -> Dictionary:
	var owners := built_in()
	owners.merge(user, true)
	var out: Dictionary = {}
	for alias in owners:
		var id: String = owners[alias]
		if not out.has(id):
			out[id] = []
		(out[id] as Array).append(alias)
	return out
