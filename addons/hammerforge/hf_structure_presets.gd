@tool
class_name HFStructurePresets
extends RefCounted
## Structure presets: a type's settings, named and put back in one pick (#1415).
##
## A project settles on a few house styles, a stair of one width and rise, a
## doorway arch of one radius, and without these each was typed again from memory
## or read off an old structure, and two people on a team drifted apart.
##
## Presets are kept by type in `PROJECT_FILE`, in the brush presets folder beside
## the bake profiles, which goes into version control so a team shares them. A
## preset is only ever read through the builder's schema: `check_ranges()` refuses
## one with a value out of range or of the wrong kind, naming the field, and
## `merge()` drops a key the builder no longer has and fills one it has gained.
## So an older file, or one edited by hand, can put nothing in the fields that the
## fields could not hold. Nothing here knows any type's settings, so every type
## `HFGeneratorSystem.known_types()` names has presets with no code of its own.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
const HFSettingsFile = preload("hf_settings_file.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The project's presets, in the brush presets folder.
const PROJECT_FILE := "structure_presets.json"
## The builder's own defaults, always first in the list and never saved.
const DEFAULTS := "Defaults"
## What the list shows while the fields hold no preset.
const CUSTOM := "Custom"
const MAX_NAME_LENGTH := 40


## A name as typed, made fit to save under.
static func clean_name(text: String) -> String:
	return text.strip_edges().left(MAX_NAME_LENGTH)


## True for a name the list already uses for something else, in any case.
static func is_reserved_name(preset_name: String) -> bool:
	for taken in [DEFAULTS, CUSTOM]:
		if taken.nocasecmp_to(preset_name.strip_edges()) == 0:
			return true
	return false


## Every type's presets in the file at `path`, as it holds them, unchecked:
## `{type: {name: settings}}`. A missing file is none. One that is not a presets
## file is said and is none.
static func read_raw(path: String) -> Dictionary:
	return HFSettingsFile.read(path, "presets", "Structure presets")


## True when there is a file at `path` that is not a presets file. Save and Delete
## write the whole file from what they read, so they ask this first rather than
## writing one preset over every shared one, as bake profiles once did (#1006).
static func file_unreadable(path: String) -> bool:
	return HFSettingsFile.unreadable(path, "presets")


## Write `presets` to `path`, keys sorted and one setting a line so a change reads
## as a small diff. Pass what `read_raw()` gave with one preset changed, so a type
## this version does not know, from a newer HammerForge, is kept for the people
## who can read it. False when the file cannot be written, which is said.
static func write(presets: Dictionary, path: String) -> bool:
	return HFSettingsFile.write(path, "presets", presets, "Structure presets")


## The presets `raw` keeps for `type`, as `{name: settings}` unchecked. A type
## entry that is not a set of presets has none.
static func of_type(raw: Dictionary, type: String) -> Dictionary:
	var kept = raw.get(type, {})
	return kept if kept is Dictionary else {}


## The saved names for `type` as a person would sort them. Defaults is not one.
static func names(raw: Dictionary, type: String) -> PackedStringArray:
	var own: Array = []
	for key in of_type(raw, type):
		if not is_reserved_name(str(key)):
			own.append(str(key))
	own.sort_custom(func(a, b) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0)
	return PackedStringArray(own)


## A preset's settings as the builder reads them, or why they cannot be had:
## `{ok, settings}` or `{ok, message}`. Defaults is the builder's own. A value out
## of range or of the wrong kind refuses the whole preset, naming the field, so
## the fields are never half filled. A key the builder does not have is dropped.
static func settings_of(raw: Dictionary, type: String, preset_name: String) -> Dictionary:
	var schema := HFGeneratorSystem.settings_schema(type)
	if schema.is_empty():
		return _refused("%s is not a structure type" % type)
	if preset_name == DEFAULTS:
		return {"ok": true, "settings": HFGeneratorSystem.default_settings(type)}
	var presets := of_type(raw, type)
	if not presets.has(preset_name):
		return _refused("Structure preset %s is not saved for %s" % [preset_name, _label(type)])
	var stored = presets[preset_name]
	if not (stored is Dictionary):
		return _refused("Structure preset %s is not a set of settings" % preset_name)
	var problem := HFGeneratorSchema.check_ranges(schema, stored)
	if problem != "":
		return _refused("Structure preset %s: %s" % [preset_name, problem])
	return {"ok": true, "settings": HFGeneratorSchema.merge(schema, stored)}


## The preset `settings` are, in the order the list shows them, or "" for none.
## `preferred` wins when it matches too, so picking a saved preset that happens
## to equal the defaults keeps showing the one picked.
static func matching(
	raw: Dictionary, type: String, settings: Dictionary, preferred: String = ""
) -> String:
	var candidates := PackedStringArray([DEFAULTS])
	candidates.append_array(names(raw, type))
	if preferred != "" and candidates.has(preferred):
		candidates.insert(0, preferred)
	for candidate in candidates:
		var read := settings_of(raw, type, candidate)
		if read["ok"] and HFGeneratorSystem.same_settings(type, read["settings"], settings):
			return candidate
	return ""


static func _label(type: String) -> String:
	return HFGeneratorSystem.display_name(type)


static func _refused(message: String) -> Dictionary:
	return {"ok": false, "message": message}
