@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What the documentation says the editor is, against what it is.
##
## `shortcut-surfaces` checks that the HUD and the tooltips still name the right
## key after a rebind. This checks the written material: the user guide, the
## in-editor tutorial wizard and the feature pages. Those are what someone
## evaluating the tool reads before they touch anything, so a number in them that
## the plugin does not agree with is a defect with the shortest possible path to
## a first impression.
##
## Everything here is read off the running plugin, not asserted against a list --
## the guide's numbers are extracted and compared against the property that
## holds them, so the check keeps working as the defaults change.

const DOC_PATHS := [
	"res://docs/HammerForge_UserGuide.md",
	"res://docs/HammerForge_MVP_GUIDE.md",
	"res://docs/features.md",
	"res://docs/HammerForge_FloorPaint_Greyboxing.md",
	"res://docs/HammerForge_Data_Portability.md",
]
const TUTORIAL = preload("res://addons/hammerforge/ui/hf_tutorial_wizard.gd")
const KEYMAP = preload("res://addons/hammerforge/hf_keymap.gd")


func id() -> String:
	return "docs-truth"


func summary() -> String:
	return "what the guide, the tutorial and the feature pages claim, against the running plugin"


func run() -> void:
	await _the_tutorial_steps()
	await _shortcuts_the_guide_names()
	await _numbers_the_guide_quotes()
	await _entity_classes_the_guide_promises()


