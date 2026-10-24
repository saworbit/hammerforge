extends GutTest

## `docs/commands.md` is what the command registry says, and every command says
## what it does (#1658).

const CommandReference = preload("res://tools/command_reference.gd")
const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")


func test_the_committed_page_is_what_the_registry_builds():
	var committed := FileAccess.get_file_as_string(CommandReference.PATH).replace("\r\n", "\n")
	var built := CommandReference.build()
	if committed == built:
		pass_test("docs/commands.md is current")
		return
	var have := committed.split("\n")
	var want := built.split("\n")
	var first := 0
	while first < mini(have.size(), want.size()) and have[first] == want[first]:
		first += 1
	fail_test(
		(
			"docs/commands.md is not what the registry builds, from line %d:\n  committed: %s\n  built:     %s\nRun: %s"
			% [
				first + 1,
				have[first] if first < have.size() else "(end)",
				want[first] if first < want.size() else "(end)",
				CommandReference.REGENERATE,
			]
		)
	)


func test_every_command_says_what_it_does():
	var missing: Array = []
	for id in HFCommandRegistry.ids():
		if HFCommandRegistry.help(id).strip_edges() == "":
			missing.append(id)
	assert_eq(missing, [], "commands with no help")


func test_the_page_lists_every_command_and_every_bridge_command_s_params():
	var page := CommandReference.build()
	for id in HFCommandRegistry.ids():
		assert_string_contains(page, "(`%s`) |" % id)
	for id in HFCommandRegistry.bridge_ids():
		assert_string_contains(page, "### %s (`%s`)" % [HFCommandRegistry.label(id), id])
		for param in HFCommandRegistry.bridge(id).get("params", []):
			assert_string_contains(page, "| `%s`" % param["key"])


func test_needs_reads_as_words():
	assert_eq(CommandReference.needs({"selection": {}, "needs_level": false}), "-")
	assert_eq(CommandReference.needs({"selection": {}, "needs_level": true}), "a level")
	assert_eq(
		CommandReference.needs({"selection": {"brushes_only": true, "minimum": 2}}), "2 brushes"
	)
	assert_eq(
		CommandReference.needs(
			{"selection": {"minimum": 1, "allow_faces": true}, "needs_level": true}
		),
		"1 item or faces, a level"
	)


func test_the_palette_tooltip_carries_the_help():
	var palette = load("res://addons/hammerforge/ui/hf_hotkey_palette.gd").new()
	add_child_autofree(palette)
	await get_tree().process_frame
	palette.populate(HFKeymap.load_or_default(""))
	var hollow: Button = null
	for entry in palette._entries:
		if entry.get("action") == "hollow":
			hollow = entry["button"]
	assert_not_null(hollow, "Hollow is in the palette")
	if hollow:
		assert_string_contains(hollow.tooltip_text, HFCommandRegistry.help("hollow"))
