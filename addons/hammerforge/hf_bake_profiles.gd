@tool
class_name HFBakeProfiles
extends RefCounted
## Bake profiles: the bake options, named and switched in one step.
##
## A profile is a set of values for the settings `HFBakeSystem.profile_setting_names()`
## lists. It decides how the level is built and never what goes into it, so the
## visibility switch and the cordons are left where the mapper put them.
##
## Two are built in, from the table in the shipping guide
## (docs/HammerForge_Shipping_A_Level.md): Editing, tuned for a fast bake, and
## Shipping, tuned for a fast frame. They switch only the options that pay for
## themselves in every game. Lightmap UV2 only matters with baked lighting, a
## navmesh only with something that pathfinds, occluders only indoors and chunking
## only past a hundred brushes or so, so the built ins leave those as they are.
## A profile the mapper saves holds every option, so it can say all of that.
##
## Nothing here is stored in the level. Which profile a level is on is read from
## its options each time, so a level saved on Shipping opens on Shipping, and one
## changed by hand reads as no profile at all.
##
## Saved profiles live in two places. This machine's are in the preferences. The
## project's are in `PROJECT_FILE` beside the brush presets, which goes into
## version control, so a team shares one shipping recipe and a fresh clone has it
## (#980). A name both keep is the project's.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFLog = preload("hf_log.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFBakeSystemType = preload("systems/hf_bake_system.gd")

const EDITING := "Editing"
const SHIPPING := "Shipping"
## What the list shows while the level's options match no profile.
const CUSTOM := "Custom"
const MAX_NAME_LENGTH := 40
## The project's shared profiles, in the brush presets folder.
const PROJECT_FILE := "bake_profiles.json"

const _BUILT_IN := {
	EDITING:
	{
		"bake_merge_meshes": false,
		"bake_generate_lods": false,
	},
	SHIPPING:
	{
		"bake_merge_meshes": true,
		"bake_generate_lods": true,
	},
}


## The built-in profiles, in the order the list shows them.
static func built_in_names() -> PackedStringArray:
	return PackedStringArray([EDITING, SHIPPING])


## A built-in profile's values, or an empty set for a name that is not one.
static func built_in(profile_name: String) -> Dictionary:
	return (_BUILT_IN.get(profile_name, {}) as Dictionary).duplicate()


## True for a name the list already uses, in any case: a built-in one, so a saved
## "shipping" cannot stand beside the real one looking like it, and Custom, which
## is what the list says when the level is on no profile.
static func is_reserved_name(profile_name: String) -> bool:
	for taken in [EDITING, SHIPPING, CUSTOM]:
		if taken.nocasecmp_to(profile_name.strip_edges()) == 0:
			return true
	return false


## A name as typed, made fit to save under.
static func clean_name(text: String) -> String:
	return text.strip_edges().left(MAX_NAME_LENGTH)


## Every profile in the order the list shows them: built in first, then the saved
## ones as a person would sort them.
static func names(saved: Dictionary) -> PackedStringArray:
	var out := built_in_names()
	var own: Array = saved.keys()
	own.sort_custom(func(a, b) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0)
	for profile in own:
		out.append(str(profile))
	return out


## A profile's values by name, built in or saved.
static func values_of(profile_name: String, saved: Dictionary) -> Dictionary:
	if _BUILT_IN.has(profile_name):
		return built_in(profile_name)
	var values = saved.get(profile_name, {})
	return (values as Dictionary).duplicate() if values is Dictionary else {}


## The saved profiles from the preferences, each held to what `root` can take.
## A profile with nothing usable left in it is dropped, because a profile that
## sets nothing would match every level.
static func read_saved(root: Object, prefs) -> Dictionary:
	if prefs == null or root == null:
		return {}
	return _read_profiles(root, prefs.get_bake_profiles())


## The project's profiles in the file at `path`, as it holds them, unchecked. A
## missing file is none. One that is not a profiles file is said and is none.
static func read_project_raw(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed.get("profiles") is Dictionary):
		HFLog.warn("Bake profiles: %s is not a profiles file. Left out." % path)
		return {}
	return parsed["profiles"]


