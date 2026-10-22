@tool
class_name HFSettingsFile
extends RefCounted
## A settings file a team shares: `{"version": 1, <key>: {...}}`, read with one
## set of rules and written whole through `HFLevelIO.write_bytes_atomic()`
## (#1679). Structure presets and bake profiles keep theirs this way.
##
## `FileAccess.WRITE` empties a file before the new text is stored, so a write the
## editor did not finish, killed or out of power, left an empty or partial file,
## and every preset or profile in it was gone (#1663). An atomic write leaves the
## old file or the new one. A write cut short between the two leaves the old one
## beside it as `.previous`, which a read takes when the file itself is gone.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFLog = preload("hf_log.gd")
const HFLevelIO = preload("hflevel_io.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The unreadable files already said, by section, path and the time they were
## written. A dock row reads the file at every turn of a field, and once is
## enough to say it.
static var _said_unreadable: Dictionary = {}


## The `key` section of the file at `path`, as it holds it, unchecked. A missing
## file is none. One that is not such a file is said once, as `label`, and is none.
static func read(path: String, key: String, label: String) -> Dictionary:
	var source := _readable_path(path)
	if source == "":
		return {}
	var section: Variant = _section_in(source, key)
	if section == null:
		var said := "%s:%s@%d" % [key, source, FileAccess.get_modified_time(source)]
		if not _said_unreadable.has(said):
			_said_unreadable[said] = true
			HFLog.warn("%s: %s is not a %s file. Left out." % [label, source, key])
		return {}
	return section


## True when there is a file at `path` that is not such a file. A save writes the
## whole file from what it read, and what it read of this one is nothing, so it
## asks this first rather than writing one item over every shared one (#1006).
static func unreadable(path: String, key: String) -> bool:
	var source := _readable_path(path)
	return source != "" and _section_in(source, key) == null


## Write `items` as the `key` section of `path`, keys sorted and one value a line
## so a change reads as a small diff. False when it cannot be written, which is
## said as `label`; the file is then as it was.
static func write(path: String, key: String, items: Dictionary, label: String) -> bool:
	var text := JSON.stringify({"version": 1, key: items}, "\t", true) + "\n"
	var err := write_text(path, text)
	if err != OK:
		HFLog.warn("%s: cannot write %s (%s)" % [label, path, error_string(err)])
	return err == OK


## Write `text` to `path` whole, making its folder first. OK, or why not.
static func write_text(path: String, text: String) -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return HFLevelIO.write_bytes_atomic(path, text.to_utf8_buffer())


## The file to read for `path`: itself, or the copy an atomic write cut short left
## beside it when it is gone, or "" when there is neither.
static func _readable_path(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
	if FileAccess.file_exists(path + ".previous"):
		return path + ".previous"
	return ""


## The `key` section of the file at `path`, or null when it is not such a file. A
## JSON object rather than `parse_string()`, which prints an engine error for a
## file that does not parse, on every read of a conflicted file.
static func _section_in(path: String, key: String) -> Variant:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	var parsed = json.data
	if not (parsed is Dictionary) or not (parsed.get(key) is Dictionary):
		return null
	return parsed[key]
