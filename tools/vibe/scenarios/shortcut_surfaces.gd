@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Every surface that tells a mapper which key does what, checked against the
## keymap that actually decides it.
##
## The keymap is rebindable -- `HFKeymap.set_binding()` writes it and the
## shortcut dialog offers it -- so a surface that spells a chord into a string
## literal is a claim that stops being true the moment someone uses that dialog.

## The HUD is scene-backed -- its @onready node paths only resolve from the
## packed scene, so instantiating the bare script logs "Node not found".
const ShortcutHudScene = preload("res://addons/hammerforge/shortcut_hud.tscn")
const CoachMarks = preload("res://addons/hammerforge/ui/hf_coach_marks.gd")
const TooltipText = preload("res://addons/hammerforge/ui/hf_tooltip_text.gd")

const KEYMAP_PATH := "user://vibe_keymap_surfaces.json"


func id() -> String:
	return "shortcut-surfaces"


func summary() -> String:
	return "whether the HUD, the coach marks and the tooltips still tell the truth after a rebind"


func run() -> void:
	await _who_reads_the_keymap_and_who_does_not()
	await _duplicate_labels_in_the_rebind_list()


func _hud() -> Control:
	var hud = ShortcutHudScene.instantiate()
	_tree.get_root().add_child(hud)
	return hud


func _select_mode_text(hud: Control) -> String:
	return hud._build_shortcuts_text({"tool": 1, "mode": 0})


func _coach_steps(guide: String) -> Array:
	var guides: Dictionary = CoachMarks.GUIDES
	return guides.get(guide, {}).get("steps", [])


func _who_reads_the_keymap_and_who_does_not() -> void:
	var keymap := HFKeymap.load_or_default(KEYMAP_PATH)
	note("default Hollow binding", keymap.get_display_string("hollow"))

	var hud = _hud()
	await frame()
	var before := _select_mode_text(hud)
	note("HUD select-mode line", before.split("\n")[7] if before.split("\n").size() > 7 else before)

	# The rebind a mapper makes when Ctrl+H is taken by something else.
	keymap.set_binding("hollow", KEY_H, true, false, true)
	note("Hollow after rebind", keymap.get_display_string("hollow"))

	var after := _select_mode_text(hud)
	note("HUD select-mode text unchanged", before == after)
	var lying: Array = []
	if after.contains("Ctrl+H"):
		lying.append("viewport HUD: '%s'" % _line_containing(after, "Ctrl+H"))
	var hollow_steps := _coach_steps("hollow")
	for step in hollow_steps:
		if str(step).contains("Ctrl+H"):
			lying.append("coach mark: '%s'" % str(step))
	var hollow_tip := str(TooltipText.TEXTS.get("hollow_btn", ""))
	note("hollow_btn tooltip", hollow_tip)
	if hollow_tip.contains("Ctrl+H"):
		lying.append("dock tooltip: '%s'" % hollow_tip)

	note("surfaces still naming the old chord", lying)
	if not lying.is_empty():
		known(
			439,
			"a rebound shortcut is still advertised under its old chord in three places",
			(
				"Hollow was rebound to %s; " % keymap.get_display_string("hollow")
				+ "%d surface(s) still say Ctrl+H: %s. " % [lying.size(), str(lying)]
				+ "HFKeymap.get_display_string() exists and is what dock.gd, "
				+ "hf_hotkey_palette.gd and hf_shortcut_dialog.gd use, so the same editor "
				+ "shows the new chord in the palette and the old one in the HUD"
			)
		)

	var hard_coded := _count_hard_coded_chords()
	note("chord literals in shortcut_hud.gd", hard_coded["hud"])
	note("chord literals in hf_coach_marks.gd", hard_coded["coach"])
	note("chord literals in hf_tooltip_text.gd", hard_coded["tooltips"])

	hud.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYMAP_PATH))


func _line_containing(text: String, needle: String) -> String:
	for line in text.split("\n"):
		if line.contains(needle):
			return line
	return ""


func _count_hard_coded_chords() -> Dictionary:
	var out := {"hud": 0, "coach": 0, "tooltips": 0}
	var files := {
		"hud": "res://addons/hammerforge/shortcut_hud.gd",
		"coach": "res://addons/hammerforge/ui/hf_coach_marks.gd",
		"tooltips": "res://addons/hammerforge/ui/hf_tooltip_text.gd",
	}
	var regex := RegEx.new()
	regex.compile("(Ctrl|Shift|Alt)[+][A-Za-z]")
	for key in files:
		var f := FileAccess.open(files[key], FileAccess.READ)
		if f:
			out[key] = regex.search_all(f.get_as_text()).size()
	return out


## Two actions with the same label in the rebind list.
func _duplicate_labels_in_the_rebind_list() -> void:
	var keymap := HFKeymap.load_or_default(KEYMAP_PATH)
	var by_label: Dictionary = {}
	for action in keymap.get_actions():
		var label := HFKeymap.get_action_label(action)
		var seen: Array = by_label.get(label, [])
		seen.append("%s (%s)" % [action, keymap.get_display_string(action)])
		by_label[label] = seen
	var collisions: Array = []
	for label in by_label:
		if (by_label[label] as Array).size() > 1:
			collisions.append("%s: %s" % [label, str(by_label[label])])
	note("labels shared by more than one action", collisions)
	if not collisions.is_empty():
		known(
			440,
			"the rebind list shows two rows with the same name and different keys",
			(
				(
					"HFKeymap.get_action_label() gives %d label(s) to more than one action: %s. "
					% [collisions.size(), str(collisions)]
				)
				+ "hf_shortcut_dialog.gd and hf_hotkey_palette.gd both list by label, so a "
				+ "mapper rebinding 'Extrude Up' cannot tell which of the two rows is the one "
				+ "their muscle memory uses, and rebinding the wrong one looks like a no-op"
			)
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYMAP_PATH))