## The wizard is the first thing a new user sees. Each step waits on a signal
## from the level, so a step naming a signal the level does not have never
## advances.
func _the_tutorial_steps() -> void:
	note("-- the in-editor tutorial wizard --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var steps: Array = TUTORIAL.STEPS
	note("steps", steps.size())
	var missing: Array[String] = []
	for step in steps:
		var sig_name := str((step as Dictionary).get("signal_name", ""))
		var title := str((step as Dictionary).get("title", "?"))
		note(title, "waits on '%s'" % sig_name)
		note("  says", str((step as Dictionary).get("text", "")))
		if sig_name != "" and not root.has_signal(sig_name):
			missing.append("%s -> %s" % [title, sig_name])
	if not missing.is_empty():
		flag(
			"a tutorial step waits on a signal the level does not emit",
			(
				(
					"%s. The wizard connects to the named signal to know when the step is "
					+ "done, so a step naming one that is not there can never be completed "
					+ "and the wizard stops on it"
				)
				% str(missing)
			)
		)


## Every `Ctrl+X`-shaped token in the docs, against the keymap.
func _shortcuts_the_guide_names() -> void:
	note("-- shortcuts the docs name, against the keymap --")
	# `HFKeymap.new()` has no bindings; `load_or_default()` is what the plugin
	# builds and what the Shortcuts panel reads.
	var keymap = KEYMAP.load_or_default("user://vibe_docs_keymap.cfg")
	var actions: PackedStringArray = keymap.get_actions()
	note("actions the keymap binds", actions.size())
	var chords: Dictionary = {}
	for action in actions:
		chords[keymap.get_display_string(action).to_upper()] = str(action)
	note("distinct chords bound", chords.size())

	# The docs write a shortcut as a bare key or a modifier chord in backticks.
	var re := RegEx.create_from_string(
		"`((?:Ctrl|Shift|Alt)\\+)?([A-Z]|F[0-9]{1,2}|Tab|Esc|Escape|Space|Delete|Enter)`"
	)
	var seen: Dictionary = {}
	for path in DOC_PATHS:
		if not FileAccess.file_exists(path):
			note("not present", path)
			continue
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			seen["%s%s" % [m.get_string(1), m.get_string(2)]] = path.get_file()
	note("shortcut-shaped tokens across the docs", seen.size())
	var unbound: Array[String] = []
	for token in seen.keys():
		if not chords.has(str(token).to_upper()):
			unbound.append("%s (%s)" % [token, seen[token]])
	note("tokens the docs name and the keymap does not bind", unbound)
	if not unbound.is_empty():
		flag(
			"the docs name a shortcut nothing is bound to",
			(
				(
					"%s. A reader presses the key and nothing happens, and the Shortcuts "
					+ "panel has no row to correct them with"
				)
				% str(unbound)
			)
		)


## Numbers a reader would act on: the default brush size, the grid, the player.
func _numbers_the_guide_quotes() -> void:
	note("-- numbers in the docs against the properties that hold them --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var facts := {
		"default brush size": str(root.brush_size_default),
		"grid snap": str(root.grid_snap),
		"autosave minutes": str(root.hflevel_autosave_minutes),
		"autosave path": str(root.hflevel_autosave_path),
		"bake chunk size": str(root.bake_chunk_size),
		"prototype materials": str(root.add_prototype_materials()),
	}
	for key in facts:
		note(key, facts[key])

	# A measurement of sixteen units or more is pre-#625 scale -- unless the line
	# is telling the reader about the change, which the guide does at length.
	# Matching on the line rather than on the number is what keeps this honest:
	# the first pass flagged "Earlier versions drew on a Quake-family grid: a 16
	# unit snap and a 32 unit brush", which is the guide being right.
	var unit_re := RegEx.create_from_string("([0-9]{2,5})\\s*(?:unit|units)\\b")
	var historical := [
		"earlier version",
		"quake",
		"hammer,",
		"radiant",
		"trenchbroom",
		"before this change",
		"used to",
	]
	var current: Dictionary = {}
	var explained := 0
	for path in DOC_PATHS:
		if not FileAccess.file_exists(path):
			continue
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var lowered := line.to_lower()
			for m in unit_re.search_all(line):
				if int(m.get_string(1)) < 16:
					continue
				var is_history := false
				for marker in historical:
					if lowered.find(marker) >= 0:
						is_history = true
				if is_history:
					explained += 1
				else:
					current["%s: %s" % [path.get_file(), line.strip_edges().substr(0, 90)]] = true
	note("pre-#625 measurements the docs explain as history", explained)
	note("pre-#625 measurements presented as current", current.keys())
	if current.size() > 0:
		flag(
			"the docs measure the world in the units #625 moved off",
			(
				(
					"a drawn brush is %s and the grid snaps at %s, and these lines are not "
					+ "the guide explaining the change: %s"
				)
				% [root.brush_size_default, root.grid_snap, str(current.keys())]
			)
		)


## The guide's worked examples name entity classes. `entities.json` ships three.
func _entity_classes_the_guide_promises() -> void:
	note("-- entity classes the docs name, against entities.json --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var defs: Dictionary = root.get_entity_definitions()
	note("classes that ship", defs.keys())
	# The dock falls back to four built-in brush entity classes when entities.json
	# has none, so a doc naming one of those is not naming something absent. And
	# `door_1` is an entity *name* in a worked example, not a class -- the first
	# pass flagged both, which was the scenario being wrong rather than the docs.
	var builtin := ["func_detail", "func_wall", "trigger_once", "trigger_multiple"]
	note("brush entity classes the dock offers as built-ins", builtin)
	var re := RegEx.create_from_string("`((?:func|trigger|info|prop|logic)_[a-z_]+)`")
	var named: Dictionary = {}
	for path in DOC_PATHS:
		if not FileAccess.file_exists(path):
			continue
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			named[m.get_string(1)] = path.get_file()
	note("entity classes the docs name", named.keys())
	var absent: Array[String] = []
	for key in named.keys():
		if not defs.has(str(key)) and not (str(key) in builtin):
			absent.append("%s (%s)" % [key, named[key]])
	note("named in the docs, not in entities.json and not a built-in", absent)
	if not absent.is_empty():
		flag(
			"the docs name entity classes nothing offers",
			(
				(
					"%s. `entities.json` defines %s and the dock's fallbacks are %s, so a "
					+ "reader following the guide has nothing to select -- see #659"
				)
				% [str(absent), str(defs.keys()), str(builtin)]
			)
		)
