extends RefCounted
## The developer's own preferences file, taken before a run that must leave it
## alone and compared after it (#1581).
##
## Every checkout and the editor share one `user://`, so whatever writes
## `HFUserPrefs.PREFS_PATH` writes the preferences of whoever is running it. The
## prefs vibe scenario wrote test text there and then deleted the file.
## `gut_pre_run.gd` and `gut_post_run.gd` take it either side of a GUT run, and
## `tools/vibe/hf_vibe_runner.gd` either side of each scenario. Nothing is put
## back: an editor open on the project saves to the same file, and the old bytes
## would undo its save.

const HFUserPrefsScript = preload("res://addons/hammerforge/hf_user_prefs.gd")


## What is at `path` now: its SHA-256, or "" when there is nothing there.
static func fingerprint(path: String = HFUserPrefsScript.PREFS_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


## How `path` differs from the `fingerprint()` taken as `before`, or "" when it
## does not.
static func change_since(before: String, path: String = HFUserPrefsScript.PREFS_PATH) -> String:
	var now := fingerprint(path)
	if now == before:
		return ""
	var where := ProjectSettings.globalize_path(path)
	if before == "":
		return "%s was written, and there was none before" % where
	if now == "":
		return "%s is gone" % where
	return "%s was rewritten" % where
