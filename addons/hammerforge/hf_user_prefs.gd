@tool
class_name HFUserPrefs
extends RefCounted

## Application-scoped user preferences for HammerForge.
##
## Persists across sessions via user://hammerforge_prefs.json.
## Stores UI layout state, defaults, and recent file paths.
## Separate from per-level settings (which live in LevelRoot / hf_state_system).

const HFOverlayColors = preload("hf_overlay_colors.gd")

const PREFS_PATH := "user://hammerforge_prefs.json"
## Where the preferences are read and written: `PREFS_PATH`, unless something
## points them elsewhere first. The editor never does. A test run does, before its
## first test (`tests/support/gut_pre_run.gd`), and so does the prefs vibe
## scenario, because every checkout and the editor share one `user://`, and a test
## that wrote this file wrote the preferences of whoever ran it (#1581).
static var prefs_path: String = PREFS_PATH
## How many materials the browser's Recent row keeps (#1422).
const RECENT_MATERIALS_MAX := 8
## Where the last settings each tool was used with are kept between sessions
## (#1406): an external tool's schema settings under its name, the Build tab's
## own controls, and the Structure section's type and each type's fields.
const TOOL_SETTINGS := "tool_settings"
const BUILD_SETTINGS := "build_settings"
const STRUCTURE_SETTINGS := "structure_settings"

## Sent once Reset Tool Settings has let go of every kept setting, so whatever
## holds a live copy of one (the tools, through `HFToolRegistry`) goes back to
## its default too.
signal tool_settings_reset

var data: Dictionary = {}
## Tests and temporary previews can disable disk writes without changing runtime behavior.
var persistence_enabled := true


static func load_prefs() -> HFUserPrefs:
	var prefs = HFUserPrefs.new()
	if FileAccess.file_exists(prefs_path):
		var file = FileAccess.open(prefs_path, FileAccess.READ)
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
			_move_aside(prefs_path, reason)
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
	"recent_files": {"type": TYPE_ARRAY},
	"collapsed_sections": {"type": TYPE_DICTIONARY},
	"show_hud": {"type": TYPE_BOOL},
	"show_welcome": {"type": TYPE_BOOL},
	"power_user_overlays": {"type": TYPE_BOOL},
	"size_at_cursor": {"type": TYPE_BOOL},
	"draw_hover_preview": {"type": TYPE_BOOL},
	"material_thumb_size": {"type": TYPE_INT, "min": 48, "max": 192},
	"snap_labels": {"type": TYPE_BOOL},
	"similar_brush_keys": {"type": TYPE_ARRAY},
	"similar_face_keys": {"type": TYPE_ARRAY},
	"similar_entity_keys": {"type": TYPE_ARRAY},
	"similar_property": {"type": TYPE_STRING},
	"show_selection_size": {"type": TYPE_BOOL},
	"ui_motion": {"type": TYPE_INT, "min": 0, "max": 2},
	"compare_fade": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0},
	"io_wire_mode": {"type": TYPE_INT, "min": 0, "max": 2},
	"nudge_follows_view": {"type": TYPE_BOOL},
	"show_agent_changes": {"type": TYPE_BOOL},
	"duplicate_keeps_prefab_link": {"type": TYPE_BOOL},
	"check_for_updates": {"type": TYPE_BOOL},
	"update_last_checked": {"type": TYPE_FLOAT, "min": 0.0},
	"update_skip_version": {"type": TYPE_STRING},
	"update_later_until": {"type": TYPE_FLOAT, "min": 0.0},
	"note_author": {"type": TYPE_STRING},
	"hints_dismissed": {"type": TYPE_DICTIONARY},
	"command_presets": {"type": TYPE_DICTIONARY},
	"favorite_materials": {"type": TYPE_ARRAY},
	"recent_materials": {"type": TYPE_ARRAY},
	"bake_profiles": {"type": TYPE_DICTIONARY},
	"uv_scale_linked": {"type": TYPE_BOOL},
	"uv_snap_enabled": {"type": TYPE_BOOL},
	"uv_snap_step": {"type": TYPE_FLOAT, "min": 0.001},
	TOOL_SETTINGS: {"type": TYPE_DICTIONARY},
	BUILD_SETTINGS: {"type": TYPE_DICTIONARY},
	STRUCTURE_SETTINGS: {"type": TYPE_DICTIONARY},
	# The overlay colours (`HFOverlayColors`), each a hex string with its alpha.
	HFOverlayColors.SELECTED_BRUSH: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.SELECTED_FACE: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.HOVER: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.VERTEX_HANDLE: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.SELECTED_VERTEX: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.ADDITIVE_BRUSH: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.SUBTRACTIVE_BRUSH: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.WIREFRAME: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.EXTRUDE_UP: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.EXTRUDE_DOWN: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.DRAW_PREVIEW: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.PENDING_CUT: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.FUNC_DETAIL: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.TRIGGER: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.FUNC_WALL: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.FUNC_CLIP: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.BRUSH_ENTITY: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.AGENT_CHANGE: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.COMPARE_ADDED: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.COMPARE_CHANGED: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.COMPARE_REMOVED: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.FACE_FRONT: {"type": TYPE_STRING, "color": true},
	HFOverlayColors.FACE_BACK: {"type": TYPE_STRING, "color": true},
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
	return held_to(pref_name, SCHEMA[pref_name], value, fallback)


