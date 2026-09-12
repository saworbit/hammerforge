@tool
class_name HFUserPrefs
extends RefCounted

## Application-scoped user preferences for HammerForge.
##
## Persists across sessions via user://hammerforge_prefs.json.
## Stores UI layout state, defaults, and recent file paths.
## Separate from per-level settings (which live in LevelRoot / hf_state_system).

const PREFS_PATH := "user://hammerforge_prefs.json"

var data: Dictionary = {}
## Tests and temporary previews can disable disk writes without changing runtime behavior.
var persistence_enabled := true


static func load_prefs() -> HFUserPrefs:
	var prefs = HFUserPrefs.new()
	if FileAccess.file_exists(PREFS_PATH):
		var file = FileAccess.open(PREFS_PATH, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			file.close()
			# The instance parser rather than `JSON.parse_string()`, because it
			# reports why the file would not read instead of pushing an engine
			# error and returning null.
			var parser := JSON.new()
			var parse_err := parser.parse(text)
			if parse_err == OK and parser.data is Dictionary:
				prefs.data = _validated(parser.data)
				return prefs
			# The file is there and cannot be read. It used to be replaced by the
			# defaults in silence and overwritten by the next save, so the user
			# lost their grid size, recent files, collapsed sections and dismissed
			# hints and was told nothing. Keep it and say so.
			var reason := (
				parser.get_error_message() if parse_err != OK else "it is not a set of values"
			)
			_move_aside(PREFS_PATH, reason)
	prefs.data = _defaults()
	return prefs


## The unreadable file, kept beside the one that replaces it.
static func _move_aside(path: String, reason: String) -> void:
	var kept := path + ".unreadable"
	var abs_path := ProjectSettings.globalize_path(path)
	var abs_kept := ProjectSettings.globalize_path(kept)
	if FileAccess.file_exists(kept):
		DirAccess.remove_absolute(abs_kept)
	if DirAccess.rename_absolute(abs_path, abs_kept) == OK:
		HFLog.warn(
			(
				"%s could not be read (%s). It is kept as %s and the defaults are in use."
				% [path, reason, kept]
			)
		)
	else:
		HFLog.warn("%s could not be read (%s). The defaults are in use." % [path, reason])


## What each preference has to be to be usable, and what a number has to be
## within. Every one of these has an accessor that reads it into a typed local,
## so a value of the wrong type is not a wrong preference, it is an error on
## every call that touches it: one bad `collapsed_sections` broke every section
## read, and `add_recent_file()` aborted before its write so the path was
## dropped in silence.
const SCHEMA := {
	"grid_snap": {"type": TYPE_FLOAT, "min": 0.001},
	"autosave_interval": {"type": TYPE_INT, "min": 0},
	"recent_files": {"type": TYPE_ARRAY},
	"collapsed_sections": {"type": TYPE_DICTIONARY},
	"last_tool_id": {"type": TYPE_INT},
	"show_hud": {"type": TYPE_BOOL},
	"show_welcome": {"type": TYPE_BOOL},
	"power_user_overlays": {"type": TYPE_BOOL},
	"hints_dismissed": {"type": TYPE_DICTIONARY},
}


## The loaded preferences with anything unusable dropped, reported once naming
## the file and the key. `HFKeymap._validated()` does this for the keymap, for
## the same reason.
static func _validated(loaded: Dictionary) -> Dictionary:
	var out := _defaults()
	for key in loaded:
		var pref_name := str(key)
		var value = loaded[key]
		if not SCHEMA.has(pref_name):
			# Not ours to judge: a key from a newer version, or one a user added.
			out[pref_name] = value
			continue
		out[pref_name] = _usable(pref_name, value, out[pref_name])
	return out


## One value, held to the schema or replaced by the fallback.
static func _usable(pref_name: String, value: Variant, fallback: Variant) -> Variant:
	var rule: Dictionary = SCHEMA[pref_name]
	var wanted: int = rule["type"]
	# JSON has one number type, so an int preference comes back as a float and a
	# float one can come back as an int. Neither is the user getting it wrong.
	if wanted == TYPE_FLOAT and value is int:
		value = float(value)
	elif wanted == TYPE_INT and value is float and value == floor(value):
		value = int(value)
	if typeof(value) != wanted:
		HFLog.warn(
			(
				"%s: '%s' is a %s, not a %s. The default is used."
				% [PREFS_PATH, pref_name, type_string(typeof(value)), type_string(wanted)]
			)
		)
		return fallback
	if rule.has("min") and value < rule["min"]:
		HFLog.warn(
			(
				"%s: '%s' is %s, below the smallest usable value %s."
				% [PREFS_PATH, pref_name, str(value), str(rule["min"])]
			)
		)
		return rule["min"]
	return value


static func _defaults() -> Dictionary:
	return {
		"grid_snap": 16.0,
		"autosave_interval": 300,
		"recent_files": [],
		"collapsed_sections": {},
		"last_tool_id": 0,
		"show_hud": true,
		"show_welcome": true,
		"power_user_overlays": false,
		"hints_dismissed": {},
	}


## Save preferences to disk.
##
## Written beside the destination and moved into place, so an editor that goes
## down mid-write leaves the old preferences rather than half of the new ones.
## `FileAccess.WRITE` truncates first, which is how the file got into a state
## that would not parse.
func save() -> void:
	if not persistence_enabled:
		return
	var payload := JSON.stringify(data, "\t").to_utf8_buffer()
	var err := HFLevelIO.write_bytes_atomic(PREFS_PATH, payload)
	if err != OK:
		HFLog.warn("%s could not be written (error %d). Preferences not saved." % [PREFS_PATH, err])


## Get a preference value with fallback to built-in default.
func get_pref(key: String, fallback: Variant = null) -> Variant:
	if data.has(key):
		return data[key]
	var defs := _defaults()
	if defs.has(key):
		return defs[key]
	return fallback


## Set a preference value. A value the schema knows is held to it here too, so a
## caller cannot write an autosave interval of -1 or a grid snap of 0 to disk.
func set_pref(key: String, value: Variant) -> void:
	if SCHEMA.has(key):
		data[key] = _usable(key, value, get_pref(key))
		return
	data[key] = value


## Record a section's collapsed state (true = collapsed, false = expanded).
func set_section_collapsed(section_name: String, collapsed: bool) -> void:
	var sections: Dictionary = data.get("collapsed_sections", {})
	sections[section_name] = collapsed
	data["collapsed_sections"] = sections


## Get a section's collapsed state. Returns null if not stored.
func get_section_collapsed(section_name: String) -> Variant:
	var sections: Dictionary = data.get("collapsed_sections", {})
	return sections.get(section_name)


## Add a file path to the recent files list (max 10, most recent first).
func add_recent_file(path: String) -> void:
	var recent: Array = data.get("recent_files", [])
	recent.erase(path)
	recent.push_front(path)
	if recent.size() > 10:
		recent.resize(10)
	data["recent_files"] = recent


## Get the recent files list.
func get_recent_files() -> Array:
	return data.get("recent_files", [])


## Radial menu, coach marks, and operation replay. Off for the core loop.
func is_power_user_overlays_enabled() -> bool:
	return bool(get_pref("power_user_overlays", false))


## Check if a contextual hint has been dismissed.
func is_hint_dismissed(hint_key: String) -> bool:
	var dismissed: Dictionary = data.get("hints_dismissed", {})
	return dismissed.get(hint_key, false)


## Mark a contextual hint as dismissed and persist.
func dismiss_hint(hint_key: String) -> void:
	var dismissed: Dictionary = data.get("hints_dismissed", {})
	dismissed[hint_key] = true
	data["hints_dismissed"] = dismissed
	save()
