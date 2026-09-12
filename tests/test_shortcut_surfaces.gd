extends GutTest

## #439, #440. The keymap is rebindable, and three of the surfaces that tell a
## mapper which key does what spelled their chords into string literals instead
## of asking it. Two actions also shared a display label, so the rebind list
## showed two rows called "Extrude Up" with different keys.

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const ShortcutHudScene = preload("res://addons/hammerforge/shortcut_hud.tscn")
const CoachMarks = preload("res://addons/hammerforge/ui/hf_coach_marks.gd")
const TooltipText = preload("res://addons/hammerforge/ui/hf_tooltip_text.gd")

var keymap


func before_each():
	keymap = HFKeymapType.load_or_default("")


# ===========================================================================
# format_chords (#439)
# ===========================================================================


func test_a_token_becomes_the_current_chord():
	assert_eq(keymap.format_chords("{hollow}: Hollow"), "Ctrl+H: Hollow")


func test_a_token_follows_a_rebind():
	keymap.set_binding("hollow", KEY_H, true, false, true)
	assert_eq(keymap.format_chords("{hollow}: Hollow"), "Ctrl+Alt+H: Hollow")


func test_several_tokens_in_one_line():
	var line: String = keymap.format_chords("{axis_x} / {axis_y} / {axis_z}: Lock Axis")
	assert_eq(line, "X / Y / Z: Lock Axis")


func test_a_token_naming_no_action_is_left_alone():
	assert_eq(
		keymap.format_chords("{not_an_action}: Nothing"),
		"{not_an_action}: Nothing",
		"A typo stays visible rather than turning into a plausible '?'"
	)


func test_text_with_no_tokens_is_untouched():
	assert_eq(keymap.format_chords("Right-click: Cancel"), "Right-click: Cancel")


func test_has_action_answers_for_both():
	assert_true(keymap.has_action("hollow"))
	assert_false(keymap.has_action("not_an_action"))


# ===========================================================================
# The three surfaces read the keymap
# ===========================================================================


func test_the_hud_names_the_current_chord():
	var hud = ShortcutHudScene.instantiate()
	add_child_autoqfree(hud)
	hud.set_keymap(keymap)
	var before: String = hud._build_shortcuts_text({"tool": 1, "mode": 0})
	assert_true(before.contains("Ctrl+H: Hollow"), "The default chord is on the HUD")
	keymap.set_binding("hollow", KEY_H, true, false, true)
	var after: String = hud._build_shortcuts_text({"tool": 1, "mode": 0})
	assert_true(after.contains("Ctrl+Alt+H: Hollow"), "And so is the rebound one")
	assert_false(after.contains("Ctrl+H: Hollow"), "The old chord is gone")


func test_the_coach_marks_name_the_current_chord():
	var marks = CoachMarks.new()
	add_child_autoqfree(marks)
	marks.set_keymap(keymap)
	assert_true(
		"Press Ctrl+H or use Command Palette" in marks.steps_for("hollow"),
		"The default chord is in the guide"
	)
	keymap.set_binding("hollow", KEY_H, true, false, true)
	assert_true("Press Ctrl+Alt+H or use Command Palette" in marks.steps_for("hollow"))


func test_the_dock_tooltip_names_the_current_chord():
	assert_string_contains(TooltipText.text_for("hollow_btn", keymap), "(Ctrl+H)")
	keymap.set_binding("hollow", KEY_H, true, false, true)
	assert_string_contains(TooltipText.text_for("hollow_btn", keymap), "(Ctrl+Alt+H)")


func test_every_chord_token_in_the_three_surfaces_names_a_real_action():
	var regex := RegEx.new()
	regex.compile("\\{([a-z_0-9]+)\\}")
	var unresolved: Array = []
	for path in [
		"res://addons/hammerforge/shortcut_hud.gd",
		"res://addons/hammerforge/ui/hf_coach_marks.gd",
		"res://addons/hammerforge/ui/hf_tooltip_text.gd",
	]:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for hit in regex.search_all(line):
				var action := hit.get_string(1)
				if not keymap.has_action(action) and not unresolved.has(action):
					unresolved.append(action)
	assert_eq(unresolved, [], "A token naming no action is rendered on screen in braces")


func test_the_surfaces_hold_no_chord_literal():
	var regex := RegEx.new()
	regex.compile('"[^"]*(Ctrl|Alt)\\+[A-Za-z][^"]*"')
	var literals: Array = []
	for path in [
		"res://addons/hammerforge/shortcut_hud.gd",
		"res://addons/hammerforge/ui/hf_coach_marks.gd",
		"res://addons/hammerforge/ui/hf_tooltip_text.gd",
	]:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for hit in regex.search_all(line):
				literals.append(hit.get_string(0))
	# Mouse gestures and held modifiers are not rebindable actions, so they are
	# the one place a chord is allowed to be written out.
	const NOT_ACTIONS := ["Scroll", "Click", "Alt+Shift", "picks material"]
	var rebindable: Array = []
	for literal in literals:
		var is_gesture := false
		for gesture in NOT_ACTIONS:
			if str(literal).contains(gesture):
				is_gesture = true
				break
		if not is_gesture:
			rebindable.append(literal)
	assert_eq(rebindable, [], "A rebindable chord belongs in a token, not a literal")


# ===========================================================================
# One label per action in the rebind list (#440)
# ===========================================================================


func test_no_two_actions_share_a_label():
	var by_label := {}
	for action in keymap.get_actions():
		var label: String = HFKeymapType.get_action_label(action)
		var seen: Array = by_label.get(label, [])
		seen.append(action)
		by_label[label] = seen
	var collisions: Array = []
	for label in by_label:
		if (by_label[label] as Array).size() > 1:
			collisions.append("%s: %s" % [label, str(by_label[label])])
	assert_eq(collisions, [], "Two rows with one name cannot be told apart in the rebind list")


func test_the_extrude_aliases_are_named_as_aliases():
	assert_eq(HFKeymapType.get_action_label("tool_extrude_up"), "Extrude Up")
	assert_eq(HFKeymapType.get_action_label("tool_extrude"), "Extrude Up (alt)")
	assert_eq(HFKeymapType.get_action_label("tool_extrude_down"), "Extrude Down")
	assert_eq(HFKeymapType.get_action_label("tool_extrude_down_alt"), "Extrude Down (alt)")