## One value held to `rule`, `{"type", "min", "max"}` with the type a `TYPE_*`
## and either end optional. A value of another type gives `fallback`, and one
## past an end is held to that end, each with a warning naming this file and
## `where`, the key it was read from. Public because a kept tool setting is
## described by the tool, or by the structure, so the rule is theirs and only the
## holding is this file's (#1406).
static func held_to(where: String, rule: Dictionary, value: Variant, fallback: Variant) -> Variant:
	var wanted: int = rule["type"]
	# JSON has one number type, so an int preference comes back as a float and a
	# float one can come back as an int. Neither is the user getting it wrong.
	if wanted == TYPE_FLOAT and value is int:
		value = float(value)
	elif wanted == TYPE_INT and value is float and value == floor(value):
		value = int(value)
	# A colour set from a picker arrives as a Color, and is kept as the string.
	if rule.get("color", false) and value is Color:
		value = HFOverlayColors.to_pref(value)
	if typeof(value) != wanted:
		HFLog.warn(
			(
				"%s: '%s' is a %s, not a %s. The default is used."
				% [prefs_path, where, type_string(typeof(value)), type_string(wanted)]
			)
		)
		return fallback
	if rule.has("min") and value < rule["min"]:
		HFLog.warn(
			(
				"%s: '%s' is %s, below the smallest usable value %s."
				% [prefs_path, where, str(value), str(rule["min"])]
			)
		)
		return int(rule["min"]) if wanted == TYPE_INT else rule["min"]
	if rule.has("max") and value > rule["max"]:
		HFLog.warn(
			(
				"%s: '%s' is %s, above the largest usable value %s."
				% [prefs_path, where, str(value), str(rule["max"])]
			)
		)
		return int(rule["max"]) if wanted == TYPE_INT else rule["max"]
	if rule.get("color", false) and not Color.html_is_valid(value):
		HFLog.warn(
			(
				"%s: '%s' is \"%s\", which is not a colour. The default is used."
				% [prefs_path, where, value]
			)
		)
		return fallback
	return value


