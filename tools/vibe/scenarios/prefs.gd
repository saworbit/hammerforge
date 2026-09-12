@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The two files a user can end up editing by hand: `hammerforge_prefs.json` and
## the keymap.
##
## `HFKeymap` was hardened for this -- `_validated()` drops anything unusable and
## names the file and the key. `HFUserPrefs` reads the same kind of file with no
## validation at all, so the question is what the difference costs. The other
## question is what happens when two actions end up on the same key, which is
## the ordinary outcome of a rebind.

const UserPrefs = preload("res://addons/hammerforge/hf_user_prefs.gd")
const Keymap = preload("res://addons/hammerforge/hf_keymap.gd")

const PREFS_PATH := "user://hammerforge_prefs.json"


func id() -> String:
	return "prefs"


func summary() -> String:
	return "user preferences and keymap files: malformed values, silent resets, and rebinds that collide"


func run() -> void:
	await _prefs_with_values_of_the_wrong_type()
	await _prefs_that_will_not_parse()
	await _a_rebind_onto_a_key_already_in_use()


func _write_prefs(text: String) -> void:
	HFVibe.write_text(PREFS_PATH, text)


func _restore_prefs() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))


## Every accessor on `HFUserPrefs` reads its container into a typed local:
##
##     var sections: Dictionary = data.get("collapsed_sections", {})
##     var recent: Array = data.get("recent_files", [])
##
## `load_prefs()` assigns whatever the file parsed to, so those types are the
## file's to choose.
func _prefs_with_values_of_the_wrong_type() -> void:
	_write_prefs(
		'{"collapsed_sections": "all", "recent_files": "res://a.tscn", "hints_dismissed": 3}'
	)
	var prefs = UserPrefs.load_prefs()
	prefs.persistence_enabled = false
	note("loaded keys", prefs.data.keys())

	var collapsed = prefs.get_section_collapsed("Brush")
	note("get_section_collapsed returned", collapsed)
	prefs.add_recent_file("res://b.tscn")
	note("recent files after add_recent_file", prefs.get_recent_files())
	var dismissed = prefs.is_hint_dismissed("first_brush")
	note("is_hint_dismissed returned", dismissed)

	var recent_now = prefs.data.get("recent_files", null)
	if str(recent_now) == "res://a.tscn":
		known(
			408,
			"a prefs file with a value of the wrong type breaks every accessor that reads it",
			(
				"load_prefs() assigns the parsed Dictionary straight to `data` with no schema"
				+ " check, and each accessor then assigns its container to a typed local:"
				+ " get_section_collapsed(), add_recent_file() and is_hint_dismissed() all"
				+ " abort with 'Trying to assign value of type String to a variable of type"
				+ (
					" Array'. add_recent_file() dropped the path silently, leaving %s."
					% str(recent_now)
				)
				+ " HFKeymap._validated() is the pattern this file is missing."
			)
		)

	# Values of the right type but absurd: nothing clamps these either.
	prefs.set_pref("autosave_interval", -1)
	prefs.set_pref("grid_snap", 0.0)
	note("autosave_interval accepted", prefs.get_pref("autosave_interval"))
	note("grid_snap accepted", prefs.get_pref("grid_snap"))
	_restore_prefs()


## A prefs file that does not parse at all -- a half-written one, which is what
## `save()` leaves behind when the editor goes down mid-write, since it opens the
## destination with FileAccess.WRITE rather than writing beside it and renaming.
func _prefs_that_will_not_parse() -> void:
	_write_prefs('{"grid_snap": 64.0, "recent_files": ["res://a.tscn", "res://')
	var prefs = UserPrefs.load_prefs()
	prefs.persistence_enabled = false
	note("grid_snap after loading a truncated file", prefs.get_pref("grid_snap"))
	note("recent files after loading a truncated file", prefs.get_recent_files())
	# #423 kept the defaults for an unreadable file -- which is right -- and added
	# the two things that were missing: the damaged file is set aside rather than
	# overwritten, and the loader says why. Both are what this checks now.
	var kept := UserPrefs.PREFS_PATH + ".unreadable"
	note("the unreadable file was kept as", kept if FileAccess.file_exists(kept) else "nothing")
	if not FileAccess.file_exists(kept):
		flag(
			"a prefs file that will not parse is discarded rather than set aside",
			(
				"load_prefs() falls back to the defaults, which is right, but the file it could"
				+ " not read is the only copy of the user's recent files, collapsed sections and"
				+ " dismissed hints. #423 kept it as <prefs>.unreadable; nothing is there now."
			)
		)
	_restore_prefs()


## Rebinding is one `set_binding()` call and there is no conflict check anywhere
## -- not in `HFKeymap`, not in the dock that calls it.
func _a_rebind_onto_a_key_already_in_use() -> void:
	var km = Keymap.load_or_default()
	var event := InputEventKey.new()
	event.keycode = KEY_G
	event.ctrl_pressed = true

	note("Ctrl+G before the rebind matches 'group'", km.matches("group", event))
	km.set_binding("hollow", KEY_G, true)
	var both := km.matches("group", event) and km.matches("hollow", event)
	note("after binding 'hollow' to Ctrl+G, both match", both)
	# Two actions sharing a chord is still what the keymap stores -- #428 made it
	# reportable rather than refused, so the question is whether the report names
	# the pair. The dialog, the loader and set_binding() all read this.
	var reported: Array = []
	if km.has_method("conflicts_for"):
		reported = Array(km.conflicts_for("hollow"))
	note("conflicts_for('hollow') after the rebind", reported)
	if both and not reported.has("group"):
		flag(
			"a rebind onto a chord another action already uses is not reported",
			(
				(
					"set_binding() wrote the binding and matches() answers true for both, which is"
					+ " what #428 settled on -- but conflicts_for() is the report that makes it"
					+ " visible in the shortcut dialog, and it does not name the action that was"
					+ " already there: %s"
				)
				% str(reported)
			)
		)

	# The same collision in the file the user hand-edits: _validated() checks the
	# action name and the keycode, but not whether two actions now share a chord.
	var duplicates := _duplicate_chords(km)
	note("chords shared by more than one action in the defaults", duplicates.size())
	for chord in duplicates:
		note("  %s" % chord, duplicates[chord])


func _duplicate_chords(km: Object) -> Dictionary:
	var by_chord: Dictionary = {}
	var bindings: Dictionary = km.get_all_bindings()
	for action in bindings:
		var b: Dictionary = bindings[action]
		var chord := (
			"%d/%s%s%s"
			% [
				int(b.get("keycode", 0)),
				"C" if bool(b.get("ctrl", false)) else "-",
				"S" if bool(b.get("shift", false)) else "-",
				"A" if bool(b.get("alt", false)) else "-",
			]
		)
		if not by_chord.has(chord):
			by_chord[chord] = []
		by_chord[chord].append(action)
	var shared: Dictionary = {}
	for chord in by_chord:
		if by_chord[chord].size() > 1:
			shared[chord] = by_chord[chord]
	return shared
