extends GutTest

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const GUIDE := "res://docs/HammerForge_UserGuide.md"
const FEATURES := "res://docs/features.md"


func _table_rows(path: String, heading: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var section := text.substr(text.find(heading) + heading.length())
	var rows: Array = []
	var started := false
	for line in section.split("\n"):
		if line.begins_with("|"):
			started = true
			var cells: Array = []
			for cell in line.split("|"):
				cells.append(cell.strip_edges().replace("&#96;", "`"))
			rows.append(cells)
		elif started:
			break
	return rows


func test_user_guide_lists_every_default_action_and_chord():
	var keymap = HFKeymapType.load_or_default("")
	var rows := _table_rows(GUIDE, "**Default bindings:**")
	for action in HFKeymapType._default_bindings():
		var found := false
		for row in rows:
			if row.size() >= 4 and row[1] == HFKeymapType.get_action_label(action):
				if row[2] == keymap.get_display_string(action):
					found = true
		assert_true(found, "%s needs its current label and chord in the guide" % action)


func test_feature_table_stars_only_current_bindings_and_lists_all_of_them():
	var keymap = HFKeymapType.load_or_default("")
	var expected: Array = []
	for action in HFKeymapType._default_bindings():
		expected.append([keymap.get_display_string(action), HFKeymapType.get_action_label(action)])
	var found: Array = []
	for row in _table_rows(FEATURES, "## Keyboard Shortcuts"):
		if row.size() >= 4 and row[1].ends_with(" *"):
			var entry := [row[1].trim_suffix(" *"), row[2]]
			assert_has(expected, entry, "A starred row must name a current binding")
			found.append(entry)
	for entry in expected:
		assert_has(found, entry, "Every rebindable action needs its own starred row")
