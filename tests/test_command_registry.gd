extends GutTest
## The command table every surface reads: what each command is called, where it
## is grouped, whether it needs a level, and what it needs selected.

const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")

## The keys the selection guard reads (`managed_action_surface_allowed`).
const SELECTION_KEYS := ["brushes_only", "minimum", "label", "allow_faces", "mixed_only"]
const ENTRY_KEYS := ["id", "label", "category", "needs_level", "selection", "guard_only"]


func test_every_id_is_listed_once():
	var seen := {}
	for entry in HFCommandRegistry.COMMANDS:
		var id := str(entry.get("id", ""))
		assert_ne(id, "", "every entry has an id")
		assert_false(seen.has(id), "%s is listed once" % id)
		seen[id] = true
	assert_eq(HFCommandRegistry.ids().size(), seen.size())


func test_every_entry_is_well_formed():
	for entry in HFCommandRegistry.COMMANDS:
		var id := str(entry.get("id", ""))
		for key in entry:
			assert_has(ENTRY_KEYS, key, "%s: %s is a field the table has" % [id, key])
		assert_true(entry.get("label") is String and entry["label"] != "", "%s has a label" % id)
		assert_true(
			entry.get("category") is String and entry["category"] != "", "%s has a category" % id
		)
		assert_true(entry.get("needs_level") is bool, "%s says whether it needs a level" % id)
		assert_true(entry.get("selection") is Dictionary, "%s has a selection entry" % id)
		var selection: Dictionary = entry.get("selection", {})
		for key in selection:
			assert_has(SELECTION_KEYS, key, "%s: the guard reads %s" % [id, key])
		if selection.has("minimum"):
			assert_true(selection["minimum"] is int, "%s: minimum is a whole number" % id)


func test_every_key_binding_names_a_command_the_dispatcher_runs():
	var dispatched := HFCommandRegistry.dispatched_ids()
	for action in HFKeymap.load_or_default("").get_actions():
		assert_has(dispatched, action, "%s is a command" % action)


func test_a_guard_only_id_is_known_but_never_dispatched():
	assert_true(HFCommandRegistry.has("apply_context_material"))
	assert_false(HFCommandRegistry.dispatched_ids().has("apply_context_material"))
	assert_true(HFCommandRegistry.dispatches("hollow"))
	assert_false(HFCommandRegistry.dispatches("apply_context_material"))
	assert_false(HFCommandRegistry.dispatches("no_such_command"))


func test_an_unknown_id_answers_empty():
	assert_false(HFCommandRegistry.has("no_such_command"))
	assert_eq(HFCommandRegistry.find("no_such_command"), {})
	assert_eq(HFCommandRegistry.label("no_such_command"), "")
	assert_eq(HFCommandRegistry.category("no_such_command"), "")
	assert_false(HFCommandRegistry.needs_level("no_such_command"))
	assert_eq(HFCommandRegistry.selection("no_such_command"), {})


func test_a_selection_handed_out_is_a_copy():
	var first := HFCommandRegistry.selection("merge")
	first["minimum"] = 99
	assert_eq(HFCommandRegistry.selection("merge")["minimum"], 2)


func test_the_lookups_read_the_table():
	assert_eq(HFCommandRegistry.label("clip_to_face"), "Clip to Face Plane")
	assert_eq(HFCommandRegistry.category("rotate_cw"), "Transform")
	assert_true(HFCommandRegistry.needs_level("carve"))
	assert_false(HFCommandRegistry.needs_level("tool_draw"))
	assert_eq(
		HFCommandRegistry.selection("merge"),
		{"brushes_only": true, "minimum": 2, "label": "Merge"},
	)
	assert_eq(HFCommandRegistry.selection("toggle_grid"), {})


func test_the_keymap_reads_its_labels_and_categories_here():
	for id in HFCommandRegistry.ids():
		assert_eq(HFKeymap.get_action_label(id), HFCommandRegistry.label(id), "%s label" % id)
		assert_eq(HFKeymap.get_category(id), HFCommandRegistry.category(id), "%s category" % id)
	assert_eq(HFKeymap.get_action_label("some_new_action"), "Some New Action")
	assert_eq(HFKeymap.get_category("some_new_action"), "Editing")