static func _defaults() -> Dictionary:
	var defaults := {
		"grid_snap": 0.5,
		"recent_files": [],
		"collapsed_sections": {},
		"show_hud": true,
		"show_welcome": true,
		"power_user_overlays": false,
		"size_at_cursor": true,
		"draw_hover_preview": true,
		"material_thumb_size": 64,
		"snap_labels": true,
		# What Select Similar matches on, as `HFSimilar.DEFAULTS` has it (#1698).
		"similar_brush_keys": ["size"],
		"similar_face_keys": ["material", "normal"],
		"similar_entity_keys": ["class"],
		"similar_property": "",
		"show_selection_size": false,
		# How the interface moves (#1703): follow the system, animate, or reduce.
		"ui_motion": 0,
		# How far a compare fades the brushes that did not change (#1864).
		"compare_fade": 0.7,
		"io_wire_mode": 0,
		"nudge_follows_view": true,
		"show_agent_changes": true,
		"duplicate_keeps_prefab_link": false,
		"check_for_updates": true,
		"update_last_checked": 0.0,
		"update_skip_version": "",
		"update_later_until": 0.0,
		"note_author": "",
		"hints_dismissed": {},
		# Settings saved by name in Adjust Last, by command id (#1867).
		"command_presets": {},
		"favorite_materials": [],
		"recent_materials": [],
		"bake_profiles": {},
		"uv_scale_linked": false,
		"uv_snap_enabled": true,
		"uv_snap_step": 0.125,
		TOOL_SETTINGS: {},
		BUILD_SETTINGS: {},
		STRUCTURE_SETTINGS: {},
	}
	for key in HFOverlayColors.DEFAULTS:
		defaults[key] = HFOverlayColors.to_pref(HFOverlayColors.DEFAULTS[key])
	return defaults


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
	var err := HFLevelIO.write_bytes_atomic(prefs_path, payload)
	if err != OK:
		HFLog.warn("%s could not be written (error %d). Preferences not saved." % [prefs_path, err])


## Get a preference value with fallback to built-in default.
func get_pref(key: String, fallback: Variant = null) -> Variant:
	if data.has(key):
		return data[key]
	var defs := _defaults()
	if defs.has(key):
		return defs[key]
	return fallback


## Set a preference value. A value the schema knows is held to it here too, so a
## caller cannot write a grid snap of 0, or a list where a switch belongs, to disk.
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


## The material palette's starred resource paths.
##
## Kept here rather than on the browser because a star only earns its keep across
## sessions: the browser is built fresh by the dock, so every star was gone at the
## next theme change, project reload or editor restart, with the Favorites view
## and the HUD's favourites row coming up empty and nothing to say why.
##
## Paths rather than palette indices, because an index is only stable while the
## palette is and this outlives the level.
func get_favorite_materials() -> Array:
	var stored = get_pref("favorite_materials", [])
	return stored if stored is Array else []


func set_favorite_materials(paths: Array) -> void:
	set_pref("favorite_materials", paths.duplicate())
	save()


## The resource paths of the materials last applied to faces or brushes, newest
## first, for the browser's Recent row (#1422). Kept beside the favourites for the
## same reason: a level is reopened, the browser is not.
func get_recent_materials() -> Array:
	var stored = get_pref("recent_materials", [])
	return stored if stored is Array else []


## Put `path` first in the recent materials, once, and drop the oldest past
## `RECENT_MATERIALS_MAX`. False when nothing changed, which is every repeat of
## the material already first, so a run of paint clicks does not rewrite the file
## each time. A material with no path cannot be found again and is left out.
func add_recent_material(path: String) -> bool:
	if path == "":
		return false
	var recent: Array = get_recent_materials().duplicate()
	if not recent.is_empty() and str(recent[0]) == path:
		return false
	recent.erase(path)
	recent.push_front(path)
	if recent.size() > RECENT_MATERIALS_MAX:
		recent.resize(RECENT_MATERIALS_MAX)
	set_pref("recent_materials", recent)
	save()
	return true


## Bake profiles saved under a name, each the bake options it sets
## (`HFBakeProfiles`). Here rather than in the level, because a profile is a way of
## baking that outlives any one level. What each holds is checked against a level
## when it is read, by `HFBakeProfiles.read_saved()`.
func get_bake_profiles() -> Dictionary:
	var stored = get_pref("bake_profiles", {})
	return stored if stored is Dictionary else {}


func set_bake_profile(profile_name: String, values: Dictionary) -> void:
	var profiles := get_bake_profiles().duplicate()
	profiles[profile_name] = values.duplicate()
	set_pref("bake_profiles", profiles)
	save()


func remove_bake_profile(profile_name: String) -> void:
	var profiles := get_bake_profiles().duplicate()
	if profiles.erase(profile_name):
		set_pref("bake_profiles", profiles)
		save()


