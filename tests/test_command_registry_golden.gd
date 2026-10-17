extends GutTest
## What every command was called, where it was grouped, whether it needed a level
## and what it needed selected, before those four lists became one table.
##
## `tests/fixtures/command_registry_golden.json` was written once from the code
## as it stood: `HFPluginCommands.requires_existing_root()`,
## `HFPluginSelectionState.managed_surface_action_requirement()`, and
## `HFKeymap.get_action_label()`, `get_category()` and `action_mode()`, for every
## arm of `HFPluginCommands.execute()` and the one id only the selection guard
## knows, with the hotkey palette's rows as it built them. The same functions must
## still give the same answers once they read `HFCommandRegistry`, so the move
## changes nothing a mapper sees. This goes once the registry is the only copy.

const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HFPluginSelectionState = preload("res://addons/hammerforge/plugin_selection_state.gd")
const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")
const HFHotkeyPalette = preload("res://addons/hammerforge/ui/hf_hotkey_palette.gd")
const GOLDEN_PATH := "res://tests/fixtures/command_registry_golden.json"

var golden: Dictionary = {}


func before_all():
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	golden = parsed if parsed is Dictionary else {}


## A value as JSON would give it back, so an int read from the file as a float
## still compares equal, and key order does not matter.
static func _canon(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)


func test_the_golden_table_was_read():
	assert_eq((golden.get("ids", []) as Array).size(), 95, "94 arms and the guard-only id")


func test_every_command_answers_as_it_did():
	var keymap := HFKeymap.load_or_default("")
	var commands: Dictionary = golden.get("commands", {})
	for id in golden.get("ids", []):
		var was: Dictionary = commands[id]
		var now := {
			"needs_level": HFPluginCommands.requires_existing_root(id),
			"selection": HFPluginSelectionState.managed_surface_action_requirement(id),
			"label": HFKeymap.get_action_label(id),
			"category": HFKeymap.get_category(id),
			"mode": HFKeymap.action_mode(id),
			"bound": keymap.has_action(id),
		}
		for key in was:
			assert_eq(_canon(now[key]), _canon(was[key]), "%s: %s" % [id, key])


func test_the_palette_lists_the_same_rows():
	var palette := HFHotkeyPalette.new()
	add_child_autofree(palette)
	palette.populate(HFKeymap.load_or_default(""))
	var rows: Array = []
	for entry in palette._entries:
		rows.append([entry["category"], entry["action"], entry["button"].text])
	assert_eq(_canon(rows), _canon(golden.get("palette_rows", [])))
