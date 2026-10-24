@tool
extends RefCounted
## Which kinds of check Validate runs, for the whole project (#1731).
##
## A mapper working on lighting does not want stair climb findings yet, and a
## team wants one answer to what is checked. The kinds left out are kept in
## `hammerforge_presets/validation_checks.json` beside the project's other shared
## presets, as `{"skip": ["traversal"]}`, so the file is committed and everyone's
## Validate agrees. Every kind runs when the file is missing.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFLog = preload("hf_log.gd")
const HFSettingsFile = preload("hf_settings_file.gd")
@warning_ignore_restore("shadowed_global_identifier")

const PROJECT_FILE := "res://hammerforge_presets/validation_checks.json"

## Each kind of check, with what the Test tab calls it. Every finding Validate
## makes carries one of these as its `check`.
const KINDS := {
	"geometry": "Brush shape and size",
	"overlap": "Brushes inside or on top of others",
	"data": "Level data: material slots, face picks, ids, paint layers",
	"entities": "Entity names and wiring",
	"spawn": "Player spawn",
	"traversal": "Stairs, doorways and ramps",
	"notes": "Open To Do notes",
}

## Where the file is read and written. A test points it somewhere of its own.
static var path := PROJECT_FILE


## The kinds the project leaves out. A file that cannot be read leaves none out,
## and says so.
static func skipped() -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(path):
		return out
	var parser := JSON.new()
	var parsed: Variant = null
	if parser.parse(FileAccess.get_file_as_string(path)) == OK:
		parsed = parser.data
	if not (parsed is Dictionary) or not (parsed.get("skip") is Array):
		HFLog.warn('Validation checks: %s is not {"skip": [...]}. Every check runs.' % path)
		return out
	for kind in parsed["skip"]:
		if KINDS.has(str(kind)):
			out.append(str(kind))
	return out


## Whether Validate runs `kind`.
static func runs(kind: String) -> bool:
	return not skipped().has(kind)


## Run `kind` or leave it out, and write the file. OK, or why not.
static func set_runs(kind: String, on: bool) -> int:
	if not KINDS.has(kind):
		return ERR_INVALID_PARAMETER
	var skip := skipped()
	if on and skip.has(kind):
		skip.remove_at(skip.find(kind))
	elif not on and not skip.has(kind):
		skip.append(kind)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := HFSettingsFile.write_text(path, JSON.stringify({"skip": Array(skip)}, "\t") + "\n")
	if err != OK:
		HFLog.warn("Validation checks: cannot write %s (%s)" % [path, error_string(err)])
	return err