## The project's profiles, each held to what `root` can take, as the
## preferences' are. A bad value in the file is dropped and named.
static func read_project(root: Object, path: String) -> Dictionary:
	if root == null:
		return {}
	return _read_profiles(root, read_project_raw(path))


## Write `profiles` as the project's to `path`, keys sorted and one option a
## line so a change reads as a small diff. Pass what `read_project_raw()` gave
## with one profile changed, so a profile this machine cannot read, such as one
## from a newer HammerForge, is kept for the people who can. False when the file
## cannot be written, which is said.
static func write_project(profiles: Dictionary, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var reason := error_string(FileAccess.get_open_error())
		HFLog.warn("Bake profiles: cannot write %s (%s)" % [path, reason])
		return false
	file.store_string(JSON.stringify({"version": 1, "profiles": profiles}, "\t", true) + "\n")
	file.close()
	return true


## The project's profiles and this machine's in one set. A name both keep is the
## project's: the shared one is what the team means by it, and a copy on one
## machine standing in for it is the drift sharing the file is for. The copy
## that is hidden is said.
static func combined(project: Dictionary, mine: Dictionary) -> Dictionary:
	var out := project.duplicate()
	for profile_name in mine:
		if out.has(profile_name):
			HFLog.warn(
				(
					"Bake profile %s: the project keeps one of that name, so yours is hidden"
					% profile_name
				)
			)
			continue
		out[profile_name] = mine[profile_name]
	return out


static func _read_profiles(root: Object, stored: Dictionary) -> Dictionary:
	var out := {}
	for key in stored:
		var profile_name := str(key)
		if is_reserved_name(profile_name):
			HFLog.warn(
				"Bake profile %s takes a name the list already uses. Left out." % profile_name
			)
			continue
		var raw = stored[key]
		if not raw is Dictionary:
			HFLog.warn("Bake profile %s is not a set of options. Left out." % profile_name)
			continue
		var values := validated(root, raw, profile_name)
		if not values.is_empty():
			out[profile_name] = values
	return out


## `values` with anything a profile cannot set taken out, each one named in a
## warning: a setting that is not a profile's, a value of the wrong kind, or a
## number where a whole one is needed. Whole numbers JSON gave back as floats are
## put back. Ranges are left to the level's setters, as they are for the dock.
static func validated(root: Object, values: Dictionary, profile_name: String) -> Dictionary:
	var out := {}
	var settings := HFBakeSystemType.profile_setting_names()
	for key in values:
		var setting := str(key)
		if setting not in settings:
			HFLog.warn(
				(
					"Bake profile %s: %s is not an option a profile sets. Left out."
					% [profile_name, setting]
				)
			)
			continue
		var value = HFBakeSystemType.profile_value(root.get(setting), values[key])
		if value == null:
			HFLog.warn(
				(
					"Bake profile %s: %s cannot be %s. Left out."
					% [profile_name, setting, JSON.stringify(values[key])]
				)
			)
			continue
		out[setting] = value
	return out


## True when the level has every value the profile sets. A profile that sets
## nothing matches nothing.
static func matches(root: Object, values: Dictionary) -> bool:
	if root == null or values.is_empty():
		return false
	for key in values:
		var have = root.get(key)
		var wanted = values[key]
		if have is float and (wanted is float or wanted is int):
			if not is_equal_approx(have, float(wanted)):
				return false
		elif typeof(have) != typeof(wanted) or have != wanted:
			return false
	return true


## The profile the level is on, or "" when it is on none. When more than one
## matches, the one that sets the most options says the most about the level,
## so a saved profile wins over the built-in whose two options it shares; a tie
## goes to the one listed first.
static func current(root: Object, saved: Dictionary) -> String:
	var best := ""
	var best_size := 0
	for profile_name in names(saved):
		var values := values_of(profile_name, saved)
		if values.size() > best_size and matches(root, values):
			best = profile_name
			best_size = values.size()
	return best


## How many of the options `values` sets differ from the level's now.
static func count_changes(root: Object, values: Dictionary) -> int:
	var changed := 0
	for key in values:
		if not matches(root, {key: values[key]}):
			changed += 1
	return changed
