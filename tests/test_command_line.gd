extends GutTest

## The Console's command line reads a command the way the Agent Bridge does
## (#1696): `hollow 0.125`, `hollow thickness=0.125`, `move to floor`.

const HFCommandLine = preload("res://addons/hammerforge/hf_command_line.gd")
const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFCommandLineView = preload("res://addons/hammerforge/ui/hf_command_line_view.gd")
const HFMcpCommands = preload("res://addons/hammerforge/mcp/hf_mcp_commands.gd")
const HFMcpTools = preload("res://addons/hammerforge/mcp/hf_mcp_tools.gd")
const HFGeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

const ALIASES := "user://test_command_line_aliases.txt"


func before_each():
	# The project's own aliases file is the user's; tests read one of their own.
	HFCommandLine.aliases_path = ALIASES


func after_each():
	HFCommandLine.aliases_path = preload("res://addons/hammerforge/hf_command_aliases.gd").USER_FILE
	if FileAccess.file_exists(ALIASES):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ALIASES))


func test_a_value_goes_in_by_place_or_by_name():
	for line in ["hollow 0.125", "hollow thickness=0.125", "Hollow   0.125", "shell 0.125"]:
		var read := HFCommandLine.read(line)
		assert_true(read["ok"], "%s reads" % line)
		assert_eq(read.get("id"), "hollow", "%s is Hollow" % line)
		assert_eq(read.get("params"), {"thickness": 0.125}, "%s gives the thickness" % line)


func test_a_command_is_named_by_its_id_its_label_or_an_alias_of_several_words():
	for line in ["move_to_floor", "move to floor", "Move to Floor"]:
		var read := HFCommandLine.read(line)
		assert_eq(read.get("id"), "move_to_floor", line)
		assert_eq(read.get("params"), {}, "%s has no values" % line)


## A script pasted from elsewhere often parts its words with tabs (#2015).
func test_a_tab_parts_words_as_a_space_does():
	assert_eq(HFCommandLine.words("hollow\t0.125"), PackedStringArray(["hollow", "0.125"]))
	var read := HFCommandLine.read("hollow\t0.125")
	assert_true(read["ok"], "a line with a tab reads")
	assert_eq(read.get("params"), {"thickness": 0.125}, "and gives the thickness")


## The line tried six words at most, and one label has seven (#2015).
func test_a_label_of_seven_words_names_its_command():
	var read := HFCommandLine.read("Point Filter: X and Z from Here")
	assert_eq(read.get("id"), "take_xz_for_next_pick", "the whole label names the command")


## The palette reads the project's aliases file, and a word in it is taken from
## the command the registry gave it to. The line knew only the registry's (#1991).
func test_the_project_aliases_name_commands_on_the_line():
	var file := FileAccess.open(ALIASES, FileAccess.WRITE)
	file.store_string("shell2 = hollow\nslice = hollow\n")
	file.close()
	var read := HFCommandLine.read("shell2 0.125")
	assert_eq(read.get("id"), "hollow", "a word only the file has")
	assert_eq(read.get("params"), {"thickness": 0.125}, "with its value")
	assert_eq(HFCommandLine.read("slice").get("id"), "hollow", "a word the file takes from Clip")


func test_values_by_name_and_place_mix_and_keep_their_shapes():
	var read := HFCommandLine.read('place_prefab "my door" position=1,2,3 linked=yes')
	assert_true(read["ok"], str(read))
	assert_eq(
		read.get("params"), {"prefab": "my door", "position": [1.0, 2.0, 3.0], "linked": true}
	)
	read = HFCommandLine.read('update_structure gen_4 {"steps": 8, "name": "a b"}')
	assert_eq(
		read.get("params"), {"generator_id": "gen_4", "settings": {"steps": 8.0, "name": "a b"}}
	)


func test_a_value_too_many_or_of_the_wrong_kind_is_refused_naming_it():
	var read := HFCommandLine.read("hollow 0.1 0.2")
	assert_false(read["ok"])
	assert_eq(read.get("message"), "Hollow takes 1 value: thickness.")
	read = HFCommandLine.read("hollow thick")
	assert_false(read["ok"])
	assert_eq(read.get("field"), "thickness")
	assert_string_contains(read.get("message"), "thickness is a number")
	read = HFCommandLine.read("place_prefab door position=1,2")
	assert_eq(read.get("field"), "position", "a vector needs three numbers")


func test_a_name_that_is_no_command_says_the_nearest():
	var read := HFCommandLine.read("hollw 0.125")
	assert_false(read["ok"])
	assert_string_contains(read.get("message"), "There is no command 'hollw'.")
	assert_string_contains(read.get("message"), "hollow")


func test_a_command_the_bridge_does_not_run_takes_no_values():
	var read := HFCommandLine.read("toggle paint mode")
	assert_true(read["ok"])
	assert_eq(read.get("id"), "toggle_paint_mode")
	assert_false(read.get("bridge"), "it runs as the palette runs it")
	read = HFCommandLine.read("toggle_paint_mode 3")
	assert_false(read["ok"])
	assert_eq(read.get("message"), "Toggle Paint Mode takes no values.")


func test_what_the_line_asks_for():
	assert_eq(_keys(HFCommandLine.missing("create_arch", {})), ["type", "position"])
	assert_eq(_keys(HFCommandLine.to_ask("hollow", {})), ["thickness"], "a bare hollow asks")
	assert_eq(HFCommandLine.to_ask("hollow", {"thickness": 1.0}), [], "a given one does not")
	var thickness: Dictionary = HFCommandRegistry.field("hollow", "thickness")
	assert_eq(HFCommandLine.prompt(thickness), "Thickness <0.25>:", "with the default shown")


