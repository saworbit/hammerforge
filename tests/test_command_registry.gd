extends GutTest
## The command table every surface reads: what each command is called, where it
## is grouped, whether it needs a level, and what it needs selected.

const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")
const HFMcpCommands = preload("res://addons/hammerforge/mcp/hf_mcp_commands.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

## The keys the selection guard reads (`managed_action_surface_allowed`).
const SELECTION_KEYS := ["brushes_only", "minimum", "label", "allow_faces", "mixed_only"]
const ENTRY_KEYS := [
	"id",
	"label",
	"help",
	"aliases",
	"category",
	"needs_level",
	"selection",
	"guard_only",
	"runs",
	"params",
	"bridge",
	"palette",
	"repeat",
]
const BRIDGE_KEYS := ["form", "description", "targets", "params", "undo"]
## Commands an agent must not run: they undo a human's work, leave the level, or
## write files no undo step records.
const NEVER_ON_THE_BRIDGE := [
	"undo",
	"redo",
	"quick_play",
	"quick_bake",
	"validate_level",
	"commit_cuts",
	"quick_save_prefab",
	"quick_save_linked_prefab",
	"push_to_source",
]


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
			entry.get("help") is String and entry["help"] != "", "%s says what it does" % id
		)
		assert_true(
			entry.get("category") is String and entry["category"] != "", "%s has a category" % id
		)
		assert_true(entry.get("needs_level") is bool, "%s says whether it needs a level" % id)
		assert_true(entry.get("selection") is Dictionary, "%s has a selection entry" % id)
		if entry.has("palette"):
			assert_true(entry["palette"] is bool, "%s: palette says yes or no" % id)
		var selection: Dictionary = entry.get("selection", {})
		for key in selection:
			assert_has(SELECTION_KEYS, key, "%s: the guard reads %s" % [id, key])
		if selection.has("minimum"):
			assert_true(selection["minimum"] is int, "%s: minimum is a whole number" % id)
		# The keys and the palette both refuse with this label, so a guard that
		# asks for anything has to carry one (#1298).
		if not selection.is_empty():
			assert_true(
				selection.get("label") is String and selection["label"] != "",
				"%s: a selection guard names the command for its toasts" % id
			)


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


func test_labels_keep_small_words_and_acronyms_as_written():
	assert_eq(HFCommandRegistry.label("entity_io"), "Entity I/O")
	assert_eq(HFCommandRegistry.label("apply_to_brush"), "Apply to Brush")
	assert_eq(HFCommandRegistry.label("push_to_source"), "Push to Source")
	# capitalize() wrote these three: it title-cases every word. A label or a
	# refusal label with a capital small word inside it is that shape again.
	var small := ["To", "Of", "In", "On", "At", "For", "From", "By", "And", "Or", "The", "With"]
	for id in HFCommandRegistry.ids():
		var labels: Array = [HFCommandRegistry.label(id)]
		var asked := HFCommandRegistry.selection(id)
		if asked.has("label"):
			labels.append(asked["label"])
		for text in labels:
			var words: PackedStringArray = str(text).split(" ")
			for i in range(1, words.size()):
				assert_false(words[i] in small, '%s: "%s" capitalises "%s"' % [id, text, words[i]])


func test_the_keymap_reads_its_labels_and_categories_here():
	for id in HFCommandRegistry.ids():
		assert_eq(HFKeymap.get_action_label(id), HFCommandRegistry.label(id), "%s label" % id)
		assert_eq(HFKeymap.get_category(id), HFCommandRegistry.category(id), "%s category" % id)
	assert_eq(HFKeymap.get_action_label("some_new_action"), "Some New Action")
	assert_eq(HFKeymap.get_category("some_new_action"), "Editing")


## A command's settings are on its entry, where the bridge, the command line and
## Adjust Last read them, and a bridge block holds none of its own (#1867).
func test_settings_are_on_the_command_not_its_bridge():
	for id in HFCommandRegistry.ids():
		var raw: Dictionary = HFCommandRegistry.find(id)
		assert_false(
			(raw.get("bridge", {}) as Dictionary).has("params"), "%s: bridge has no params" % id
		)
		if raw.has("bridge"):
			assert_eq(HFCommandRegistry.bridge(id)["params"], HFCommandRegistry.params(id), id)


func test_every_bridge_entry_is_well_formed():
	var forms := HFMcpCommands.new(null)
	assert_gt(HFCommandRegistry.bridge_ids().size(), 0)
	for id in HFCommandRegistry.bridge_ids():
		var spec := HFCommandRegistry.bridge(id)
		for key in BRIDGE_KEYS:
			assert_true(spec.has(key), "%s: bridge has %s" % [id, key])
		assert_ne(str(spec.get("description", "")), "", "%s says what it does" % id)
		assert_true(forms.has_method("check_" + str(spec["form"])), "%s: its form exists" % id)
		assert_has(["scope", "level"], spec["undo"], "%s: undo is scope or level" % id)
		var rule: Dictionary = spec["targets"]
		var low := int(rule["min"])
		var high := int(rule["max"])
		assert_true(high < 0 or high >= low, "%s: max is not below min" % id)
		var asked := HFCommandRegistry.selection(id)
		if asked.has("minimum"):
			assert_gte(low, int(asked["minimum"]), "%s: never asks less than the palette" % id)
		if bool(asked.get("brushes_only", false)):
			assert_false(bool(rule["entities"]), "%s: brushes only, as the palette" % id)
		for field_def in spec["params"]:
			var key := str(field_def.get("key", ""))
			assert_ne(key, "", "%s: every param has a key" % id)
			assert_has(
				HFCommandRegistry.PARAM_TYPES, field_def.get("type"), "%s.%s type" % [id, key]
			)
			assert_ne(str(field_def.get("description", "")), "", "%s.%s is described" % [id, key])
			if field_def.has("default") and field_def.has("min"):
				assert_gte(
					float(field_def["default"]), float(field_def["min"]), "%s.%s" % [id, key]
				)
				assert_lte(
					float(field_def["default"]), float(field_def["max"]), "%s.%s" % [id, key]
				)
	for id in NEVER_ON_THE_BRIDGE:
		assert_eq(HFCommandRegistry.bridge(id), {}, "%s is not on the bridge" % id)


func test_the_dock_offers_hollow_the_range_the_bridge_does():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	var wall := HFCommandRegistry.field("hollow", "thickness")
	var spin: SpinBox = dock.hollow_thickness
	assert_eq(
		[spin.min_value, spin.max_value, spin.step, spin.value],
		[wall["min"], wall["max"], wall["step"], wall["default"]]
	)
