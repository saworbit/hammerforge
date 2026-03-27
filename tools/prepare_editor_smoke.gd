extends SceneTree
## Reset HammerForge user prefs for a repeatable editor smoke run.
##
## Usage:
##   godot --headless -s res://tools/prepare_editor_smoke.gd --path .
##   godot --headless -s res://tools/prepare_editor_smoke.gd --path . -- --tutorial-step=3
##   godot --headless -s res://tools/prepare_editor_smoke.gd --path . -- --show-welcome=false

const HFUserPrefs = preload("res://addons/hammerforge/hf_user_prefs.gd")


func _init() -> void:
	var options := {
		"tutorial_step": 0,
		"show_welcome": true,
		"help": false,
	}
	_parse_args(OS.get_cmdline_user_args(), options)
	if options["help"]:
		_print_usage()
		quit(0)
		return

	var prefs = HFUserPrefs.new()
	prefs.data = HFUserPrefs._defaults()
	prefs.set_pref("tutorial_step", int(options["tutorial_step"]))
	prefs.set_pref("show_welcome", bool(options["show_welcome"]))
	prefs.save()

	print("HammerForge editor smoke prefs reset")
	print("prefs_path=", ProjectSettings.globalize_path(HFUserPrefs.PREFS_PATH))
	print("tutorial_step=", prefs.get_pref("tutorial_step", 0))
	print("show_welcome=", prefs.get_pref("show_welcome", true))
	print(
		"Open res://samples/hf_editor_smoke_start.tscn and follow docs/HammerForge_Editor_Smoke_Checklist.md"
	)
	quit(0)


func _parse_args(args: PackedStringArray, options: Dictionary) -> void:
	for arg in args:
		if arg == "--help" or arg == "-h":
			options["help"] = true
		elif arg.begins_with("--tutorial-step="):
			var value := arg.trim_prefix("--tutorial-step=")
			if value.is_valid_int():
				options["tutorial_step"] = maxi(0, int(value))
		elif arg.begins_with("--show-welcome="):
			options["show_welcome"] = _parse_bool(arg.trim_prefix("--show-welcome="))


func _parse_bool(value: String) -> bool:
	var lowered := value.strip_edges().to_lower()
	return lowered in ["1", "true", "yes", "on"]


func _print_usage() -> void:
	print("HammerForge editor smoke prep")
	print("  --tutorial-step=N   Set persisted tutorial step before opening the editor.")
	print("  --show-welcome=BOOL Set show_welcome in prefs (true/false).")
	print("Examples:")
	print("  godot --headless -s res://tools/prepare_editor_smoke.gd --path .")
	print(
		"  godot --headless -s res://tools/prepare_editor_smoke.gd --path . -- --tutorial-step=3"
	)