func test_suggestions_put_the_exact_name_first_and_stop_at_eight():
	var offered := HFCommandLine.suggestions("hollow")
	assert_eq(offered[0], "hollow")
	assert_lte(HFCommandLine.suggestions("t").size(), HFCommandLine.MOST_SUGGESTIONS)
	assert_has(HFCommandLine.suggestions("mov"), "move_to_floor")
	assert_string_contains(HFCommandLine.hint("hollow"), "thickness, 0.05 to 128")


## Every command the bridge runs reads the same from a line as from a request:
## by name, and by place, through the bridge's own reader.
func test_every_bridge_command_reads_the_same_on_the_line_as_over_the_bridge():
	var commands := HFMcpCommands.new(HFMcpTools.new())
	var wrong: PackedStringArray = []
	for id in HFCommandRegistry.bridge_ids():
		var spec := HFCommandRegistry.bridge(id)
		var params := _example(spec)
		var by_bridge: Dictionary = commands.read_params(
			spec, JSON.parse_string(JSON.stringify(params))
		)
		if not by_bridge["ok"]:
			wrong.append("%s: the example does not read over the bridge: %s" % [id, by_bridge])
			continue
		for line in [HFCommandLine.line_for(id, params), _by_place(id, spec, params)]:
			var read := HFCommandLine.read(line)
			if not read["ok"] or read["id"] != id:
				wrong.append("%s: '%s' reads as %s" % [id, line, read])
				continue
			var by_line: Dictionary = commands.read_params(spec, read["params"])
			if not by_line["ok"] or str(by_line["value"]) != str(by_bridge["value"]):
				wrong.append("%s: '%s' gives %s, the bridge %s" % [id, line, by_line, by_bridge])
	assert_eq(wrong, PackedStringArray(), "\n".join(wrong))


## A value for every field of `spec`, inside its range.
static func _example(spec: Dictionary) -> Dictionary:
	var out := {}
	for field_def in spec.get("params", []):
		var key := str(field_def["key"])
		match str(field_def.get("type", "float")):
			"float":
				out[key] = float(field_def.get("min", 0.0)) + 0.5
			"int":
				out[key] = float(int(field_def.get("min", 0)) + 2)
			"bool":
				out[key] = true
			"enum":
				var options: Array = field_def.get("options", [])
				if str(field_def.get("options_from", "")) == "generator_types":
					options = Array(HFGeneratorSystem.known_types())
				out[key] = str(options[0])
			"axis":
				out[key] = "z"
			"vec3":
				out[key] = [1.0, 2.5, -3.0]
			"cell":
				out[key] = [2.0, -3.0]
			"layer":
				out[key] = 1.0
			"object":
				out[key] = {"steps": 8.0}
			"face":
				out[key] = {"normal": [0.0, 1.0, 0.0]}
			_:
				out[key] = "a name"
	return out


## The line with every value by place, in the order the entry lists them.
static func _by_place(id: String, spec: Dictionary, params: Dictionary) -> String:
	var parts: PackedStringArray = [id]
	for field_def in spec.get("params", []):
		var one := HFCommandLine.line_for(id, {str(field_def["key"]): params[field_def["key"]]})
		parts.append(one.substr(one.find("=") + 1))
	return " ".join(parts)


static func _keys(fields: Array) -> Array:
	return fields.map(func(f): return str(f["key"]))


# ===========================================================================
# The line itself
# ===========================================================================


func _view() -> HFCommandLineView:
	var view := HFCommandLineView.new()
	add_child_autoqfree(view)
	watch_signals(view)
	return view


func _ran(view: HFCommandLineView) -> Array:
	var out: Array = []
	for i in get_signal_emit_count(view, "run_requested"):
		out.append(get_signal_parameters(view, "run_requested", i))
	return out


func test_a_bare_command_asks_for_its_value_and_enter_takes_the_default():
	var view := _view()
	view.submit("hollow")
	assert_eq(view.asking(), "Thickness <0.25>:")
	view.submit("")
	assert_eq(_ran(view), [["hollow", {"thickness": 0.25}, "hollow thickness=0.25"]])
	assert_eq(view.asking(), "", "nothing more is asked")


func test_a_required_value_has_to_be_typed_and_escape_cancels():
	var view := _view()
	view.submit("create_arch type=stairs")
	assert_eq(view.asking(), "Position:")
	view.submit("")
	assert_eq(view.asking(), "Position:", "Enter without a value asks again")
	view.cancel()
	assert_eq(view.asking(), "")
	assert_eq(_ran(view), [], "nothing ran")


func test_up_recalls_the_last_line_and_enter_on_an_empty_line_runs_it_again():
	var view := _view()
	view.submit("move to floor")
	view.submit("hollow 0.5")
	view.submit("")
	var ran := _ran(view)
	assert_eq(ran.size(), 3)
	assert_eq(ran[2][2], "hollow 0.5", "the last line again")
	assert_eq(view.history(), ["move to floor", "hollow 0.5"], "kept once")
	view._step_history(-1)
	assert_eq(view._line.text, "hollow 0.5")
	view._step_history(-1)
	assert_eq(view._line.text, "move to floor")


func test_a_refused_line_says_why_and_runs_nothing():
	var view := _view()
	view.submit("hollow thick")
	assert_string_contains(view._hint.text, "thickness is a number")
	assert_eq(_ran(view), [])


func test_escape_on_an_empty_line_asks_to_close():
	var view := _view()
	view.cancel()
	assert_signal_emitted(view, "close_requested")