## The settings kept for the tool called `tool_key`, as they were written: what
## each has to be is the tool's to say, so `HFToolRegistry` holds them to its
## schema as it puts them back. A copy.
func get_tool_settings(tool_key: String) -> Dictionary:
	var stored = _kept(TOOL_SETTINGS).get(tool_key, {})
	return (stored as Dictionary).duplicate() if stored is Dictionary else {}


## Keep one of a tool's settings for the next session, and write the file when
## it changed.
func set_tool_setting(tool_key: String, key: String, value: Variant) -> void:
	var tools := _kept(TOOL_SETTINGS).duplicate()
	var stored = tools.get(tool_key, {})
	var settings: Dictionary = (stored as Dictionary).duplicate() if stored is Dictionary else {}
	if settings.has(key) and _same(settings[key], value):
		return
	settings[key] = value
	tools[tool_key] = settings
	data[TOOL_SETTINGS] = tools
	save()


## The Build tab's kept controls, as they were written. `HFDockToolMemory` holds
## each to its control's range as it puts it back. A copy.
func get_build_settings() -> Dictionary:
	return _kept(BUILD_SETTINGS).duplicate()


## Keep these Build tab settings, by key, and write the file once if any changed.
func set_build_settings(values: Dictionary) -> void:
	var build := _kept(BUILD_SETTINGS).duplicate()
	var changed := false
	for key in values:
		if build.has(key) and _same(build[key], values[key]):
			continue
		build[key] = values[key]
		changed = true
	if not changed:
		return
	data[BUILD_SETTINGS] = build
	save()


## The Structure section's kept type and, under `fields`, each type's own
## settings by type name, as they were written. A copy.
func get_structure_settings() -> Dictionary:
	return _kept(STRUCTURE_SETTINGS).duplicate(true)


func set_structure_type(type: String) -> void:
	var structure := _kept(STRUCTURE_SETTINGS).duplicate(true)
	if _same(structure.get("type", null), type):
		return
	structure["type"] = type
	data[STRUCTURE_SETTINGS] = structure
	save()


## Keep one structure type's settings. Each type has its own, so a look at the
## stairs does not cost the arch it was tuned to.
func set_structure_fields(type: String, fields: Dictionary) -> void:
	var structure := _kept(STRUCTURE_SETTINGS).duplicate(true)
	var by_type = structure.get("fields", {})
	if not (by_type is Dictionary):
		by_type = {}
	if by_type.has(type) and _same(by_type[type], fields):
		return
	by_type[type] = fields.duplicate()
	structure["fields"] = by_type
	data[STRUCTURE_SETTINGS] = structure
	save()


## Let go of every kept tool setting, so each tool, the Build tab and the
## Structure section start from their defaults, and say so.
func reset_tool_settings() -> void:
	for key in [TOOL_SETTINGS, BUILD_SETTINGS, STRUCTURE_SETTINGS]:
		data[key] = {}
	save()
	tool_settings_reset.emit()


## One of the kept-settings dictionaries, or an empty one when the file held
## something else there.
func _kept(key: String) -> Dictionary:
	var stored = data.get(key, {})
	return stored if stored is Dictionary else {}


## Whether two kept values are the same, without `==` raising on two types it
## cannot compare. The file is JSON, so a number reads back as a float, and the
## same number a field hands back as an int is no change; nor is a set of fields
## that holds such numbers (#1667).
static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


## Set every overlay colour from `colors`, a colour by `HFOverlayColors` key, and
## save: Settings' High Contrast and Reset buttons. A key `colors` leaves out
## goes back to its default, so a preset always sets the whole palette.
func set_overlay_colors(colors: Dictionary) -> void:
	for key in HFOverlayColors.DEFAULTS:
		set_pref(key, colors.get(key, HFOverlayColors.DEFAULTS[key]))
	save()


## Mark a contextual hint as dismissed and persist.
func dismiss_hint(hint_key: String) -> void:
	var dismissed: Dictionary = data.get("hints_dismissed", {})
	dismissed[hint_key] = true
	data["hints_dismissed"] = dismissed
	save()
