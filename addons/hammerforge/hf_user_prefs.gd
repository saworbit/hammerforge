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


static func load_prefs() -> HFUserPrefs:
	var prefs = HFUserPrefs.new()
	if FileAccess.file_exists(PREFS_PATH):
		var file = FileAccess.open(PREFS_PATH, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				prefs.data = parsed
				return prefs
	prefs.data = _defaults()
	return prefs


static func _defaults() -> Dictionary:
	return {
		"grid_snap": 16.0,
		"autosave_interval": 300,
		"recent_files": [],
		"collapsed_sections": {},
		"last_tool_id": 0,
		"show_hud": true,
	}


## Save preferences to disk.
func save() -> void:
	var file = FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


## Get a preference value with fallback to built-in default.
func get_pref(key: String, fallback: Variant = null) -> Variant:
	if data.has(key):
		return data[key]
	var defs := _defaults()
	if defs.has(key):
		return defs[key]
	return fallback


## Set a preference value.
func set_pref(key: String, value: Variant) -> void:
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
