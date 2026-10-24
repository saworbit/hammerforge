@tool
extends RefCounted
## What a `.hflevel` saves, and which format number that is (#1638).
##
## `HFLevelIO.FORMAT_VERSION` guarded the direction that was already safe: a
## build reading an older file gives every missing key its default. The other
## direction lost data and said nothing. A build that does not know a key skips
## it on load and drops it on the next save, so a teammate on an older build
## opening a newer level and saving it threw away whatever the newer build added.
##
## So every change to what a level saves raises the number. The keys the last
## release saved are listed in `data/format.json`, by path: `state.brushes[].faces[]`
## for a list, and the keys of a record a level fills with names of its own, such
## as its visgroups, folded into `{}` by the `maps` the record names. A pull
## request that saves something new adds a fragment to `data/format.d/`, one file
## each, so two never touch the same lines. While any fragment is waiting, the
## build's number is the release's plus one, and a file names the fragments it
## was written with, so two development builds tell each other apart by name. The
## release folds the fragments into `format.json`
## (`python tools/format_fragments.py --compile`).

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFLog = preload("hf_log.gd")
@warning_ignore_restore("shadowed_global_identifier")

const RECORD := "res://addons/hammerforge/data/format.json"
const FRAGMENTS := "res://addons/hammerforge/data/format.d"

static var _record_cache: Dictionary = {}
static var _pending_cache: Array = []
static var _pending_read := false


## The format number the last release wrote.
static func released() -> int:
	return int(_record().get("released", 0))


## The number this build should write: the release's, plus one while fragments
## wait. `HFLevelIO.FORMAT_VERSION` is held to this by a test.
static func version_wanted() -> int:
	return released() + (1 if not pending().is_empty() else 0)


## The waiting fragments, by name, each `{name, what, older_builds, keys, maps}`.
## An exported game that left the folder out has none, and checks by number alone.
static func pending() -> Array:
	if _pending_read:
		return _pending_cache
	_pending_read = true
	_pending_cache = []
	if not DirAccess.dir_exists_absolute(FRAGMENTS):
		return _pending_cache
	var names := Array(DirAccess.get_files_at(FRAGMENTS))
	names.sort()
	for file in names:
		if not str(file).ends_with(".json"):
			continue
		var parsed: Variant = _read_json(FRAGMENTS.path_join(file))
		if not (parsed is Dictionary):
			HFLog.warn("Format: %s is not a format fragment. Left out." % file)
			continue
		var fragment: Dictionary = (parsed as Dictionary).duplicate()
		fragment["name"] = str(file).get_basename()
		_pending_cache.append(fragment)
	return _pending_cache


## The names of the waiting fragments, which a file this build writes carries.
static func pending_names() -> PackedStringArray:
	var out := PackedStringArray()
	for fragment in pending():
		out.append(str(fragment["name"]))
	return out


## Every key path the release and the waiting fragments name.
static func known_keys() -> Dictionary:
	var out := {}
	for key in _record().get("keys", []):
		out[str(key)] = true
	for fragment in pending():
		for key in fragment.get("keys", []):
			out[str(key)] = true
	return out


## The paths whose keys are a level's own names, folded into `{}`.
static func maps() -> PackedStringArray:
	var out := PackedStringArray(_record().get("maps", []))
	for fragment in pending():
		for path in fragment.get("maps", []):
			if not out.has(str(path)):
				out.append(str(path))
	return out


## Every key path in `value`, a bundle as `capture_hflevel_payload()` gives one:
## `a.b` for a key, `a[]` for what a list holds, and `a{}` for a map's entries.
static func census(value: Variant, folded: PackedStringArray = maps()) -> PackedStringArray:
	var found := {}
	_walk(value, "", folded, found)
	var out := PackedStringArray(found.keys())
	out.sort()
	return out


static func _walk(
	value: Variant, path: String, folded: PackedStringArray, found: Dictionary
) -> void:
	if value is Dictionary:
		if folded.has(path):
			for entry in (value as Dictionary).values():
				_walk(entry, path + "{}", folded, found)
			found[path + "{}"] = true
			return
		for key in value:
			var at := str(key) if path == "" else "%s.%s" % [path, str(key)]
			found[at] = true
			_walk(value[key], at, folded, found)
	elif value is Array:
		for entry in value:
			_walk(entry, path + "[]", folded, found)


## Why a file written with `version` and `names` cannot be read by this build, or
## "": a newer number, or the same number with a fragment this build lacks.
static func refusal(version: int, names: Variant, own_version: int) -> String:
	if version > own_version:
		return (
			"was written by a newer build (format %d, this build reads %d)" % [version, own_version]
		)
	if version < own_version or not (names is Array or names is PackedStringArray):
		return ""
	var ours := pending_names()
	var missing := PackedStringArray()
	for name in names:
		if not ours.has(str(name)):
			missing.append(str(name))
	if missing.is_empty():
		return ""
	return (
		"was written by a development build with changes this build does not have (%s)"
		% ", ".join(missing)
	)


## Forget what was read, so a test that writes fragments reads them again.
static func reload() -> void:
	_record_cache = {}
	_pending_cache = []
	_pending_read = false


static func _record() -> Dictionary:
	if _record_cache.is_empty():
		var parsed: Variant = _read_json(RECORD)
		_record_cache = parsed if parsed is Dictionary else {"released": 0, "keys": [], "maps": []}
	return _record_cache


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return parser.data
