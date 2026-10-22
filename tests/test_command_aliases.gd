extends GutTest

## The palette finds a command by the other words people use for it: the
## registry's aliases and a project's own in `hammerforge_presets/aliases.txt`
## (#1695).

const HFHotkeyPalette = preload("res://addons/hammerforge/ui/hf_hotkey_palette.gd")
const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")
const HFCommandAliases = preload("res://addons/hammerforge/hf_command_aliases.gd")

const USER_FILE := "user://test_command_aliases.txt"

var palette: HFHotkeyPalette


func before_each() -> void:
	palette = HFHotkeyPalette.new()
	palette.aliases_path = USER_FILE + ".none"
	add_child_autofree(palette)
	palette.populate(HFKeymap.load_or_default())


func after_each() -> void:
	HFLog.end_test_capture()
	if FileAccess.file_exists(USER_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_FILE))
	palette = null


func _write_user_file(text: String) -> void:
	var file := FileAccess.open(USER_FILE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _top(query: String) -> Dictionary:
	palette._on_search_changed(query)
	return palette._shown[0] if not palette._shown.is_empty() else {}


func test_every_alias_names_a_command_the_palette_lists():
	var listed := {}
	for entry in palette._entries:
		listed[entry["action"]] = true
	var count := 0
	for id in HFCommandRegistry.ids():
		for alias in HFCommandRegistry.aliases(id):
			count += 1
			assert_true(listed.has(id), "%s (%s) is in the palette" % [id, alias])
	assert_gt(count, 40, "fixture: the registry gives aliases")


func test_no_alias_belongs_to_two_commands_or_names_another():
	var labels := {}
	for id in HFCommandRegistry.ids():
		labels[HFCommandRegistry.label(id).to_lower()] = id
	var owner := {}
	for id in HFCommandRegistry.ids():
		for alias in HFCommandRegistry.aliases(id):
			assert_eq(alias, HFCommandAliases.normal(alias), "%s is lower case" % alias)
			assert_false(owner.has(alias), "%s names %s and %s" % [alias, owner.get(alias), id])
			assert_false(labels.has(alias), "%s is the label of %s" % [alias, labels.get(alias)])
			owner[alias] = id


func test_the_words_people_use_find_the_command_first():
	for pair in [["shell", "hollow"], ["subtract", "toggle_operation"], ["slice", "clip"]]:
		assert_eq(_top(pair[0]).get("action"), pair[1], "%s finds %s first" % pair)
	_top("shell")
	assert_eq(palette._shown[0]["button"].text, "Hollow (shell)", "the row says the word")
	assert_eq(palette._list.get_child(0), palette._shown[0]["button"], "and is the top row")


func test_a_short_alias_beats_a_label_that_holds_it():
	assert_eq(_top("ho").get("action"), "hollow")
	assert_eq(_top("split").get("action"), "clip", "above Split Edge and Vertex Split")


func test_the_label_is_back_and_the_order_too_once_the_search_is_cleared():
	_top("shell")
	palette._on_search_changed("")
	var listed := palette._list.get_children().filter(func(c): return c != palette._recent_header)
	assert_eq(listed, palette._rows)
	for row in palette._rows:
		assert_true(row.visible)
	for entry in palette._entries:
		assert_eq(entry["button"].text, entry["label"])


func test_enter_runs_the_top_row():
	palette.update_state({"brush_count": 1})
	var ran := []
	palette.action_invoked.connect(func(action): ran.append(action))
	palette._on_search_changed("slice")
	palette._execute_first_match()
	assert_eq(ran, ["clip"])


func test_a_typo_puts_the_closest_command_first():
	assert_eq(_top("hllow").get("action"), "hollow")
	assert_eq(palette._suggest_label.text, "Did you mean: Hollow?")
	assert_true(palette._suggest_label.visible)


func test_the_project_file_adds_aliases_and_takes_a_word_from_the_registry():
	_write_user_file("# ours\nshell = clip\nbevel = hollow  # a short one\n")
	palette.aliases_path = USER_FILE
	palette.populate(HFKeymap.load_or_default())
	assert_eq(_top("shell").get("action"), "clip", "the user's word wins")
	assert_eq(_top("bevel").get("action"), "hollow")
	assert_false(_top("shell").get("aliases", []).is_empty())
	var hollow: Dictionary = palette._entries.filter(func(e): return e["action"] == "hollow")[0]
	assert_false(hollow["aliases"].has("shell"), "and Hollow no longer has it")


func test_bad_lines_are_left_out_with_one_warning():
	_write_user_file("ok = hollow\nnot a line\n= clip\nwall = no_such_command\n")
	HFLog.begin_test_capture(["Command aliases"])
	var read := HFCommandAliases.read_user(USER_FILE)
	var said := HFLog.get_captured_warnings()
	assert_eq(read, {"ok": "hollow"})
	assert_eq(said.size(), 1, "one warning")
	for part in ["line 2", "line 3", 'line 4 names no command "no_such_command"']:
		assert_string_contains(said[0], part)


func test_no_file_is_no_aliases_and_nothing_said():
	HFLog.begin_test_capture([])
	assert_eq(HFCommandAliases.read_user(USER_FILE), {})
	assert_eq(HFLog.get_captured_warnings(), [])


func test_aliases_compare_without_case_or_extra_spaces():
	assert_eq(HFCommandAliases.parse("  Make   BIG = hollow", "x"), {"make big": "hollow"})
	assert_eq(_top("  Make   Hollow ").get("action"), "hollow")
